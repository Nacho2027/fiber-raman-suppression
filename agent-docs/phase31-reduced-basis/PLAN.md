# Phase 31 Plan 02 — Branch B + transferability + analysis

Continuation of Plan 01 (Branch A basis sweep — complete). This plan tests the **penalty** side of the model-selection question, then combines both branches into a transferability + Pareto + FINDINGS writeup.

Reference: full-fidelity archived plan at `docs/planning-history/phases/31-reduced-basis-and-regularized-phase-parameterization/31-02-PLAN.md`. This PLAN.md is the streamlined working version under the new agent-docs convention.

## Task 1 — Branch B penalty sweep

**Goal:** replace the `run_branch_B(; dry_run)` stub in `scripts/run.jl` with a working penalty-on-full-grid sweep.

**Scope:** iterate `P31_PENALTY_PROGRAM = [(:tikhonov, [0.0, 1e-6, 1e-4, 1e-2, 1e0]), (:gdd, [0.0, 1e-6, 1e-4, 1e-2]), (:tod, [0.0, 1e-8, 1e-6, 1e-4]), (:tv, [0.0, 1e-4, 1e-2, 1e0]), (:dct_l1, [0.0, 1e-4, 1e-2, 1e0])]` → 21 runs. Each run: `optimize_phase_lowres` with `kind=:identity` is memory-prohibitive at Nt=16384 (2 GB identity matrix), so bypass: directly `Optim.optimize(Optim.only_fg!(wrapper), phi0, LBFGS(), Optim.Options(f_tol=1e-10, iterations=P31_MAX_ITER, show_trace=false))` where the wrapper calls `cost_and_gradient(...)` and adds the relevant penalty from `penalty_lib.jl` BEFORE the `log_cost` rescale.

**Branch B row packaging:** `c_opt = phi_opt_vec` (length Nt), `B = nothing`, `kind = "identity"`, `N_phi = sim["Nt"]`, `kappa_B = NaN`, `kappa_H_restricted = NaN`, `hess_probe_skipped_reason = "identity_basis_Branch_B"`, plus the penalty-family metadata (`penalty_name`, `lambda`, `J_raman_linear`, `J_penalty`). Store `"phi_opt" => vec(phi_opt)::Vector{Float64}` uniformly.

**Execute on the Mac** (not burst VM). Expected wall-time ~35 min. Apply the same resume + PyPlot cleanup pattern already in `run_branch_A`.

**Deliverables:**
- `scripts/run.jl` — `run_branch_B` with real body (no `error(...)` stub).
- `results/raman/phase31/sweep_B_penalty.jld2` — 21 rows.
- `results/raman/phase31/sweep_B/images/*_phase_profile.png` — 21 files.
- `results/raman/phase31/manifest_B_*.json`.
- Smoke test: `julia --project=. -e 'include("scripts/run.jl"); run_branch_B(; dry_run=true)'` exits cleanly and writes a 1-row dry-run JLD2.

**Acceptance:** 21 rows, all 17 schema keys present, every `regularization_mode == "penalty"`, ≥19/21 converged, no shared-file mutations outside `phase31_*` namespace.

## Task 2 — Transferability probe

**Goal:** quantify how well every Branch A + Branch B optimum holds up when the fiber / pulse / power changes, without re-optimization.

**New file:** `scripts/transfer.jl`.

**Probes (forward-only evaluations):**
1. **HNLF transfer** — reload `phi_opt` from a Branch A/B row, evaluate `J_raman_linear` on HNLF L=0.5 m P=0.01 W (use `setup_raman_problem(; fiber_preset=:HNLF, L_fiber=0.5, P_cont=0.01, Nt=16384)`). Record `J_transfer_HNLF`.
2. **Perturbed canonical** — for each row, evaluate on three perturbed SMF28 L=2m P=0.2W configs:
   - +5% FWHM via `setup_raman_problem(...; pulse_fwhm = base_fwhm * 1.05)` → record `J_transfer_fwhm_5pct` + flag `fwhm_applied=true`.
   - +10% P via `setup_raman_problem(...; P_cont = 0.2 * 1.10)` → record `J_transfer_P_10pct` + flag `P_applied=true`.
   - +5% β₂ via `setup_raman_problem(...; betas_user = (base_beta2 * 1.05, base_beta3, ...))` — if the `betas_user` kwarg exists in `scripts/common.jl`. If it does not, record `beta2_applied=false` with a string reason.
