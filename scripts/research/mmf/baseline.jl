"""
Phase 36 — multimode baseline stabilization.

Goals:
1. Identify which GRIN-50 multimode regimes have real Raman headroom.
2. Compare the three MMF cost variants on the strongest trustworthy regime.

Heavy run. Launch on burst with:

    julia -t auto --project=. scripts/research/mmf/baseline.jl
"""

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Dates
using JLD2

using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))

const SAVE_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase36")
const RUN_NT = 2^12
const REGIME_CONFIGS = [
    (name = "mild",       L_fiber = 1.0, P_cont = 0.05, time_window = 10.0, max_iter = 4),
    (name = "threshold",  L_fiber = 2.0, P_cont = 0.20, time_window = 10.0, max_iter = 6),
    (name = "aggressive", L_fiber = 2.0, P_cont = 0.50, time_window = 12.0, max_iter = 8),
]
const COST_VARIANTS = [:sum, :fundamental, :worst_mode]
const FIXED_SEED = 42
const COST_COMPARE_MAX_ITER = 6

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

function _save_run(path, cfg, variant, run; max_iter::Int)
    jldopen(path, "w") do f
        f["config_name"] = cfg.name
        f["variant"] = String(variant)
        f["L_fiber"] = cfg.L_fiber
        f["P_cont"] = cfg.P_cont
        f["seed"] = FIXED_SEED
        f["max_iter"] = max_iter
        f["Nt_used"] = run.setup.sim["Nt"]
        f["time_window_used_ps"] = run.setup.sim["time_window"]
        f["time_window_recommended_ps"] = run.setup.window_recommendation.time_window_ps
        f["J_ref_dB"] = run.J_ref_dB
        f["J_final_lin_dB"] = run.J_final_lin_dB
        f["improvement_dB"] = run.improvement_dB
        f["wall_time"] = run.wall_time
        f["phi_opt"] = run.opt.φ_opt
        f["J_history"] = run.opt.J_history
        f["quality_label"] = _quality_label(run)

        for (prefix, trust) in (("ref", run.trust_ref), ("opt", run.trust_opt))
            report = trust.cost_report
            f["$(prefix)_sum_dB"] = report.sum_dB
            f["$(prefix)_fundamental_dB"] = report.fundamental_dB
            f["$(prefix)_worst_mode_dB"] = report.worst_mode_dB
            f["$(prefix)_worst_mode_true_dB"] = report.worst_mode_true_dB
            f["$(prefix)_per_mode_dB"] = report.per_mode_dB
            f["$(prefix)_per_mode_lin"] = report.per_mode_lin
            f["$(prefix)_boundary_edge_fraction"] = trust.boundary_edge_fraction
            f["$(prefix)_boundary_ok"] = trust.boundary_ok
        end
    end
end

function _run_one(cfg; variant::Symbol, max_iter::Int = cfg.max_iter)
    tag = @sprintf(
        "%s_%s_l%gm_p%gw",
        cfg.name,
        String(variant),
        cfg.L_fiber,
        cfg.P_cont,
    )
    @info "="^72
    @info @sprintf(
        "Phase 36 run: %s, variant=%s, L=%.2fm, P=%.3fW",
        cfg.name, String(variant), cfg.L_fiber, cfg.P_cont,
    )
    @info "="^72

    run = run_mmf_baseline(
        preset = :GRIN_50,
        L_fiber = cfg.L_fiber,
        P_cont = cfg.P_cont,
        Nt = RUN_NT,
        time_window = cfg.time_window,
        max_iter = max_iter,
        variant = variant,
        seed = FIXED_SEED,
        save_dir = SAVE_DIR,
        tag = tag,
    )

    out = (
        config_name = cfg.name,
        variant = variant,
        quality = _quality_label(run),
        L_fiber = cfg.L_fiber,
        P_cont = cfg.P_cont,
        J_ref_dB = run.J_ref_dB,
        J_opt_dB = run.J_final_lin_dB,
        improvement_dB = run.improvement_dB,
        sum_opt_dB = run.trust_opt.cost_report.sum_dB,
        fundamental_opt_dB = run.trust_opt.cost_report.fundamental_dB,
        worst_mode_opt_dB = run.trust_opt.cost_report.worst_mode_true_dB,
        boundary_edge_fraction = run.trust_opt.boundary_edge_fraction,
        boundary_ok = run.trust_opt.boundary_ok,
        time_window_used_ps = run.setup.sim["time_window"],
        time_window_recommended_ps = run.setup.window_recommendation.time_window_ps,
        Nt_used = run.setup.sim["Nt"],
        result = run,
    )

    jld2_path = joinpath(SAVE_DIR, @sprintf("%s_%s.jld2", cfg.name, String(variant)))
    _save_run(jld2_path, cfg, variant, run; max_iter = max_iter)
    @info @sprintf(
        "Saved %s (quality=%s, edge=%.2e, Jsum=%.2f dB, Jfund=%.2f dB, Jworst=%.2f dB)",
        basename(jld2_path),
        out.quality,
        out.boundary_edge_fraction,
        out.sum_opt_dB,
        out.fundamental_opt_dB,
        out.worst_mode_opt_dB,
    )
    return out
