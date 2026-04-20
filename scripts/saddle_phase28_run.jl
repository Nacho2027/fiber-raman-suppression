"""
Phase 28 runner — reduced-basis Hessian ladder + negative-curvature escape.

Usage:
  julia -t 8 --project=. scripts/saddle_phase28_run.jl

Outputs:
  - results/raman/phase28/phase28_results.jld2
  - results/raman/phase28/ladder_summary.md
  - results/raman/phase28/escape_summary.md
  - results/raman/phase28/images/*  (standard image sets for fresh phi_opt)
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Dates
using LinearAlgebra
using Statistics
using Random
using JLD2

include(joinpath(@__DIR__, "sweep_simple_param.jl"))
include(joinpath(@__DIR__, "phase13_hvp.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))

ensure_deterministic_environment()
ensure_deterministic_fftw()

const P28_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase28")
const P28_IMAGES_DIR = joinpath(P28_RESULTS_DIR, "images")
const P28_SWEEP1_PATH = joinpath(@__DIR__, "..", "results", "raman",
                                 "phase_sweep_simple", "sweep1_Nphi.jld2")

const P28_NPHI_LIMIT = 128
const P28_HVP_EPS = 1e-4
const P28_EIG_TOL_REL = 1e-6
const P28_SCAN_ALPHAS = [0.01, 0.02, 0.05, 0.10, 0.20]
const P28_ESCAPE_EIGS = 3
const P28_REOPT_TOP = 4
const P28_MAX_ITER = 40

lin_to_dB_safe(x) = 10 * log10(max(Float64(x), 1e-15))

function _mkdirs()
    mkpath(P28_RESULTS_DIR)
    mkpath(P28_IMAGES_DIR)
    return nothing
end

function build_canonical_problem()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset = :SMF28,
        β_order = 3,
        L_fiber = 2.0,
        P_cont = 0.2,
        Nt = 2^14,
        time_window = 10.0,
    )
    bw_mask = pulse_bandwidth_mask(uω0)
    return (
        uω0 = uω0,
        fiber = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        raman_threshold = raman_threshold,
        bw_mask = bw_mask,
    )
end

function load_sweep1_rows()
    data = JLD2.load(P28_SWEEP1_PATH)
    rows = data["results"]
    out = Dict{Int, Dict{String, Any}}()
    for row in rows
        cfg = row["config"]
        fiber_name = haskey(cfg, :fiber_preset) ? cfg[:fiber_preset] : cfg["fiber_preset"]
        L_fiber = haskey(cfg, :L_fiber) ? cfg[:L_fiber] : cfg["L_fiber"]
        P_cont = haskey(cfg, :P_cont) ? cfg[:P_cont] : cfg["P_cont"]
        fiber_name == :SMF28 || fiber_name == "SMF28" || continue
        L_fiber == 2.0 || continue
        P_cont == 0.2 || continue
        N_phi = Int(row["N_phi"])
        out[N_phi] = row
    end
    return out
end

function basis_from_row(row, prob)
    N_phi = Int(row["N_phi"])
    kind = Symbol(row["kind"])
    if kind === :identity
        return Matrix{Float64}(I, prob.sim["Nt"], prob.sim["Nt"])
    end
    return build_phase_basis(prob.sim["Nt"], N_phi;
                             kind = kind,
                             bandwidth_mask = prob.bw_mask)
end

function control_oracle(B, prob)
    fiber_local = deepcopy(prob.fiber)
    fiber_local["zsave"] = nothing
    return function(c_vec::AbstractVector{<:Real})
        _, dc = cost_and_gradient_lowres(c_vec, B, prob.uω0, fiber_local, prob.sim,
                                         prob.band_mask;
                                         log_cost = false,
                                         λ_gdd = 0.0,
                                         λ_boundary = 0.0)
        return dc
    end
end

function eval_plain_J_dB(c_vec, B, prob)
    fiber_local = deepcopy(prob.fiber)
    fiber_local["zsave"] = nothing
    J_lin, _ = cost_and_gradient_lowres(c_vec, B, prob.uω0, fiber_local, prob.sim,
                                        prob.band_mask;
                                        log_cost = false,
                                        λ_gdd = 0.0,
                                        λ_boundary = 0.0)
    return lin_to_dB_safe(J_lin)
end

function classify_hessian(λmin::Real, λmax::Real)
    tol = max(1e-10, P28_EIG_TOL_REL * abs(λmax))
    if λmin < -tol < λmax
        return "indefinite"
    elseif λmin >= -tol
        return "minimum_like"
    else
        return "nonpositive"
    end
end

function dense_hessian_analysis(row, prob)
    N_phi = Int(row["N_phi"])
    c_opt = Vector{Float64}(row["c_opt"])
    B = basis_from_row(row, prob)
    oracle = control_oracle(B, prob)
    H, max_asym = build_full_hessian_small(c_opt, oracle; eps = P28_HVP_EPS)
    F = eigen(Symmetric(H))
    λs = collect(F.values)
    V = Matrix(F.vectors)
    λmin = λs[1]
    λmax = λs[end]
    cls = classify_hessian(λmin, λmax)
    return Dict(
        "N_phi" => N_phi,
        "kind" => row["kind"],
        "J_dB" => Float64(row["J_final"]),
        "iterations" => Int(row["iterations"]),
        "converged" => Bool(row["converged"]),
        "lambda_min" => λmin,
        "lambda_max" => λmax,
        "ratio_absmin_to_max" => λmax > 0 ? abs(λmin) / λmax : NaN,
        "classification" => cls,
        "max_asymmetry" => max_asym,
        "eigenvalues" => λs,
        "eigenvectors" => V,
        "c_opt" => c_opt,
        "phi_opt" => Vector{Float64}(row["phi_opt"]),
    )
end

function line_scan(candidate, B, prob)
    λs = candidate["eigenvalues"]
    V = candidate["eigenvectors"]
    x0 = candidate["c_opt"]
    baseline = candidate["J_dB"]
    scans = Dict{String, Any}[]
    k = min(P28_ESCAPE_EIGS, count(<(0.0), λs))
    for idx in 1:k
        v = V[:, idx]
        for sign in (-1.0, 1.0)
            best = nothing
            for α in P28_SCAN_ALPHAS
                x = x0 .+ sign * α .* v
                J_dB = eval_plain_J_dB(x, B, prob)
                rec = Dict(
                    "eig_index" => idx,
                    "lambda" => λs[idx],
                    "sign" => sign,
                    "alpha" => α,
                    "J_dB" => J_dB,
                    "delta_dB" => J_dB - baseline,
                    "x_start" => x,
                )
                push!(scans, rec)
                if best === nothing || rec["J_dB"] < best["J_dB"]
                    best = rec
                end
            end
        end
    end
    sort!(scans, by = r -> r["J_dB"])
    return scans
end

function emit_standard_images(phi_opt, tag, prob)
    save_standard_set(phi_opt, prob.uω0, prob.fiber, prob.sim,
                      prob.band_mask, prob.Δf, prob.raman_threshold;
                      tag = tag,
                      fiber_name = "SMF28",
                      L_m = 2.0,
                      P_W = 0.2,
                      output_dir = P28_IMAGES_DIR)
    return nothing
end

function reopt_escape(scan_rec, candidate_row, B, prob, baseline_J_dB::Real)
    N_phi = Int(candidate_row["N_phi"])
    kind = Symbol(candidate_row["kind"])
    sign_str = scan_rec["sign"] > 0 ? "pos" : "neg"
    tag = @sprintf("smf28_canonical_nphi%d_escape_%s_a%0.3f",
                   N_phi, sign_str, scan_rec["alpha"])
    tag = replace(tag, "." => "p")

    fiber_local = deepcopy(prob.fiber)
    fiber_local["zsave"] = nothing
    res = optimize_phase_lowres(prob.uω0, fiber_local, prob.sim, prob.band_mask;
                                N_phi = N_phi,
                                kind = kind,
                                bandwidth_mask = prob.bw_mask,
                                c0 = Vector{Float64}(scan_rec["x_start"]),
                                B_precomputed = B,
                                max_iter = P28_MAX_ITER,
                                log_cost = true,
                                store_trace = false)

    c_opt = vec(res.c_opt)
    phi_opt = res.phi_opt
    J_plain_dB = eval_plain_J_dB(c_opt, B, prob)

    analysis_row = Dict(
        "N_phi" => N_phi,
        "kind" => String(kind),
        "c_opt" => c_opt,
        "phi_opt" => vec(phi_opt),
        "J_final" => J_plain_dB,
        "iterations" => res.iterations,
        "converged" => res.converged,
    )
    hess = dense_hessian_analysis(analysis_row, prob)
    emit_standard_images(phi_opt, tag, prob)

    return Dict(
        "tag" => tag,
        "start_eig_index" => scan_rec["eig_index"],
        "start_lambda" => scan_rec["lambda"],
        "start_sign" => scan_rec["sign"],
        "start_alpha" => scan_rec["alpha"],
        "start_J_dB" => scan_rec["J_dB"],
        "final_J_dB" => J_plain_dB,
        "delta_vs_baseline_dB" => J_plain_dB - baseline_J_dB,
        "iterations" => res.iterations,
        "converged" => res.converged,
        "classification" => hess["classification"],
        "lambda_min" => hess["lambda_min"],
        "lambda_max" => hess["lambda_max"],
        "ratio_absmin_to_max" => hess["ratio_absmin_to_max"],
    )
end

function write_ladder_summary(path, ladder, fullspace_J_dB)
    open(path, "w") do io
        println(io, "# Phase 28 Ladder Summary")
        println(io)
        println(io, "| N_phi | J_dB | classification | lambda_min | lambda_max | |lambda_min|/lambda_max |")
        println(io, "|---:|---:|---|---:|---:|---:|")
        for rec in sort(ladder, by = r -> r["N_phi"])
            @printf(io, "| %d | %.2f | %s | %.3e | %.3e | %.3e |\n",
                    rec["N_phi"], rec["J_dB"], rec["classification"],
                    rec["lambda_min"], rec["lambda_max"], rec["ratio_absmin_to_max"])
        end
        println(io)
        println(io, "Full-space anchor from Phase 13 / sweep1 identity row:")
        @printf(io, "- `N_phi = 16384` baseline depth: %.2f dB\n", fullspace_J_dB)
        println(io, "- Hessian classification: `indefinite` (from Phase 13 Findings)")
    end
    return nothing
end

function write_escape_summary(path, candidate, escape_runs)
    open(path, "w") do io
        println(io, "# Phase 28 Escape Summary")
        println(io)
        @printf(io, "Baseline candidate: `N_phi = %d`, `J_dB = %.2f`, class `%s`\n\n",
                candidate["N_phi"], candidate["J_dB"], candidate["classification"])
        println(io, "| tag | start eig | alpha | sign | final J_dB | delta vs baseline | class | lambda_min |")
        println(io, "|---|---:|---:|---:|---:|---:|---|---:|")
        for rec in escape_runs
            @printf(io, "| %s | %d | %.3f | %.0f | %.2f | %.2f | %s | %.3e |\n",
                    rec["tag"], rec["start_eig_index"], rec["start_alpha"],
                    rec["start_sign"], rec["final_J_dB"], rec["delta_vs_baseline_dB"],
                    rec["classification"], rec["lambda_min"])
        end
    end
    return nothing
end

function main()
    _mkdirs()
    prob = build_canonical_problem()
    rows = load_sweep1_rows()
    dense_keys = sort([k for k in keys(rows) if k <= P28_NPHI_LIMIT])
    full_row = rows[16384]

    @info "Analyzing control-space Hessian ladder" levels=dense_keys
    ladder = Dict{String, Any}[]
    for N_phi in dense_keys
        rec = dense_hessian_analysis(rows[N_phi], prob)
        push!(ladder, rec)
        @info "Ladder point" N_phi=N_phi J_dB=rec["J_dB"] classification=rec["classification"] λmin=rec["lambda_min"] λmax=rec["lambda_max"]
    end

    indefinite = [r for r in ladder if r["classification"] == "indefinite"]
    isempty(indefinite) && error("No indefinite dense ladder point found; escape study has nothing to target.")
    candidate = sort(indefinite, by = r -> r["J_dB"])[1]
    candidate_row = rows[Int(candidate["N_phi"])]
    B = basis_from_row(candidate_row, prob)

    @info "Running negative-curvature scan" N_phi=candidate["N_phi"] baseline_J_dB=candidate["J_dB"]
    scans = line_scan(candidate, B, prob)
    chosen = scans[1:min(P28_REOPT_TOP, length(scans))]

    escape_runs = Dict{String, Any}[]
    for scan_rec in chosen
        run = reopt_escape(scan_rec, candidate_row, B, prob, candidate["J_dB"])
        push!(escape_runs, run)
        @info "Escape run done" tag=run["tag"] final_J_dB=run["final_J_dB"] classification=run["classification"]
    end

    ladder_path = joinpath(P28_RESULTS_DIR, "ladder_summary.md")
    escape_path = joinpath(P28_RESULTS_DIR, "escape_summary.md")
    write_ladder_summary(ladder_path, ladder, full_row["J_final"])
    write_escape_summary(escape_path, candidate, escape_runs)

    out_path = joinpath(P28_RESULTS_DIR, "phase28_results.jld2")
    JLD2.jldsave(out_path;
        created_at = string(Dates.now()),
        dense_ladder = ladder,
        fullspace_baseline_J_dB = full_row["J_final"],
        candidate = candidate,
        scans = scans,
        chosen_scans = chosen,
        escape_runs = escape_runs,
        image_dir = P28_IMAGES_DIR,
    )
    @info "Phase 28 results written" path=out_path
    return out_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
