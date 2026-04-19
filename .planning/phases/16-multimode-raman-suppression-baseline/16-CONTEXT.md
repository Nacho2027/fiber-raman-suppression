---
phase: 16-multimode-raman-suppression-baseline
session: sessions/C-multimode
worktree: /home/ignaciojlizama/raman-wt-C
started: 2026-04-17
---

# Phase 16 — Multimode Raman Suppression Baseline

**Goal.** Extend the M=1 Raman suppression pipeline to M=6 multimode GRIN fibers. Produce a converged spectral-phase optimization at M=6 with physically meaningful figures, numerical correctness checks against M=1, and seeds for three adjacent research questions.

**Namespace.** Session C owns `scripts/mmf_*.jl`, `src/mmf_*.jl`, `.planning/phases/16-multimode-*`, `.planning/notes/mmf-*.md`, `.planning/seeds/mmf-*.md`, `.planning/sessions/C-multimode-*.md`. No edits to `scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/sharpness_optimization.jl`, `src/simulation/*.jl`.

**Decisions.** See `.planning/sessions/C-multimode-decisions.md` (D1–D8).

## Tasks (plan 01)

1. **Fiber preset library** — `scripts/mmf_fiber_presets.jl`. Exports `MMF_FIBER_PRESETS[:GRIN_50]`, `MMF_FIBER_PRESETS[:STEP_9]`, and `MMF_DEFAULT_MODE_WEIGHTS`. Pure data; no side effects.
2. **Setup helper** — `scripts/mmf_setup.jl`. Wraps `get_params` (from `src/simulation/fibers.jl`) + pulse initialization to return `(uω0, fiber, sim, band_mask, Δf)`. Must NOT call `setup_raman_problem`. Uses the fiber preset's spatial parameters.
3. **Cost variants** — `src/mmf_cost.jl`. Three functions: `mmf_cost_sum(uωf, band_mask)` (= `spectral_band_cost` wrapped), `mmf_cost_fundamental(uωf, band_mask)`, `mmf_cost_worst_mode(uωf, band_mask)`. Each returns `(J, dJ)` with dJ of shape (Nt, M). Include unit tests in-file via a standalone test block.
4. **Optimization entry point** — `scripts/mmf_raman_optimization.jl`. Defines:
   - `cost_and_gradient_mmf(φ, c_m, uω0_base, fiber, sim, band_mask; variant=:sum, λ_gdd, λ_boundary)` where `φ::Vector{Float64}` (length Nt, shared across modes) and `c_m::Vector{ComplexF64}` (length M, input mode weights; can be held fixed in phase 01 baseline).
   - `optimize_mmf_phase(...)` — L-BFGS on φ alone (c_m fixed) for the phase-01 baseline.
   - Plotting: per-mode output spectrum, total output spectrum, phase profile, convergence trace.
5. **Numerical correctness** — `test/test_phase16_mmf.jl`. Four assertions:
   - Energy conservation at M=6 — `|E_in - E_out| / E_in < 1e-4` at L=0.5m (short enough to minimize attenuator absorption).
   - M=1-limit: seeding `cost_and_gradient_mmf` at M=1 with LP01-only launch reproduces `cost_and_gradient` from `raman_optimization.jl` within `max|ΔJ_dB| < 0.1 dB` and `max|Δ∇J| / max|∇J| < 1e-3` at two random φ.
   - Gradient check via finite differences on 5 random φ components at M=6 — relative error < 1e-4.
   - Shape sanity: output `∂J/∂φ` has shape `(Nt,)` (not `(Nt, M)`) after reduction.
6. **Baseline run** — `scripts/mmf_baseline_run.jl` that wraps `optimize_mmf_phase` at L=1m, P=0.05W, GRIN-50, 30 L-BFGS iters, seeds=(42, 123, 7) for 3 starts. Saves `results/raman/phase16/baseline_M6.jld2` + per-seed PNG figures. Wall time benchmark logged.
7. **First M=6 optimization plus M=1 comparison** — both runs produce before/after figures. Log `J_dB` improvement. Note whether the optimal φ at M=6 looks qualitatively different from M=1 (gauge-fixed polynomial projection per Phase 13 pitfalls).
8. **Seeds for adjacent threads** — three seed files in `.planning/seeds/`:
   - `mmf-phi-opt-length-generalization.md` (= free-exploration option b)
   - `mmf-fiber-type-comparison.md` (= option c)
   - `mmf-joint-phase-mode-optimization.md` (= option a — planted as a seed BEFORE Phase 17 runs it).

## Free exploration thread (Phase 17, follow-on)

Joint phase + {c_m} optimization at M=6 — option (a) per session prompt.
Explicit out-of-scope for Phase 16 plan 01 to bound the first deliverable.

## Success criteria

- [ ] `scripts/mmf_raman_optimization.jl` exists, runs at M=6, L-BFGS converges within 30 iters at L=1m, GRIN-50.
- [ ] Numerical correctness: energy conservation + M=1-limit reproduction + FD gradient check all pass.
- [ ] Baseline produces at least one JLD2 + three PNG figures (input vs output per-mode spectrum; convergence; phase profile).
- [ ] Per-solve wall time at M=6 benchmarked on the burst VM (vs M=1 for scaling).
- [ ] 3 seeds planted in `.planning/seeds/mmf-*.md`.
- [ ] This session log and decisions committed to `sessions/C-multimode` branch.

## Dependencies

- **Phase 14 (sharpness)** — independent. Not required; MMF path does not consume sharpness-aware optimizer.
- **Phase 15 (FFTW determinism)** — advisory. We use `FFTW.ESTIMATE` inside the new MMF code (matches existing `get_p_disp_mmf`). Wisdom file optional for the M=1-limit regression check; not required for Phase 16 plan 01.
- **MMF simulation core** — in place at `src/simulation/simulate_disp_mmf.jl` + `sensitivity_disp_mmf.jl` + `fibers.jl`. No modifications.
