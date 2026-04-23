# scripts/research/phases/phase34/continuation_dispersion_ladder.jl
#
# Short Phase 34 continuation-ladder benchmark:
# compare `:none` vs `:dispersion` trust-region PCG across a small sequence
# of increasingly hard SMF-28 targets, carrying each variant's previous-rung
# solution forward as the next starting point.
#
# Ladder:
#   1. base solve at L = 0.5 m with L-BFGS
#   2. trust-region target at L = 1.0 m
#   3. trust-region target at L = 2.0 m
#
# Fixed settings:
#   - P = 0.1 W
#   - requested Nt = 256
#   - requested time_window = 10 ps
#
# Output:
#   results/raman/phase34/continuation_dispersion_ladder/
#
# HEAVY-ISH but bounded. Prefer burst for durable runs:
#
#   burst-ssh "cd fiber-raman-suppression && git pull && \
#              ~/bin/burst-run-heavy Q-phase34-contladder \
#              'julia -t auto --project=. scripts/research/phases/phase34/continuation_dispersion_ladder.jl'"

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

const P34L_OUTDIR = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "phase34", "continuation_dispersion_ladder")
const P34L_SUMMARY_MD = joinpath(P34L_OUTDIR, "SUMMARY.md")
const P34L_RESULTS_JLD2 = joinpath(P34L_OUTDIR, "ladder.jld2")

const P34L_BASE = Dict{String,Any}(
    "fiber_preset" => :SMF28,
    "P" => 0.1,
    "Nt" => 256,
    "time_window_ps" => 10.0,
)

const P34L_LENGTHS = [0.5, 1.0, 2.0]
const P34L_VARIANTS = [:none, :dispersion]

function _build_case(L_fiber::Float64)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = P34L_BASE["fiber_preset"],
        L_fiber = L_fiber,
        P_cont = P34L_BASE["P"],
        Nt = P34L_BASE["Nt"],
        time_window = P34L_BASE["time_window_ps"],
        β_order = 3,
    )
    return (uω0=uω0, fiber=fiber, sim=sim, band_mask=band_mask,
            Δf=Δf, raman_threshold=raman_threshold)
end

function _interpolate_between_cases(phi_src::AbstractVector, source_case, target_case)
    return vec(longfiber_interpolate_phi(
        vec(phi_src),
        source_case.sim["Nt"],
        source_case.sim["time_window"],
        target_case.sim["Nt"],
        target_case.sim["time_window"],
    ))
end

function _solve_base_lbfgs(base_case)
    result = optimize_spectral_phase(
        base_case.uω0, deepcopy(base_case.fiber), base_case.sim, base_case.band_mask;
        φ0 = zeros(Float64, size(base_case.uω0)),
        max_iter = 40,
        log_cost = false,
        store_trace = false,
    )
    save_standard_set(
        result.minimizer, base_case.uω0, base_case.fiber, base_case.sim,
        base_case.band_mask, base_case.Δf, base_case.raman_threshold;
        tag = "ladder_base_lbfgs",
        fiber_name = String(P34L_BASE["fiber_preset"]),
        L_m = P34L_LENGTHS[1],
        P_W = P34L_BASE["P"],
        output_dir = P34L_OUTDIR,
    )
    return result
end

function _run_variant_on_case(variant::Symbol, target_case, phi_init::Vector{Float64}, tag::String)
    M = variant === :dispersion ? build_dispersion_precond(target_case.sim) : nothing
    solver = PreconditionedCGSolver(preconditioner = variant, max_iter = 20, K_dct = 16)
    result = optimize_spectral_phase_tr(
        target_case.uω0, deepcopy(target_case.fiber), target_case.sim, target_case.band_mask;
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
        result.minimizer, target_case.uω0, target_case.fiber, target_case.sim,
        target_case.band_mask, target_case.Δf, target_case.raman_threshold;
        tag = tag,
        fiber_name = String(P34L_BASE["fiber_preset"]),
        L_m = target_case.fiber["L"],
        P_W = P34L_BASE["P"],
        output_dir = P34L_OUTDIR,
    )
    return result
end

function _accepted_rhos(result)
    return [r.rho for r in result.telemetry if r.step_accepted && isfinite(r.rho)]
end

function _count_steps(result)
    accepted = count(r -> r.step_accepted, result.telemetry)
    rejected = count(r -> !r.step_accepted, result.telemetry)
    return accepted, rejected
