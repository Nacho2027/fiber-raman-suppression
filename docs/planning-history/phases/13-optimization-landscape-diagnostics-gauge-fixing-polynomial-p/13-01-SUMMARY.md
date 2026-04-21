---
phase: 13-optimization-landscape-diagnostics
plan: 01
subsystem: optimization-diagnostics
tags: [gauge-fix, polynomial-projection, lbfgs, adjoint, fftw, determinism, raman]

# Dependency graph
requires:
  - phase: 07-parameter-sweeps
    provides: 24 JLD2 sweep optima (12 SMF-28 + 12 HNLF) at Nt=8192
  - phase: 11-classical-physics-completion
    provides: 10-start multistart JLD2 at SMF-28 P=0.2W L=2m
  - phase: 06-cross-run-comparison
    provides: 5 canonical run JLD2 files
provides:
  - "Tested primitives library (scripts/phase13_primitives.jl) with gauge_fix, polynomial_project, phase_similarity, determinism_check, input_band_mask"
  - "Full gauge-fixed + polynomial-decomposed dataset for all 39 existing phi_opt (results/raman/phase13/gauge_polynomial_analysis.jld2 + .csv)"
  - "Three diagnostic figures establishing NO-COLLAPSE and NO-POLYNOMIAL-DOMINANCE findings"
  - "Determinism baseline: FFTW.MEASURE non-determinism quantified (max|Δφ|=1.04 rad, ΔJ=-1.83 dB)"
affects: [13-02-hessian-eigenspectrum, 14-sharpness-aware-optimization]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "P13_ const prefix for phase-13 scripts (alongside existing RC_, SW_, SR_)"
    - "Module-level using outside include-guards (STATE.md convention, enforced)"
    - "Base.invokelatest for Julia 1.12 cross-include world-age safety"
    - "QR-orthonormalised monomial projection for numerical stability at high polynomial order"
    - "Dropping residual>=0.95 records from coefficient scatter plots with symlog scaling"

key-files:
  created:
    - scripts/phase13_primitives.jl
    - scripts/phase13_gauge_and_polynomial.jl
    - test/test_phase13_primitives.jl
    - results/raman/phase13/gauge_polynomial_analysis.jld2
    - results/raman/phase13/gauge_polynomial_summary.csv
    - results/raman/phase13/determinism.md
    - results/images/phase13/phase13_01_gauge_before_after.png
    - results/images/phase13/phase13_02_polynomial_residuals.png
    - results/images/phase13/phase13_03_polynomial_coefficients.png
  modified: []

key-decisions:
  - "Gauge-fix recipe: subtract mean(phi[band_input]) globally, then fit and subtract alpha*(omega - mean(omega_band)) globally (centered regression for numerical decoupling of C and alpha)"
  - "Input-band mask reconstructed from |uomega0|^2 at 99.9% cumulative energy cutoff (JLD2 band_mask field is the OUTPUT Raman mask, not what PITFALLS.md Pitfall 4 calls band_mask_input)"
  - "Polynomial basis: QR-orthonormalised monomials {x^2, x^3, x^4, x^5, x^6} on x = 2*(omega - omega_mean)/omega_range in [-1,1] over the input band"
  - "Residual fraction = ||phi_gf - phi_poly||^2_band / max(||phi_gf||^2_band, eps) with denominator guard"
  - "Collapse threshold: rms_gauge_fixed < 10% * rms_raw for same-config pairs"
  - "Determinism check pinned to FFTW.set_num_threads(1) and BLAS.set_num_threads(1) with Random.seed!(42)"

patterns-established:
  - "Pattern 1: Lazy include of raman_optimization.jl only when determinism_check is called (keeps primitives library lightweight, avoids PyPlot startup cost for test runs)"
  - "Pattern 2: Lazy Base.invokelatest for cross-include function calls under Julia 1.12 stricter world-age semantics"
  - "Pattern 3: Residual-aware plot filtering (drop records where polynomial fit is saturated noise) with explicit subtitle annotation"

requirements-completed:
  - "P13-01-A: Analysis primitives library with unit tests"
  - "P13-01-B: Determinism baseline established empirically"
  - "P13-01-C: Gauge fix applied to all existing multi-start + sweep phi_opt; before/after phase similarity reported"
  - "P13-01-D: GDD/TOD/FOD polynomial projection across starts AND parameter sweeps"
  - "P13-01-E: Scripts do NOT modify common.jl, raman_optimization.jl, or any src/simulation files"

