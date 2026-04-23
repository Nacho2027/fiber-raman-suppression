# scripts/research/phases/phase34/continuation_dispersion_pairs.jl
#
# Focused Phase 34 follow-up:
# compare `:none` vs `:dispersion` trust-region PCG on continuation-style
# starts for a short bounded ladder of SMF-28 targets.
#
# This script exists because the bounded reruns showed:
#   - path quality matters more than preconditioning alone
#   - `:dispersion` is the only preconditioner that still looks promising
#   - `:dct` is not earning its complexity on the tested bounded cases
#
# It evaluates two source→target transfers:
#   1. L = 0.5 m  -> 1.0 m,  P = 0.1 W, Nt request = 256, tw request = 10 ps
#   2. L = 1.0 m  -> 2.0 m,  P = 0.1 W, Nt request = 256, tw request = 10 ps
#
# For each pair:
#   - solve the source problem with L-BFGS
#   - build the target problem with setup_raman_problem
#   - interpolate the source phase onto the target grid when Nt/tw change
#   - run TR with `:none` and `:dispersion`
#   - save standard images for the source optimum and each TR target optimum
#   - write a summary markdown + JLD2 bundle under:
#       results/raman/phase34/continuation_dispersion_pairs/
#
# HEAVY-ISH but bounded. Prefer running on burst for reproducibility:
#
#   burst-ssh "cd fiber-raman-suppression && git pull && \
#              ~/bin/burst-run-heavy Q-phase34-contdisp \
#              'julia -t auto --project=. scripts/research/phases/phase34/continuation_dispersion_pairs.jl'"
#
# Do not run substantial Julia workloads bare on claude-code-host.

try using Revise catch end
using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "..", ".."))

using LinearAlgebra
using Printf
using Dates
using JLD2
using MultiModeNoise

