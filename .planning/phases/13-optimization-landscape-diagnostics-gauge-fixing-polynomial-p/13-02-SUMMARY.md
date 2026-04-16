---
phase: 13-optimization-landscape-diagnostics
plan: 02
subsystem: optimization-diagnostics
tags: [hessian, eigendecomposition, arpack, lanczos, hvp, adjoint, saddle-point, fftw-determinism, raman]

# Dependency graph
requires:
  - phase: 13-01
    provides: "gauge_polynomial_analysis.jld2 and phase13_primitives.jl (input_band_mask, gauge_fix)"
  - phase: 07-parameter-sweeps
    provides: "results/raman/sweeps/{smf28,hnlf}/.../opt_result.jld2 canonical optima used as the Hessian base points"
  - phase: 15-01
    provides: "ensure_deterministic_fftw() + ESTIMATE planner — prerequisite for reproducible HVPs"
provides:
  - "HVP primitive (scripts/phase13_hvp.jl) with Taylor-remainder-validated O(eps^2) accuracy"
  - "Arpack matrix-free Lanczos wrapper for top-K / bottom-K Hessian eigendecomposition (scripts/phase13_hessian_eigspec.jl)"
  - "Hessian eigenspectra at 2 canonical L-BFGS optima (results/raman/phase13/hessian_{smf28,hnlf}_canonical.jld2)"
  - "3 publication-quality diagnostic figures (phase13_04..06)"
  - "results/raman/phase13/FINDINGS.md — Phase 13 synthesis document with indefinite_hessian verdict"
affects: [14-sharpness-aware-optimization, 16-newton-trust-region-if-needed]

# Tech tracking
tech-stack:
  added:
    - "Arpack.jl matrix-free eigs via custom HVPOperator with mul! / issymmetric / eltype / size"
  patterns:
    - "P13_ const prefix extended to hessian_eigspec + hessian_figures scripts"
    - "HVP oracle closure built once, passed by reference to the operator; avoids per-call setup overhead"
    - "JLD2 schema with both top and bottom eigenpairs + full reproducibility metadata (eps, tol, maxiter, threading)"
    - "Figure rendering decoupled into a separate standalone script (phase13_hessian_figures.jl) so figures can be regenerated without rerunning the eigendecomposition"

key-files:
  created:
    - scripts/phase13_hvp.jl
    - scripts/phase13_hessian_eigspec.jl
    - scripts/phase13_hessian_figures.jl
    - test/test_phase13_hvp.jl
    - results/raman/phase13/hessian_smf28_canonical.jld2
    - results/raman/phase13/hessian_hnlf_canonical.jld2
    - results/raman/phase13/FINDINGS.md
    - results/images/phase13/phase13_04_hessian_eigvals_stem.png
    - results/images/phase13/phase13_05_top_eigenvectors.png
    - results/images/phase13/phase13_06_bottom_eigenvectors.png
  modified: []

key-decisions:
  - "Arpack matrix-free eigs used with :LR and :SR; no shift-invert attempted (requires factorisation, impossible for matrix-free HVP). Consequence: the 2 theoretically-predicted gauge null-modes at lambda=0 are NOT in the reported 40-vector spectrum. Their existence is a symmetry theorem (cost invariant under phi -> phi + C + alpha*omega) and their position was inferred from projection norms, not measured directly."
  - "Both canonical optima analysed at Nt=8192 (production grid). Cross-validation against dense Hessian at Nt=2^8 confirmed HVP machinery is correct."
  - "FFTW pinned to ESTIMATE + single thread to satisfy Plan 01's determinism finding (MEASURE drifts 1 rad between runs). BLAS also pinned to single thread for bit-reproducible reductions."
  - "Figures decoupled from compute: scripts/phase13_hessian_figures.jl reads the JLD2 outputs and is idempotent / cheap. This plan's remaining tasks (figures + FINDINGS) could therefore be finished on the 2-vCPU local host after the burst VM delivered the raw data."
  - "Headline verdict indefinite_hessian rather than non_gauge_flatness: both configs have bottom-20 eigenvalues that are ALL negative (100%), with |lambda_min|/lambda_max = 2.6% (SMF) / 0.41% (HNLF) — saddle, not flat region."

patterns-established:
  - "Pattern 1: Matrix-free LinearAlgebra operator via duck typing on size/eltype/mul! — any HVP closure can be passed to Arpack.eigs without allocating the Hessian"
  - "Pattern 2: ensure_deterministic_fftw() at script entry and log FFTW/BLAS/Julia thread counts in the saved JLD2 so run metadata can be audited after the fact"
  - "Pattern 3: cosine-similarity annotation of bottom eigenvectors against analytic gauge references — turns 'is this a gauge null-mode?' into a number, not a visual check"

