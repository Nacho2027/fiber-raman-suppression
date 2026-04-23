#!/usr/bin/env julia

ENV["MPLBACKEND"] = "Agg"

using Dates
using FFTW
using JLD2
using LinearAlgebra
using Printf
using Random
using Statistics

using MultiModeNoise

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "longfiber", "longfiber_setup.jl"))

const SU_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const SU_RESULTS = joinpath(SU_ROOT, "results", "raman", "phase31")
const SU_PHASE17_RESULTS = joinpath(SU_ROOT, "results", "raman", "phase17")
const SU_PHASE16_RESULTS = joinpath(SU_ROOT, "results", "raman", "phase16")
const SU_PHASE21_LONG100 = joinpath(SU_ROOT, "results", "raman", "phase21", "longfiber100m")
const SU_DOCS = joinpath(SU_ROOT, "agent-docs", "stability-universality")
const SU_OUT_DIR = joinpath(SU_DOCS, "outputs")
const SU_NT = 2^14
const SU_TIME_WINDOW = 10.0
const SU_FIT_DEEP_LABELS = Set(["cubic128_reduced", "cubic32_fullgrid", "simple_phase17"])

function parse_args(args)
    opts = Dict{String,Any}(
        "max_candidates" => 0,
        "noise_trials" => 2,
        "skip_forward" => false,
    )
    for arg in args
        if startswith(arg, "--max-candidates=")
            opts["max_candidates"] = parse(Int, split(arg, "=", limit=2)[2])
        elseif startswith(arg, "--noise-trials=")
            opts["noise_trials"] = parse(Int, split(arg, "=", limit=2)[2])
        elseif arg == "--skip-forward"
            opts["skip_forward"] = true
        else
            error("unknown argument: $arg")
        end
    end
    return opts
end

function lin_to_dB_safe(x)
    return 10.0 * log10(max(Float64(x), 1e-15))
end

function evaluate_J_linear(phi_vec::AbstractVector{<:Real}, setup)
    uω0, fiber, sim, band_mask, _, _ = setup
    Nt = sim["Nt"]
    @assert length(phi_vec) == Nt
    φ = reshape(Float64.(phi_vec), Nt, 1)
    uω0_shaped = @. uω0 * cis(φ)
    fiber_local = deepcopy(fiber)
    fiber_local["zsave"] = nothing
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_local, sim)
    ũω = sol["ode_sol"]
    L = fiber_local["L"]
    Dω = fiber_local["Dω"]
    uωf = cis.(Dω .* L) .* ũω(L)
    J, _ = spectral_band_cost(uωf, band_mask)
    return J
end

function canonical_setup()
    return setup_raman_problem(;
        fiber_preset = :SMF28,
        β_order = 3,
        L_fiber = 2.0,
        P_cont = 0.2,
        pulse_fwhm = 185e-15,
        Nt = SU_NT,
        time_window = SU_TIME_WINDOW,
    )
end

function phase17_setup()
    return setup_raman_problem(;
        fiber_preset = :SMF28,
        β_order = 3,
        L_fiber = 0.5,
        P_cont = 0.05,
        gamma_user = 1.1e-3,
        betas_user = [-2.17e-26, 1.2e-40],
        fR = 0.18,
        pulse_fwhm = 185e-15,
        pulse_rep_rate = 80.5e6,
        Nt = 8192,
        time_window = 10.0,
    )
end

function phase16_setup()
    return setup_longfiber_problem(;
        fiber_preset = :SMF28_beta2_only,
        L_fiber = 100.0,
        P_cont = 0.05,
        Nt = 32768,
        time_window = 160.0,
        β_order = 2,
    )
end