# Metrics
duration: ~40 min
completed: 2026-04-16
---

# Phase 13 Plan 01: Gauge-Fix + Polynomial Projection Summary

**Diagnostic primitives (gauge_fix, polynomial_project, phase_similarity, determinism_check) validated by 31 unit tests; applied to 39 existing phi_opt confirming that L-BFGS optima are NOT gauge-equivalent and are NOT dominated by low-order polynomial structure. FFTW.MEASURE-mode non-determinism empirically quantified.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-04-16T18:05:00Z
- **Completed:** 2026-04-16T18:40:00Z
- **Tasks:** 5 (all completed)
- **Files created:** 9

## Accomplishments

1. **Primitives library shipped and tested.** 31 unit tests pass (`julia --project=. test/test_phase13_primitives.jl`). Covers gauge-fix idempotence, gauge invariance (removes C + alpha*omega exactly), polynomial recovery under both clean and noisy inputs, phase-similarity symmetry, shape preservation, and input-band mask construction.
2. **All 39 existing phi_opt processed through the pipeline** — 5 canonical + 24 sweep + 10 multistart. CSV summary and JLD2 serialisation written.
3. **Three diagnostic figures generated** (Fig 1 gauge-before-after, Fig 2 residual bars, Fig 3 coefficient symlog scatter) at 300 DPI.
4. **Determinism baseline established empirically.** Non-deterministic by 1.04 rad / 1.83 dB due to FFTW.MEASURE; cause diagnosed and documented for Plan 02 / Phase 14 to act on.
5. **No modifications to protected files.** `git diff` against common.jl, raman_optimization.jl, and src/simulation/ shows zero lines changed.

## Task Commits

1. **Task 1: Primitives library + unit tests** — `cfad5dc` (feat)
2. **Task 2+4: Analysis pipeline + 3 figures** — `15395f0` (feat)
3. **Task 3: Determinism check + FFTW diagnosis** — `9003b44` (feat)

## Verdict Table

| Claim | Verdict | Quantification |
|---|---|---|
| Determinism: identical seed → identical phi_opt | **FAIL** | max|Δφ| = 1.04 rad, ΔJ = -1.83 dB |
| Gauge fix collapses multi-start phases | **FALSE** | 0/55 same-config pairs collapsed (threshold: rms_gf < 10% rms_raw) |
| Gauge fix collapses sweep-neighbour phases | **FALSE** | same 0/55 pairs; alpha & C already near zero in raw phi_opt |
| Low-order polynomial (orders 2..6) explains phi | **WEAKLY** | median residual fraction = 0.924; only 0/39 optima under 50% residual; 9/39 under 80% residual |
| (a_2, a_3, a_4) vary smoothly across (L, P) | **PARTIAL** | Clear (a_2, a_4) anti-correlation in middle panel of Fig 3 (3 decades spanned) but scatter dominates (a_3)-dependent panels; 3 HNLF sweep optima dropped for residual >= 0.95 |

## Files Created/Modified

- `scripts/phase13_primitives.jl` (411 lines) — Library: gauge_fix, polynomial_project, phase_similarity, input_band_mask, omega_vector, determinism_check, cost_invariance_under_gauge
- `scripts/phase13_gauge_and_polynomial.jl` (480 lines) — Entry point: processes all JLD2 optima, writes 3 figures + 1 JLD2 + 1 CSV + determinism.md
- `test/test_phase13_primitives.jl` (158 lines) — 31 unit tests in 10 testsets
- `results/raman/phase13/gauge_polynomial_analysis.jld2` (12 MB) — Per-optimum gauge-fixed phi, polynomial coefficients a2..a6, residual fractions, pairwise similarity matrices
- `results/raman/phase13/gauge_polynomial_summary.csv` (40 rows, 20 cols) — Tabular summary for quick inspection
- `results/raman/phase13/determinism.md` — Determinism verdict + FFTW root-cause diagnosis
- `results/images/phase13/phase13_01_gauge_before_after.png` — Multi-start overlay: raw vs gauge-fixed, zoomed to input band
- `results/images/phase13/phase13_02_polynomial_residuals.png` — Residual fraction per optimum, grouped, log y
- `results/images/phase13/phase13_03_polynomial_coefficients.png` — (a2,a3), (a2,a4), (a3,a4) symlog scatter across sweeps

## Decisions Made

