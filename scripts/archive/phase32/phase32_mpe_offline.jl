#!/usr/bin/env julia
# ─────────────────────────────────────────────────────────────────────────────
# Phase 32 Plan 02 — Experiment 2: offline MPE / RRE on the 3-point history.
#
# Goal (RESEARCH §6 Experiment 2): take the three converged phi_opt from
# Phase 30's 3-step SMF-28 warm-start ladder, combine them via MPE and RRE
# (`scripts/acceleration.jl`), gate with `safeguard_gamma`, polish each
# combined phi with L-BFGS at L=100m, and compare depth + iters versus the
# naive endpoint (`phi_hist[end]` = Phase 30 step 3).
#
# Gate Path (per 32-PHASE30-GATE.md): **Path B** — Phase 30 heavy-run
# artifacts are NOT on disk. The driver probes in order and runs inline
# ladder regeneration as a last resort:
#
#   1. results/phase30/continuation_L_100m/continuation_step_{1,2,3}.jld2
#   2. results/phase32/expt1_polywarmstart_L100m/results_naive.jld2
#   3. Inline 3-step ladder (mirrors scripts/demo.jl).
#
# All paths end in a `phi_hist::Vector{Vector{Float64}}` of 3 entries on the
# fixed Nt = 2^14 grid.
#
# Before combining, each phi is passed through `project_gauge_phi` (RESEARCH
# §9 Q8) to kill the exact Hessian null-modes (mean shift + ω-linear slope on
# the input band). Then `mpe_combine` / `rre_combine` produce combined phis
# and weights; `safeguard_gamma(γ; threshold=ACCEL_SAFEGUARD_GAMMA_MAX=1e3)`
# gates acceptance. If a combiner fails the safeguard, we fall back to
# `phi_hist[end]` and record `accelerator="trivial", safeguard_passed=false`.
#
# Each accepted combined phi is polished at L=100m with 40 L-BFGS iters
# (budget parity with Phase 30) and rendered with `save_standard_set` (2 arms
# × 4 panels = 8 PNGs).
#
# Verdict is derived from `classify_acceleration_verdict` using the same
# locked thresholds as Experiment 1 (ACCEL_STOP_SAVINGS_FRAC=0.15,
# ACCEL_STOP_DB_REGRESSION=1.0). Schema version stays "28.0".
#
# HEAVY RUN — use burst-run-heavy wrapper per CLAUDE.md Rule P5:
#   burst-ssh "cd fiber-raman-suppression && git pull && \
#              ~/bin/burst-run-heavy P-32-accel-expt2 \
#              'julia -t auto --project=. scripts/mpe_offline.jl'"
# Stop the burst VM on exit (`burst-stop`, Rule 3).
#
# Outputs (under results/phase32/expt2_mpe_rre_polish_L100m/):
#   smf28_L100m_mpe_polish_{phase_profile,evolution,phase_diagnostic,
#                            evolution_unshaped}.png
#   smf28_L100m_rre_polish_{...}.png
#   polish_mpe.jld2, polish_rre.jld2
#   history_source.jld2   — the phi_hist used, plus provenance
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
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "acceleration.jl"))

ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Module-level constants
# ─────────────────────────────────────────────────────────────────────────────

const P32M_LADDER_L     = [1.0, 10.0, 100.0]
const P32M_P_CONT       = 0.2
const P32M_NT           = 2^14
const P32M_TIME_WINDOW  = 40.0
const P32M_MAX_ITER     = 40
const P32M_BETA_ORDER   = 3

const P32M_TAG_MPE      = "smf28_L100m_mpe_polish"
const P32M_TAG_RRE      = "smf28_L100m_rre_polish"

const P32M_OUTDIR       = joinpath("results", "phase32", "expt2_mpe_rre_polish_L100m")
const P32M_RESULTS_PATH = joinpath(@__DIR__, "..", ".planning", "phases",
    "32-extrapolation-and-acceleration-for-parameter-studies-and-con",
    "32-RESULTS.md")

const P32M_PROBE_PATHS = [
    # Path A — Phase 30 artifacts
    ("phase30_jld2", [
        "results/phase30/continuation_L_100m/continuation_step_1.jld2",
        "results/phase30/continuation_L_100m/continuation_step_2.jld2",
        "results/phase30/continuation_L_100m/continuation_step_3.jld2",
    ]),
    # Path A' — Experiment 1 naive arm bundle (same 3 phi, same grid)
    ("phase32_expt1_naive", [
        "results/phase32/expt1_polywarmstart_L100m/results_naive.jld2",
    ]),
]

