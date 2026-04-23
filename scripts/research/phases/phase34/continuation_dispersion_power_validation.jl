# scripts/research/phases/phase34/continuation_dispersion_power_validation.jl
#
# Bounded Phase 34 validation sweep:
# repeat the short continuation ladder at a few nearby powers to see whether
# the `:dispersion` advantage is stable or just local to one setting.
#
# Ladder per power:
#   1. base solve at L = 0.5 m with L-BFGS
#   2. trust-region continuation step at L = 1.0 m
#   3. trust-region continuation step at L = 2.0 m
#
# Compared variants:
#   - :none
#   - :dispersion
#
# Fixed settings:
#   - powers = [0.08, 0.10, 0.12] W
#   - requested Nt = 256
#   - requested time_window = 10 ps
#
# Output:
#   results/raman/phase34/continuation_dispersion_power_validation/

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

const P34PV_RUN_ID = let rid = get(ENV, "P34PV_RUN_ID", "default")
    isempty(strip(rid)) ? "default" : strip(rid)
end
const P34PV_OUTROOT = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "phase34", "continuation_dispersion_power_validation")
const P34PV_OUTDIR = P34PV_RUN_ID == "default" ? P34PV_OUTROOT : joinpath(P34PV_OUTROOT, P34PV_RUN_ID)
const P34PV_SUMMARY_MD = joinpath(P34PV_OUTDIR, "SUMMARY.md")
const P34PV_RESULTS_JLD2 = joinpath(P34PV_OUTDIR, "power_validation.jld2")

function _parse_powers()
    raw = get(ENV, "P34PV_POWERS", "")
    isempty(strip(raw)) && return [0.08, 0.10, 0.12]
    vals = Float64[]
    for piece in split(raw, ",")
        s = strip(piece)
        isempty(s) && continue
        push!(vals, parse(Float64, s))
    end
    isempty(vals) && error("P34PV_POWERS was set but no valid floats were parsed: '$raw'")
    return vals
end

const P34PV_POWERS = _parse_powers()
const P34PV_LENGTHS = [0.5, 1.0, 2.0]
const P34PV_VARIANTS = [:none, :dispersion]
const P34PV_TR_MAX_ITER = parse(Int, get(ENV, "P34PV_TR_MAX_ITER", "10"))
const P34PV_PCG_MAX_ITER = parse(Int, get(ENV, "P34PV_PCG_MAX_ITER", "20"))

function _build_case(P_W::Float64, L_fiber::Float64)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = :SMF28,
        L_fiber = L_fiber,
        P_cont = P_W,
        Nt = 256,
        time_window = 10.0,
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

function _solve_base_lbfgs(P_W::Float64, base_case)
    result = optimize_spectral_phase(
        base_case.uω0, deepcopy(base_case.fiber), base_case.sim, base_case.band_mask;
        φ0 = zeros(Float64, size(base_case.uω0)),
        max_iter = 40,
        log_cost = false,
        store_trace = false,
    )
    tag = replace(@sprintf("power_validation_P%.2f_base_lbfgs", P_W), "." => "p")
    save_standard_set(
        result.minimizer, base_case.uω0, base_case.fiber, base_case.sim,
        base_case.band_mask, base_case.Δf, base_case.raman_threshold;
        tag = tag,
        fiber_name = "SMF28",
        L_m = P34PV_LENGTHS[1],
        P_W = P_W,
        output_dir = P34PV_OUTDIR,
    )
    return result
end