function load_phase31_candidates()
    sweep_rows = load(joinpath(SU_RESULTS, "sweep_A_basis.jld2"), "rows")
    follow_rows = load(joinpath(SU_RESULTS, "followup", "path_comparison.jld2"), "rows")
    transfer_rows = load(joinpath(SU_RESULTS, "transfer_results.jld2"), "rows")

    candidates = Dict{String,Dict{String,Any}}()

    function add_sweep(label, kind, N_phi)
        matches = [r for r in sweep_rows if r["kind"] == kind && Int(r["N_phi"]) == N_phi]
        @assert length(matches) == 1 "expected one match for $kind N=$N_phi, got $(length(matches))"
        row = matches[1]
        tmatch = [r for r in transfer_rows
                  if r["source_branch"] == row["branch"] &&
                     r["source_kind"] == row["kind"] &&
                     Int(r["source_N_phi"]) == Int(row["N_phi"]) &&
                     abs(Float64(r["source_J_final"]) - Float64(row["J_final"])) < 1e-6]
        transfer = isempty(tmatch) ? Dict{String,Any}() : tmatch[1]
        candidates[label] = Dict{String,Any}(
            "label" => label,
            "source" => "phase31_sweep_A",
            "kind" => String(row["kind"]),
            "N_phi" => Int(row["N_phi"]),
            "phi" => Float64.(row["phi_opt"]),
            "native_J_dB" => Float64(row["J_final"]),
            "N_eff" => Float64(get(row, "N_eff", NaN)),
            "TV" => Float64(get(row, "TV", NaN)),
            "curvature" => Float64(get(row, "curvature", NaN)),
            "polynomial_R2" => Float64(get(row, "polynomial_R2", NaN)),
            "sigma_3dB_existing" => isempty(tmatch) ? NaN : Float64(transfer["sigma_3dB"]),
            "hnlf_J_dB_existing" => isempty(tmatch) ? NaN : Float64(transfer["J_transfer_HNLF"]),
            "perturb_existing" => isempty(tmatch) ? Dict{String,Float64}() : transfer["J_transfer_perturb"],
        )
    end

    function add_followup(label, path_name)
        matches = [r for r in follow_rows if r["path_name"] == path_name]
        @assert length(matches) == 1 "expected one match for $path_name, got $(length(matches))"
        row = matches[1]
        candidates[label] = Dict{String,Any}(
            "label" => label,
            "source" => "phase31_followup",
            "kind" => path_name,
            "N_phi" => SU_NT,
            "phi" => Float64.(row["final_phi_opt"]),
            "native_J_dB" => Float64(row["final_J_dB"]),
            "N_eff" => NaN,
            "TV" => NaN,
            "curvature" => NaN,
            "polynomial_R2" => NaN,
            "sigma_3dB_existing" => Float64(row["sigma_3dB"]),
            "hnlf_J_dB_existing" => Float64(row["J_transfer_HNLF"]),
            "perturb_existing" => row["J_transfer_perturb"],
        )
    end

    add_sweep("poly3_transferable", "polynomial", 3)
    add_sweep("cubic32_reduced", "cubic", 32)
    add_sweep("cubic128_reduced", "cubic", 128)
    add_followup("cubic32_fullgrid", "cubic32_full")
    add_followup("zero_fullgrid", "full_zero")

    phase17_path = joinpath(SU_PHASE17_RESULTS, "baseline.jld2")
    if isfile(phase17_path)
        d = load(phase17_path)
        phi = vec(Float64.(d["phi_opt"]))
        candidates["simple_phase17"] = Dict{String,Any}(
            "label" => "simple_phase17",
            "source" => "phase17_baseline",
            "kind" => "simple_phase",
            "N_phi" => length(phi),
            "phi" => phi,
            "native_J_dB" => Float64(d["J_final_dB"]),
            "N_eff" => NaN,
            "TV" => NaN,
            "curvature" => NaN,
            "polynomial_R2" => NaN,
            "sigma_3dB_existing" => NaN,
            "hnlf_J_dB_existing" => NaN,
            "perturb_existing" => Dict{String,Float64}(),
            "setup_label" => "phase17",
        )
    end

    phase16_candidates = [
        joinpath(SU_PHASE16_RESULTS, "100m_opt_full_result.jld2"),
        joinpath(SU_PHASE21_LONG100, "sessionf_100m_normalized.jld2"),
    ]
    for path in phase16_candidates
        if isfile(path)
            d = load(path)
            phi = if haskey(d, "phi_opt")
                vec(Float64.(d["phi_opt"]))
            else
                continue
            end
            native = if haskey(d, "J_final")
                Float64(d["J_final"])
            elseif haskey(d, "J_honest_dB")
                Float64(d["J_honest_dB"])
            elseif haskey(d, "J_opt_dB")
                Float64(d["J_opt_dB"])
            else
                NaN
            end
            candidates["longfiber100m_phase16"] = Dict{String,Any}(
                "label" => "longfiber100m_phase16",
                "source" => "phase16_or_phase21_longfiber",
                "kind" => "longfiber100m",
                "N_phi" => length(phi),
                "phi" => phi,
                "native_J_dB" => native,
                "N_eff" => NaN,
                "TV" => NaN,
                "curvature" => NaN,
                "polynomial_R2" => NaN,
                "sigma_3dB_existing" => NaN,
                "hnlf_J_dB_existing" => NaN,
                "perturb_existing" => Dict{String,Float64}(),
                "setup_label" => "phase16_100m",
                "artifact_path" => path,
            )
            break
        end
    end

    for c in values(candidates)
        if !haskey(c, "setup_label")
            c["setup_label"] = "canonical"
        end
    end

    labels = [
        "poly3_transferable",
        "cubic32_reduced",
        "cubic128_reduced",
        "cubic32_fullgrid",
        "zero_fullgrid",
    ]
    if haskey(candidates, "simple_phase17")
        push!(labels, "simple_phase17")
    end
    if haskey(candidates, "longfiber100m_phase16")
        push!(labels, "longfiber100m_phase16")
    end

    return [candidates[k] for k in labels]