include(joinpath(@__DIR__, "..", "..", "..", "lib", "determinism.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "standard_images.jl"))
include(joinpath(@__DIR__, "..", "..", "longfiber", "longfiber_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "trust_region", "trust_region_optimize.jl"))
include(joinpath(@__DIR__, "..", "..", "trust_region", "trust_region_preconditioner.jl"))
include(joinpath(@__DIR__, "..", "..", "trust_region", "trust_region_pcg.jl"))

ensure_deterministic_environment()

const P34C_OUTDIR = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "phase34", "continuation_dispersion_pairs")
const P34C_SUMMARY_MD = joinpath(P34C_OUTDIR, "SUMMARY.md")
const P34C_RESULTS_JLD2 = joinpath(P34C_OUTDIR, "pairs.jld2")

const P34C_PAIRS = [
    Dict{String,Any}(
        "tag" => "pair_L0p5_to_L1p0_P0p1",
        "L_source" => 0.5,
        "L_target" => 1.0,
        "P" => 0.1,
        "Nt" => 256,
        "time_window_ps" => 10.0,
    ),
    Dict{String,Any}(
        "tag" => "pair_L1p0_to_L2p0_P0p1",
        "L_source" => 1.0,
        "L_target" => 2.0,
        "P" => 0.1,
        "Nt" => 256,
        "time_window_ps" => 10.0,
    ),
]

function _solve_source(cfg::Dict{String,Any})
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = :SMF28,
        L_fiber = cfg["L_source"],
        P_cont = cfg["P"],
        Nt = cfg["Nt"],
        time_window = cfg["time_window_ps"],
        β_order = 3,
    )
    result = optimize_spectral_phase(
        uω0, deepcopy(fiber), sim, band_mask;
        φ0 = zeros(Float64, size(uω0)),
        max_iter = 40,
        log_cost = false,
        store_trace = false,
    )
    save_standard_set(
        result.minimizer, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag = "$(cfg["tag"])_source_lbfgs",
        fiber_name = "SMF28",
        L_m = cfg["L_source"],
        P_W = cfg["P"],
        output_dir = P34C_OUTDIR,
    )
    return (uω0=uω0, fiber=fiber, sim=sim, band_mask=band_mask,
            Δf=Δf, raman_threshold=raman_threshold, result=result)
end

function _build_target(cfg::Dict{String,Any})
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = :SMF28,
        L_fiber = cfg["L_target"],
        P_cont = cfg["P"],
        Nt = cfg["Nt"],
        time_window = cfg["time_window_ps"],
        β_order = 3,
    )
    return (uω0=uω0, fiber=fiber, sim=sim, band_mask=band_mask,
            Δf=Δf, raman_threshold=raman_threshold)
end

function _continuation_init(source, target)
    phi_src = vec(copy(source.result.minimizer))
    Nt_src = source.sim["Nt"]
    tw_src = source.sim["time_window"]
    Nt_tgt = target.sim["Nt"]
    tw_tgt = target.sim["time_window"]
    phi_tgt = longfiber_interpolate_phi(phi_src, Nt_src, tw_src, Nt_tgt, tw_tgt)
    return vec(phi_tgt)
end

function _run_tr_variant(cfg::Dict{String,Any}, target, phi_init::Vector{Float64},
                         variant::Symbol)
    M = variant === :dispersion ? build_dispersion_precond(target.sim) : nothing
    solver = PreconditionedCGSolver(preconditioner = variant, max_iter = 20, K_dct = 16)
    result = optimize_spectral_phase_tr(
        target.uω0, deepcopy(target.fiber), target.sim, target.band_mask;
        φ0 = phi_init,
        solver = solver,
        M = M,
        max_iter = 10,
        Δ0 = 0.5,
        Δ_max = 10.0,
        Δ_min = 1e-6,
        g_tol = 1e-5,
        H_tol = -1e-6,
        λ_gdd = 0.0,
        λ_boundary = 0.0,
        log_cost = false,
        lambda_probe_cadence = 100,
    )
    save_standard_set(
        result.minimizer, target.uω0, target.fiber, target.sim,
        target.band_mask, target.Δf, target.raman_threshold;
        tag = "$(cfg["tag"])_$(String(variant))",
        fiber_name = "SMF28",
        L_m = cfg["L_target"],
        P_W = cfg["P"],
        output_dir = P34C_OUTDIR,
    )
    return result
end

function _accepted_rhos(result)
    return [r.rho for r in result.telemetry if r.step_accepted && isfinite(r.rho)]
end

function _summarize_pair(io, cfg::Dict{String,Any}, source, target, none_res, disp_res)
    println(io, "## ", cfg["tag"])
    println(io)
    println(io, @sprintf("- Source → target: `L = %.2f -> %.2f m`, `P = %.3f W`", cfg["L_source"], cfg["L_target"], cfg["P"]))
    println(io, @sprintf("- Requested grid: `Nt = %d`, `time_window = %.1f ps`", cfg["Nt"], cfg["time_window_ps"]))
    println(io, @sprintf("- Actual source grid: `Nt = %d`, `time_window = %.1f ps`", source.sim["Nt"], source.sim["time_window"]))
    println(io, @sprintf("- Actual target grid: `Nt = %d`, `time_window = %.1f ps`", target.sim["Nt"], target.sim["time_window"]))
    println(io, @sprintf("- Source L-BFGS: `J = %.6e`, `iters = %d`", source.result.minimum, source.result.iterations))
    println(io)
    println(io, "| Variant | Exit | J_final | Iter | Accepted | Rejected | HVPs |")
    println(io, "|---------|------|---------:|-----:|---------:|---------:|-----:|")
    for (label, res) in [("none", none_res), ("dispersion", disp_res)]
        accepted = count(r -> r.step_accepted, res.telemetry)
        rejected = count(r -> !r.step_accepted, res.telemetry)
        println(io, @sprintf("| %s | %s | %.6e | %d | %d | %d | %d |",
            label, string(res.exit_code), res.J_final, res.iterations, accepted, rejected, res.hvps_total))
        println(io)
        println(io, @sprintf("Accepted-step rho (%s): `%s`",
            label, string(round.(Float64.(_accepted_rhos(res)); digits=6))))
        println(io)
    end
end

function main()
    mkpath(P34C_OUTDIR)
    pair_rows = Vector{Dict{String,Any}}()

    open(P34C_SUMMARY_MD, "w") do io
        println(io, "# Phase 34 Continuation vs Dispersion Pair Summary")
        println(io)
        println(io, "Generated: ", Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"))
        println(io)
        println(io, "This script runs the focused bounded Phase 34 follow-up:")
        println(io, "- continuation-style starts only")
        println(io, "- `:none` vs `:dispersion` only")
        println(io, "- source optima generated by L-BFGS, target optima by trust-region PCG")
        println(io)

        for cfg in P34C_PAIRS
            source = _solve_source(cfg)
            target = _build_target(cfg)
            phi_init = _continuation_init(source, target)
            none_res = _run_tr_variant(cfg, target, phi_init, :none)
            disp_res = _run_tr_variant(cfg, target, phi_init, :dispersion)
            _summarize_pair(io, cfg, source, target, none_res, disp_res)

            push!(pair_rows, Dict{String,Any}(
                "tag" => cfg["tag"],
                "L_source" => cfg["L_source"],
                "L_target" => cfg["L_target"],
                "P" => cfg["P"],
                "Nt_requested" => cfg["Nt"],
                "time_window_requested_ps" => cfg["time_window_ps"],
                "Nt_source" => source.sim["Nt"],
                "time_window_source_ps" => source.sim["time_window"],
                "Nt_target" => target.sim["Nt"],
                "time_window_target_ps" => target.sim["time_window"],
                "source_lbfgs_J" => source.result.minimum,
                "source_lbfgs_iters" => source.result.iterations,
                "none_exit" => string(none_res.exit_code),
                "none_J_final" => none_res.J_final,
                "none_iters" => none_res.iterations,
                "none_accepted_rhos" => _accepted_rhos(none_res),
                "disp_exit" => string(disp_res.exit_code),
                "disp_J_final" => disp_res.J_final,
                "disp_iters" => disp_res.iterations,
                "disp_accepted_rhos" => _accepted_rhos(disp_res),
            ))
        end
    end

    jldsave(P34C_RESULTS_JLD2; pairs = pair_rows)
    @info "phase34 continuation/dispersion pair summary written" summary=P34C_SUMMARY_MD jld2=P34C_RESULTS_JLD2
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
