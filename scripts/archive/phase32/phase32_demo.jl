#!/usr/bin/env julia
# ─────────────────────────────────────────────────────────────────────────────
# Phase 32 Plan 02 — Experiment 1: Polynomial warm-start acceleration
# on the SMF-28 L-ladder.
#
# Three arms, budget parity, SMF-28 L = [1.0, 10.0, 100.0] m, P = 0.2 W:
#   • COLD   — phi_init = zeros at every step (baseline 1).
#   • NAIVE  — trivial_predictor warm-start chain (Phase 30 behaviour).
#   • ACCEL  — Phase 32 polynomial_predict in log(L) with D = min(k-1, 2)
#              (RESEARCH §9 Q3; ACCEL_MAX_DEGREE_DEFAULT = 2).
#
# Nt cap: `setup_longfiber_problem` is passed as `setup_fn` to `run_ladder`
# to BYPASS the auto-sizing inside `setup_raman_problem` (CLAUDE.md /
# 32-CONTEXT.md hard prerequisite — auto-sizing at SMF-28 L=100m blows Nt up
# super-linearly). Fixed Nt = 2^14 and time_window = 40 ps across all three
# steps for both arms.
#
# HEAVY RUN — use burst-run-heavy wrapper per CLAUDE.md Rule P5:
#   burst-ssh "cd fiber-raman-suppression && git pull && \
#              ~/bin/burst-run-heavy P-32-accel-expt1 \
#              'julia -t auto --project=. scripts/demo.jl'"
# Stop the burst VM on exit (`burst-stop`, Rule 3).
#
# Outputs (under results/phase32/expt1_polywarmstart_L100m/):
#   smf28_L100m_cold_{phase_profile,evolution,phase_diagnostic,
#                     evolution_unshaped}.png
#   smf28_L100m_naive_{...}.png
#   smf28_L100m_accel_polyd2_logL_{...}.png
#   results_{cold,naive,accel}.jld2
#   trust/{arm}_step_{k}_trust.md
#
# 32-RESULTS.md is overwritten on the Experiment 1 section with a head-to-
# head arm comparison and the `classify_acceleration_verdict` outcome.
#
# Load-time cost: zero (main guard).
# ─────────────────────────────────────────────────────────────────────────────

try using Revise catch end

using Printf
using Logging
using LinearAlgebra
using Statistics
using FFTW
using Dates
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using JLD2
using MultiModeNoise

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "longfiber_setup.jl"))
include(joinpath(@__DIR__, "continuation.jl"))
include(joinpath(@__DIR__, "acceleration.jl"))

ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Regime — long-fiber SMF-28 L-ladder (RESEARCH §6 Experiment 1)
# ─────────────────────────────────────────────────────────────────────────────

const P32_LADDER_L     = [1.0, 10.0, 100.0]   # metres
const P32_P_CONT       = 0.2                  # W
const P32_NT           = 2^14                 # capped — NO auto-size
const P32_TIME_WINDOW  = 40.0                 # ps (large enough for L = 100 m)
const P32_MAX_ITER     = 40                   # per-step corrector budget (parity)
const P32_BETA_ORDER   = 3

const P32_TAG_COLD     = "smf28_L100m_cold"
const P32_TAG_NAIVE    = "smf28_L100m_naive"
const P32_TAG_ACCEL    = "smf28_L100m_accel_polyd2_logL"

const P32_OUTDIR       = joinpath("results", "phase32", "expt1_polywarmstart_L100m")
const P32_RESULTS_PATH = joinpath(@__DIR__, "..", ".planning", "phases",
    "32-extrapolation-and-acceleration-for-parameter-studies-and-con",
    "32-RESULTS.md")

# ─────────────────────────────────────────────────────────────────────────────
# Setup_fn — setup_longfiber_problem wrapper for run_ladder
# ─────────────────────────────────────────────────────────────────────────────

