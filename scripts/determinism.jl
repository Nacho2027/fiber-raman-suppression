# ═══════════════════════════════════════════════════════════════════════════════
# Phase 15 — Deterministic Numerical Environment
# ═══════════════════════════════════════════════════════════════════════════════
# Fixes the max|Δφ| = 1.04 rad non-determinism bug found in Phase 13 Plan 01
# (see results/raman/phase13/determinism.md for the empirical baseline).
#
# Root cause: FFTW.MEASURE plan selection is timing-dependent — different runs
# can pick different FFT algorithms whose numerical behavior differs slightly,
# and those differences compound through L-BFGS iterations + adjoint ODE.
#
# Usage:
#   include(joinpath(@__DIR__, "determinism.jl"))
#   ensure_deterministic_environment()
#   Random.seed!(42)  # caller still controls the seed
#
# The helper also patches the handful of hardcoded `flags=FFTW.MEASURE`
# plan-builder calls in `src/simulation/*.jl` — see the companion mechanical
# replacement done in Phase 15 Plan 01 Task 1.5. Together they give full,
# bit-identical reproducibility on a single machine/Julia version.
#
# This file is include-guarded: safe to include any number of times.
# ═══════════════════════════════════════════════════════════════════════════════

# Module-level imports must live OUTSIDE the include guard so macros are
# visible at compile time (per STATE.md "Include Guards" convention).
using FFTW
using LinearAlgebra

if !(@isdefined _DETERMINISM_JL_LOADED)
const _DETERMINISM_JL_LOADED = true

const DET_VERSION = "1.0.0"
const DET_PHASE = "15-01"

# State flag (Ref so we can mutate under const) — avoids re-applying the pins
# on every call. Safe because FFTW / BLAS thread pools and planner flags are
# process-global; once they are set, they stay set for the lifetime of the
# Julia process.
const _DETERMINISM_APPLIED = Ref(false)

"""
    ensure_deterministic_environment(; force::Bool=false, verbose::Bool=false)

Pin numerical environment settings so identical inputs + identical `Random.seed!`
produce bit-identical outputs. Safe to call any number of times — the effects
are idempotent.

Sets (process-global, persists for the lifetime of the Julia process):
- `FFTW.set_provider!` is *not* touched (the active provider — FFTW vs MKL — is
  a build-time decision; we only influence planner flags).
- `FFTW.set_num_threads(1)` — kills threading reduction-order variance in FFTs.
- `LinearAlgebra.BLAS.set_num_threads(1)` — same for BLAS reductions.

FFTW's `set_planner_flags` is NOT a public API (was removed in FFTW.jl ≥ 1.0).
Per-call planner flags are the canonical way to choose between MEASURE and
ESTIMATE, so the complementary patch in `src/simulation/*.jl` (Task 1.5 of the
plan) swaps `flags=FFTW.MEASURE` → `flags=FFTW.ESTIMATE` at each `plan_fft!` /
`plan_ifft!` / `plan_fft` call site. That patch + this helper together give the
deterministic guarantee.

Does NOT set a random seed — callers should `Random.seed!(N)` explicitly.

Keyword arguments:
- `force=true`  — re-apply pins even if already applied (rarely needed; useful
                  if something else in the process changed the thread counts
                  after first application).
- `verbose=true` — log the applied settings at `@info` level instead of `@debug`.

Returns `nothing`.
"""
function ensure_deterministic_environment(; force::Bool=false, verbose::Bool=false)
    if _DETERMINISM_APPLIED[] && !force
        return nothing
    end
    FFTW.set_num_threads(1)
    LinearAlgebra.BLAS.set_num_threads(1)
    _DETERMINISM_APPLIED[] = true
    if verbose
        @info "Deterministic environment applied" FFTW_threads=1 BLAS_threads=1 planner_flags="ESTIMATE (via src/simulation/*.jl patch)" version=DET_VERSION
    else
        @debug "Deterministic environment applied" FFTW_threads=1 BLAS_threads=1 planner_flags="ESTIMATE (via src/simulation/*.jl patch)" version=DET_VERSION
    end
    return nothing
end

"""
    deterministic_environment_status()

Return a NamedTuple describing the currently active deterministic-environment
pins. Useful for sanity-logging at the top of a run.
"""
function deterministic_environment_status()
    return (
        applied      = _DETERMINISM_APPLIED[],
        fftw_threads = FFTW.get_num_threads(),
        blas_threads = LinearAlgebra.BLAS.get_num_threads(),
        version      = DET_VERSION,
        phase        = DET_PHASE,
    )
end

end  # include guard