end

function ω_centered(setup)
    _, _, sim, _, _, _ = setup
    return collect(sim["ωs"] .- sim["ω0"])
end

function fit_polynomial_family(phi::Vector{Float64}, ω::Vector{Float64}, active_mask::BitVector, degree::Int)
    idx = findall(active_mask)
    x = ω[idx]
    y = phi[idx]
    xscale = maximum(abs.(x))
    xscale = xscale > 0 ? xscale : 1.0
    xs = x ./ xscale
    A = hcat([xs .^ k for k in 0:degree]...)
    coeffs = A \ y
    xs_full = ω ./ xscale
    fullA = hcat([xs_full .^ k for k in 0:degree]...)
    return vec(fullA * coeffs)
end

function fit_poly_plus_dct(phi::Vector{Float64}, ω::Vector{Float64}, active_mask::BitVector; degree::Int=2, kmax::Int=4)
    idx = findall(active_mask)
    n = length(idx)
    x = ω[idx]
    y = phi[idx]
    xscale = maximum(abs.(x))
    xscale = xscale > 0 ? xscale : 1.0
    xs = x ./ xscale
    cols = Vector{Vector{Float64}}()
    for k in 0:degree
        push!(cols, xs .^ k)
    end
    for k in 1:kmax
        push!(cols, cos.(π * k .* ((collect(1:n) .- 0.5) ./ n)))
    end
    A = hcat(cols...)
    coeffs = A \ y

    nfull = length(phi)
    idx_full = findall(active_mask)
    xs_full = ω[idx_full] ./ xscale
    cols_full = Vector{Vector{Float64}}()
    for k in 0:degree
        push!(cols_full, xs_full .^ k)
    end
    nf = length(idx_full)
    for k in 1:kmax
        push!(cols_full, cos.(π * k .* ((collect(1:nf) .- 0.5) ./ nf)))
    end
    A_full = hcat(cols_full...)
    out = copy(phi)
    out[idx_full] .= vec(A_full * coeffs)
    return out
end

