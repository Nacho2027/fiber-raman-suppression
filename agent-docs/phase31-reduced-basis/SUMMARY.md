---
topic: phase31-reduced-basis
status: complete
completed: 2026-04-21
plans:
  - Plan 01 — Branch A basis sweep (20 optima)
  - Plan 02 — Branch B penalty sweep + transferability probe + analysis
---

# Phase 31 — SUMMARY

Compares reduced-basis phase parameterization (Branch A) against full-grid penalty regularization (Branch B) on the canonical SMF-28 L=2m P=0.2W Raman-suppression problem, with transferability + robustness probes and a Pareto / L-curve / AIC write-up.

**Deliverable:** `FINDINGS.md` (this directory) — phase answer.
**Top-10 AIC ranking:** `candidates.md`.

## What was built

| File | Purpose |
|---|---|
| `scripts/phase31_basis_lib.jl` | Legendre polynomial + chirp_ladder basis builders; `build_basis_dispatch(kind, Nt, N_phi, bw_mask, sim)` routes to existing `:cubic`/`:dct`/`:linear` kinds in `sweep_simple_param.jl` |
| `scripts/phase31_penalty_lib.jl` | `apply_tikhonov_phi!`, `apply_tod_curvature!`, `apply_tv_phi!`, `apply_dct_l1!` — in-place gradient accumulators, applied BEFORE log_cost rescale |
| `scripts/phase31_run.jl` | Driver with `--branch=A|B`, deterministic env, resume-from-JLD2, save_standard_set per optimum, PyPlot + GC cleanup, manifest output. Plan 01 added `run_branch_A`; Plan 02 added `run_branch_B` (bypasses `optimize_phase_lowres` — would allocate 2 GB identity at full Nt; uses `Optim.LBFGS` directly on φ_vec with a cost+gradient wrapper that applies the penalty before log_cost rescale) |
| `scripts/phase31_transfer.jl` | Forward-only J (no adjoint, 2.66s/call at Nt=16384) + early-exit σ_3dB + HNLF + 3 perturbed-canonical evaluations. `Threads.@threads` across 41 source rows |
| `scripts/phase31_analyze.jl` | 4-panel Pareto, per-penalty L-curves, AIC ranking CSV, `candidates.md` + `FINDINGS.md` from `sweep_A_basis.jld2` + `sweep_B_penalty.jld2` + `transfer_results.jld2` |
| `test/test_phase31_basis.jl` | 8 testsets (identity reproduction, polynomial κ, chirp_ladder gauge orthogonality, coefficient-space FD gradient, Taylor-remainder-2 slope per penalty, continuation upsample, DCT orthonormal fast path, Phase 35 hess_indef_ratio reproduction). All pass. |

## What was executed

All runs on the Mac (16-core Apple Silicon, 48 GB, Julia 1.12.4, `-t auto` → 12 threads). Canonical SMF-28 L=2m P=0.2W Nt=16384 time_window=10→27 ps (auto-sized).

| Sweep | Rows | Wall-time | Artifact |
|---|---|---|---|
| Branch A (basis) | 20 / 21 (DCT N_phi=256 correctly skipped on bandwidth) | ~62 min (26 min first attempt truncated by PyCall segfault + 36 min resume) | `results/raman/phase31/sweep_A_basis.jld2` |
| Branch B (penalty) | 21 / 21 | ~30 min | `results/raman/phase31/sweep_B_penalty.jld2` |
| Transfer + σ_3dB probe | 41 source rows | 6.4 min (after forward-only + early-exit optimization) | `results/raman/phase31/transfer_results.jld2` |
| Analyze | — | < 1 min | `pareto.png`, `L_curves/*.png`, `aic_ranking.csv`, `candidates.md`, `FINDINGS.md` |

## Headline result

**Branch A cubic basis at N_phi = 128 wins canonical depth (−67.6 dB).** Full-grid zero-init L-BFGS (Branch B λ = 0) plateaus at −57.75 dB regardless of penalty family — continuation through a reduced basis is a better optimizer path than full-grid zero init, not just a regularizer. See `FINDINGS.md` for the full narrative, caveats (σ_3dB basin width, HNLF gap, saddle-masking), and follow-on questions.

## Key physics findings

1. **Cubic basis dominates.** Top 5 AIC rows are all cubic or linear Branch A; no penalty family reaches within 10 dB of cubic N_phi = 128.
2. **Polynomial plateau at −26.5 dB.** All polynomial N_phi ∈ {3..8} converge to the same quadratic-chirp basin; multi-start seeds (flat + ±quadratic) don't escape. DCT N_phi ≤ 64 plateaus similarly.
3. **Depth trades against basin width + transferability.** Cubic N_phi = 128 has σ_3dB = 0.07 rad (tightest) and HNLF gap = +21.5 dB. Cubic N_phi = 16 has σ_3dB = 0.31 rad and J = −54 dB.
4. **Polynomial N_phi = 3 is the most fiber-transferable** (HNLF gap ≈ 0) — the analytical quadratic-chirp optimum is roughly fiber-agnostic. But shallow.
5. **Regularization did NOT give a cheaper path to the cubic basin.** λ = 0 Branch B full-grid zero-init L-BFGS never reaches cubic depth. Saddle-trap behavior (consistent with Phase 35).