end

function _write_variant_section(io, variant::Symbol, rows)
    println(io, "## Variant `:", String(variant), "`")
    println(io)
    println(io, "| Rung | Actual grid | Exit | J_final | Iter | Accepted | Rejected | HVPs |")
    println(io, "|------|-------------|------|---------:|-----:|---------:|---------:|-----:|")
    for row in rows
        accepted, rejected = row["accepted"], row["rejected"]
        grid = @sprintf("Nt=%d, tw=%.1f ps", row["Nt_actual"], row["time_window_actual_ps"])
        println(io, @sprintf("| %.1f -> %.1f m | %s | %s | %.6e | %d | %d | %d | %d |",
            row["L_source"], row["L_target"], grid, row["exit"], row["J_final"],
            row["iters"], accepted, rejected, row["hvps_total"]))
        println(io)
        println(io, @sprintf("Accepted-step rho: `%s`",
            string(round.(Float64.(row["accepted_rhos"]); digits=6))))
        println(io)
    end
end

function main()
    mkpath(P34L_OUTDIR)

    base_case = _build_case(P34L_LENGTHS[1])
    base_result = _solve_base_lbfgs(base_case)

    variant_phi = Dict{Symbol,Vector{Float64}}(
        variant => vec(copy(base_result.minimizer)) for variant in P34L_VARIANTS
    )
    variant_case = Dict{Symbol,Any}(variant => base_case for variant in P34L_VARIANTS)
    ladder_rows = Dict{Symbol,Vector{Dict{String,Any}}}(variant => Dict{String,Any}[] for variant in P34L_VARIANTS)

    for idx in 2:length(P34L_LENGTHS)
        target_L = P34L_LENGTHS[idx]
        target_case = _build_case(target_L)
        source_L = P34L_LENGTHS[idx - 1]

        for variant in P34L_VARIANTS
            phi_init = _interpolate_between_cases(variant_phi[variant], variant_case[variant], target_case)
            tag = @sprintf("ladder_%s_L%.1f_to_L%.1f", String(variant), source_L, target_L)
            result = _run_variant_on_case(variant, target_case, phi_init, replace(tag, "." => "p"))
            accepted, rejected = _count_steps(result)
            push!(ladder_rows[variant], Dict{String,Any}(
                "L_source" => source_L,
                "L_target" => target_L,
                "Nt_actual" => target_case.sim["Nt"],
                "time_window_actual_ps" => target_case.sim["time_window"],
                "exit" => string(result.exit_code),
                "J_final" => result.J_final,
                "iters" => result.iterations,
                "accepted" => accepted,
                "rejected" => rejected,
                "hvps_total" => result.hvps_total,
                "accepted_rhos" => _accepted_rhos(result),
            ))
            variant_phi[variant] = vec(copy(result.minimizer))
            variant_case[variant] = target_case
        end
    end

    open(P34L_SUMMARY_MD, "w") do io
        println(io, "# Phase 34 Continuation Ladder Summary")
        println(io)
        println(io, "Generated: ", Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"))
        println(io)
        println(io, "Short continuation ladder benchmark:")
        println(io, "- base solve at `L = 0.5 m` with L-BFGS")
        println(io, "- trust-region continuation steps at `L = 1.0 m` and `L = 2.0 m`")
        println(io, "- fixed `P = 0.1 W`, requested `Nt = 256`, requested `time_window = 10 ps`")
        println(io, "- each variant carries its own previous-rung solution forward")
        println(io)
        println(io, @sprintf("- Base L-BFGS objective: `%.6e` in `%d` iterations", base_result.minimum, base_result.iterations))
        println(io)
        for variant in P34L_VARIANTS
            _write_variant_section(io, variant, ladder_rows[variant])
        end
        println(io, "## Interpretation")
        println(io)
        println(io, "- This benchmark is meant to test whether a small `:dispersion` advantage compounds across a short continuation path.")
        println(io, "- The comparison is intentionally narrow: `:none` vs `:dispersion` only.")
    end

    jldsave(P34L_RESULTS_JLD2;
        base_length_m = P34L_LENGTHS[1],
        base_lbfgs_J = base_result.minimum,
        base_lbfgs_iters = base_result.iterations,
        ladder_rows = ladder_rows,
    )

    @info "phase34 continuation ladder summary written" summary=P34L_SUMMARY_MD jld2=P34L_RESULTS_JLD2
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
