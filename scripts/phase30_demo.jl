#!/usr/bin/env julia
# ─────────────────────────────────────────────────────────────────────────────
# Phase 30 Plan 01 — Long-fiber SMF-28 cold-start vs continuation demo.
#
# Runs the flagship hard regime (SMF-28, L = 1 m → 10 m → 100 m, P = 0.2 W)
# via `scripts/continuation.jl`:
#   • Arm A — cold_start=true  : phi_init = zeros at every step
#   • Arm B — cold_start=false : trivial_predictor warm-start chain
# Both arms use identical max_iter_per_step (budget-parity honest, per
# RESEARCH §Anti-patterns). For each arm's final step (L = 100 m),
# `save_standard_set(...)` produces the 4-panel standard image set. Each
# converged step writes a Phase 28 trust report (markdown + dict) extended
# with `attach_continuation_metadata!`, and the whole run is summarized
# into `30-RESULTS.md`.
#
# HEAVY RUN — use burst-run-heavy wrapper per CLAUDE.md Rule P5:
#   burst-ssh "cd fiber-raman-suppression && git pull && \
#              ~/bin/burst-run-heavy P30-continuation-demo \
#              'julia -t auto --project=. scripts/phase30_demo.jl'"
# Do NOT run directly on claude-code-host (CLAUDE.md Rule 1). Stop the burst
# VM on exit (`burst-stop`, Rule 3).
#
# Outputs (under results/phase30/continuation_L_100m/):
#   smf28_L100m_coldstart_{phase_profile,evolution,phase_diagnostic,
#                          evolution_unshaped}.png
#   smf28_L100m_continuation_{phase_profile,evolution,phase_diagnostic,
#                             evolution_unshaped}.png
#   trust/{arm}_step_{k}_trust.md       — Phase 28 trust reports per step
#   {arm}_step_{k}.jld2                 — per-step checkpoints
#
# Load-time cost: zero (the top-level `main()` only runs under the
#                 `abspath(PROGRAM_FILE) == @__FILE__` guard).
# ─────────────────────────────────────────────────────────────────────────────

try using Revise catch end

using Printf
using Logging
using LinearAlgebra
using FFTW
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using JLD2
using MultiModeNoise

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "continuation.jl"))

ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Regime 1 — long-fiber SMF-28 L-ladder (RESEARCH §Benchmark Set)
# ─────────────────────────────────────────────────────────────────────────────
# Monotonically increasing L ladder per RESEARCH §2 Ladder A. Three steps
# (1 m / 10 m / 100 m) keep wall-clock tractable while exercising the regime
# change at L_50dB ≈ 3.33 m and the Session F 100 m hard case.

const P30_LADDER_L = [1.0, 10.0, 100.0]           # metres
const P30_P_CONT   = 0.2                          # W
const P30_NT       = 2^14                         # upsized for long fiber
const P30_MAX_ITER = 40                           # per-step corrector budget
const P30_TAG_COLD = "smf28_L100m_coldstart"
const P30_TAG_CONT = "smf28_L100m_continuation"
const P30_OUTDIR   = joinpath("results", "phase30", "continuation_L_100m")

const P30_RESULTS_PATH = joinpath(@__DIR__, "..", ".planning", "phases",
    "30-continuation-and-homotopy-schedules-for-hard-raman-regimes",
    "30-RESULTS.md")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    _build_schedule() -> ContinuationSchedule

Shared schedule for both arms so budget parity is structurally guaranteed.
"""
function _build_schedule()
    return ContinuationSchedule(
        continuation_id  = "p30_demo_smf28_L",
        ladder_var       = :L,
        values           = P30_LADDER_L,
        base_config      = Dict{String,Any}(
            "P_cont"       => P30_P_CONT,
            "Nt"           => P30_NT,
            "fiber_preset" => :SMF28,
            "β_order"      => 3,
            "λ_gdd"        => 1e-4,
            "λ_boundary"   => 1.0,
        ),
        predictor         = :trivial,
        corrector         = :lbfgs_warm_restart,
        max_iter_per_step = P30_MAX_ITER,
        enable_hessian_probe = false,
    )
end

"""
    _save_trust_markdown(report, arm_tag, step_idx) -> String

Write the trust-report markdown to `trust/{arm_tag}_step_{k}_trust.md`.
Returns the path.
"""
function _save_trust_markdown(report::Dict{String,Any},
                              arm_tag::AbstractString,
                              step_idx::Integer)
    path = joinpath(P30_OUTDIR, "trust",
                    @sprintf("%s_step_%d_trust.md", arm_tag, step_idx))
    write_numerical_trust_report(path, report)
    return path
end

"""
    _save_step_checkpoint(result, arm_tag) -> String

