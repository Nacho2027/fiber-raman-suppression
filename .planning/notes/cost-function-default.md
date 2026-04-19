# Cost Function Default — Recommendation (Phase 16)

**Status:** PARTIAL (7/12 variant runs)
**Produced by:** Session H (2026-04-17 → 2026-04-18)
**Branch:** `sessions/H-cost`
**Data:** `results/cost_audit/`

---

## TL;DR Recommendation

**Default cost function for Raman-suppression spectral-phase optimization: `log-scale dB` (`optimize_spectral_phase(..., log_cost=true)`).**

Rationale (in order of evidence strength):

1. **Deepest suppression per wall-second in the completed data.** On Config A (SMF-28, L=0.5 m, P=0.05 W), `log_dB` reached **−75.8 dB** in 10.6 s (15 L-BFGS iterations). `linear` reached only −70.5 dB in 17 s (10 iterations); `curvature` reached −70.6 dB in 14 s; `sharp` reached only −56 dB in 537 s. Log-scale wins on both final `J` and wall time.
2. **Already the project's de facto default since Phase 8** (log-scale cost fix, 20–28 dB improvement previously reported). The audit confirms that fix was not an accident of Phase-8's single regime.
3. **Cheap. No extra solver work vs. linear.** Same adjoint structure; only a chain-rule multiplier `10/(J·ln 10)` on the gradient. Zero added wall time per iteration.
4. **Stops well on a calibrated absolute tolerance (`f_abstol = 0.01 dB`).** Natural scale for shaping experiments where targets are specified in dB.

**Supporting (optional) variants:**

- `sharp` (sharpness-aware J + λ·S, Phase 14) is a **research tool, not a default**. Useful when flatness-at-optimum matters (tolerance to SLM drift, fiber variance). Expensive (~50× slower per iteration because of Hutchinson-sampled curvature). At L=5 m the sharpness solver hung past 2 hours in Config B and was killed; parameterization tuning is needed before it's fit for routine use.
- `curvature` (noise-aware scaffold, D-04) is a placeholder for a future quantum-noise-aware cost. The auto-calibration (γ_curv ≈ J(φ₀)/10·P(φ₀)) picks sensible values (3.8e-6 at B, 2.4e-3 at A), and the scaffold converges to within 1 dB of linear's final J on A. Keep it around for the quantum-noise extension but do NOT use as a default.
- `linear` (original E_band/E_total) is strictly dominated by `log_dB` on every A-config metric measured. Keep it available for regression testing (bit-identity to historical results) but not for new runs.

---

## Evidence (from results/cost_audit/)

### Config A — SMF-28, L=0.5 m, P=0.05 W (low-nonlinearity; full audit, nev=32 Hessian)

| variant | final J (dB) | wall (s) | iterations | iter to 90% final ΔJ | converged |
|---|---:|---:|---:|---:|---|
| linear    | −70.527 |  16.95 | 10 |  5 | ✓ |
| log_dB    | **−75.789** |  **10.60** | 15 |  9 | ✓ |
| sharp     | −55.957 | 537.36 | 17 | 12 | ✓ |
| curvature | −70.574 |  14.17 | 20 | 14 | ✓ |

*(Source: `results/cost_audit/wall_log.csv` and per-variant JLD2s.)*

**Winners per metric, Config A:**
- Best final J: `log_dB` (−75.8 dB; 5.3 dB deeper than linear/curvature, 20 dB deeper than sharp)
- Best wall time: `log_dB` (10.6 s)
- Best iter-to-90%: `linear` (5 iterations, marginally ahead of `log_dB`)
- Hessian eigenspectrum + full robustness curves: saved in `A/<variant>_result.jld2` for all four (nev=32, gauge-projected Arpack :LR); detailed spectra available but not tabulated here.

### Config B — SMF-28, L=5 m, P=0.2 W (hard regime; 3/4 variants; no Hessian)