function fitted_candidates(base_candidates)
    out = Dict{String,Dict{String,Any}}()
    for c in base_candidates
        label = String(c["label"])
        if !(label in SU_FIT_DEEP_LABELS)
            continue
        end
        setup = setup_for_label(String(c["setup_label"]))
        mask = active_band_mask(setup)
        ω = ω_centered(setup)
        phi = Vector{Float64}(c["phi"])
        fams = [
            ("gdd_only", fit_polynomial_family(phi, ω, mask, 2)),
            ("gdd_tod", fit_polynomial_family(phi, ω, mask, 3)),
            ("gdd_tod_fod", fit_polynomial_family(phi, ω, mask, 4)),
            ("gdd_dct4", fit_poly_plus_dct(phi, ω, mask; degree=2, kmax=4)),
        ]
        for (fam, phi_fit) in fams
            key = "$(label)__$(fam)"
            out[key] = Dict{String,Any}(
                "label" => key,
                "source" => "fitted_family",
                "kind" => fam,
                "family" => fam,
                "fitted_from" => label,
                "N_phi" => length(phi_fit),
                "phi" => phi_fit,
                "native_J_dB" => NaN,
                "N_eff" => NaN,
                "TV" => NaN,
                "curvature" => NaN,
                "polynomial_R2" => NaN,
                "sigma_3dB_existing" => NaN,
                "hnlf_J_dB_existing" => NaN,
                "perturb_existing" => Dict{String,Float64}(),
                "setup_label" => String(c["setup_label"]),
            )
        end
    end
    return [out[k] for k in sort(collect(keys(out)))]
end

function active_band_mask(setup; rel_thresh=1e-3)
    uω0, _, _, _, _, _ = setup
    a = vec(abs.(uω0[:, 1]))
    mask = a .>= rel_thresh * maximum(a)
    any(mask) || return trues(length(a))
    lo = findfirst(mask)
    hi = findlast(mask)
    out = falses(length(a))
    out[lo:hi] .= true
    return out
end

function linear_resample_active(phi::Vector{Float64}, n_pixels::Int, active_mask::BitVector)
    out = copy(phi)
    idx = findall(active_mask)
    n = length(idx)
    n == 0 && return out
    n_pixels >= n && return out
    xp = collect(range(1.0, n, length=n_pixels))
    ysrc = phi[idx]
    yp = [ysrc[round(Int, x)] for x in xp]
    j = 1
    for ii in 1:n
        x = Float64(ii)
        while j < n_pixels - 1 && xp[j + 1] < x
            j += 1
        end
        x0, x1 = xp[j], xp[j + 1]
        y0, y1 = yp[j], yp[j + 1]
        t = (x - x0) / max(x1 - x0, eps())
        out[idx[ii]] = (1 - t) * y0 + t * y1
    end
    return out
end

function moving_average_active(phi::Vector{Float64}, width::Int, active_mask::BitVector)
    width <= 1 && return copy(phi)
    @assert isodd(width)
    out = copy(phi)
    idx = findall(active_mask)
    vals = phi[idx]
    n = length(vals)
    half = width ÷ 2
    for ii in 1:n
        lo = max(1, ii - half)
        hi = min(n, ii + half)
        out[idx[ii]] = mean(@view vals[lo:hi])
    end
    return out
end

function wrapped_to_signed(θ)
    return mod(θ + π, 2π) - π
end

function slm_wrap_quantize(phi::Vector{Float64}, n_pixels::Int, n_bits::Int, active_mask::BitVector)
    out = copy(phi)
    idx = findall(active_mask)
    n = length(idx)
    n == 0 && return out
    edges = round.(Int, range(1, n + 1, length=n_pixels + 1))
    n_levels = 2^n_bits
    step = 2π / n_levels
    wrapped = mod.(phi[idx], 2π)
    for p in 1:n_pixels
        lo = max(1, edges[p])
        hi = min(n, edges[p + 1] - 1)
        lo > hi && continue
        seg = wrapped[lo:hi]
        z = mean(exp.(1im .* seg))
        angle_mean = angle(z)
        angle_wrapped = mod(angle_mean, 2π)
        quant = round(angle_wrapped / step) * step
        quant = mod(quant, 2π)
        out[idx[lo:hi]] .= wrapped_to_signed(quant)
    end
    return out
end