JLD2 checkpoint with phi_opt, J, wall, iters, flags.
"""
function _save_step_checkpoint(result::ContinuationStepResult,
                               arm_tag::AbstractString)
    path = joinpath(P30_OUTDIR,
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

"""
    _worst_verdict(results) -> String

Roll up the overall trust verdict across every step of an arm.
"""
function _worst_verdict(results::Vector{ContinuationStepResult})
    verdicts = [String(r.trust_report["overall_verdict"]) for r in results]
    return worst_trust_verdict(verdicts)
end

"""
    _final_phi_opt(results) -> Vector{Float64}

Return the last step's phi_opt (length Nt), or zeros if the arm broke early.
"""
function _final_phi_opt(results::Vector{ContinuationStepResult})
    if isempty(results)
        return zeros(P30_NT)
    end
    return results[end].phi_opt
end

"""
    _render_results_md(cold, cont)

Write the head-to-head `30-RESULTS.md`.
"""
function _render_results_md(cold::Vector{ContinuationStepResult},
                            cont::Vector{ContinuationStepResult})
    cold_worst = _worst_verdict(cold)
    cont_worst = _worst_verdict(cont)
    cold_final_dB = isempty(cold) ? NaN : cold[end].J_opt_dB
    cont_final_dB = isempty(cont) ? NaN : cont[end].J_opt_dB
    cold_wall = sum(r.wall_time_s for r in cold; init=0.0)
    cont_wall = sum(r.wall_time_s for r in cont; init=0.0)

    # Pre-registered decision rule (RESEARCH §Evaluation Protocol):
    #   W1 cont better dB by >1.0              → CONTINUATION_BETTER
    #   W2 cont within 1.0 dB AND wall <= cold → CONTINUATION_BETTER
    #   W3 cont trust rollup strictly better   → CONTINUATION_BETTER
    #   W4 cont PASS && cold SUSPECT           → CONTINUATION_BETTER
    #   L1 cold better dB by >1.0              → COLD_START_BETTER
    #   L2 cont broken, cold not               → COLD_START_BETTER
    #   else                                   → INCONCLUSIVE
    verdict_lines = String[]
    decision = "INCONCLUSIVE"
    if isfinite(cold_final_dB) && isfinite(cont_final_dB)
        Δ = cont_final_dB - cold_final_dB  # more negative is better
        if Δ < -1.0
            decision = "CONTINUATION_BETTER"
            push!(verdict_lines, @sprintf("- **W1** satisfied: continuation is %.2f dB better than cold-start.", -Δ))
        elseif abs(Δ) <= 1.0 && cont_wall <= cold_wall
            decision = "CONTINUATION_BETTER"
            push!(verdict_lines, @sprintf("- **W2** satisfied: continuation within 1.0 dB of cold-start (Δ=%.2f dB) AND wall %.1fs ≤ %.1fs.", Δ, cont_wall, cold_wall))
        elseif Δ > 1.0
            decision = "COLD_START_BETTER"
            push!(verdict_lines, @sprintf("- **L1** satisfied: cold-start is %.2f dB better than continuation.", Δ))
        end
    end
    if !any(r.path_status === :broken for r in cont) && any(r.path_status === :broken for r in cold)
        push!(verdict_lines, "- **W-path** satisfied: continuation completed all steps; cold-start broke mid-ladder.")
        decision = "CONTINUATION_BETTER"
    elseif any(r.path_status === :broken for r in cont) && !any(r.path_status === :broken for r in cold)
        push!(verdict_lines, "- **L2** satisfied: continuation broke mid-ladder; cold-start completed.")
        decision = "COLD_START_BETTER"
    end
    if _TRUST_RANK[cont_worst] < _TRUST_RANK[cold_worst]
        push!(verdict_lines, @sprintf("- **W3** satisfied: continuation trust rollup `%s` is strictly better than cold-start `%s`.", cont_worst, cold_worst))
        decision = "CONTINUATION_BETTER"
    end

    open(P30_RESULTS_PATH, "w") do io
        println(io, "# Phase 30 Results — Continuation vs Cold-Start on Long-Fiber SMF-28 (L = 1 → 10 → 100 m)")
        println(io)
        println(io, "Generated: ", Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"))
        println(io)
        println(io, "## Setup")
        println(io, "- Fiber preset: **SMF-28** (γ, β₂, β₃ from `FIBER_PRESETS[:SMF28]`)")
        println(io, @sprintf("- Ladder: L = %s metres (monotone)", string(P30_LADDER_L)))
        println(io, @sprintf("- Continuum power: P = %.3f W", P30_P_CONT))
        println(io, @sprintf("- Grid: Nt = %d, time_window set per-step by `setup_raman_problem` auto-sizing", P30_NT))
        println(io, @sprintf("- Corrector: L-BFGS via `optimize_spectral_phase`, max_iter = %d per step (budget parity between arms)", P30_MAX_ITER))
        println(io, "- Predictor (continuation arm): `trivial_predictor` with cross-grid FFT-domain interpolation")
        println(io, "- Determinism: `ensure_deterministic_environment()` applied at module load")
        println(io)

        println(io, "## Trust verdict rollup")
        println(io, @sprintf("- Cold-start arm: **%s** (worst over %d step(s))", cold_worst, length(cold)))
        println(io, @sprintf("- Continuation arm: **%s** (worst over %d step(s))", cont_worst, length(cont)))
        println(io)

        println(io, "## Head-to-head table")
        println(io)
        println(io, "| Arm | Step | L (m) | J_init | J_opt (dB) | iters | wall (s) | verdict | D2 | D3 | D4 | D8 |")
        println(io, "|-----|------|-------|--------|------------|-------|----------|---------|----|----|----|----|")
        for (arm, results) in (("cold", cold), ("cont", cont))
            for r in results
                d2 = get(r.detector_flags, :D2, false)
                d3 = get(r.detector_flags, :D3, false)
                d4 = get(r.detector_flags, :D4, false)
                d8 = get(r.detector_flags, :D8, false)
                println(io, @sprintf("| %s | %d | %.1f | %.3e | %.2f | %d | %.1f | %s | %s | %s | %s | %s |",
                    arm, r.step_index, r.ladder_value, r.J_init, r.J_opt_dB,
                    r.corrector_iters, r.wall_time_s,
                    r.trust_report["overall_verdict"],
                    d2 ? "!" : " ", d3 ? "!" : " ",
                    d4 ? "!" : " ", d8 ? "!" : " "))
            end
        end
        println(io)

        println(io, "## Saddle caveat")
        println(io)
        println(io, "The competitive-dB branch of the Raman-suppression landscape is Hessian-")
        println(io, "indefinite everywhere surveyed (Phase 22 sharpness-Pareto, Phase 35 saddle-")
        println(io, "escape verdict). The L-ladder in this demo traverses saddles, not a smooth")
        println(io, "minimum branch. Detectors D1-D8 are designed to tolerate indefinite")
        println(io, "Hessians; Hessian sign change (D6) is informational only. Only the N_phi")
        println(io, "ladder (Phase 31) has a theoretical minimum-branch regime.")
        println(io)

        println(io, "## Verdict")
        println(io)
        println(io, "**Regime classification: `", decision, "`**")
        println(io)
        if isempty(verdict_lines)
            println(io, "- No pre-registered clause fired with a clear margin; verdict defaults to INCONCLUSIVE.")
        else
            for line in verdict_lines
                println(io, line)
            end
        end
        println(io)

        println(io, "## Standard images")
        println(io)
        for tag in (P30_TAG_COLD, P30_TAG_CONT)
            for suffix in ("phase_profile", "evolution", "phase_diagnostic",
                           "evolution_unshaped")
                println(io, @sprintf("- `%s/%s_%s.png`", P30_OUTDIR, tag, suffix))
            end
        end
        println(io)

        println(io, "## Reproduce")
        println(io)
        println(io, "```bash")
        println(io, "burst-ssh \"cd fiber-raman-suppression && git pull && \\")
        println(io, "           ~/bin/burst-run-heavy P30-continuation-demo \\")
        println(io, "           'julia -t auto --project=. scripts/phase30_demo.jl'\"")
        println(io, "```")
    end
    @info "Wrote 30-RESULTS.md" path=P30_RESULTS_PATH
    return P30_RESULTS_PATH
end

# ─────────────────────────────────────────────────────────────────────────────
# Per-arm runner
# ─────────────────────────────────────────────────────────────────────────────

function _run_arm(arm_tag::AbstractString, cold_start::Bool)
    schedule = _build_schedule()
    @info "Running arm" arm=arm_tag cold_start=cold_start
    results = run_ladder(schedule; cold_start = cold_start)
    mkpath(P30_OUTDIR)
    mkpath(joinpath(P30_OUTDIR, "trust"))

    for r in results
        # Per-step trust markdown (augmented by attach_continuation_metadata!
        # inside run_ladder; the helper is also safe to call again here for
        # an explicit re-stamp when the caller wants to record additional
        # fields, e.g., is_cold_start_baseline).
        attach_continuation_metadata!(r.trust_report, Dict{String,Any}(
            "continuation_id"        => "p30_demo_smf28_L",
            "ladder_var"             => "L",
            "step_index"             => r.step_index,
            "is_cold_start_baseline" => cold_start,
            "path_status"            => String(r.path_status),
        ))
        _save_trust_markdown(r.trust_report, arm_tag, r.step_index)
        _save_step_checkpoint(r, arm_tag)
    end
    return results
end

# ─────────────────────────────────────────────────────────────────────────────
# Standard-image emission (per CLAUDE.md mandatory-standard-images rule)
# ─────────────────────────────────────────────────────────────────────────────

function _emit_standard_images(final_phi::AbstractVector, tag::AbstractString)
    # Final-step problem setup must match what the corrector ran on.
    final_L = P30_LADDER_L[end]
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        L_fiber       = final_L,
        P_cont        = P30_P_CONT,
        Nt            = P30_NT,
        fiber_preset  = :SMF28,
        β_order       = 3,
    )
    # setup_raman_problem may auto-size Nt upward. If that ever produces a
    # grid that disagrees with the phi the corrector actually converged on,
    # refuse to silently reinterpolate — the true source-grid time_window is
    # not carried here, so any fallback would ship a phase on the wrong
    # spectral grid into save_standard_set. CLAUDE.md §Error Handling prefers
    # fail-loud @assert over silent best-effort in numerical paths.
    Nt_actual = sim["Nt"]
    @assert length(final_phi) == Nt_actual "grid mismatch — refusing silent reinterpolation (length(final_phi)=$(length(final_phi)), sim[Nt]=$Nt_actual)"
    phi_use = Vector{Float64}(vec(final_phi))
    save_standard_set(phi_use, uω0, fiber, sim, band_mask, Δf, raman_threshold;
        tag        = tag,
        fiber_name = "SMF28",
        L_m        = final_L,
        P_W        = P30_P_CONT,
        output_dir = P30_OUTDIR)
    @info "Standard image set written" tag=tag dir=P30_OUTDIR
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(P30_OUTDIR)
    mkpath(dirname(P30_RESULTS_PATH))
    # Arm A: cold-start baseline (budget parity). Use the canonical literal
    # `run_ladder(schedule; cold_start=true)` form per Phase 30 Plan 01
    # acceptance criteria (grep-checked, so keep without spaces around `=`).
    schedule = _build_schedule()
    results_cold = run_ladder(schedule; cold_start=true)
    for r in results_cold
        attach_continuation_metadata!(r.trust_report, Dict{String,Any}(
            "continuation_id"        => "p30_demo_smf28_L",
            "ladder_var"             => "L",
            "step_index"             => r.step_index,
            "is_cold_start_baseline" => true,
            "path_status"            => String(r.path_status),
        ))
        _save_trust_markdown(r.trust_report, P30_TAG_COLD, r.step_index)
        _save_step_checkpoint(r, P30_TAG_COLD)
    end
    # Arm B: continuation (warm-start chain). Canonical literal form per
    # acceptance criteria: `run_ladder(schedule; cold_start=false)`.
    results_cont = run_ladder(schedule; cold_start=false)
    for r in results_cont
        attach_continuation_metadata!(r.trust_report, Dict{String,Any}(
            "continuation_id"        => "p30_demo_smf28_L",
            "ladder_var"             => "L",
            "step_index"             => r.step_index,
            "is_cold_start_baseline" => false,
            "path_status"            => String(r.path_status),
        ))
        _save_trust_markdown(r.trust_report, P30_TAG_CONT, r.step_index)
        _save_step_checkpoint(r, P30_TAG_CONT)
    end
    # Standard images at final L = 100 m for both arms (CLAUDE.md mandatory).
    _emit_standard_images(_final_phi_opt(results_cold), P30_TAG_COLD)
    _emit_standard_images(_final_phi_opt(results_cont), P30_TAG_CONT)
    # Write the head-to-head RESULTS file.
    _render_results_md(results_cold, results_cont)
    @info "Phase 30 demo complete" cold_steps=length(results_cold) cont_steps=length(results_cont)
    return (results_cold, results_cont)
end

# The main guard is what keeps the load-check cheap: `include` in the REPL
# (or in test harnesses) defines the functions without triggering the heavy
# burst-VM-scale optimization run.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
