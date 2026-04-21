# Phase 31 Plan 01 Task 3 — Branch A execution notes

**Run tag:** `20260421_082700`
**Git commit at sweep time:** `c34ac614fbcb95009567927b7a8c97e9e3d26be7` (pre-resume-patch driver)
**Executed on:** Mac (16-core Apple Silicon, 48 GB RAM), NOT burst VM
**Julia:** 1.12.4, `-t auto` → 12 threads
**Nt:** 16384
**Canonical config:** SMF28, L=2 m, P=0.2 W
**Max iterations:** 80

## Execution summary

| Metric | Value |
|---|---|
| Rows saved | **20** (expected 21 per plan; 1 physically skipped — see below) |
| `_phase_profile.png` images | 20 |
| Manifest | `results/raman/phase31/manifest_A_20260421_082700.json` |
| Total wall time (second run only) | 2185 s (36.4 min) |
| First-attempt wall time | ~26 min, 5/21 rows before PyCall segfault |
| Combined wall time | ~62 min |
| Converged | 20 / 20 (all) |

## Results by kind (best J_final)

| Kind | N_phi | J (dB) | Notes |
|---|---|---|---|
| polynomial | 3 | −26.50 | Plateau across N_phi ∈ {3,4,5,6,8} — low-order polynomial expresses only quadratic GVD |
| chirp_ladder | 4 | −29.91 | Slight improvement over pure polynomial |
| dct | 128 | −31.12 | Flat at −26.15 dB for N_phi ≤ 64, then jumps to −31.12 at 128; DCT N_phi=256 skipped (exceeds bandwidth support) |
| **cubic** | **128** | **−67.60** | **Best Branch A result.** Cubic splines with local support express structure DCT global modes cannot |
| linear | 64 | −63.94 | Linear N_phi=16 already at −60.3 dB — surprisingly strong |

## Physics observations (preliminary — full analysis deferred to Plan 02)

1. **Polynomial / DCT plateau at ~ −26 dB**: low-order polynomial bases and DCT up through N_phi=64 all converge to the same quadratic-chirp-dominated optimum. This is physically consistent — the dominant analytical phase compensation is a quadratic chirp (β₂-cancellation); higher-order polynomials don't escape this basin given the multi-start seeds used.
2. **Cubic basis outperforms DCT dramatically**: at N_phi=128, cubic reaches −67.6 dB vs DCT's −31.1 dB (a 36 dB gap at identical dimensionality). This suggests the optimal phase has **localized structure** that cubic splines' local support captures but global DCT modes do not.
3. **Linear basis also strong**: linear N_phi=16 → −60.3 dB, meaning 16 piecewise-linear segments already capture most of the suppression. The optimal phase is "mostly piecewise smooth" rather than globally smooth.
4. **Saddle-masking check (Phase 35 pitfall)**: Hessian indefiniteness ratios are mostly 0.0 or small (< 0.08) in coefficient space. Ambient-space probe deferred per Plan 02 design; all basis-restricted optima flagged `PSD_UNVERIFIED_AMBIENT`.

## Deviations from plan

1. **Executed locally on the Mac, not the burst VM.** User directed: "ur on a mac so yea i would hope u dont use a burst vm, kick it off on the mac". The "always burst VM" rule in CLAUDE.md §Running Simulations was written for sessions on `claude-code-host` (the 4-vCPU always-on VM); on the Mac (primary editing machine, 16-core Apple Silicon, 48 GB) running Julia locally is the correct default. Memory updated accordingly in `feedback_burst_vm_only_from_remote.md`.
2. **20 rows instead of 21.** The driver's existing `if N_phi > bw_bins: continue` guard correctly skipped DCT N_phi=256 — it exceeds the pulse bandwidth support (basis would have zero columns). This is a physically-meaningful skip, not a bug. The plan's acceptance criterion "exactly 21 rows" conflicts with the driver's sound skip logic; noting here rather than silently workarounding.
3. **PyCall segfault interrupted the first attempt** (`_PyObject_Free → unicode_dealloc → pydecref_` at Julia shutdown/GC). Root cause: matplotlib figure handles accumulate across many `save_standard_set` calls and trigger a Python object lifetime bug on Julia 1.12 aarch64. Fixed in commit `38be4c5` by adding (a) resume-from-JLD2 support and (b) explicit `PyPlot.close("all")` + `GC.gc()` between runs.
4. **Polynomial J_final identical across N_phi ∈ {3..8}**: all five polynomial rows reached J=−26.497 dB. Not a bug — the multi-start seeds (flat + ±quadratic chirp) all collapse to the dominant quadratic-compensation optimum. Higher-order polynomials fail to escape the quadratic basin under these seeds. Plan 02 analysis should surface this as a real physics observation about the basin topology.

## Artifacts

- `results/raman/phase31/sweep_A_basis.jld2` — 20 optimization rows
- `results/raman/phase31/sweep_A/images/*.png` — 80 images (20 × 4: phase_profile, evolution, evolution_unshaped, phase_diagnostic) per `save_standard_set`
- `results/raman/phase31/manifest_A_20260421_082700.json`
- `results/burst-logs/A-phase31-mac_20260421T115734Z.log` (first attempt, truncated by segfault)
- `results/burst-logs/A-phase31-mac-resume_20260421T122651Z.log` (resume run, completed)

## Ready for Plan 02

Plan 02 Task 1 (Branch B penalty sweep) can consume `sweep_A_basis.jld2` as-is. Plan 02 Task 2 (transferability probe) can iterate over the 20 Branch A optima. Plan 02 Task 3 (analysis) will document the polynomial-plateau and cubic-dominance findings above as part of the model-selection writeup.