requirements-completed:
  - "P13-02-A: Finite-difference Hessian-vector-product function with Taylor-remainder validation showing O(eps^2) convergence"
  - "P13-02-B: Arpack/Lanczos eigendecomposition wrapper extracting top-K and bottom-K eigenvalues + eigenvectors"
  - "P13-02-C: Eigenspectrum computed at 2 canonical optima (SMF-28 and HNLF); near-zero-mode count reported"
  - "P13-02-D: Top-K and bottom-K eigenvectors visualized as phase curves over omega"
  - "P13-02-E: FINDINGS.md synthesizes gauge+polynomial result from Plan 01 and Hessian spectrum from Plan 02; issues explicit verdict + routing recommendation"
  - "P13-02-F: Heavy compute runs on burst VM (fiber-raman-burst); burst-stop after"
  - "P13-02-G: Scripts do NOT modify any existing files — only ADD new phase13 scripts"

# Metrics
duration: ~30 min (figures + FINDINGS + SUMMARY; raw-data compute ~4 min on burst finished earlier)
completed: 2026-04-16
---

# Phase 13 Plan 02: Hessian Eigenspectrum at Converged L-BFGS Optima — Summary

**Indefinite Hessian spectrum measured at both canonical optima: lambda_max positive, all 20 reported bottom eigenvalues negative (ratio 0.4 %–2.6 % of lambda_max), proving L-BFGS stops at saddles — not minima — and motivating Phase 14 sharpness-aware cost.**

Detailed synthesis (gauge + polynomial + Hessian spectrum + routing): `results/raman/phase13/FINDINGS.md`.

## Performance

- **Duration:** ~30 min figures + FINDINGS + SUMMARY; raw data compute ~4 min on burst ($0.18 GCP credit) delivered earlier
- **Started (this resumption):** 2026-04-16T21:50:00Z
- **Completed:** 2026-04-16T22:15:00Z
- **Tasks:** 6 (Tasks 1–2 = code + unit tests; Task 4 = burst compute; Tasks 3, 5, 6 = figures + FINDINGS + SUMMARY — all completed)
- **Files created:** 10 (3 scripts, 1 test file, 2 JLD2s, 3 PNGs, 1 FINDINGS.md)

## Accomplishments

1. **Matrix-free HVP library** shipped (`scripts/phase13_hvp.jl`, `test/test_phase13_hvp.jl`). Symmetric central-difference HVP on top of the existing first-order adjoint gradient. Taylor-remainder slope ≈ 2.0 verified (commit `b962091`). HVP symmetry `|v' H w - w' H v| < 1e-5 |v' H w|`.
2. **Arpack matrix-free eigendecomposition** at two canonical L-BFGS optima (SMF-28 L=2 m P=0.2 W; HNLF L=0.5 m P=0.01 W) via `HVPOperator <: LinearAlgebra.AbstractMatrix`-like duck typing. `:LR` and `:SR` wings, `nev = 20` each. Wall time on burst: 31.8 s / 204.4 s (SMF) and 7.0 s / 108.9 s (HNLF) for `:LR` / `:SR` respectively.
3. **Three figures** rendered and committed at 300 DPI:
   - Fig 4: signed-log stem of top-20 + bottom-20 eigenvalues; sign pattern INDEFINITE annotated.
   - Fig 5: top-5 eigenvectors as phi(Δf) with input band shaded.
   - Fig 6: bottom-5 eigenvectors with analytic gauge references overlaid; per-vector cosine similarity annotated in legend.
4. **Gauge-mode identity check.** Bottom-5 cosine similarity to `{const, omega-linear-centered-on-band}` is ≤ 0.014 for all k at both configs — the reported :SR wing does NOT contain the gauge null-modes (documented limitation of matrix-free Lanczos without shift-invert; the gauge modes sit in the ~1e-7 .. 1e-6 eigenvalue gap between wings).
5. **FINDINGS.md** (295 lines) synthesizing all three workstreams (determinism, gauge+polynomial, Hessian spectrum) with an explicit verdict `indefinite_hessian` and routing recommendation for Phase 14.
6. **Read-only on protected files.** `git diff` against `scripts/common.jl`, `scripts/raman_optimization.jl`, and `src/simulation/*` shows zero changes across the entire plan.

## Task Commits

Raw-data and code commits (earlier in Plan 02 execution):

1. **Task 1 — HVP library + Arpack wrapper + tests**: `941dab6` (feat)
2. **Task 4 — Hessian eigendecomposition outputs (burst VM)**: `cd4db45` (results)

This resumption (Tasks 3 + 5 + 6):

3. **Task 3 — Figure script + 3 PNGs**: `568078c` (feat)
4. **Task 5 — FINDINGS.md synthesis**: `17681cd` (docs)
5. **Task 6 — Plan 02 SUMMARY.md**: committed next (this commit)

**Plan metadata commit:** will follow via `gsd-tools commit`.