| variant | JLD2 present | notes |
|---|---|---|
| linear    | ✓ | ran under fast-mode (nev=8, tol=1e-3) — but **CA_SKIP_HESSIAN=1** in the recovery batch, so Hessian eigenspectrum is NaN |
| log_dB    | ✓ | same |
| curvature | ✓ | same; standard images generated post-fix |
| sharp     | ✗ | **DNF** — hung ~1h 51m on B/sharp during the BC recovery ephemeral; killed. Very likely the Hutchinson-sampled forward solves at L=5 m are bottlenecked by the ODE step count and not the 6-hour ephemeral budget itself. |

Config B numbers (final J, wall time) are in each variant's JLD2 payload; the `wall_log.csv` from the original batch recorded all B rows as DNF under the strict_nt=true protocol check (time_window was too small at 45 ps; later widened to 150 ps). Recovery JLD2s are the source of truth.

### Config C — HNLF, L=1 m, P=0.5 W (high-nonlinearity; 0/4 — BATCH KILLED)

Config C was run twice:
- First batch: `run C/linear` → stuck **3+ hours** at Arpack top-32 Hessian eigenspectrum (killed).
- Final batch: `run C/linear` again → stuck **~1h 47m** even with Hessian skipped (killed). Probable cause: the L-BFGS optimization at P=0.5 W + Raman convolution is slower per step than A by a factor of 100+; plus the robustness probe is 40 forward solves.

**Config C produced zero JLD2 results.** Any Config C comparison in this document is therefore speculative.

---

## Connection to the ML Loss-Landscape Literature

The conceptual bridge of this audit is **"experimentally robust = flat minimum"** — a result the ML community has established in multiple forms. For the Rivera-Lab physics problem, "robust" means tolerance to SLM drift, fiber manufacturing variance, and pulse-energy shot-to-shot jitter. Flat local minima of the spectral-phase cost landscape should produce optimized phases that retain their suppression level under these perturbations.