See frontmatter `key-decisions`. Highlights:
- The JLD2 `band_mask` field is the OUTPUT Raman-band mask, not the `band_mask_input` that PITFALLS.md Pitfall 4 prescribes. Rebuilt the input mask from |uomega0|^2 energy accumulation (99.9% cutoff) — this is documented in the primitives library and would have been a subtle trap for Plan 02.
- Determinism check results are NOT a bug to fix but a diagnostic finding. The project has been tolerating FFTW.MEASURE non-determinism unknowingly. Any future comparison that re-runs an optimization needs to account for this (see `results/raman/phase13/determinism.md` §Implication).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Module-level `using` statements**
- **Found during:** Task 1 (first test run)
- **Issue:** First run errored with `UndefVarError: @sprintf not defined in Main` — macros behind an `if !(@isdefined _GUARD)` guard aren't visible at compile-time per STATE.md's "Include Guards" section.
- **Fix:** Moved `using LinearAlgebra, Statistics, Printf, Random, FFTW` and the `include("common.jl")` outside the guard block; kept constant + function definitions inside.
- **Files modified:** `scripts/phase13_primitives.jl`
- **Verification:** Tests pass after fix.
- **Committed in:** `cfad5dc`

**2. [Rule 1 - Bug] Polynomial-project test expectations**
- **Found during:** Task 1 (test run after primitives fix)
- **Issue:** Original test expected a polynomial-in-x input to be recovered exactly by `gauge_fix` + `polynomial_project`. But on a finite symmetric band, x^3 and x^5 have nonzero least-squares linear slopes, so gauge_fix removes a linear term, leaving a linear residual that orders 2..6 cannot represent. Test was asking for an impossible thing.
- **Fix:** Split into Test 3 (polynomial_project on a pure polynomial input WITHOUT gauge_fix, passes exactly) and Test 3b (even polynomial under gauge_fix — confirms alpha=0 and mean-only removal). Both pass.
- **Files modified:** `test/test_phase13_primitives.jl`
- **Committed in:** `cfad5dc`

**3. [Rule 2 - Missing critical] Documented FFTW.MEASURE-mode non-determinism**
- **Found during:** Task 3
- **Issue:** Determinism check failed (max|Δφ| = 1.04 rad). Plan said "if it fails, investigate FFTW/BLAS threading". Single-thread pinning didn't help. Root cause is FFTW.MEASURE-mode plan construction picking different algorithms per invocation based on microbenchmark timing noise.
- **Fix:** Documented in `results/raman/phase13/determinism.md` with three downstream mitigations for Plan 02 and Phase 14. Did NOT modify the production pipeline per the plan's protect-file directive and the spirit of "this is diagnostic-only" from 13-CONTEXT.md.
- **Committed in:** `9003b44`

**4. [Rule 1 - Bug] `colormaps["tab10"]` → `PyPlot.get_cmap("tab10")`**
- **Found during:** Task 4 (figure 2 rendering)
- **Issue:** Newer matplotlib API `matplotlib.colormaps[...]` not available in this Julia-PyPlot binding.
- **Fix:** Used `PyPlot.get_cmap("tab10")` (stable older API).
- **Committed in:** `15395f0`

**5. [Rule 1 - Bug] Figure 3 outlier scale**
- **Found during:** Task 4 (Fig 3 review)
- **Issue:** Two HNLF optima with |a_i| > 400 rad compressed the entire coefficient cluster into one pixel. Linear axes unusable.
- **Fix:** (a) Dropped records with residual_fraction >= 0.95 (polynomial fit saturates on these — coefficients are effectively noise) and (b) switched both axes to symlog with data-driven linthresh (50th percentile of |coefficient|). Annotated subtitle with count dropped.
- **Committed in:** `15395f0`

**6. [Rule 3 - Blocking] World-age error on `optimize_spectral_phase`**
- **Found during:** Task 3 (first determinism run)
- **Issue:** `determinism_check` lazily included `raman_optimization.jl` inside a function, then called `optimize_spectral_phase` from the same world → Julia 1.12 strict world-age error: `method too new to be called from this world context`.
- **Fix:** Used `Base.invokelatest(Main.optimize_spectral_phase, ...)` plus `@eval Main include(...)` so symbols land in Main's namespace. Same treatment for `cost_and_gradient`.
- **Committed in:** `9003b44`

---