# ─────────────────────────────────────────────────────────────────────────────
# History acquisition — 3 paths, first-hit wins
# ─────────────────────────────────────────────────────────────────────────────

"""
    _load_phase30_steps() -> (phi_hist, L_hist) or (nothing, nothing)

Load Phase 30 `continuation_step_{1,2,3}.jld2`. Each file has `phi_opt`
(Vector{Float64}) and `L` (Float64). Returns `(nothing, nothing)` if any of
the three is missing.
"""
function _load_phase30_steps()
    paths = P32M_PROBE_PATHS[1][2]
    for p in paths
        isfile(p) || return (nothing, nothing)
    end
    phi_hist = Vector{Vector{Float64}}()
    L_hist   = Float64[]
    for p in paths
        d = JLD2.load(p)
        push!(phi_hist, Vector{Float64}(vec(d["phi_opt"])))
        push!(L_hist,   Float64(d["L"]))
    end
    @info "Loaded Phase 30 continuation history" paths=paths
    return phi_hist, L_hist
end

"""
    _load_phase32_expt1_naive() -> (phi_hist, L_hist) or (nothing, nothing)

Fallback Path A' — if Experiment 1 already ran and produced
`results_naive.jld2`, we can consume its `phi_hist`/`L_hist` directly.
"""
function _load_phase32_expt1_naive()
    p = P32M_PROBE_PATHS[2][2][1]
    isfile(p) || return (nothing, nothing)
    d = JLD2.load(p)
    haskey(d, "phi_hist") || return (nothing, nothing)
    phi_hist = [Vector{Float64}(vec(ph)) for ph in d["phi_hist"]]
    L_hist   = Vector{Float64}(vec(d["L_hist"]))
    @info "Loaded Phase 32 Expt 1 naive history" path=p
    return phi_hist, L_hist
end

"""
    _run_inline_ladder() -> (phi_hist, L_hist)

Path B — regenerate the 3-step SMF-28 warm-start ladder inline using
`run_ladder` with `setup_fn = setup_longfiber_problem` and default trivial
predictor (Phase 30 behaviour). Same grid as Experiment 1.
"""
function _run_inline_ladder()
    @info "No cached history found; running inline 3-step warm-start ladder"
    base_cfg = Dict{String,Any}(
        "P_cont"       => P32M_P_CONT,
        "Nt"           => P32M_NT,
        "time_window"  => P32M_TIME_WINDOW,
        "fiber_preset" => :SMF28,
        "β_order"      => P32M_BETA_ORDER,
        "λ_gdd"        => 1e-4,
        "λ_boundary"   => 1.0,
    )
    schedule = ContinuationSchedule(
        continuation_id   = "p32_expt2_inline_history",
        ladder_var        = :L,
        values            = P32M_LADDER_L,
        base_config       = base_cfg,
        predictor         = :trivial,
        corrector         = :lbfgs_warm_restart,
        max_iter_per_step = P32M_MAX_ITER,
    )
    setup_fn = function (cfg::Dict{String,Any})
        return setup_longfiber_problem(
            fiber_preset = get(cfg, "fiber_preset", :SMF28),
            L_fiber      = Float64(cfg["L_fiber"]),
            P_cont       = Float64(cfg["P_cont"]),
            Nt           = Int(cfg["Nt"]),
            time_window  = Float64(get(cfg, "time_window", P32M_TIME_WINDOW)),
            β_order      = Int(get(cfg, "β_order", P32M_BETA_ORDER)),
        )
    end
    results = run_ladder(schedule; setup_fn = setup_fn, cold_start = false)
    phi_hist = [Vector{Float64}(vec(r.phi_opt)) for r in results]
    L_hist   = [Float64(r.ladder_value) for r in results]
    return phi_hist, L_hist
end

"""
    _acquire_history() -> (phi_hist, L_hist, provenance::String)

First-hit-wins probe across Path A, Path A', Path B.
"""
function _acquire_history()
    ph, Lh = _load_phase30_steps()
    ph !== nothing && return ph, Lh, "phase30_continuation_step_1_2_3.jld2"

    ph, Lh = _load_phase32_expt1_naive()
    ph !== nothing && return ph, Lh, "phase32_expt1_naive_results_naive.jld2"

    ph, Lh = _run_inline_ladder()
    return ph, Lh, "inline_3step_ladder"