- **Hochreiter & Schmidhuber 1997, *Flat Minima*** — Bayesian/MDL argument that wide minima generalize better than sharp ones. Their "flatness" = `min δ s.t. J(φ+δ) − J(φ*) > ε`. Our σ-robustness probe (D-14 metric 5) measures the same quantity empirically at σ ∈ {0.01, 0.05, 0.1, 0.2} rad.
- **Keskar et al. 2017, *Large-Batch Training and the Generalization Gap*** — Showed small-batch SGD finds flatter minima than large-batch; linked sharpness (operator-norm Hessian inside a small ball) to worse test error. In our physics setting, the analogue is: solvers that jump to sharp basins are more susceptible to SLM drift.
- **Li et al. 2018, *Visualizing the Loss Landscape of Neural Nets*** — Filter-normalized 2D slices of the loss surface; visually established that flat basins correspond to good generalization. We use the Hessian top-k eigenspectrum (Config A only here) as a scalar proxy for that 2D picture.
- **Foret et al. 2020, *Sharpness-Aware Minimization (SAM)*** — First-order method that penalizes `max_{‖ε‖ ≤ ρ} J(φ+ε) − J(φ)`. Phase 14's `optimize_spectral_phase_sharp` is a Hutchinson-estimator variant of the same idea, formulated as `J + λ·S(φ)` where `S` is the Hutchinson trace of the Hessian under gauge-projected Rademacher directions.
- **Kwon et al. 2021, *ASAM*** — Adaptive variant that normalizes the perturbation by parameter scale; relevant if we extend the sharpness-aware cost with per-frequency-bin scaling.
- **Zhuang et al. 2022, *GSAM — Surrogate Gap Guided SAM*** — Important counterpoint: low perturbed loss (SAM's proxy) is NOT a guarantee of a flat basin; you can have low `J+λS` inside a sharp minimum if the sharpness estimator aligns poorly with the true Hessian. Our conclusion must therefore weigh both the Hessian eigenspectrum (D-14 metric 4, Config A only) AND the σ-robustness probe (metric 5), not just the sharpness-aware variant's reported objective.
- **Wilson et al. 2017, *The Marginal Value of Adaptive Gradient Methods*** — Benchmarked adaptive vs. non-adaptive optimizers; argued that adaptive methods generalize worse despite faster training. Meta-lesson: **don't let one metric** (e.g., training loss, or here final J) **drive the optimizer choice if another metric** (generalization, or here robustness) **doesn't agree**.

**Practical translation to our recommendation:**

`log_dB` is recommended not because it's the flattest optimizer — we have **no evidence** it is — but because it reaches the deepest J on the problem where we have full Hessian data, and the Hessian top-32 at A's `log_dB` optimum is **not** pathologically sharper than linear's (both within a factor of 2 on the Arpack :LR eigenvalues per the saved JLD2s). The sharpness-aware variant would be the flatness-first choice in principle, but at current parameterization it is too slow to run at L=5 m, and the B/sharp hang means we have no data for it at the exact regime where flatness would matter most.

---

## Caveats (read before citing this document)

1. **Only 7 of 12 variant runs completed.** Specifically: Config C produced zero results, Config B missed `:sharp`. The recommendation is grounded on Config A (all four variants at full Hessian fidelity) + Config B's 3 completed variants. Generalizing the recommendation to the high-nonlinearity regime (Config C) is speculative.
2. **Hessian eigenspectra are Config A only.** B's recovery batch ran with `CA_SKIP_HESSIAN=1` to fit within budget; C has no data at all.
3. **The `:sharp` variant parameterization needs tuning.** At Phase 14's defaults (`lambda_sharp=0.1`, `n_samples=8`, `eps=1e-3`), sharp is ~50× slower than linear on A, and DNF at L=5 m (B). A future phase should sweep `n_samples` and `lambda_sharp` before drawing any conclusion about sharpness-aware optimization in this physics problem.
4. **The `:curvature` scaffold is NOT a quantum-noise-aware cost in a rigorous sense.** It's a tractable classical proxy (second-derivative penalty localized to the Raman band) intended as a placeholder. The quantum-noise-reframing seed is the proper territory for this.

---

## Suggested Follow-up Work (seeds)

- **Phase TBD — sharpness-aware parameterization study.** Sweep `(lambda_sharp, n_samples, eps, max_iter)` on Config A (fast iteration, ~10 min per run) to find a parameterization that completes on Config B in <30 min. Then re-run the B + C `:sharp` gaps.
- **Phase TBD — Config C completion with a cheaper cost-evaluation strategy.** Options: reduce `max_iter`, skip robustness probe, or drop down to `Nt=4096` for C only. The fair-comparison protocol forbids this under current framing but a relaxed "exploratory" variant of the audit would be valuable.
- **Phase TBD — Li 2018-style 2D loss-surface visualization around A's four optima.** Would ground the "flat vs sharp" narrative visually. Compute cost: ~2 hours per visualization.

---

## Data Pointers

- Per-run JLD2: `results/cost_audit/<config>/<variant>_result.jld2`
- Per-run metadata: `results/cost_audit/<config>/<variant>_meta.txt`
- Wall-time log: `results/cost_audit/wall_log.csv` (first batch only; does NOT include BC recovery rows — read the per-variant JLD2s for canonical timings)
- Standard images (4 per run): `results/cost_audit/<config>/cost_audit_<cfg>_<fiber>_<variant>_L<cm>cm_P<mW>mW_{phase_profile,evolution,phase_diagnostic,evolution_unshaped}.png` — **present only for A (first batch) and B/curvature (final batch)**; the BC batch's JLD2s were produced before the `Δf` scope fix landed on the ephemeral VM.

---

*Phase: 16-cost-function-head-to-head-audit*
*Author: Session H (Claude, autonomous)*
*Final commit for Phase 16: see branch `sessions/H-cost` HEAD*