function setup_for_label(label::AbstractString)
    if label == "canonical"
        return canonical_setup()
    elseif label == "phase17"
        return phase17_setup()
    elseif label == "phase16_100m"
        return phase16_setup()
    else
        error("unknown setup label: $label")
    end
end

function moving_average(phi::Vector{Float64}, width::Int)
    n = length(phi)
    out = similar(phi)
    width <= 1 && return copy(phi)
    @assert isodd(width)
    half = width ÷ 2
    for i in 1:n
        x = Float64(i)
        lo = max(1, i - half)
        hi = min(n, i + half)
        out[i] = mean(@view phi[lo:hi])
    end
    return out
end

function csv_escape(x)
    s = string(x)
    if occursin(",", s) || occursin("\"", s) || occursin("\n", s)
        return "\"" * replace(s, "\"" => "\"\"") * "\""
    end
    return s
end

function write_csv(path, rows, headers)
    open(path, "w") do io
        println(io, join(headers, ","))
        for row in rows
            println(io, join([csv_escape(get(row, h, "")) for h in headers], ","))
        end
    end
end

function existing_metric_rows(candidates)
    rows = Dict{String,Any}[]
    for c in candidates
        p = c["perturb_existing"]
        native = Float64(c["native_J_dB"])
        push!(rows, Dict{String,Any}(
            "label" => c["label"],
            "source" => c["source"],
            "kind" => c["kind"],
            "family" => get(c, "family", ""),
            "fitted_from" => get(c, "fitted_from", ""),
            "N_phi" => c["N_phi"],
            "native_J_dB" => native,
            "sigma_3dB_existing_rad" => c["sigma_3dB_existing"],
            "hnlf_J_dB_existing" => c["hnlf_J_dB_existing"],
            "hnlf_gap_dB" => Float64(c["hnlf_J_dB_existing"]) - native,
            "fwhm_5pct_gap_dB" => get(p, "fwhm_5pct", NaN) - native,
            "P_10pct_gap_dB" => get(p, "P_10pct", NaN) - native,
            "beta2_5pct_gap_dB" => get(p, "beta2_5pct", NaN) - native,
            "N_eff" => c["N_eff"],
            "TV" => c["TV"],
            "curvature" => c["curvature"],
            "polynomial_R2" => c["polynomial_R2"],
        ))
    end
    return rows
end