end

# ─────────────────────────────────────────────────────────────────────────────
# Combining + polish + verdict
# ─────────────────────────────────────────────────────────────────────────────

"""
    _build_final_problem() -> (uω0, fiber, sim, band_mask, Δf, raman_threshold)

Final-step (L=100m) problem; shared between the two polish runs AND the
standard-image renders.
"""
function _build_final_problem()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(
        fiber_preset = :SMF28,
        L_fiber      = P32M_LADDER_L[end],
        P_cont       = P32M_P_CONT,
        Nt           = P32M_NT,
        time_window  = P32M_TIME_WINDOW,
        β_order      = P32M_BETA_ORDER,
    )
    @assert sim["Nt"] == P32M_NT "Nt drift in setup_longfiber_problem"
    return uω0, fiber, sim, band_mask, Δf, raman_threshold
end

# ω axis (rad/ps) for project_gauge_phi. Matches get_disp_sim_params convention
# where sim["ωs"] is the FFT-ordered angular frequency vector in rad/ps.
function _omega_axis(sim::Dict{String,Any})
    if haskey(sim, "ωs")
        return Vector{Float64}(vec(sim["ωs"]))
    end
    Δt_ps = Float64(sim["Δt"])
    Nt = Int(sim["Nt"])
    ωs = 2π .* fftfreq(Nt, 1.0 / Δt_ps)   # rad/ps, FFT order
    return collect(ωs)
end

"""
    _gauge_fix_history(phi_hist, ω, band_mask) -> Vector{Vector{Float64}}

Apply `project_gauge_phi` to every past iterate so MPE/RRE combiners do not
amplify the two exact Hessian null-modes (mean shift + ω-linear slope on the
input band). Per RESEARCH §9 Q8.
"""
function _gauge_fix_history(phi_hist::AbstractVector{<:AbstractVector{<:Real}},
                            ω::AbstractVector{<:Real},
                            band_mask::AbstractVector{Bool})
    return [project_gauge_phi(Vector{Float64}(vec(p)), ω, band_mask) for p in phi_hist]
end

"""
    _apply_combiner(combine_name, phi_hist_gf) -> (phi_combined, γ, passed, reason, accel_tag)

Wrap `mpe_combine` / `rre_combine` with `safeguard_gamma`. On safeguard
failure, falls back to `phi_hist[end]` and returns `passed=false`.
Returns the accelerator enum string consumed by
`attach_acceleration_metadata!` (one of "mpe", "rre", "trivial").
"""
function _apply_combiner(combine_name::Symbol,
                         phi_hist_gf::Vector{Vector{Float64}})
    combiner = combine_name === :mpe ? mpe_combine :
               combine_name === :rre ? rre_combine :
               error("unknown combiner $(combine_name)")
    result = combiner(phi_hist_gf)
    passed, reason = safeguard_gamma(result.gamma;
        threshold = ACCEL_SAFEGUARD_GAMMA_MAX)
    if !passed
        @warn "Safeguard REJECTED combination — falling back to phi_hist[end]" combiner=combine_name reason=reason γmax=maximum(abs, result.gamma)
        return (Vector{Float64}(phi_hist_gf[end]),
                result.gamma, false, reason, "trivial")
    end
    tag = combine_name === :mpe ? "mpe" : "rre"
    return (Vector{Float64}(result.combined),
            result.gamma, true, reason, tag)
end

"""
    _polish_with_lbfgs(phi_init, uω0, fiber, sim, band_mask; max_iter) -> NamedTuple

Wrap `optimize_spectral_phase` to report phi_opt + J_dB + iters + wall_s.
Budget parity with Phase 30 / Experiment 1 (max_iter = 40).
"""
function _polish_with_lbfgs(phi_init::AbstractVector;
                            uω0, fiber, sim, band_mask,
                            max_iter::Integer = P32M_MAX_ITER)
    Nt = sim["Nt"]
    M  = sim["M"]
    @assert length(phi_init) == Nt "phi_init / sim[Nt] mismatch"
    φ0 = reshape(Vector{Float64}(vec(phi_init)), Nt, M)
    t0 = time()
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0 = φ0, max_iter = Int(max_iter),
        log_cost = true, store_trace = false)
    wall_s = time() - t0
    phi_opt = Vector{Float64}(vec(result.minimizer))
    J_dB    = Float64(result.minimum)           # log_cost=true → already dB
    iters   = Int(result.iterations)
    return (phi_opt = phi_opt, J_dB = J_dB, iters = iters, wall_s = wall_s)
