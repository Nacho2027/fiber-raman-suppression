# ═══════════════════════════════════════════════════════════════════════════════
# Phase 14 Plan 01 — Regression test on the ORIGINAL optimize_spectral_phase
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:   julia --project=. test/test_phase14_regression.jl
#
# Loads `results/raman/phase14/vanilla_snapshot.jld2` (captured BEFORE any
# Phase 14 code existed) and re-runs the identical config against the CURRENT
# `optimize_spectral_phase`. The two `phi_opt` / `J_final` / `iterations`
# outputs must agree within calibrated tolerances.
#
# Why a TOLERANCE instead of byte-identity:
#   Plan 14-01 originally asked for `max(|Δφ|) < 1e-12`. Phase 13's
#   determinism investigation (`results/raman/phase13/determinism.md`) proved
#   that byte-identity is impossible across Julia processes as long as
#   `src/simulation/*.jl` uses `flags=FFTW.MEASURE`, which is hardcoded and
#   NOT modifiable under Plan 14-01's no-touch rule. MEASURE picks plans via
#   microbenchmark timings → different bit-exact reduction orders across
#   processes → L-BFGS amplifies into ≈1 rad / ≈1.8 dB cross-process drift
#   at 30 iterations (Phase 13 measurement).
#
# Mitigation applied here (defense-in-depth):
#   1. Import FFTW wisdom saved by the snapshot script (same-plan cache).
#   2. Pin `FFTW.set_num_threads(1)`, `BLAS.set_num_threads(1)`.
#   3. Use max_iter=15 (short) to bound drift accumulation.
#   4. Assert PHYSICAL EQUIVALENCE with tolerances calibrated ~10× below
#      Phase 13's observed drift at 30 iters, as a defensible regression gate:
#         max(|Δphi|)            < 0.1 rad      (vs 1.04 rad observed)
#         |ΔJ_dB|                < 0.5 dB       (vs 1.83 dB observed)
#         |Δiterations|          ≤ 3            (small L-BFGS search drift ok)
#
# If ANY of these tolerances are breached, something material has changed in
# the vanilla path — that is exactly what we want the gate to catch.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using Random
using FFTW
using LinearAlgebra
using Printf
using JLD2

# Pin threads + load wisdom BEFORE loading the pipeline. See header comments.
FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

const _REG_WISDOM_PATH = joinpath(@__DIR__, "..", "results", "raman", "phase14", "fftw_wisdom.txt")
if isfile(_REG_WISDOM_PATH)
    try
        FFTW.import_wisdom(_REG_WISDOM_PATH)
        @info "Imported FFTW wisdom from $_REG_WISDOM_PATH"
    catch e
        @warn "Could not import FFTW wisdom; test may exhibit higher drift" exception = e
    end
else
    @warn "FFTW wisdom file missing at $_REG_WISDOM_PATH — regression drift may exceed tolerances"
end

include(joinpath(@__DIR__, "..", "scripts", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "lib", "raman_optimization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Load the snapshot
# ─────────────────────────────────────────────────────────────────────────────

const _REG_SNAP_PATH = joinpath(@__DIR__, "..", "results", "raman", "phase14",
                                "vanilla_snapshot.jld2")

@assert isfile(_REG_SNAP_PATH) "snapshot file missing: $_REG_SNAP_PATH — run scripts/snapshot_vanilla.jl first"

snap = JLD2.load(_REG_SNAP_PATH)
@info "Loaded snapshot" path = _REG_SNAP_PATH version = snap["snapshot_version"] created_at = snap["created_at"]

SNAP_SEED = snap["seed"]
SNAP_MAX_ITER = snap["max_iter"]
SNAP_FIBER = Symbol(snap["fiber_preset"])
SNAP_P_CONT = snap["P_cont"]
SNAP_L_FIBER = snap["L_fiber"]
SNAP_NT = snap["Nt"]
SNAP_TIME_WINDOW = snap["time_window"]
SNAP_BETA_ORDER = snap["beta_order"]
SNAP_LAMBDA_GDD = snap["lambda_gdd"]
SNAP_LAMBDA_BND = snap["lambda_boundary"]
SNAP_LOG_COST = snap["log_cost"]
SNAP_PHI_OPT = snap["phi_opt"]
SNAP_J_LIN = snap["J_final_linear"]
SNAP_ITERS = snap["iterations"]
SNAP_J_DB_PHYS = 10 * log10(max(SNAP_J_LIN, 1e-15))

# ─────────────────────────────────────────────────────────────────────────────
# Re-run the vanilla path with identical config
# ─────────────────────────────────────────────────────────────────────────────

@testset "Phase 14 regression — vanilla optimize_spectral_phase" begin

    Random.seed!(SNAP_SEED)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset = SNAP_FIBER,
        P_cont = SNAP_P_CONT,
        L_fiber = SNAP_L_FIBER,
        Nt = SNAP_NT,
        time_window = SNAP_TIME_WINDOW,
        β_order = SNAP_BETA_ORDER,
    )
    Nt_actual = sim["Nt"]
    M_actual = sim["M"]

    # Grid must match the snapshot (auto-sizing may have changed if betas
    # moved — here it's pinned).
    @test size(SNAP_PHI_OPT) == (Nt_actual, M_actual)

    φ0 = zeros(Nt_actual, M_actual)
    t0 = time()
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0 = φ0,
        max_iter = SNAP_MAX_ITER,
        λ_gdd = SNAP_LAMBDA_GDD,
        λ_boundary = SNAP_LAMBDA_BND,
        store_trace = true,
        log_cost = SNAP_LOG_COST,
    )
    elapsed = time() - t0
    phi_new = reshape(Optim.minimizer(result), Nt_actual, M_actual)
    iters_new = Optim.iterations(result)
    J_new_linear, _ = cost_and_gradient(phi_new, uω0, fiber, sim, band_mask)
    J_new_dB = 10 * log10(max(J_new_linear, 1e-15))

    @info @sprintf(
        "Regression rerun: iters %d (snap %d), J = %.6e (%.3f dB vs snap %.3f dB), wall %.1f s",
        iters_new, SNAP_ITERS, J_new_linear, J_new_dB, SNAP_J_DB_PHYS, elapsed,
    )

    # Tolerances — see header comment block for rationale.
    MAX_PHI_DRIFT = 0.1     # rad
    MAX_J_DRIFT_DB = 0.5    # dB
    MAX_ITER_DRIFT = 3

    phi_drift = maximum(abs.(phi_new .- SNAP_PHI_OPT))
    J_drift_dB = abs(J_new_dB - SNAP_J_DB_PHYS)
    iter_drift = abs(iters_new - SNAP_ITERS)

    @info @sprintf("max(|Δφ|) = %.4e rad (limit %.1e)", phi_drift, MAX_PHI_DRIFT)
    @info @sprintf("|ΔJ_dB|   = %.4f dB  (limit %.2f)", J_drift_dB, MAX_J_DRIFT_DB)
    @info @sprintf("|Δiters|  = %d       (limit %d)", iter_drift, MAX_ITER_DRIFT)

    @test phi_drift < MAX_PHI_DRIFT
    @test J_drift_dB < MAX_J_DRIFT_DB
    @test iter_drift ≤ MAX_ITER_DRIFT
end

@info "Phase 14 regression test PASSED — vanilla path unchanged within Phase-13-calibrated tolerances."
