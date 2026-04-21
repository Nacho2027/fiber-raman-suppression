---
phase: 31-reduced-basis-and-regularized-phase-parameterization
plan: 01
status: complete
completed: 2026-04-21
tags:
  - reduced-basis
  - regularization
  - raman
  - phase31
---

# Phase 31 Plan 01 — Summary

Libraries + driver + unit tests + Branch A basis sweep. Plan 02 (Branch B penalty sweep + transferability probe + Pareto/L-curve/AIC analysis) can now execute.

## What was built

**New files**
- `scripts/phase31_basis_lib.jl` — Legendre polynomial basis + chirp_ladder wrapper + `build_basis_dispatch(kind, Nt, N_phi, bw_mask, sim)` router (extends the existing DCT/cubic/linear/identity kinds in `sweep_simple_param.jl` without modifying that file)
- `scripts/phase31_penalty_lib.jl` — `apply_tikhonov_phi!`, `apply_tod_curvature!`, `apply_tv_phi!`, `apply_dct_l1!` with in-place gradient accumulation BEFORE the `log_cost` rescale (per project memory `project_dB_linear_fix.md`)
- `scripts/phase31_run.jl` — driver with `--branch=A|B`, deterministic env, resume-from-JLD2, mandatory `save_standard_set` per optimum, incremental JLD2 save, manifest output
- `test/test_phase31_basis.jl` — 8 testsets (identity reproduction, polynomial κ, chirp_ladder gauge orthogonality, coefficient-space FD gradient check, Taylor-remainder-2 slope per penalty, continuation upsample, DCT orthonormal fast path, Phase 35 hess_indef_ratio reproduction)

**Patches to `scripts/phase31_run.jl` (commit `38be4c5`)**
- Resume support: load rows from existing `sweep_A_basis.jld2`, skip (kind, N_phi) combos already complete.
- `PyPlot.close("all")` + `GC.gc()` between runs. Fixes a Julia 1.12 aarch64 PyCall finalizer segfault (`_PyObject_Free → unicode_dealloc → pydecref_`) that was triggered by accumulated matplotlib figure handles across many `save_standard_set` calls.

## What was executed

**Branch A basis sweep** on the Mac (16-core Apple Silicon, 48 GB, Julia 1.12.4, `-t auto` → 12 threads). Canonical config: SMF28, L=2 m, P=0.2 W, Nt=16384.

- **20 rows saved** to `results/raman/phase31/sweep_A_basis.jld2` (the plan called for 21; DCT N_phi=256 was correctly skipped by the existing `N_phi > bw_bins` guard — it exceeds the pulse bandwidth support).
- **20 `_phase_profile.png`** images in `results/raman/phase31/sweep_A/images/` (plus 60 other panels across the 4-image standard set per optimum).
- **Manifest** at `results/raman/phase31/manifest_A_20260421_082700.json`.
- **20 / 20 converged**.
- Wall time: ~62 min combined (26 min first attempt truncated by segfault + 36 min resume).

**Best J_final per basis kind:**

| Kind | Best N_phi | J (dB) |
|---|---|---|
| polynomial | 3 | −26.50 (plateau across N_phi ∈ {3,4,5,6,8}) |
| chirp_ladder | 4 | −29.91 |
| dct | 128 | −31.12 (flat at −26 dB for N_phi ≤ 64) |
| **cubic** | **128** | **−67.60** ← best basis |
| linear | 64 | −63.94 |

## Physics observations

1. **Polynomial / DCT plateau near −26 dB for low N_phi.** The multi-start seeds (flat + ±quadratic chirp) all collapse to the same quadratic-compensation basin; higher-order polynomials don't escape it under these seeds. Real observation about the basin topology, not a bug.
2. **Cubic bases dramatically outperform DCT at identical dimensionality.** At N_phi=128, cubic → −67.6 dB vs DCT's −31.1 dB (36 dB gap). Suggests the optimal phase has **localized structure** that cubic splines' local support captures but global DCT modes cannot.
3. **Linear basis already strong at low N_phi.** Linear N_phi=16 → −60.3 dB; 16 piecewise-linear segments capture most of the suppression.
4. **Hessian indefiniteness ratios are small in coefficient space.** All basis-restricted optima flagged `PSD_UNVERIFIED_AMBIENT` per Plan 02 design. Ambient-Hessian probe deferred out of Phase 31 (resolved Open Question 5 in 31-RESEARCH.md).

## Must-haves — status

| # | Truth | Status |
|---|---|---|
| 1 | `phase31_basis_lib.jl` with polynomial + chirp_ladder | ✅ |
| 2 | `phase31_penalty_lib.jl` with 4 penalty apply-* functions | ✅ |
| 3 | Unit tests pass | ✅ (committed in `a829164`) |
| 4 | Driver runs `--branch=A` and emits JLD2 rows | ✅ (20 rows; 21 target not met due to bw_bins skip — documented) |
| 5 | Every row has 17 required keys incl. `phi_opt::Vector{Float64}` length Nt | ✅ |
| 6 | ≥ 21 `_phase_profile.png` files | ⚠ 20 (one skip, see above) |
| 7 | No shared-file mutations | ✅ `git diff --stat scripts/common.jl scripts/visualization.jl src/ Project.toml Manifest.toml` is empty |

## Deviations

1. **Executed on the Mac, not the burst VM.** Per user direction. CLAUDE.md §Running Simulations "always burst VM" rule was written for sessions on `claude-code-host`; on the Mac, local execution is correct. Memory updated (`feedback_burst_vm_only_from_remote.md`).
2. **20 rows instead of 21.** DCT N_phi=256 skipped by the `N_phi > bw_bins` guard (physically meaningless — basis would have zero columns on the bandwidth-masked support). The plan's "exactly 21" count conflicts with the driver's sound skip logic. Documented in `31-01-BRANCH-A-NOTES.md`.
3. **First run segfaulted at 5/21** (PyCall finalizer). Fixed in `38be4c5` with resume support and explicit PyPlot cleanup.

## Commits

- `a829164` — `feat(phase31-01): add basis + penalty libraries with unit tests`
- `1873cc3` — `feat(phase31-01): add phase31_run.jl driver with Branch A basis sweep`
- `c34ac61` — `fix(phase31-01): cap dense Hessian probe at N_phi=16 to keep per-run wall time bounded`
- `38be4c5` — `fix(phase31-01): resumable Branch A sweep + matplotlib GC to prevent PyCall segfault`

## Ready for Plan 02

- `results/raman/phase31/sweep_A_basis.jld2` — 20 rows of Branch A optima, schema as specified in Plan 01 truth 5.
- `scripts/phase31_basis_lib.jl`, `scripts/phase31_penalty_lib.jl` — both importable by Plan 02's `run_branch_B` and `phase31_analyze.jl`.
- `scripts/phase31_run.jl` — Plan 02 Task 1 extends `run_branch_B` (currently a stub that errors out).