end

"""
    _evaluate_J_dB(phi, uω0, fiber, sim, band_mask) -> Float64

Linear J from `cost_and_gradient`, then convert to dB. Used for the
`phi_hist[end]` baseline report (no polish).
"""
function _evaluate_J_dB(phi::AbstractVector; uω0, fiber, sim, band_mask)
    Nt = sim["Nt"]
    M  = sim["M"]
    J_lin, _ = cost_and_gradient(reshape(Vector{Float64}(vec(phi)), Nt, M),
                                 uω0, fiber, sim, band_mask; log_cost = false)
    return 10.0 * log10(max(Float64(J_lin), 1e-300))
end

# ─────────────────────────────────────────────────────────────────────────────
# Persistence
# ─────────────────────────────────────────────────────────────────────────────

function _save_polish_jld2(name::AbstractString, data::Dict{String,Any})
    path = joinpath(P32M_OUTDIR, "polish_$(name).jld2")
    mkpath(dirname(path))
    # Splat only Symbol-safe keys — JLD2.jldsave accepts NamedTuple splat.
    JLD2.jldopen(path, "w") do io
        for (k, v) in data
            io[String(k)] = v
        end
    end
    @info "Wrote polish JLD2" path=path arm=name
    return path
end

function _save_history_provenance(phi_hist, L_hist, provenance)
    path = joinpath(P32M_OUTDIR, "history_source.jld2")
    mkpath(dirname(path))
    JLD2.jldsave(path;
        phi_hist   = phi_hist,
        L_hist     = L_hist,
        provenance = provenance,
    )
    return path
end

# ─────────────────────────────────────────────────────────────────────────────
# Results doc
# ─────────────────────────────────────────────────────────────────────────────