3. **σ_3dB robustness** — for each row, draw 20 Gaussian perturbations of `phi_opt` (`phi' = phi + σ · z`, `z ~ N(0, I)`), evaluate J for each, and find the σ at which J degrades by 3 dB. This is the 1D variant of the Phase 22 sharpness probe.

**Output:** `results/raman/phase31/transfer_results.jld2` keyed by `(branch, row_index)` with `J_transfer_HNLF`, `J_transfer_perturb::Dict`, `sigma_3dB`, and the applied-flag dict.

**Parallelization:** `Threads.@threads` over rows, `deepcopy(fiber)` per thread.

**Acceptance:** all 41 rows (20 Branch A + 21 Branch B) have non-NaN `J_transfer_HNLF` and `sigma_3dB`; `fwhm_applied == true` (proves the stub isn't lingering); `beta2_applied` flag present (may be `false` with disclosure).

## Task 3 — Analysis + FINDINGS

**New file:** `scripts/analyze.jl`.

**Outputs:**
1. `results/raman/phase31/pareto.png` — 4-panel Pareto with axes `(J_dB, N_eff)`, `(J_dB, σ_3dB)`, `(J_dB, polynomial_R²)`, `(J_dB, J_transfer_HNLF - J_canonical)`.
2. `results/raman/phase31/L_curves/*.png` — one L-curve per penalty family (Tikhonov, GDD, TOD, TV, DCT-L1): log(J_raman) vs log(λ).
3. `results/raman/phase31/aic_ranking.csv` — AIC = N_effective_params + 2 · J_raman_dB per row, sorted.
4. `agent-docs/phase31-reduced-basis/candidates.md` — name the recommended operational basis / penalty with justification.
5. `agent-docs/phase31-reduced-basis/FINDINGS.md` — the phase narrative answer: "does reduced-basis or regularization give simpler + more transferable + equally-deep suppression?"

**Saddle-masking contract:** every Branch A basis-restricted PSD optimum flagged `PSD_UNVERIFIED_AMBIENT` (per the resolved Open Question 5 from the archived research — ambient Hessian probe is deferred out of Phase 31).

**Analysis loads from:** `sweep_A_basis.jld2`, `sweep_B_penalty.jld2`, `transfer_results.jld2`. No re-running of simulations.

## Risks + mitigations (Plan 01 experience)

1. **PyCall finalizer segfault.** `run.jl` already has `PyPlot.close("all")` + `GC.gc()` between runs. Replicate in `transfer.jl` wherever `save_standard_set` is called.
2. **Resume-from-JLD2.** Mirror the pattern from `run_branch_A` in `run_branch_B` so an interrupted sweep can be re-launched.
3. **Log-cost gradient scaling.** Penalties go in BEFORE the `log_cost` rescale in `cost_and_gradient`, matching the existing convention in `scripts/raman_optimization.jl`.
4. **`deepcopy(fiber)` per thread** — always, for any `@threads` block.
5. **Wall-time** — target Branch B ≤ 45 min, Task 2 ≤ 25 min, Task 3 ≤ 15 min on the Mac.

## Execution order

1. Implement Task 1 code + smoke test → commit → launch Branch B sweep in background.
2. While Branch B runs, implement Task 2 code + smoke test → commit → queue transfer probe.
3. When Branch B finishes: launch Task 2 probe.
4. When Task 2 finishes: implement + run Task 3 analysis.
5. Write `SUMMARY.md`, `FINDINGS.md`, `candidates.md`. Commit. Done.