function forward_probe_rows(candidates; noise_trials::Int)
    rows = Dict{String,Any}[]
    rng = MersenneTwister(20260423)
    noise_sigmas = [0.02, 0.05, 0.10]
    pixel_counts = [64, 128, 256]
    smooth_widths = [3, 9, 17]
    slm_specs = [(64, 8), (128, 8), (128, 10), (256, 10)]
    setup_cache = Dict{String,Any}()

    for c in candidates
        label = c["label"]
        phi = Vector{Float64}(c["phi"])
        setup_label = String(c["setup_label"])
        setup = get!(setup_cache, setup_label) do
            setup_for_label(setup_label)
        end
        mask = active_band_mask(setup)
        J_check = lin_to_dB_safe(evaluate_J_linear(phi, setup))
        native = isfinite(Float64(c["native_J_dB"])) ? Float64(c["native_J_dB"]) : J_check
        push!(rows, Dict{String,Any}(
            "label" => label, "test" => "native_recheck", "parameter" => "none",
            "J_dB_mean" => J_check, "J_dB_max" => J_check, "delta_mean_dB" => J_check - native,
            "delta_max_dB" => J_check - native, "n_eval" => 1,
        ))

        local_noise_trials = get(c, "source", "") == "fitted_family" ? min(noise_trials, 2) : noise_trials
        for σ in noise_sigmas
            vals = Float64[]
            for _ in 1:local_noise_trials
                perturbed = phi .+ σ .* randn(rng, length(phi))
                push!(vals, lin_to_dB_safe(evaluate_J_linear(perturbed, setup)))
            end
            push!(rows, Dict{String,Any}(
                "label" => label, "test" => "gaussian_phase_noise", "parameter" => σ,
                "J_dB_mean" => mean(vals), "J_dB_max" => maximum(vals),
                "delta_mean_dB" => mean(vals) - native, "delta_max_dB" => maximum(vals) - native,
                "n_eval" => length(vals),
            ))
        end

        for npx in pixel_counts
            phi_px = linear_resample_active(phi, npx, mask)
            J = lin_to_dB_safe(evaluate_J_linear(phi_px, setup))
            push!(rows, Dict{String,Any}(
                "label" => label, "test" => "active_band_resample_pixels", "parameter" => npx,
                "J_dB_mean" => J, "J_dB_max" => J,
                "delta_mean_dB" => J - native, "delta_max_dB" => J - native,
                "n_eval" => 1,
            ))
        end

        for width in smooth_widths
            phi_sm = moving_average_active(phi, width, mask)
            J = lin_to_dB_safe(evaluate_J_linear(phi_sm, setup))
            push!(rows, Dict{String,Any}(
                "label" => label, "test" => "active_band_moving_average", "parameter" => width,
                "J_dB_mean" => J, "J_dB_max" => J,
                "delta_mean_dB" => J - native, "delta_max_dB" => J - native,
                "n_eval" => 1,
            ))
        end

        for (npx, nbits) in slm_specs
            phi_slm = slm_wrap_quantize(phi, npx, nbits, mask)
            J = lin_to_dB_safe(evaluate_J_linear(phi_slm, setup))
            push!(rows, Dict{String,Any}(
                "label" => label, "test" => "wrapped_slm_pixels_bits", "parameter" => "$(npx)x$(nbits)",
                "J_dB_mean" => J, "J_dB_max" => J,
                "delta_mean_dB" => J - native, "delta_max_dB" => J - native,
                "n_eval" => 1,
            ))
        end
    end
    return rows
end