## Deviations from original plan

1. **Executed on the Mac, not the burst VM.** Per user direction: the "always burst VM" rule in CLAUDE.md §Running Simulations was written for sessions on `claude-code-host`; on the Mac (primary editing machine) running Julia locally with `-t auto` is the default. Memory updated in `feedback_burst_vm_only_from_remote.md`.
2. **20 Branch A rows instead of 21.** DCT N_phi = 256 skipped by the `N_phi > bw_bins` guard — physically meaningless (exceeds pulse bandwidth support).
3. **Ambient-Hessian probe deferred.** All basis-restricted optima flagged `PSD_UNVERIFIED_AMBIENT`. Proper ambient probe requires Phase 33/34 Krylov-preconditioned Newton machinery.
4. **σ_3dB probe performance fix.** Initial design was ~24 h worst-case (n_trials=20 × 9 σ × 41 rows × 12s/adjoint-solve). Patched to forward-only J (2.66s) + early-exit at 3 dB crossover → 6.4 min total.
5. **PyCall finalizer segfault** on the Mac (Julia 1.12 aarch64) — observed during Branch A at 5/21 configs. Fixed by adding `PyPlot.close("all")` + `GC.gc()` between runs in both Branch A and Branch B. Never fired on Branch B after the fix.

## Commits

- `a829164` `feat(phase31-01): add basis + penalty libraries with unit tests`
- `1873cc3` `feat(phase31-01): add phase31_run.jl driver with Branch A basis sweep`
- `c34ac61` `fix(phase31-01): cap dense Hessian probe at N_phi=16 to keep per-run wall time bounded`
- `38be4c5` `fix(phase31-01): resumable Branch A sweep + matplotlib GC to prevent PyCall segfault`
- `efd5cbb` `docs(phase31): create agent-docs topic with Plan 01 SUMMARY + Plan 02 PLAN`
- `ea655ba` `feat(phase31-02): implement run_branch_B penalty sweep`
- `d48bfe0` `feat(phase31-02): add phase31_transfer.jl and phase31_analyze.jl`
- `e23eede` `perf(phase31-02): forward-only J eval + early-exit sigma_3dB`

## Seeds for next phase

See `FINDINGS.md §Follow-on questions`:

1. Close the 10 dB gap between full-grid L-BFGS and cubic N_phi=128 via (a) multi-start from perturbed zero, (b) anchored continuation (DCT → cubic → identity), (c) Phase 33/34 second-order with negative-curvature handling.
2. Test whether the HNLF gap is a property of the cubic basis or the canonical optimum.
3. Ambient-Hessian probe on cubic N_phi = 128 — tractable once Phase 33/34 Krylov-preconditioned HVP is built.

## 2026-04-22 extension

Follow-up files added in the Phase 31 namespace:

| File | Purpose |
|---|---|
| `scripts/phase31_extension_lib.jl` | pure path-program + seed/projection helpers for continuation/refinement comparisons |
| `scripts/phase31_extension_run.jl` | resumable follow-up driver comparing 5 continuation paths ending in full-grid refinement; emits standard images per step |
| `scripts/phase31_extension_analyze.jl` | writes `FOLLOWUP-PHASE31-EXTENSION.md` from the follow-up JLD2 |
| `test/test_phase31_extension.jl` | unit tests for path-program, row selection, projection, and labeling helpers |

Executed result:

- `zero -> full-grid`: `−55.75 dB`, `σ_3dB = 0.230`, HNLF gap `+11.47 dB`
- `cubic32 -> full-grid`: `−67.16 dB`, `σ_3dB = 0.070`, HNLF gap `+22.31 dB`
- `linear64 -> full-grid`: `−64.23 dB`, `σ_3dB = 0.093`, HNLF gap `+20.80 dB`
- `cubic128 -> full-grid`: `−67.60 dB`, `σ_3dB = 0.072`, HNLF gap `+21.50 dB`
- `linear64 -> cubic128 -> full-grid`: `−64.40 dB`, `σ_3dB = 0.100`, HNLF gap `+20.74 dB`

Interpretation:

- The reduced-basis continuation result **does** extend to a strong ambient/full-grid refinement.
- The full-grid polish **does not** preserve the attractive robustness/transferability of shallower seeds; it pulls them into the same narrow canonical family as the best cubic result.
- The current cubic route remains the best depth-seeking path among the tested options.