function _run_variant_on_case(P_W::Float64, variant::Symbol, target_case, phi_init::Vector{Float64}, source_L::Float64, target_L::Float64)
    M = variant === :dispersion ? build_dispersion_precond(target_case.sim) : nothing
    solver = PreconditionedCGSolver(preconditioner = variant, max_iter = P34PV_PCG_MAX_ITER, K_dct = 16)
    result = optimize_spectral_phase_tr(
        target_case.uω0, deepcopy(target_case.fiber), target_case.sim, target_case.band_mask;
        φ0 = phi_init,
        solver = solver,
        M = M,
        max_iter = P34PV_TR_MAX_ITER,
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
    tag = replace(@sprintf("power_validation_P%.2f_%s_L%.1f_to_L%.1f", P_W, String(variant), source_L, target_L), "." => "p")
    save_standard_set(
        result.minimizer, target_case.uω0, target_case.fiber, target_case.sim,
        target_case.band_mask, target_case.Δf, target_case.raman_threshold;
        tag = tag,
        fiber_name = "SMF28",
        L_m = target_case.fiber["L"],
        P_W = P_W,
        output_dir = P34PV_OUTDIR,
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

function _run_power_ladder(P_W::Float64)
    base_case = _build_case(P_W, P34PV_LENGTHS[1])
    base_result = _solve_base_lbfgs(P_W, base_case)

    variant_phi = Dict{Symbol,Vector{Float64}}(
        variant => vec(copy(base_result.minimizer)) for variant in P34PV_VARIANTS
    )
    variant_case = Dict{Symbol,Any}(variant => base_case for variant in P34PV_VARIANTS)
    ladder_rows = Dict{Symbol,Vector{Dict{String,Any}}}(variant => Dict{String,Any}[] for variant in P34PV_VARIANTS)

    for idx in 2:length(P34PV_LENGTHS)
        source_L = P34PV_LENGTHS[idx - 1]
        target_L = P34PV_LENGTHS[idx]
        target_case = _build_case(P_W, target_L)
        for variant in P34PV_VARIANTS
            phi_init = _interpolate_between_cases(variant_phi[variant], variant_case[variant], target_case)
            result = _run_variant_on_case(P_W, variant, target_case, phi_init, source_L, target_L)
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

    hardest_none = ladder_rows[:none][end]
    hardest_disp = ladder_rows[:dispersion][end]
    return Dict{String,Any}(
        "P_W" => P_W,
        "base_lbfgs_J" => base_result.minimum,
        "base_lbfgs_iters" => base_result.iterations,
        "ladder_rows" => ladder_rows,
        "hardest_final_J_none" => hardest_none["J_final"],
        "hardest_final_J_dispersion" => hardest_disp["J_final"],
        "hardest_accept_none" => hardest_none["accepted"],
        "hardest_accept_dispersion" => hardest_disp["accepted"],
    )
end

function _write_variant_rows(io, rows)
    println(io, "| Rung | Actual grid | Exit | J_final | Accepted | Rejected | HVPs |")
    println(io, "|------|-------------|------|---------:|---------:|---------:|-----:|")
    for row in rows
        grid = @sprintf("Nt=%d, tw=%.1f ps", row["Nt_actual"], row["time_window_actual_ps"])
        println(io, @sprintf("| %.1f -> %.1f m | %s | %s | %.6e | %d | %d | %d |",
            row["L_source"], row["L_target"], grid, row["exit"], row["J_final"],
            row["accepted"], row["rejected"], row["hvps_total"]))
    end
    println(io)
end

function main()
    mkpath(P34PV_OUTDIR)
    power_rows = [_run_power_ladder(P_W) for P_W in P34PV_POWERS]

    open(P34PV_SUMMARY_MD, "w") do io
        println(io, "# Phase 34 Power Validation Summary")
        println(io)
        println(io, "Generated: ", Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"))
        println(io)
        println(io, "This bounded validation reruns the short continuation ladder at nearby powers to test whether the `:dispersion` advantage is stable.")
        println(io, @sprintf("- TR max_iter = %d, PCG max_iter = %d", P34PV_TR_MAX_ITER, P34PV_PCG_MAX_ITER))
        println(io)
        println(io, "## Proposed success metric")
        println(io)
        println(io, "Primary metric:")
        println(io, "- final `J` on the hardest rung (`1.0 -> 2.0 m`), because that is the closest bounded proxy for whether the method is buying better suppression where the path is most stressed.")
        println(io)
        println(io, "Secondary metrics:")
        println(io, "- accepted-step count on the hardest rung, as a reliability proxy")
        println(io, "- accepted-step `rho`, as a local model-quality proxy")
        println(io, "- HVP count, as a bounded inner-solve cost proxy")
        println(io)
        println(io, "A power setting counts as a `:dispersion` win only if it improves the primary metric; the others are supporting evidence, not substitutes.")
        println(io)
        println(io, "## Hardest-rung summary")
        println(io)
        println(io, "| Power [W] | none J_final | dispersion J_final | Better final J | none accepted | dispersion accepted | More accepted |")
        println(io, "|-----------:|-------------:|-------------------:|----------------|--------------:|--------------------:|---------------|")
        for row in power_rows
            better = row["hardest_final_J_dispersion"] < row["hardest_final_J_none"] ? "dispersion" : "none"
            more_acc = row["hardest_accept_dispersion"] > row["hardest_accept_none"] ? "dispersion" :
                       row["hardest_accept_dispersion"] < row["hardest_accept_none"] ? "none" : "tie"
            println(io, @sprintf("| %.2f | %.6e | %.6e | %s | %d | %d | %s |",
                row["P_W"], row["hardest_final_J_none"], row["hardest_final_J_dispersion"], better,
                row["hardest_accept_none"], row["hardest_accept_dispersion"], more_acc))
        end
        println(io)

        for row in power_rows
            println(io, "## Power `", @sprintf("%.2f", row["P_W"]), " W`")
            println(io)
            println(io, @sprintf("- Base `0.5 m` L-BFGS: `J = %.6e` in `%d` iterations", row["base_lbfgs_J"], row["base_lbfgs_iters"]))
            println(io)
            println(io, "### Variant `:none`")
            println(io)
            _write_variant_rows(io, row["ladder_rows"][:none])
            println(io, "### Variant `:dispersion`")
            println(io)
            _write_variant_rows(io, row["ladder_rows"][:dispersion])
        end

        disp_primary_wins = count(row -> row["hardest_final_J_dispersion"] < row["hardest_final_J_none"], power_rows)
        println(io, "## Validation takeaway")
        println(io)
        println(io, @sprintf("- `:dispersion` improved the hardest-rung final objective in `%d/%d` nearby power settings.", disp_primary_wins, length(power_rows)))
        println(io, "- If that primary-metric pattern holds, `:dispersion` is the right default Phase 34 comparison branch and `:none` remains the baseline.")
    end

    jldsave(P34PV_RESULTS_JLD2; power_rows = power_rows)
    @info "phase34 power validation summary written" summary=P34PV_SUMMARY_MD jld2=P34PV_RESULTS_JLD2
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