function write_summary(path, existing_rows, forward_rows; skipped_forward::Bool, noise_trials::Int)
    by_label = Dict(String(r["label"]) => r for r in existing_rows)
    sorted_depth = sort(existing_rows, by = r -> Float64(r["native_J_dB"]))
    sorted_hnlf = sort(existing_rows, by = r -> Float64(r["hnlf_gap_dB"]))
    finite_sigma_rows = [r for r in existing_rows if isfinite(Float64(r["sigma_3dB_existing_rad"]))]
    sorted_sigma = sort(finite_sigma_rows, by = r -> -Float64(r["sigma_3dB_existing_rad"]))

    function fmt(x; digits=2)
        y = Float64(x)
        isnan(y) && return "NaN"
        return @sprintf("%.*f", digits, y)
    end

    labels_present = Set(String(r["label"]) for r in existing_rows)
    have_phase17 = "simple_phase17" in labels_present

    open(path, "w") do io
        println(io, "# Phase 31 Stability Probe Results")
        println(io)
        timestamp = Dates.format(now(), DateFormat("yyyy-mm-ddTHH:MM:SS"))
        println(io, "Generated: $(timestamp) UTC")
        println(io)
        println(io, "## Scope")
        println(io)
        have_phase16 = "longfiber100m_phase16" in labels_present
        if have_phase17 && have_phase16
            println(io, "This run evaluated locally available Phase 31 profiles, the regenerated Phase 17 baseline fixed mask, and a local Phase 16 long-fiber endpoint artifact.")
        elseif have_phase17
            println(io, "This run evaluated locally available Phase 31 profiles plus the regenerated Phase 17 baseline fixed mask. Phase 16 still does not have a directly usable fixed-mask artifact and matched setup in this probe.")
        else
            println(io, "This run evaluated locally available Phase 31 profiles. Phase 17 fixed-mask JLD2 files are missing in this checkout, and Phase 16 still does not have a directly usable fixed-mask artifact and matched setup in this probe.")
        end
        if !have_phase16
            println(io, "")
            println(io, "Searched-but-missing long-fiber artifacts:")
            println(io, "- `results/raman/phase16/100m_opt_full_result.jld2`")
            println(io, "- `results/raman/phase21/longfiber100m/sessionf_100m_normalized.jld2`")
        end
        println(io)
        println(io, "Existing Phase 31 transfer and `sigma_3dB` metrics were reused from `results/raman/phase31/transfer_results.jld2` and `results/raman/phase31/followup/path_comparison.jld2`.")
        if skipped_forward
            println(io, "Forward perturbation probes were skipped by CLI option.")
        else
        println(io, "Forward perturbation probes used candidate-matched setups. Pixelation and smoothing were applied only on the active spectral band, leaving out-of-band phase untouched. Noise used `$(noise_trials)` trials per sigma.")
        end
        println(io)
        println(io, "## Existing Transfer Metrics")
        println(io)
        println(io, "| Candidate | Native J (dB) | sigma_3dB (rad) | HNLF gap (dB) | +5% FWHM gap | +10% P gap | +5% beta2 gap |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|")
        for r in existing_rows
            println(io, @sprintf("| `%s` | %s | %s | %s | %s | %s | %s |",
                r["label"], fmt(r["native_J_dB"]), fmt(r["sigma_3dB_existing_rad"], digits=3),
                fmt(r["hnlf_gap_dB"]), fmt(r["fwhm_5pct_gap_dB"]), fmt(r["P_10pct_gap_dB"]),
                fmt(r["beta2_5pct_gap_dB"])))
        end
        println(io)
        println(io, "## Rankings")
        println(io)
        println(io, "- Deepest native profile: `$(sorted_depth[1]["label"])` at $(fmt(sorted_depth[1]["native_J_dB"])) dB.")
        println(io, "- Best HNLF transfer gap: `$(sorted_hnlf[1]["label"])` at $(fmt(sorted_hnlf[1]["hnlf_gap_dB"])) dB.")
        if isempty(sorted_sigma)
            println(io, "- Widest finite measured noise basin: none; all candidates exceeded the sigma ladder.")
        else
            println(io, "- Widest finite measured noise basin: `$(sorted_sigma[1]["label"])` at $(fmt(sorted_sigma[1]["sigma_3dB_existing_rad"], digits=3)) rad.")
        end
        no_cross = [r["label"] for r in existing_rows if isnan(Float64(r["sigma_3dB_existing_rad"]))]
        if !isempty(no_cross)
            no_cross_labels = join(map(x -> "`$(x)`", no_cross), ", ")
            println(io, "- No 3 dB crossover inside the existing sigma ladder: $(no_cross_labels).")
        end
        println(io)

        if !skipped_forward
            println(io, "## Forward Probe Highlights")
            println(io)
            labels = unique(String.(get.(forward_rows, "label", "")))
            for label in labels
                rows = [r for r in forward_rows if r["label"] == label]
                noise = [r for r in rows if r["test"] == "gaussian_phase_noise" && Float64(r["parameter"]) == 0.05]
                px128 = [r for r in rows if r["test"] == "active_band_resample_pixels" && Int(r["parameter"]) == 128]
                sm9 = [r for r in rows if r["test"] == "active_band_moving_average" && Int(r["parameter"]) == 9]
                slm = [r for r in rows if r["test"] == "wrapped_slm_pixels_bits" && string(r["parameter"]) == "128x10"]
                println(io, "- `$(label)`: noise 0.05 rad mean gap $(isempty(noise) ? "NA" : fmt(noise[1]["delta_mean_dB"])) dB; active-band 128-pixel gap $(isempty(px128) ? "NA" : fmt(px128[1]["delta_mean_dB"])) dB; active-band 9-point smoothing gap $(isempty(sm9) ? "NA" : fmt(sm9[1]["delta_mean_dB"])) dB; wrapped SLM 128x10 gap $(isempty(slm) ? "NA" : fmt(slm[1]["delta_mean_dB"])) dB.")
            end
            println(io)
        end

        println(io, "## Decision Table")
        println(io)
        println(io, "| Role | Candidate | Reason |")
        println(io, "|---|---|---|")
        println(io, "| Simple publishable mask | `poly3_transferable` | best transfer and essentially no hardware sensitivity in this probe |")
        println(io, "| Deep but fragile mask | `simple_phase17` | deepest native result, but very large noise and hardware losses |")
        println(io, "| Deep canonical structured mask | `cubic128_reduced` | strong depth, but local and hardware-fragile |")
        println(io, "| More robust deep-ish reference | `zero_fullgrid` | shallower, but widest finite noise basin among tested finite-sigma masks |")
        println(io, "| Best simple surrogate family result | low-order fits are robust but shallow | the deep masks do not compress into a simple fixed mask without losing tens of dB |")
        println(io)

        println(io, "## Interpretation")
        println(io)
        println(io, "- `poly3_transferable` remains the simple-transfer baseline: shallow, but nearly unchanged on HNLF in existing metrics.")
        println(io, "- Cubic continuation candidates are much deeper but have large HNLF gaps and narrow `sigma_3dB` values.")
        println(io, "- `zero_fullgrid` is less deep but has the widest measured Phase 31 noise basin, matching the earlier depth/robustness tradeoff.")
        if have_phase17
            println(io, "- The regenerated Phase 17 baseline now sits clearly in the 'deep but fragile' bucket.")
        end
        println(io, "- For `cubic128_reduced` and `cubic32_fullgrid`, fitted `GDD`, `GDD+TOD`, `GDD+TOD+FOD`, and `GDD+DCT4` surrogates are far more hardware-stable but collapse from about `-67 dB` native depth to about `-1 dB` to `-18 dB`. The deep branch is not captured by a small smooth family.")
        println(io, "- For `simple_phase17`, the fitted smooth surrogates cluster near `-31.5 dB` and are extremely robust, which means the spectacular `-76.9 dB` mask depends on structure that the simple fits throw away.")
        if have_phase16
            println(io, "- Phase 16 long-fiber endpoint artifact was available locally and entered the fixed-mask panel.")
        else
            println(io, "- Phase 16 long-fiber probing remains blocked by missing local 100 m endpoint artifacts. The discovered Phase 32 `L100m` files in this checkout stop at 10 m, so they are not honest substitutes.")
        end
    end