function _render_experiment2_section(
    phi_hist::Vector{Vector{Float64}},
    L_hist::Vector{Float64},
    provenance::String,
    baseline_dB::Float64,
    baseline_iters::Int,
    mpe_outcome::Dict{String,Any},
    rre_outcome::Dict{String,Any},
    mpe_verdict::String,
    rre_verdict::String,
)
    mkpath(dirname(P32M_RESULTS_PATH))
    buf = IOBuffer()
    println(buf, "")
    println(buf, "## Experiment 2 — Offline MPE/RRE on Phase 30 3-point history")
    println(buf, "")
    println(buf, "_populated by scripts/mpe_offline.jl_")
    println(buf, "")
    println(buf, "Generated: ", Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"))
    println(buf, "")
    println(buf, "### History acquisition")
    println(buf, "")
    println(buf, "- Provenance: `$(provenance)`")
    println(buf, "- Ladder: L = $(L_hist) m")
    println(buf, "- Baseline endpoint (phi_hist[end]): **J = $(@sprintf("%.3f", baseline_dB)) dB** at L = $(L_hist[end]) m")
    println(buf, "")
    println(buf, "### Polish results (budget parity, max_iter = $(P32M_MAX_ITER))")
    println(buf, "")
    println(buf, "| Combiner | max|γ| | safeguard | safeguard reason | polish iters | polished J_dB | ΔJ vs naive (dB) |")
    println(buf, "|----------|--------|-----------|------------------|--------------|---------------|------------------|")
    for (name, out) in (("MPE", mpe_outcome), ("RRE", rre_outcome))
        γmax = Float64(get(out, "gamma_max", NaN))
        passed = Bool(get(out, "safeguard_passed", false)) ? "PASS" : "FAIL"
        reason = String(get(out, "safeguard_reason", ""))
        pit = Int(get(out, "polish_iters", 0))
        pdb = Float64(get(out, "polish_J_dB", NaN))
        ΔJ  = pdb - baseline_dB
        println(buf, @sprintf("| %s | %.3e | %s | %s | %d | %.3f | %+.3f |",
            name, γmax, passed, reason, pit, pdb, ΔJ))
    end
    println(buf, "")
    println(buf, "### Verdicts (per combiner, from `classify_acceleration_verdict`)")
    println(buf, "")
    println(buf, @sprintf("- **MPE: `%s`**", mpe_verdict))
    println(buf, @sprintf("- **RRE: `%s`**", rre_verdict))
    println(buf, "")
    println(buf, "### Standard images")
    println(buf, "")
    for tag in (P32M_TAG_MPE, P32M_TAG_RRE)
        for suffix in ("phase_profile", "evolution", "phase_diagnostic",
                       "evolution_unshaped")
            println(buf, @sprintf("- `%s/%s_%s.png`", P32M_OUTDIR, tag, suffix))
        end
    end
    println(buf, "")
    new_block = String(take!(buf))

    if isfile(P32M_RESULTS_PATH)
        existing = read(P32M_RESULTS_PATH, String)
        heading = "## Experiment 2 — Offline MPE/RRE on Phase 30 3-point history"
        idx = findfirst(heading, existing)
        if idx !== nothing
            before = existing[1:prevind(existing, first(idx))]
            next_idx = findnext(r"\n## ", existing, last(idx) + 1)
            after = next_idx === nothing ? "" : existing[first(next_idx):end]
            open(P32M_RESULTS_PATH, "w") do io
                write(io, rstrip(before), "\n", new_block, after)
            end
        else
            open(P32M_RESULTS_PATH, "a") do io
                write(io, new_block)
            end
        end
    else
        open(P32M_RESULTS_PATH, "w") do io
            write(io, "# Phase 32 Results — Extrapolation and Acceleration\n", new_block)
        end
    end
    @info "Wrote Experiment 2 section" path=P32M_RESULTS_PATH
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(P32M_OUTDIR)

    # 1. Acquire the 3-point history.
    phi_hist, L_hist, provenance = _acquire_history()
    @assert length(phi_hist) == 3 "expected 3 past iterates, got $(length(phi_hist))"
    @assert all(length(p) == P32M_NT for p in phi_hist) "phi_hist grid mismatch with P32M_NT=$P32M_NT"
    _save_history_provenance(phi_hist, L_hist, provenance)

    # 2. Build the final-step (L=100m) problem once. Reused for polish + images.
    uω0, fiber, sim, band_mask, Δf, raman_threshold = _build_final_problem()
    ω_axis = _omega_axis(sim)

    # 3. Gauge-project each past iterate before combining (RESEARCH §9 Q8).
    phi_hist_gf = _gauge_fix_history(phi_hist, ω_axis, band_mask)

    # 4. Baseline for comparison: J_dB at phi_hist[end] with NO polish
    #    (reports how good the Phase 30 naive endpoint is).
    baseline_phi   = Vector{Float64}(phi_hist[end])
    baseline_J_dB  = _evaluate_J_dB(baseline_phi;
        uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask)
    baseline_iters = P32M_MAX_ITER   # Phase 30 used this budget on its final step

    # 5. MPE arm — combine, gate, polish, record.
    @info "──────── MPE arm ────────"
    phi_mpe, γ_mpe, ok_mpe, reason_mpe, accel_mpe = _apply_combiner(:mpe, phi_hist_gf)
    polish_mpe = _polish_with_lbfgs(phi_mpe;
        uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
        max_iter = P32M_MAX_ITER)
    mpe_outcome = Dict{String,Any}(
        "gamma"             => γ_mpe,
        "gamma_max"         => Float64(maximum(abs, γ_mpe)),
        "safeguard_passed"  => ok_mpe,
        "safeguard_reason"  => reason_mpe,
        "accelerator"       => accel_mpe,
        "phi_combined"      => phi_mpe,
        "polish_phi"        => polish_mpe.phi_opt,
        "polish_J_dB"       => polish_mpe.J_dB,
        "polish_iters"      => polish_mpe.iters,
        "polish_wall_s"     => polish_mpe.wall_s,
    )
    _save_polish_jld2("mpe", mpe_outcome)

    # 6. RRE arm — same drill.
    @info "──────── RRE arm ────────"
    phi_rre, γ_rre, ok_rre, reason_rre, accel_rre = _apply_combiner(:rre, phi_hist_gf)
    polish_rre = _polish_with_lbfgs(phi_rre;
        uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
        max_iter = P32M_MAX_ITER)
    rre_outcome = Dict{String,Any}(
        "gamma"             => γ_rre,
        "gamma_max"         => Float64(maximum(abs, γ_rre)),
        "safeguard_passed"  => ok_rre,
        "safeguard_reason"  => reason_rre,
        "accelerator"       => accel_rre,
        "phi_combined"      => phi_rre,
        "polish_phi"        => polish_rre.phi_opt,
        "polish_J_dB"       => polish_rre.J_dB,
        "polish_iters"      => polish_rre.iters,
        "polish_wall_s"     => polish_rre.wall_s,
    )
    _save_polish_jld2("rre", rre_outcome)

    # 7. Verdict per combiner.
    mpe_metrics = Dict{String,Any}(
        "savings_frac"        => baseline_iters > 0 ?
            (baseline_iters - polish_mpe.iters) / baseline_iters : 0.0,
        "worst_verdict_delta" => 0,                  # trust not compared here
        "db_delta"            => polish_mpe.J_dB - baseline_J_dB,
        "new_hard_halt"       => !isfinite(polish_mpe.J_dB),
    )
    rre_metrics = Dict{String,Any}(
        "savings_frac"        => baseline_iters > 0 ?
            (baseline_iters - polish_rre.iters) / baseline_iters : 0.0,
        "worst_verdict_delta" => 0,
        "db_delta"            => polish_rre.J_dB - baseline_J_dB,
        "new_hard_halt"       => !isfinite(polish_rre.J_dB),
    )
    mpe_verdict = classify_acceleration_verdict(mpe_metrics)
    rre_verdict = classify_acceleration_verdict(rre_metrics)

    # 8. Build a minimal trust report for each polish arm and attach
    #    acceleration metadata (schema 28.0 stays literal).
    det_status = deterministic_environment_status()
    for (tag, outcome, verdict) in (
            (P32M_TAG_MPE, mpe_outcome, mpe_verdict),
            (P32M_TAG_RRE, rre_outcome, rre_verdict))
        trust = build_numerical_trust_report(;
            det_status = det_status,
            edge_input_frac  = NaN,   # not measured in this offline driver
            edge_output_frac = NaN,
            energy_drift     = NaN,
            gradient_validation = nothing,
            log_cost    = true,
            λ_gdd       = 0.0,
            λ_boundary  = 0.0,
            objective_label = "phase32 expt2 polish $(tag)",
        )
        attach_acceleration_metadata!(trust, Dict{String,Any}(
            "accelerator"       => String(outcome["accelerator"]),
            "prediction_norm"   => Float64(norm(outcome["phi_combined"])),
            "coefficient_max"   => Float64(outcome["gamma_max"]),
            "safeguard_passed"  => Bool(outcome["safeguard_passed"]),
            "safeguard_reason"  => String(outcome["safeguard_reason"]),
            "corrector_iters"   => Int(outcome["polish_iters"]),
            "j_opt_db_delta"    => Float64(outcome["polish_J_dB"]) - baseline_J_dB,
            "verdict"           => String(verdict),
        ))
        trust_path = joinpath(P32M_OUTDIR, "trust", "$(tag)_trust.md")
        mkpath(dirname(trust_path))
        write_numerical_trust_report(trust_path, trust)
    end

    # 9. Standard images — 2 arms × 4 panels = 8 PNGs.
    save_standard_set(
        Vector{Float64}(vec(polish_mpe.phi_opt)),
        uω0, fiber, sim, band_mask, Δf, raman_threshold;
        tag        = P32M_TAG_MPE,
        fiber_name = "SMF28",
        L_m        = P32M_LADDER_L[end],
        P_W        = P32M_P_CONT,
        output_dir = P32M_OUTDIR,
    )
    @info "Standard image set written" arm="MPE" tag=P32M_TAG_MPE dir=P32M_OUTDIR

    save_standard_set(
        Vector{Float64}(vec(polish_rre.phi_opt)),
        uω0, fiber, sim, band_mask, Δf, raman_threshold;
        tag        = P32M_TAG_RRE,
        fiber_name = "SMF28",
        L_m        = P32M_LADDER_L[end],
        P_W        = P32M_P_CONT,
        output_dir = P32M_OUTDIR,
    )
    @info "Standard image set written" arm="RRE" tag=P32M_TAG_RRE dir=P32M_OUTDIR

    # 10. Append to 32-RESULTS.md.
    _render_experiment2_section(phi_hist, L_hist, provenance,
        baseline_J_dB, baseline_iters,
        mpe_outcome, rre_outcome,
        mpe_verdict, rre_verdict)

    @info "Phase 32 Experiment 2 complete" mpe_verdict=mpe_verdict rre_verdict=rre_verdict
    return (mpe_outcome, rre_outcome, mpe_verdict, rre_verdict, provenance)
end

# Main guard — `include` at REPL / load-check defines functions without
# triggering polish runs.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
