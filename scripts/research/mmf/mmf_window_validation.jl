"""
Targeted MMF time-window validation.

The Phase 36 MMF baseline found large apparent suppression in the threshold and
aggressive GRIN-50 regimes, but the trust diagnostics marked the optimized
outputs as boundary-corrupted. This driver reruns only those unresolved regimes
with deliberately larger temporal windows. It is a validation/closure campaign,
not a new MMF science direction.

Run on burst:

    julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl

Useful environment overrides:

    MMF_VALIDATION_CASES=threshold,aggressive
    MMF_VALIDATION_MAX_ITER=6
    MMF_VALIDATION_THRESHOLD_TW=64
    MMF_VALIDATION_THRESHOLD_NT=8192
    MMF_VALIDATION_AGGRESSIVE_TW=96
    MMF_VALIDATION_AGGRESSIVE_NT=16384
"""

ENV["MPLBACKEND"] = "Agg"

using Dates
using Logging
using Printf

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))

const SAVE_DIR = get(ENV, "MMF_VALIDATION_SAVE_DIR",
    joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase36_window_validation"))
const DEFAULT_SEED = 42

function _env_int(name::AbstractString, default::Int)
    return parse(Int, get(ENV, name, string(default)))
end

function _env_float(name::AbstractString, default::Float64)
    return parse(Float64, get(ENV, name, string(default)))
end

function _case_configs()
    return Dict(
        "threshold" => (
            name = "threshold",
            L_fiber = 2.0,
            P_cont = 0.20,
            time_window = _env_float("MMF_VALIDATION_THRESHOLD_TW", 64.0),
            Nt = _env_int("MMF_VALIDATION_THRESHOLD_NT", 8192),
        ),
        "aggressive" => (
            name = "aggressive",
            L_fiber = 2.0,
            P_cont = 0.50,
            time_window = _env_float("MMF_VALIDATION_AGGRESSIVE_TW", 96.0),
            Nt = _env_int("MMF_VALIDATION_AGGRESSIVE_NT", 16384),
        ),
    )
end

function _selected_cases()
    configs = _case_configs()
    requested = split(get(ENV, "MMF_VALIDATION_CASES", "threshold,aggressive"), ",")
    names = [strip(x) for x in requested if !isempty(strip(x))]
    unknown = setdiff(names, collect(keys(configs)))
    if !isempty(unknown)
        error("unknown MMF validation case(s): $(join(unknown, ", "))")
    end
    return [configs[name] for name in names]
end

function _quality_label(run)
    if !run.trust_opt.boundary_ok
        return "invalid-window"
    elseif run.J_ref_dB <= -50 || run.improvement_dB < 1.0
        return "no_headroom"
    elseif run.J_ref_dB <= -45 || run.improvement_dB < 3.0
        return "borderline"
    else
        return "meaningful"
    end
end

function _record_failure(cfg, err)
    return (
        config_name = cfg.name,
        status = "failed",
        quality = "failed",
        L_fiber = cfg.L_fiber,
        P_cont = cfg.P_cont,
        Nt_used = cfg.Nt,
        time_window_used_ps = cfg.time_window,
        time_window_recommended_ps = NaN,
        λ_gdd = cfg.λ_gdd,
        λ_boundary = cfg.λ_boundary,
        J_ref_dB = NaN,
        J_opt_dB = NaN,
        improvement_dB = NaN,
        edge_fraction = NaN,
        input_edge_fraction = NaN,
        output_edge_fraction = NaN,
        boundary_ok = false,
        input_boundary_ok = false,
        output_boundary_ok = false,
        error = sprint(showerror, err),
    )
end

function _record_success(cfg, run)
    return (
        config_name = cfg.name,
        status = "ok",
        quality = _quality_label(run),
        L_fiber = cfg.L_fiber,
        P_cont = cfg.P_cont,
        Nt_used = run.setup.sim["Nt"],
        time_window_used_ps = run.setup.sim["time_window"],
        time_window_recommended_ps = run.setup.window_recommendation.time_window_ps,
        λ_gdd = cfg.λ_gdd,
        λ_boundary = cfg.λ_boundary,
        J_ref_dB = run.J_ref_dB,
        J_opt_dB = run.J_final_lin_dB,
        improvement_dB = run.improvement_dB,
        edge_fraction = run.trust_opt.boundary_edge_fraction,
        input_edge_fraction = run.trust_opt.input_boundary_edge_fraction,
        output_edge_fraction = run.trust_opt.output_boundary_edge_fraction,
        boundary_ok = run.trust_opt.boundary_ok,
        input_boundary_ok = run.trust_opt.input_boundary_ok,
        output_boundary_ok = run.trust_opt.output_boundary_ok,
        error = "",
    )
end

function _write_summary(rows)
    mkpath(SAVE_DIR)
    path = joinpath(SAVE_DIR, "mmf_window_validation_summary.md")
    open(path, "w") do io
        println(io, "# MMF Window Validation")
        println(io)
        println(io, @sprintf(
            "Generated %s UTC from `scripts/research/mmf/mmf_window_validation.jl`.",
            Dates.format(now(UTC), dateformat"yyyy-mm-dd HH:MM:SS"),
        ))
        println(io)
        println(io, "Purpose: decide whether the Phase 36 threshold/aggressive MMF gains survive larger temporal windows.")
        println(io)
        println(io, "| Config | Status | Quality | L [m] | P [W] | Nt | TW used [ps] | TW rec [ps] | lambda_gdd | lambda_boundary | J_ref [dB] | J_opt [dB] | Delta [dB] | Max edge frac | Input edge | Output edge | Boundary ok |")
        println(io, "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
        for r in rows
            println(io, @sprintf(
                "| %s | %s | %s | %.1f | %.2f | %d | %.1f | %.1f | %.2e | %.2e | %.2f | %.2f | %.2f | %.2e | %.2e | %.2e | %s |",
                r.config_name, r.status, r.quality, r.L_fiber, r.P_cont,
                r.Nt_used, r.time_window_used_ps, r.time_window_recommended_ps,
                r.λ_gdd, r.λ_boundary, r.J_ref_dB, r.J_opt_dB, r.improvement_dB, r.edge_fraction,
                r.input_edge_fraction, r.output_edge_fraction,
                string(r.boundary_ok),
            ))
        end
        failures = filter(r -> r.status != "ok", rows)
        if !isempty(failures)
            println(io)
            println(io, "## Failures")
            for r in failures
                println(io, "- `$(r.config_name)`: $(r.error)")
            end
        end
        println(io)
        println(io, "Decision rule:")
        println(io, "- If suppression remains large and `boundary_ok=true`, keep MMF active for cost/mode-launch follow-up.")
        println(io, "- If gains vanish or stay `invalid-window`, close the current Phase 36 MMF result as a numerical-window artifact and park deeper MMF.")
    end
    @info "Saved $path"
    return path
end

function run_mmf_window_validation()
    mkpath(SAVE_DIR)
    max_iter = _env_int("MMF_VALIDATION_MAX_ITER", 6)
    λ_gdd = _env_float("MMF_VALIDATION_LAMBDA_GDD", 0.0)
    λ_boundary = _env_float("MMF_VALIDATION_LAMBDA_BOUNDARY", 0.0)
    rows = NamedTuple[]
    @info "MMF window validation"
    @info @sprintf("Threads: %d", Threads.nthreads())
    @info @sprintf("max_iter=%d lambda_gdd=%.3e lambda_boundary=%.3e save_dir=%s",
        max_iter, λ_gdd, λ_boundary, SAVE_DIR)

    for cfg in _selected_cases()
        cfg = merge(cfg, (λ_gdd = λ_gdd, λ_boundary = λ_boundary))
        @info "="^72
        @info @sprintf(
            "Validation case %s: L=%.2fm P=%.3fW Nt=%d tw=%.1fps lambda_gdd=%.3e lambda_boundary=%.3e",
            cfg.name, cfg.L_fiber, cfg.P_cont, cfg.Nt, cfg.time_window,
            cfg.λ_gdd, cfg.λ_boundary,
        )
        @info "="^72
        try
            tag = @sprintf(
                "window_valid_%s_l%gm_p%gw_nt%d_tw%g",
                cfg.name, cfg.L_fiber, cfg.P_cont, cfg.Nt, cfg.time_window,
            )
            run = run_mmf_baseline(;
                preset = :GRIN_50,
                L_fiber = cfg.L_fiber,
                P_cont = cfg.P_cont,
                Nt = cfg.Nt,
                time_window = cfg.time_window,
                max_iter = max_iter,
                variant = :sum,
                λ_gdd = cfg.λ_gdd,
                λ_boundary = cfg.λ_boundary,
                seed = DEFAULT_SEED,
                save_dir = SAVE_DIR,
                tag = tag,
            )
            push!(rows, _record_success(cfg, run))
        catch err
            bt = catch_backtrace()
            @error "MMF validation case failed" cfg.name exception=(err, bt)
            push!(rows, _record_failure(cfg, err))
        end
        _write_summary(rows)
    end

    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_mmf_window_validation()
end