end

function _select_candidate(regime_runs)
    meaningful = filter(r -> r.quality == "meaningful", regime_runs)
    pool = isempty(meaningful) ? regime_runs : meaningful
    best_idx = argmax([r.improvement_dB for r in pool])
    return pool[best_idx]
end

function _write_summary(regime_runs, variant_runs, chosen_name)
    summary_path = joinpath(SAVE_DIR, "phase36_summary.md")
    open(summary_path, "w") do io
        println(io, "# Phase 36 — Multimode Baseline Stabilization")
        println(io)
        println(io, @sprintf(
            "Generated %s UTC from `scripts/research/mmf/baseline.jl`.",
            Dates.format(now(UTC), dateformat"yyyy-mm-dd HH:MM:SS"),
        ))
        println(io)
        println(io, "## Regime sweep (`:sum` cost)")
        println(io)
        println(io, "| Config | L [m] | P [W] | Quality | J_ref [dB] | J_opt [dB] | Δ [dB] | J_fund(opt) [dB] | J_worst(opt) [dB] | Edge frac | TW used [ps] | TW rec [ps] | Nt |")
        println(io, "|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in regime_runs
            println(io, @sprintf(
                "| %s | %.1f | %.2f | %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2e | %.1f | %.1f | %d |",
                r.config_name, r.L_fiber, r.P_cont, r.quality,
                r.J_ref_dB, r.J_opt_dB, r.improvement_dB,
                r.fundamental_opt_dB, r.worst_mode_opt_dB,
                r.boundary_edge_fraction, r.time_window_used_ps,
                r.time_window_recommended_ps, r.Nt_used,
            ))
        end
        println(io)
        println(io, @sprintf("Selected cost-comparison regime: **%s**.", chosen_name))
        println(io)
        println(io, "Quality labels:")
        println(io, "- `meaningful`: non-trivial starting Raman plus clear optimization gain with clean boundaries")
        println(io, "- `borderline`: some headroom, but either the initial Raman or the gain is still modest")
        println(io, "- `no_headroom`: too little Raman or essentially no optimization gain")
        println(io, "- `invalid-window`: boundary corruption at the output")
        println(io)
        println(io, "## Cost comparison on selected regime")
        println(io)
        println(io, "| Optimized cost | Quality | J_sum(opt) [dB] | J_fund(opt) [dB] | J_worst(opt) [dB] | Δ_sum [dB] | Edge frac |")
        println(io, "|---|---|---:|---:|---:|---:|---:|")
        for r in variant_runs
            println(io, @sprintf(
                "| `%s` | %s | %.2f | %.2f | %.2f | %.2f | %.2e |",
                String(r.variant), r.quality, r.sum_opt_dB, r.fundamental_opt_dB,
                r.worst_mode_opt_dB, r.improvement_dB, r.boundary_edge_fraction,
            ))
        end
    end
    @info "Saved $summary_path"
end

function run_phase36()
    mkpath(SAVE_DIR)
    @info "Phase 36 — multimode baseline stabilization"
    @info @sprintf("Threads: %d", Threads.nthreads())

    regime_runs = [_run_one(cfg; variant = :sum) for cfg in REGIME_CONFIGS]
    chosen = _select_candidate(regime_runs)
    chosen_cfg = only(filter(c -> c.name == chosen.config_name, REGIME_CONFIGS))

    variant_runs = [_run_one(chosen_cfg; variant = v, max_iter = COST_COMPARE_MAX_ITER) for v in COST_VARIANTS]

    summary_jld2 = joinpath(SAVE_DIR, "phase36_results.jld2")
    jldopen(summary_jld2, "w") do f
        f["generated_at_utc"] = string(now(UTC))
        f["selected_config_name"] = chosen.config_name
        f["selected_L_fiber"] = chosen.L_fiber
        f["selected_P_cont"] = chosen.P_cont
        f["regime_config_names"] = [r.config_name for r in regime_runs]
        f["regime_quality"] = [r.quality for r in regime_runs]
        f["regime_J_ref_dB"] = [r.J_ref_dB for r in regime_runs]
        f["regime_J_opt_dB"] = [r.J_opt_dB for r in regime_runs]
        f["regime_improvement_dB"] = [r.improvement_dB for r in regime_runs]
        f["variant_names"] = [String(r.variant) for r in variant_runs]
        f["variant_quality"] = [r.quality for r in variant_runs]
        f["variant_sum_opt_dB"] = [r.sum_opt_dB for r in variant_runs]
        f["variant_fundamental_opt_dB"] = [r.fundamental_opt_dB for r in variant_runs]
        f["variant_worst_mode_opt_dB"] = [r.worst_mode_opt_dB for r in variant_runs]
        f["variant_improvement_dB"] = [r.improvement_dB for r in variant_runs]
    end
    @info "Saved $summary_jld2"

    _write_summary(regime_runs, variant_runs, chosen.config_name)
    return regime_runs, variant_runs
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_phase36()
end
