# Phase 31 — Reduced-basis and regularized phase parameterization — Context

**Topic origin:** migrated from the old GSD phase `.planning/phases/31-reduced-basis-and-regularized-phase-parameterization/` (now archived in `docs/planning-history/phases/31-…/`). Plan 01 completed under the GSD workflow before the repo migrated to the stock `docs/` convention. Plan 02 continues under this new topic directory.

## Phase question

Does **reduced-basis** or **regularization** give a simpler, more transferable, equally-deep Raman-suppression optimum than full-grid L-BFGS optimization?

## Why this matters

- **Phase 27** (numerics audit) reframed regularization as model-selection: the optimal phase has structure; the right question is which *family of structures* recovers it at lowest dimensionality.
- **Phase 35** (saddle-escape study) concluded that competitive-dB optima are saddle-dominated in the full-grid space. Basis restriction could either unmask real minima (signal) or hide indefiniteness behind a restricted Hessian (artifact) — the saddle-masking pitfall must be tracked.
- **Phase 22** produced a sharpness-aware Pareto; Phase 31 completes it with the *dimensionality* axis.

## Locked decisions (from pre-migration CONTEXT.md)

1. Extend the repo's existing basis infrastructure (`build_phase_basis` in `scripts/sweep_simple_param.jl`) before inventing new basis code.
2. The amplitude DCT path (`amplitude_optimization.jl::build_dct_basis`) is the first reuse target for phase reduction.
3. Explicit basis restriction and penalty-based regularization are compared head-to-head, not conflated.
4. Interpretability, robustness, and transferability matter as much as best J_final (dB).

## Canonical configuration

SMF28, L = 2 m, P = 0.2 W, Nt = 16384, time_window = 10 ps, β_order = 3. Determinism enforced via `ensure_deterministic_environment()` at script top.

## Plan 01 — done (Branch A basis sweep)

See `SUMMARY.md` and `BRANCH-A-NOTES.md`. Key results:

- 20 rows at `results/raman/phase31/sweep_A_basis.jld2` (DCT N_phi=256 correctly skipped on bandwidth).
- Best basis: **cubic N_phi=128 → −67.6 dB** (36 dB deeper than DCT at same dimensionality).
- Polynomial plateau at −26.5 dB for all N_phi ∈ {3..8} — the quadratic-compensation basin dominates.
- `scripts/basis_lib.jl`, `scripts/penalty_lib.jl`, `scripts/run.jl`, `test/test_phase31_basis.jl` committed. All 8 testsets pass.

## Plan 02 — done (this topic)

See `PLAN.md`. Three tasks:

1. Branch B penalty sweep on full-grid: Tikhonov / GDD / TOD / TV / DCT-L1 at log-spaced λ, 21 runs.
2. Transferability probe: apply every Branch A + Branch B optimum to HNLF and to three perturbed canonical configs (+5% FWHM, +10% P, +5% β₂) without re-optimization.
3. Analysis: Pareto front, L-curve, AIC ranking, saddle-masking classification, FINDINGS.md narrative.

## Plan 03 — done (2026-04-22 follow-up extension)

Question carried forward from `FINDINGS.md`: can the reduced-basis continuation result be turned into a stronger or more transferable **full-grid refinement** result, and is there a better refinement path than simply taking the best cubic optimum?

Executed follow-up paths:

1. `zero -> full-grid`
2. `cubic 32 -> full-grid`
3. `linear 64 -> full-grid`
4. `cubic 128 -> full-grid`
5. `linear 64 -> cubic 128 -> full-grid`

Headline outcome:

- **Yes, reduced-basis continuation survives a final full-grid polish.** `cubic32 -> full-grid` reached **−67.16 dB**, closing almost all of the gap to the best Phase 31 cubic optimum without starting from the deepest reduced-basis seed.
- **No, the full-grid polish does not preserve robustness/transferability.** Once the path is allowed onto the full grid, the promising wider-basin starts collapse toward the same narrow, canonical-specific family: `σ_3dB ≈ 0.07–0.10 rad`, HNLF gap ≈ `+20.7` to `+22.3 dB`.
- **The current cubic route still wins on depth.** `cubic128 -> full-grid` stayed at **−67.60 dB**; the alternative `linear64 -> cubic128 -> full-grid` plateaued at **−64.40 dB**.

Artifacts:

- `results/raman/phase31/followup/path_comparison.jld2`
- `results/raman/phase31/followup/images/`
- `agent-docs/phase31-reduced-basis/FOLLOWUP-PHASE31-EXTENSION.md`
- `scripts/phase31_extension_{lib,run,analyze}.jl`
- `test/test_phase31_extension.jl`

## Constraints inherited from CLAUDE.md

- `save_standard_set(...)` mandatory for every driver producing `phi_opt`.
- `deepcopy(fiber)` per thread inside every `Threads.@threads` block.
- SI units as stated in the repo convention section.
- Run simulations locally on the Mac (`julia -t auto`).
- Log-cost + gradient rescale (`10 * log10(J)`, gradient scaled by `10 / (J * ln10)`) — penalties accumulate BEFORE the log_cost block.
- Any `save_standard_set` call should be followed by `PyPlot.close("all")` + `GC.gc()` (known Julia 1.12 aarch64 PyCall finalizer segfault; already patched in `run.jl`).

## References

- Archived planning artifacts: `docs/planning-history/phases/31-reduced-basis-and-regularized-phase-parameterization/`
- Research document (~1256 lines): `docs/planning-history/phases/31-…/31-RESEARCH.md` (basis catalog, penalty catalog, pitfalls, wall-time estimates)
- Pattern map: `docs/planning-history/phases/31-…/31-PATTERNS.md` (file-to-analog table)
- Phase 27 audit: `docs/planning-history/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md`
- Phase 35 saddle-escape verdict: `docs/planning-history/phases/35-saddle-escape-and-genuine-minima-reachability-study/`