## Files Created/Modified

- `scripts/phase13_hvp.jl` (~400 lines) — `fd_hvp`, `build_oracle`, `validate_hvp_taylor`, `ensure_deterministic_fftw`
- `scripts/phase13_hessian_eigspec.jl` (~620 lines) — entry point: loads phi_opt, builds oracle, runs `Arpack.eigs`, saves JLD2. Also contains an inline `make_figures()` that is superseded by the dedicated figure script for this deliverable.
- `scripts/phase13_hessian_figures.jl` (~310 lines) — standalone figure renderer consuming the two JLD2s; runs locally without burst.
- `test/test_phase13_hvp.jl` — Taylor-remainder slope, HVP symmetry, dense-Hessian cross-validation at Nt=2^8
- `results/raman/phase13/hessian_smf28_canonical.jld2` (2.8 MB) — 20 top + 20 bottom eigenpairs, phi_opt, full metadata
- `results/raman/phase13/hessian_hnlf_canonical.jld2` (2.8 MB) — same structure, HNLF config
- `results/raman/phase13/FINDINGS.md` (295 lines) — Phase 13 synthesis, headline verdict `indefinite_hessian`, routing for Phase 14
- `results/images/phase13/phase13_04_hessian_eigvals_stem.png` — top/bottom stem plot, symlog, sign-pattern annotation
- `results/images/phase13/phase13_05_top_eigenvectors.png` — top-5 stiff directions
- `results/images/phase13/phase13_06_bottom_eigenvectors.png` — bottom-5 soft directions + gauge reference overlays

## Decisions Made

1. **Matrix-free Lanczos without shift-invert.** Anticipated in the plan's "deviations allowed"; no fallback used because bottom eigenvalues are well-resolved in their own magnitude range (~1e-7 to 1e-8) and the gauge null-modes' non-appearance is a known limitation, not a bug.
2. **Separate figure script.** Plan Task 3 specified `scripts/phase13_hessian_figures.jl`; chose to build this as a new file rather than reuse the embedded `make_figures()` in `phase13_hessian_eigspec.jl` so figure regeneration doesn't require reloading the full HVP stack.
3. **Headline verdict chosen as `indefinite_hessian`.** Over `non_gauge_flatness` because all 20 reported bottom eigenvalues are NEGATIVE (not just small). This is a stronger and more actionable statement: L-BFGS is at a saddle, not a flat minimum basin.
4. **Sharpness-aware recommendation.** Phase 14 should use a full (signed-abs) sharpness penalty rather than a PSD-truncated one — the negative-curvature directions carry the physics. Documented in FINDINGS § Routing.
5. **HVP eps=1e-4 kept at default.** Taylor-remainder test bounds HVP noise at ~1e-9; smallest reported |lambda| is 2.4e-8 (HNLF) — comfortably above the floor.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Arpack does not accept matrix-free shift-invert**
- **Found during:** Task 2 (first Arpack :SM attempt on smf28_canonical)
- **Issue:** Plan suggested `eigs(op; which=:SM, sigma=0.0)` for bottom eigenvalues via shift-invert. Arpack's shift-invert path requires `factorize(H - sigma*I)`, which is impossible for a matrix-free operator (no explicit Hessian). The call errored with "shift-invert needs a factorization".
- **Fix:** Replaced with `:SR` (smallest real / smallest algebraic) which uses plain Lanczos on the unshifted operator. The returned wing is the 20 most-negative-algebraic eigenvalues, which is what we need for saddle detection. Documented the gauge-mode-visibility consequence in FINDINGS § Workstream 3 Limitations.
- **Files modified:** `scripts/phase13_hessian_eigspec.jl`
- **Committed in:** `941dab6` (Task 1/2 commit)

**2. [Rule 2 - Missing critical] Determinism pinning at HVP entry**
- **Found during:** Task 2 (HVP was producing slightly different eigenvalues per run)
- **Issue:** Without `ensure_deterministic_fftw()` and BLAS pinning at script entry, consecutive Arpack runs on the same `phi_opt` returned different `lambda_top[1]` at the 1e-9 relative level — consistent with Plan 01's FFTW.MEASURE diagnosis. The eigenspectrum is the central deliverable; not fixing this would make the result non-reproducible.
- **Fix:** Added `ensure_deterministic_fftw()` + `BLAS.set_num_threads(1)` calls at the top of `run_eigendecomposition`. Also logged `FFTW.get_num_threads()` and `BLAS.get_num_threads()` into the JLD2 so the run is auditable.
- **Files modified:** `scripts/phase13_hessian_eigspec.jl`, `scripts/phase13_hvp.jl`
- **Committed in:** `941dab6`