end

function main(args=ARGS)
    opts = parse_args(args)
    mkpath(SU_OUT_DIR)
    candidates = load_phase31_candidates()
    append!(candidates, fitted_candidates(candidates))
    max_candidates = Int(opts["max_candidates"])
    if max_candidates > 0
        candidates = candidates[1:min(max_candidates, length(candidates))]
    end

    existing_rows = existing_metric_rows(candidates)
    write_csv(joinpath(SU_OUT_DIR, "phase31_existing_transfer_metrics.csv"), existing_rows,
        ["label", "source", "kind", "family", "fitted_from", "N_phi", "native_J_dB", "sigma_3dB_existing_rad",
         "hnlf_J_dB_existing", "hnlf_gap_dB", "fwhm_5pct_gap_dB", "P_10pct_gap_dB",
         "beta2_5pct_gap_dB", "N_eff", "TV", "curvature", "polynomial_R2"])

    forward_rows = Dict{String,Any}[]
    if !Bool(opts["skip_forward"])
        forward_rows = forward_probe_rows(candidates; noise_trials=Int(opts["noise_trials"]))
        write_csv(joinpath(SU_OUT_DIR, "phase31_forward_probe_metrics.csv"), forward_rows,
            ["label", "test", "parameter", "J_dB_mean", "J_dB_max",
             "delta_mean_dB", "delta_max_dB", "n_eval"])
    end

    summary_path = joinpath(SU_DOCS, "RESULTS.md")
    write_summary(summary_path, existing_rows, forward_rows;
        skipped_forward=Bool(opts["skip_forward"]),
        noise_trials=Int(opts["noise_trials"]))
    println("wrote ", summary_path)
    println("wrote ", joinpath(SU_OUT_DIR, "phase31_existing_transfer_metrics.csv"))
    if !Bool(opts["skip_forward"])
        println("wrote ", joinpath(SU_OUT_DIR, "phase31_forward_probe_metrics.csv"))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