**Total deviations:** 6 auto-fixed (1 Rule 3 lexical, 2 Rule 1 test-expectation + plotting, 2 Rule 2 hardening/diagnosis, 1 Rule 3 world-age)
**Impact on plan:** All fixes were necessary to complete planned tasks; no scope creep. Production pipeline (common.jl, raman_optimization.jl, src/simulation/) untouched as required.

## Issues Encountered

- **FFTW.MEASURE non-determinism:** Documented (not resolved). Downstream phases should read `results/raman/phase13/determinism.md` before running any re-optimisation comparison.
- **Polynomial-projection saturation on low-power HNLF sweeps:** 3 of 24 sweep optima have residual_fraction >= 0.95. These are NOT failures of the fitter — they are evidence that orders 2..6 genuinely cannot capture the shape. Flagged in Fig 3 subtitle and filtered out of the scatter for readability.

## Handoff Note for Plan 02 (Hessian eigendecomposition)

**Preferred starting configuration:** `results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2`

Rationale:
- Converged cleanly (L-BFGS declared convergence at 18 iterations, J_after = 8.82e-7, -59.4 dB).
- Shares exact (Nt, time_window_ps, beta_2, beta_3) with the 10 multistart points, so the Hessian eigendecomposition at this point contextualises all 10 multistart runs.
- Phase 11 already identified this as the canonical point for landscape analysis.
- Input-band mask (derived at 99.9% energy cutoff) has ~1700 bins out of 8192 — ample dimension for Lanczos-style Krylov-subspace eigendecomposition on the input-band projection of the Hessian.

**Constraints Plan 02 must honour:**
1. Do not re-optimise on this point — pull phi_opt from the JLD2 directly.
2. If Plan 02's HVPs call `solve_disp_mmf` repeatedly, use a single (forward + adjoint) FFTW plan built once (cache it) rather than letting MEASURE re-decide per call. Otherwise HVP results will differ run-to-run at the 1 rad / 1.8 dB scale documented in `determinism.md`.
3. The input-band projection (`input_band_mask`) lives in `scripts/phase13_primitives.jl` — import via `include` not copy-paste.

**Verdict on Newton-vs-L-BFGS question (interim):**
The symptom that random starts give different phases is NOT explained by gauge modes (collapse fraction = 0). It is also NOT explained by low-order polynomial equivalence (median residual 92%, all multistart residuals > 93%). Something richer — higher-order polynomial, sinusoidal, or genuinely multi-minimum — is responsible. Plan 02's Hessian eigendecomposition will tell us which.

## Next Phase Readiness

- **Plan 02 (Hessian eigenspectrum):** Ready. The canonical config is identified; `scripts/phase13_primitives.jl` provides `input_band_mask` and `omega_vector` helpers; the JLD2 analysis file has the gauge-fixed phi and input-band mask for every optimum. Plan 02 can reuse these without touching production code.
- **Plan 03 (if any, findings doc):** Fig 1/2/3 are all production-ready and interpretable at a glance. Findings document should lead with Fig 2 (residual fraction) and Fig 3 middle panel (a_2, a_4 anti-correlation) because those are the clean quantitative answers.

## Self-Check

- [x] `scripts/phase13_primitives.jl` exists (411 lines) — FOUND
- [x] `scripts/phase13_gauge_and_polynomial.jl` exists (480 lines) — FOUND
- [x] `test/test_phase13_primitives.jl` exists, all 31 tests pass — FOUND
- [x] `results/raman/phase13/gauge_polynomial_analysis.jld2` exists (12 MB, JLD2.load succeeds) — FOUND
- [x] `results/raman/phase13/gauge_polynomial_summary.csv` exists, 40 lines — FOUND
- [x] `results/raman/phase13/determinism.md` exists, verdict = FAIL — FOUND
- [x] `results/images/phase13/phase13_01_gauge_before_after.png` exists (703 KB) — FOUND
- [x] `results/images/phase13/phase13_02_polynomial_residuals.png` exists (215 KB) — FOUND
- [x] `results/images/phase13/phase13_03_polynomial_coefficients.png` exists (152 KB) — FOUND
- [x] Commit `cfad5dc` exists — FOUND
- [x] Commit `15395f0` exists — FOUND
- [x] Commit `9003b44` exists — FOUND
- [x] `git diff` against `scripts/common.jl`, `scripts/raman_optimization.jl`, `src/simulation/` shows zero changes — FOUND

## Self-Check: PASSED

---
*Phase: 13-optimization-landscape-diagnostics*
*Plan: 01 — Primitives + gauge/polynomial analysis + determinism*
*Completed: 2026-04-16*