**3. [Rule 1 - Bug] Figure 4 y-axis symlog linthresh = 0**
- **Found during:** Task 3 (first figure render)
- **Issue:** Passing `linthresh=thr` when `thr = 1e-6 * lambda_max` and `lambda_max ≈ 1e-5` gives `linthresh ≈ 1e-11`, fine; but if a future run had `lambda_max = 0` (pure flat), `thr = 0` would crash matplotlib symlog. Preempted with `max(thr, 1e-16)`.
- **Files modified:** `scripts/phase13_hessian_figures.jl`
- **Committed in:** `568078c`

**4. [Rule 2 - Missing critical] Gauge-mode cosine similarity annotation**
- **Found during:** Task 3 (Fig 6 review)
- **Issue:** Plan asked for visual confirmation of gauge modes. A purely visual check is insufficient — the bottom eigenvectors are oscillatory and could visually be mistaken for gauge modes. Added per-vector cos-similarity to `{const, omega-linear}` in the legend, with an explicit `[gauge: C]` or `[gauge: ω-linear]` marker when cos > 0.95.
- **Fix:** `gauge_reference_modes()` helper + annotation in `plot_bot_eigvecs`; @info log summarising gauge hits per config.
- **Committed in:** `568078c`

---

**Total deviations:** 4 auto-fixed (1 Rule 3 Arpack API constraint, 2 Rule 2 hardening, 1 Rule 1 plotting robustness)
**Impact on plan:** No scope change; each deviation was necessary to produce correct, reproducible, interpretable results. The gauge-mode non-visibility is NOT a deviation — it is a correctly-reported limitation of the chosen (plan-specified) matrix-free method.

## Issues Encountered

- **Burst VM upgrade window** landed between Task 4 (raw data compute, delivered commit `cd4db45`) and Tasks 3/5/6 (this resumption). Handled cleanly by the pattern-3 decoupling — figures + FINDINGS + SUMMARY finished on the local host without recomputing.
- **Gauge null-modes invisible to matrix-free Lanczos.** Known and documented in the plan; the FINDINGS § Workstream 3 Limitations calls this out explicitly so downstream readers do not mistake it for a negative result.

## Next Phase Readiness

- **Phase 14 (sharpness-aware cost) is fully unblocked.** FINDINGS § Routing specifies:
  - Use full signed-abs sharpness penalty (not PSD-truncated).
  - Vanilla `lambda = 0.1` snapshot at commit `3ba48cd` is a reasonable starting regularisation strength.
  - If `lambda = 0.1` shows no qualitative change, step to `lambda = 1.0` before declaring sharpness-aware approaches don't work.
  - Bottom wing (negative eigenvalues) carries the decisive information — don't truncate it out.
- **Newton-CG exploration.** Now has direct Hessian-spectrum evidence that the landscape is indefinite — the engineering cost of a second-order adjoint is justified IF Phase 14's cheap sharpness approach fails. See `.planning/notes/newton-exploration-summary.md §7`.
- **Follow-up question for Phase 14 Plan 02 or later.** Does the saddle structure persist across a 5-point (L, P) grid? Plan 02's `run_eigendecomposition` is now cheap enough (~2 min/config on burst) that this would be a 10-minute follow-up.

## Self-Check

- [x] `scripts/phase13_hvp.jl` exists — FOUND (15 KB)
- [x] `scripts/phase13_hessian_eigspec.jl` exists — FOUND (28 KB)
- [x] `scripts/phase13_hessian_figures.jl` exists — FOUND (new file this commit)
- [x] `test/test_phase13_hvp.jl` exists — FOUND (from Task 1 commit)
- [x] `results/raman/phase13/hessian_smf28_canonical.jld2` exists (2.8 MB) — FOUND
- [x] `results/raman/phase13/hessian_hnlf_canonical.jld2` exists (2.8 MB) — FOUND
- [x] `results/images/phase13/phase13_04_hessian_eigvals_stem.png` exists — FOUND
- [x] `results/images/phase13/phase13_05_top_eigenvectors.png` exists — FOUND
- [x] `results/images/phase13/phase13_06_bottom_eigenvectors.png` exists — FOUND
- [x] `results/raman/phase13/FINDINGS.md` exists (295 lines, verdict=indefinite_hessian) — FOUND
- [x] Commit `941dab6` exists (Task 1/2 code) — FOUND
- [x] Commit `cd4db45` exists (Task 4 raw data) — FOUND
- [x] Commit `568078c` exists (Task 3 figures) — FOUND
- [x] Commit `17681cd` exists (Task 5 FINDINGS) — FOUND
- [x] `git diff` against `scripts/common.jl`, `scripts/raman_optimization.jl`, `src/simulation/` shows zero changes — FOUND

## Self-Check: PASSED

---
*Phase: 13-optimization-landscape-diagnostics*
*Plan: 02 — HVP + Arpack eigendecomposition + synthesis FINDINGS*
*Completed: 2026-04-16*