"""
    _longfiber_setup_fn(cfg) -> (uω0, fiber, sim, band_mask, Δf, raman_threshold)

Thin wrapper so `run_ladder`'s `setup_fn` seam accepts a `Dict{String,Any}`.
Bypasses `setup_raman_problem` auto-sizing (CLAUDE.md §Running Simulations
and CONTEXT hard prerequisite). Fails loudly if `cfg` is missing required
keys so the schedule cannot silently drop to bad defaults.
"""
function _longfiber_setup_fn(cfg::Dict{String,Any})
    L_fiber = Float64(cfg["L_fiber"])
    P_cont  = Float64(cfg["P_cont"])
    Nt      = Int(cfg["Nt"])
    tw_ps   = Float64(get(cfg, "time_window", P32_TIME_WINDOW))
    preset  = get(cfg, "fiber_preset", :SMF28)
    β_order = Int(get(cfg, "β_order", P32_BETA_ORDER))
    return setup_longfiber_problem(
        fiber_preset = preset,
        L_fiber      = L_fiber,
        P_cont       = P_cont,
        Nt           = Nt,
        time_window  = tw_ps,
        β_order      = β_order,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Schedule builder — shared across all three arms for structural parity
# ─────────────────────────────────────────────────────────────────────────────

function _build_schedule()
    base_cfg = Dict{String,Any}(
        "P_cont"       => P32_P_CONT,
        "Nt"           => P32_NT,
        "time_window"  => P32_TIME_WINDOW,
        "fiber_preset" => :SMF28,
        "β_order"      => P32_BETA_ORDER,
        "λ_gdd"        => 1e-4,
        "λ_boundary"   => 1.0,
    )
    return ContinuationSchedule(
        continuation_id   = "p32_smf28_L_polywarm",
        ladder_var        = :L,
        values            = P32_LADDER_L,
        base_config       = base_cfg,
        predictor         = :trivial,       # overridden for ACCEL via corrector_fn
        corrector         = :lbfgs_warm_restart,
        max_iter_per_step = P32_MAX_ITER,
        enable_hessian_probe = false,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# ACCEL corrector — closes over phi/L history, injects polynomial_predict
# ─────────────────────────────────────────────────────────────────────────────

"""
    _accel_corrector_fn(phi_hist, L_hist, accel_meta) -> corr

Factory for the ACCEL arm's corrector. Called once at run_ladder bootstrap;
returns a closure that:
  - Overrides the `phi_init` run_ladder handed us with a polynomial prediction
    in `s = log(L)` using `polynomial_predict(max_degree = ACCEL_MAX_DEGREE_DEFAULT)`
    whenever the history has ≥ 1 past iterate. On step 1, uses `phi_init` as-is
    (which is `zeros(Nt)` under `cold_start=true`).
  - Delegates the L-BFGS solve to `_default_corrector_lbfgs`
    (defined in scripts/continuation.jl).
  - Pushes the converged phi + L onto the captured history lists.
  - Records per-step `accel_meta[k] = Dict(...)` (prediction_norm,
    prediction_vs_prev_norm, degree, coefficient_max) so the main loop can
    attach_acceleration_metadata! onto the per-step trust dict.

`phi_hist`, `L_hist`, `accel_meta` are captured by reference — mutating them
is the whole point, so we can inspect results AFTER `run_ladder` returns.
"""
function _accel_corrector_fn(phi_hist::Vector{Vector{Float64}},
                             L_hist::Vector{Float64},
                             accel_meta::Vector{Dict{String,Any}})
    function corr(phi_init, cfg;
                  uω0, fiber, sim, band_mask, max_iter)
        Nt = sim["Nt"]
        L_target = Float64(cfg["L_fiber"])
        k = length(phi_hist)

        local phi_init_used::Vector{Float64}
        local pred_norm::Float64
        local pred_minus_prev::Float64
        local degree::Int

        if k == 0
            # Step 1 — no history, use whatever run_ladder handed us (zeros).
            phi_init_used = Vector{Float64}(vec(phi_init))
            pred_norm = norm(phi_init_used)
            pred_minus_prev = 0.0
            degree = 0
        else
            # Build log-L history and predict at log(L_target).
            s_hist = log.(L_hist)
            # Safety: collapse duplicates (shouldn't happen, but L_ladder is
            # monotone-increasing so this is a no-op in the happy path).
            phi_pred = polynomial_predict(
                s_history   = s_hist,
                phi_history = phi_hist,
                s_target    = log(L_target),
                max_degree  = ACCEL_MAX_DEGREE_DEFAULT,
            )
            # Sanity: the prediction must live on the current grid. Since the
            # L-ladder uses fixed Nt across steps, phi_hist entries all have
            # length Nt — polynomial_predict preserves length.
            @assert length(phi_pred) == Nt "poly prediction Nt mismatch"
            phi_init_used = Vector{Float64}(phi_pred)
            pred_norm = norm(phi_init_used)
            pred_minus_prev = norm(phi_init_used .- phi_hist[end])
            degree = min(k - 1, ACCEL_MAX_DEGREE_DEFAULT)
        end

        # Delegate to the default L-BFGS corrector. `_default_corrector_lbfgs`
        # is defined in scripts/continuation.jl inside the `_CONTINUATION_JL_LOADED`
        # include guard, so it is visible at this scope (we `include`d the file
        # into Main at the top of this driver).
        phi_opt, J_linear, iters, wall_s = _default_corrector_lbfgs(
            phi_init_used, cfg;
            uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
            max_iter = max_iter,
        )

        # Record history for the next step's prediction.
        push!(phi_hist, Vector{Float64}(vec(phi_opt)))
        push!(L_hist,   L_target)
        push!(accel_meta, Dict{String,Any}(
            "accelerator"             => "polynomial_d$(degree)",
            "polynomial_degree"       => degree,
            "prediction_norm"         => pred_norm,
            "prediction_vs_prev_norm" => pred_minus_prev,
            "corrector_iters"         => iters,
            "k_history_before"        => k,
        ))

        return phi_opt, J_linear, iters, wall_s
    end
    return corr
end

# ─────────────────────────────────────────────────────────────────────────────
# Per-arm persistence (trust markdown + JLD2 per step, bulk JLD2 per arm)
# ─────────────────────────────────────────────────────────────────────────────

function _save_trust_markdown(report::Dict{String,Any},
                              arm_tag::AbstractString, step_idx::Integer)
    path = joinpath(P32_OUTDIR, "trust",
        @sprintf("%s_step_%d_trust.md", arm_tag, step_idx))
    mkpath(dirname(path))
    write_numerical_trust_report(path, report)
    return path
end

function _save_step_checkpoint(result::ContinuationStepResult, arm_tag::AbstractString)
    path = joinpath(P32_OUTDIR,
        @sprintf("%s_step_%d.jld2", arm_tag, result.step_index))
    mkpath(dirname(path))
    JLD2.jldsave(path;
        phi_opt         = result.phi_opt,
        J_opt_dB        = result.J_opt_dB,
        L               = result.ladder_value,
        corrector_iters = result.corrector_iters,
        wall_time_s     = result.wall_time_s,
        detector_flags  = result.detector_flags,
        path_status     = String(result.path_status),
    )
    return path
end

function _save_arm_bundle(results::Vector{ContinuationStepResult},
                          arm_tag::AbstractString,
                          extra::Dict{String,Any})
    path = joinpath(P32_OUTDIR, "results_$(arm_tag_short(arm_tag)).jld2")
    mkpath(dirname(path))
    JLD2.jldsave(path;
        phi_hist        = [r.phi_opt for r in results],
        L_hist          = [r.ladder_value for r in results],
        J_opt_dB_hist   = [r.J_opt_dB for r in results],
        iters_hist      = [r.corrector_iters for r in results],
        wall_s_hist     = [r.wall_time_s for r in results],
        path_status     = [String(r.path_status) for r in results],
        extra           = extra,
    )
    return path
end

# Short arm label (cold / naive / accel) for the bundle filename.
function arm_tag_short(tag::AbstractString)
    endswith(tag, "cold")                    && return "cold"
    endswith(tag, "naive")                   && return "naive"
    endswith(tag, "accel_polyd2_logL")       && return "accel"
    return replace(String(tag), r"[^A-Za-z0-9_]" => "_")
end

function _persist_arm(results::Vector{ContinuationStepResult},
                      arm_tag::AbstractString,
                      arm_label::AbstractString,
                      arm_extra::Dict{String,Any})
    for r in results
        # Re-stamp continuation metadata with the arm label so trust rows are
        # auditable post-hoc. `attach_continuation_metadata!` is additive via
        # merge — safe to call twice.
        attach_continuation_metadata!(r.trust_report, Dict{String,Any}(
            "continuation_id" => "p32_smf28_L_polywarm",
            "ladder_var"      => "L",
            "step_index"      => r.step_index,
            "path_status"     => String(r.path_status),
            "is_cold_start_baseline" => (arm_label == "cold"),
        ))
        _save_trust_markdown(r.trust_report, arm_tag, r.step_index)
        _save_step_checkpoint(r, arm_tag)
    end
    _save_arm_bundle(results, arm_tag, arm_extra)
    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# Standard-image emission — 3 arms × 4 panels = 12 PNGs (CLAUDE.md mandate)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _build_final_problem() -> (uω0, fiber, sim, band_mask, Δf, raman_threshold)

Build the final-step (L = 100 m) Raman problem once so each arm's
`save_standard_set` call reuses the same spectral grid. Nt cap honored
via `setup_longfiber_problem` — the CONTEXT hard prerequisite.
"""
function _build_final_problem()
    final_L = P32_LADDER_L[end]
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(
        fiber_preset = :SMF28,
        L_fiber      = final_L,
        P_cont       = P32_P_CONT,
        Nt           = P32_NT,
        time_window  = P32_TIME_WINDOW,
        β_order      = P32_BETA_ORDER,
    )
    @assert sim["Nt"] == P32_NT "Nt drift in setup_longfiber_problem"
    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

"""
    _check_phi_grid(phi, tag) -> Vector{Float64}

Refuse silent reinterpolation — phi MUST live on the fixed Nt = P32_NT grid.
"""
function _check_phi_grid(phi::AbstractVector, tag::AbstractString)
    @assert length(phi) == P32_NT "final phi/Nt mismatch for $(tag) — refusing silent reinterpolation"
    return Vector{Float64}(vec(phi))
end

# ─────────────────────────────────────────────────────────────────────────────
# Verdict table → 32-RESULTS.md (Experiment 1 section)
# ─────────────────────────────────────────────────────────────────────────────

# Attach acceleration metadata onto the ACCEL arm's trust dicts BEFORE rendering.
function _attach_accel_metadata!(results::Vector{ContinuationStepResult},
                                 accel_meta::Vector{Dict{String,Any}},
                                 verdict::AbstractString)
    @assert length(results) == length(accel_meta) "accel_meta length mismatch"
    for (r, m) in zip(results, accel_meta)
        m2 = copy(m)
        m2["verdict"] = verdict
        attach_acceleration_metadata!(r.trust_report, m2)
    end
    return nothing
end

function _worst_verdict(results::Vector{ContinuationStepResult})
    verdicts = [String(r.trust_report["overall_verdict"]) for r in results]
    return worst_trust_verdict(verdicts)
end

function _total_iters(results::Vector{ContinuationStepResult})
    return sum(r.corrector_iters for r in results; init = 0)
end

function _final_phi_opt(results::Vector{ContinuationStepResult})
    isempty(results) && return zeros(P32_NT)
    return results[end].phi_opt
end

function _final_dB(results::Vector{ContinuationStepResult})
    isempty(results) && return NaN
    return results[end].J_opt_dB
end

function _arm_has_broken(results::Vector{ContinuationStepResult})
    return any(r -> r.path_status === :broken, results)
end

"""
    _render_experiment1_section(cold, naive, accel, verdict, metrics, accel_meta)

Overwrite the `## Experiment 1` section in `32-RESULTS.md`. Keeps the scaffold
header + other sections untouched; merges the arm table + verdict in place.
"""
function _render_experiment1_section(
    cold::Vector{ContinuationStepResult},
    naive::Vector{ContinuationStepResult},
    accel::Vector{ContinuationStepResult},
    verdict::AbstractString,
    metrics::Dict{String,Any},
    accel_meta::Vector{Dict{String,Any}},
)
    mkpath(dirname(P32_RESULTS_PATH))
    buf = IOBuffer()
    println(buf, "")
    println(buf, "## Experiment 1 — Polynomial warm-start on SMF-28 L-ladder [1, 10, 100] m")
    println(buf, "")
    println(buf, "_populated by scripts/demo.jl_")
    println(buf, "")
    println(buf, "Generated: ", Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"))
    println(buf, "")
    println(buf, "### Setup (shared across arms — budget parity)")
    println(buf, "")
    println(buf, "- Fiber preset: **SMF-28** (γ, β₂, β₃ from `FIBER_PRESETS[:SMF28]`)")
    println(buf, "- Ladder: L = $(P32_LADDER_L) m, P = $(P32_P_CONT) W")
    println(buf, "- Grid: **Nt = $(P32_NT)**, time_window = $(P32_TIME_WINDOW) ps, β_order = $(P32_BETA_ORDER)")
    println(buf, "- `setup_fn = setup_longfiber_problem` — auto-sizing BYPASSED (CONTEXT prerequisite)")
    println(buf, "- Corrector: L-BFGS via `optimize_spectral_phase`, `max_iter = $(P32_MAX_ITER)` per step")
    println(buf, "- ACCEL predictor: `polynomial_predict` in s = log(L), D = min(k-1, $(ACCEL_MAX_DEGREE_DEFAULT))")
    println(buf, "- Locked thresholds: `ACCEL_STOP_SAVINGS_FRAC=$(ACCEL_STOP_SAVINGS_FRAC)`, `ACCEL_STOP_DB_REGRESSION=$(ACCEL_STOP_DB_REGRESSION)`, `ACCEL_SAFEGUARD_GAMMA_MAX=$(ACCEL_SAFEGUARD_GAMMA_MAX)`")
    println(buf, "")
    println(buf, "### Head-to-head")
    println(buf, "")
    println(buf, "| Arm   | total_iters | worst_verdict | final J_dB | hard halts | 4 PNGs? |")
    println(buf, "|-------|-------------|---------------|------------|------------|---------|")
    for (label, r) in (("COLD", cold), ("NAIVE", naive), ("ACCEL", accel))
        println(buf, @sprintf("| %s | %d | %s | %.3f | %s | yes |",
            label, _total_iters(r), _worst_verdict(r), _final_dB(r),
            _arm_has_broken(r) ? "YES" : "no"))
    end
    println(buf, "")
    println(buf, "### Verdict metrics (fed to `classify_acceleration_verdict`)")
    println(buf, "")
    for (k, v) in metrics
        println(buf, @sprintf("- `%s` = %s", k, string(v)))
    end
    println(buf, "")
    println(buf, "**Verdict (classify_acceleration_verdict): `$(verdict)`**")
    println(buf, "")
    println(buf, "### Aitken Δ² stop-rule diagnostic")
    println(buf, "")
    aitken_naive = aitken([r.J_opt_dB for r in naive])
    aitken_accel = aitken([r.J_opt_dB for r in accel])
    println(buf, @sprintf("- J_∞ estimate (naive J_dB sequence): **%s dB**",
        isfinite(aitken_naive) ? @sprintf("%.3f", aitken_naive) : "NaN (denominator too small)"))
    println(buf, @sprintf("- J_∞ estimate (accel J_dB sequence): **%s dB**",
        isfinite(aitken_accel) ? @sprintf("%.3f", aitken_accel) : "NaN (denominator too small)"))
    println(buf, "")
    println(buf, "### Per-step acceleration metadata (ACCEL arm)")
    println(buf, "")
    println(buf, "| step | L (m) | degree | prediction_norm | pred_vs_prev_norm | corrector_iters |")
    println(buf, "|------|-------|--------|-----------------|-------------------|-----------------|")
    for (i, m) in enumerate(accel_meta)
        L_i = i <= length(accel) ? accel[i].ladder_value : NaN
        println(buf, @sprintf("| %d | %.2f | %d | %.4e | %.4e | %d |",
            i, L_i,
            Int(get(m, "polynomial_degree", 0)),
            Float64(get(m, "prediction_norm", NaN)),
            Float64(get(m, "prediction_vs_prev_norm", NaN)),
            Int(get(m, "corrector_iters", 0))))
    end
    println(buf, "")
    println(buf, "### Standard images")
    println(buf, "")
    for tag in (P32_TAG_COLD, P32_TAG_NAIVE, P32_TAG_ACCEL)
        for suffix in ("phase_profile", "evolution", "phase_diagnostic",
                       "evolution_unshaped")
            println(buf, @sprintf("- `%s/%s_%s.png`", P32_OUTDIR, tag, suffix))
        end
    end
    println(buf, "")
    new_block = String(take!(buf))

    if isfile(P32_RESULTS_PATH)
        existing = read(P32_RESULTS_PATH, String)
        heading = "## Experiment 1 — Polynomial warm-start on SMF-28 L-ladder [1, 10, 100] m"
        idx = findfirst(heading, existing)
        if idx !== nothing
            before = existing[1:prevind(existing, first(idx))]
            next_idx = findnext(r"\n## ", existing, last(idx) + 1)
            after = next_idx === nothing ? "" : existing[first(next_idx):end]
            open(P32_RESULTS_PATH, "w") do io
                write(io, rstrip(before), "\n", new_block, after)
            end
        else
            open(P32_RESULTS_PATH, "a") do io
                write(io, new_block)
            end
        end
    else
        open(P32_RESULTS_PATH, "w") do io
            write(io, "# Phase 32 Results — Extrapolation and Acceleration\n", new_block)
        end
    end
    @info "Wrote Experiment 1 section" path=P32_RESULTS_PATH verdict=verdict
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(P32_OUTDIR)
    mkpath(joinpath(P32_OUTDIR, "trust"))
    mkpath(dirname(P32_RESULTS_PATH))

    schedule = _build_schedule()

    # ── Arm COLD — cold_start=true, no warm start, no predictor ──────────
    @info "──────── COLD arm ────────"
    results_cold = run_ladder(schedule;
        setup_fn = _longfiber_setup_fn,
        cold_start = true,
    )
    _persist_arm(results_cold, P32_TAG_COLD, "cold", Dict{String,Any}(
        "arm" => "COLD",
    ))

    # ── Arm NAIVE — default trivial_predictor (Phase 30 behaviour) ───────
    @info "──────── NAIVE arm ────────"
    results_naive = run_ladder(schedule;
        setup_fn = _longfiber_setup_fn,
        cold_start = false,
    )
    _persist_arm(results_naive, P32_TAG_NAIVE, "naive", Dict{String,Any}(
        "arm" => "NAIVE",
    ))

    # ── Arm ACCEL — polynomial_predict in log(L) via custom corrector_fn ──
    @info "──────── ACCEL arm ────────"
    accel_phi_hist  = Vector{Vector{Float64}}()
    accel_L_hist    = Vector{Float64}()
    accel_meta      = Vector{Dict{String,Any}}()
    accel_corr      = _accel_corrector_fn(accel_phi_hist, accel_L_hist, accel_meta)
    # cold_start=true forces step 1 phi_init = zeros, which our corrector will
    # pass through as-is (k == 0 branch). Steps 2/3 then polynomial-predict.
    results_accel = run_ladder(schedule;
        setup_fn = _longfiber_setup_fn,
        corrector_fn = accel_corr,
        cold_start = true,
    )

    # ── Verdict metrics + classifier ─────────────────────────────────────
    total_iters_naive = _total_iters(results_naive)
    total_iters_accel = _total_iters(results_accel)
    savings_frac = if total_iters_naive > 0
        (total_iters_naive - total_iters_accel) / total_iters_naive
    else
        0.0
    end
    worst_n = _worst_verdict(results_naive)
    worst_a = _worst_verdict(results_accel)
    verdict_delta = _TRUST_RANK[worst_a] - _TRUST_RANK[worst_n]
    db_delta = _final_dB(results_accel) - _final_dB(results_naive)
    new_hard_halt = _arm_has_broken(results_accel) && !_arm_has_broken(results_naive)

    metrics = Dict{String,Any}(
        "savings_frac"        => savings_frac,
        "worst_verdict_delta" => verdict_delta,
        "db_delta"            => db_delta,
        "new_hard_halt"       => new_hard_halt,
        "total_iters_naive"   => total_iters_naive,
        "total_iters_accel"   => total_iters_accel,
    )
    verdict = classify_acceleration_verdict(metrics)

    # Attach acceleration metadata onto ACCEL trust dicts BEFORE persisting.
    _attach_accel_metadata!(results_accel, accel_meta, verdict)
    _persist_arm(results_accel, P32_TAG_ACCEL, "accel", Dict{String,Any}(
        "arm"               => "ACCEL",
        "accel_meta"        => accel_meta,
        "verdict"           => verdict,
        "metrics"           => metrics,
    ))

    # ── Standard images (4 PNGs per arm × 3 arms = 12 PNGs) ───────────────
    # CLAUDE.md mandate: every phi_opt gets a 4-panel standard image set.
    # Build the L = 100 m problem once; each arm's final phi reuses the
    # same spectral grid (Nt = P32_NT, time_window = P32_TIME_WINDOW).
    uω0_std, fiber_std, sim_std, band_mask_std, Δf_std, raman_threshold_std =
        _build_final_problem()
    final_L = P32_LADDER_L[end]

    # Arm COLD.
    save_standard_set(
        _check_phi_grid(_final_phi_opt(results_cold), P32_TAG_COLD),
        uω0_std, fiber_std, sim_std, band_mask_std, Δf_std, raman_threshold_std;
        tag        = P32_TAG_COLD,
        fiber_name = "SMF28",
        L_m        = final_L,
        P_W        = P32_P_CONT,
        output_dir = P32_OUTDIR,
    )
    @info "Standard image set written" arm="COLD" tag=P32_TAG_COLD dir=P32_OUTDIR

    # Arm NAIVE.
    save_standard_set(
        _check_phi_grid(_final_phi_opt(results_naive), P32_TAG_NAIVE),
        uω0_std, fiber_std, sim_std, band_mask_std, Δf_std, raman_threshold_std;
        tag        = P32_TAG_NAIVE,
        fiber_name = "SMF28",
        L_m        = final_L,
        P_W        = P32_P_CONT,
        output_dir = P32_OUTDIR,
    )
    @info "Standard image set written" arm="NAIVE" tag=P32_TAG_NAIVE dir=P32_OUTDIR

    # Arm ACCEL.
    save_standard_set(
        _check_phi_grid(_final_phi_opt(results_accel), P32_TAG_ACCEL),
        uω0_std, fiber_std, sim_std, band_mask_std, Δf_std, raman_threshold_std;
        tag        = P32_TAG_ACCEL,
        fiber_name = "SMF28",
        L_m        = final_L,
        P_W        = P32_P_CONT,
        output_dir = P32_OUTDIR,
    )
    @info "Standard image set written" arm="ACCEL" tag=P32_TAG_ACCEL dir=P32_OUTDIR

    # ── 32-RESULTS.md Experiment 1 section ────────────────────────────────
    _render_experiment1_section(results_cold, results_naive, results_accel,
        verdict, metrics, accel_meta)

    @info "Phase 32 Experiment 1 complete" verdict=verdict savings_frac=savings_frac
    return (results_cold, results_naive, results_accel, verdict, metrics)
end

# Main guard — `include` at REPL or load-check defines functions without
# triggering the heavy burst-VM run.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
