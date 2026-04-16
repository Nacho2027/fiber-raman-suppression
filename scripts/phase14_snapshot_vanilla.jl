# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 Plan 01 — one-time snapshot of the vanilla optimizer
# ═══════════════════════════════════════════════════════════════════════════════
#
# Purpose: capture a fixed-seed, fixed-config run of the CURRENT (pre-Phase-14)
# `optimize_spectral_phase` pipeline so that `test/test_phase14_regression.jl`
# can later assert the original path is unchanged after Phase 14 modifications.
#
# This script is run ONCE, before any Phase 14 code is merged into the
# production pipeline. It is intentionally standalone, and writes
# `results/raman/phase14/vanilla_snapshot.jld2` plus a companion FFTW wisdom
# file (`fftw_wisdom.txt`) to minimise cross-process FFTW.MEASURE non-determinism
# (see `results/raman/phase13/determinism.md`).
#
# Usage:
#   julia --project=. scripts/phase14_snapshot_vanilla.jl
#
# Re-running is idempotent: the JLD2 will be overwritten with the same values
# assuming FFTW wisdom caching holds. The companion regression test imports
# the wisdom file, then re-runs with the same seed and compares against
# tolerance thresholds calibrated from Phase 13 determinism findings.
# ═══════════════════════════════════════════════════════════════════════════════

using Random
using FFTW
using LinearAlgebra
using Printf
using JLD2
using Dates

# Pin single-threaded FFTW and BLAS BEFORE loading MultiModeNoise so that any
# internal plan construction picks the single-thread algorithm path.
# MultiModeNoise.jl's src/simulation/*.jl files use `flags=FFTW.MEASURE` which
# is non-deterministic in plan selection cross-process; single-threaded +
# wisdom export mitigates (but does not eliminate) the drift.
FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

# Import previously-saved wisdom if it exists, so MEASURE-mode plan creation
# reuses cached plans deterministically. Safe to skip on the very first run.
const SN_WISDOM_PATH = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
if isfile(SN_WISDOM_PATH)
    try
        FFTW.import_wisdom(SN_WISDOM_PATH)
        @info "Imported FFTW wisdom from $SN_WISDOM_PATH"
    catch e
        @warn "Could not import FFTW wisdom; proceeding with fresh MEASURE" exception = e
    end
end

# Load READ-ONLY production pipeline.  Must be in Main so `cost_and_gradient`
# and `optimize_spectral_phase` are globally available.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Fixed configuration — do NOT change without bumping the snapshot version
# ─────────────────────────────────────────────────────────────────────────────

const SN_SEED = 42
const SN_MAX_ITER = 15        # kept modest so FFTW non-determinism drift stays < 1 dB
const SN_FIBER = :SMF28
const SN_P_CONT = 0.2         # W
const SN_L_FIBER = 2.0        # m
const SN_NT = 2^13            # 8192
const SN_TIME_WINDOW = 40.0   # ps (will auto-grow via setup if too small)
const SN_BETA_ORDER = 3
const SN_LAMBDA_GDD = 1e-4
const SN_LAMBDA_BOUNDARY = 1.0
const SN_LOG_COST = true

@info "Phase 14 snapshot: configuration" seed=SN_SEED max_iter=SN_MAX_ITER fiber=SN_FIBER P_cont=SN_P_CONT L=SN_L_FIBER Nt=SN_NT

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────

Random.seed!(SN_SEED)

uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
    fiber_preset = SN_FIBER,
    P_cont = SN_P_CONT,
    L_fiber = SN_L_FIBER,
    Nt = SN_NT,
    time_window = SN_TIME_WINDOW,
    β_order = SN_BETA_ORDER,
)

Nt_actual = sim["Nt"]
M_actual = sim["M"]
@info "Setup complete" Nt_actual = Nt_actual M_actual = M_actual band_bins = sum(band_mask)

φ0 = zeros(Nt_actual, M_actual)

t0 = time()
result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
    φ0 = φ0,
    max_iter = SN_MAX_ITER,
    λ_gdd = SN_LAMBDA_GDD,
    λ_boundary = SN_LAMBDA_BOUNDARY,
    store_trace = true,
    log_cost = SN_LOG_COST,
)
elapsed = time() - t0

phi_opt = reshape(Optim.minimizer(result), Nt_actual, M_actual)
J_final_optim = Optim.minimum(result)   # already in dB if log_cost=true

# Compute physical J (linear) at phi_opt via a final (unscaled) cost eval
J_final_linear, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask)

iterations = Optim.iterations(result)
converged = Optim.converged(result)
history = collect(Optim.f_trace(result))

@info @sprintf(
    "Snapshot run done: %d iters, J_final = %.6e (%.3f dB), wall %.1f s",
    iterations, J_final_linear, 10 * log10(max(J_final_linear, 1e-15)), elapsed,
)

# ─────────────────────────────────────────────────────────────────────────────
# Serialize
# ─────────────────────────────────────────────────────────────────────────────

out_dir = joinpath(@__DIR__, "..", "results", "raman", "phase14")
mkpath(out_dir)
out_path = joinpath(out_dir, "vanilla_snapshot.jld2")

jldsave(out_path;
    # Identification
    phase = "14",
    plan = "01",
    snapshot_version = "1.0",
    created_at = string(Dates.now()),
    # Config (for regression test to reproduce exactly)
    seed = SN_SEED,
    max_iter = SN_MAX_ITER,
    fiber_preset = string(SN_FIBER),
    P_cont = SN_P_CONT,
    L_fiber = SN_L_FIBER,
    Nt = SN_NT,
    time_window = SN_TIME_WINDOW,
    beta_order = SN_BETA_ORDER,
    lambda_gdd = SN_LAMBDA_GDD,
    lambda_boundary = SN_LAMBDA_BOUNDARY,
    log_cost = SN_LOG_COST,
    # Results
    phi_opt = phi_opt,
    J_final_optim = J_final_optim,      # dB if log_cost=true, linear otherwise
    J_final_linear = J_final_linear,
    iterations = iterations,
    converged = converged,
    convergence_history = history,
    wall_time_s = elapsed,
)

# Export FFTW wisdom so the regression test can reuse the same plans.
try
    FFTW.export_wisdom(SN_WISDOM_PATH)
    @info "Exported FFTW wisdom to $SN_WISDOM_PATH"
catch e
    @warn "Could not export FFTW wisdom" exception = e
end

@info "Snapshot written to $out_path"
