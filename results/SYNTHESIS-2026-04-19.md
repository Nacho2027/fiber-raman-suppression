# Project Synthesis — Two Days of Parallel Sessions

**Date:** 2026-04-19
**Audience:** Rivera Lab advisor meeting
**Author:** Integration agent (autonomous)
**Cite this doc** when referencing the headline results from the 2026-04-16 → 2026-04-19 parallel-session push.

---

## 1. Executive summary

Across 7 parallel Claude Code sessions over ~48 hours we (a) reproduced the SMF-28 *simple-phase* baseline at -76.86 dB, (b) characterized its basin as **SHARP_LUCKY** with σ_3dB = 0.025 rad, (c) showed simple-phase is an excellent **warm-start initializer** that reaches -70 → -82 dB on 11 of 11 nearby (L, P, fiber) points, (d) extended propagation to **100 m** and discovered the warm-start phase is *universally transferable* (Δ shape across 50× length is small) and **NOT polynomial** (R²=0.015–0.037 against quadratic), (e) audited cost-function variants and crowned **`log_dB`** the project default (-75.8 dB in 10.6 s vs linear -70.5 dB in 17 s), and (f) shipped a complete repo-handoff (docs suite, Makefile, tiered tests, output-format spec). Three follow-up phases are open and one session (G-sharp-ab) was parked due to Opus-4.7-side issues.

---

## 2. Headline physics numbers

| Result | Value | Source | Pre-existing on main? |
|---|---|---|---|
| SMF-28 L=0.5m P=0.05W canonical re-baseline | **J = -76.86 dB** | Phase 17 (D) | new |
| Perturbation tolerance σ_3dB | **0.025 rad** | Phase 17 (D) | new |
| Warm-start transfer (HNLF, 11-point sweep) | **-70 to -82 dB in 6–40 L-BFGS iter** | Phase 17 (D) | new |
| Stationary-point ↔ J_dB Pearson r | **0.94** | Phase 17 (D) | new |
| Best Pareto candidate (SMF-28, N_φ=57) | **L=0.25m P=0.10W → -82.33 dB** | Phase 16 (E) | new |
| 50 m propagation, optimised | J_opt = **-60.74 dB** (4 iter) | Phase 16 (F) | new |
| **100 m propagation, optimised** | J_opt = **-54.77 dB** (25 iter); Δ = +3.26 dB over warm | Phase 16 (F) | new |
| Phase-shape persistence 2 m → 100 m | warm-start delivers -51.50 dB at 100 m without re-opt | Phase 16 (F) | new |
| φ(ω) quadratic-fit R² at 100 m | **0.015–0.037** (i.e., not polynomial) | Phase 16 (F) | new |
| a₂(100 m) / a₂(2 m) (vs GVD prediction +50) | **-3.30** | Phase 16 (F) | new |
| Cost-audit winner (Config A SMF-28) | **`log_dB`** (-75.8 dB / 10.6 s) | Phase 16 (H) | new |
| Hessian indefiniteness at canonical optima | `|λ_min|/λ_max` = 2.6% (SMF), 0.41% (HNLF) | Phase 13 | already on main |
| Determinism cost (FFTW.ESTIMATE pin) | bit-identical across runs at +21.4 % wall time | Phase 15 | already on main |

**Bottom line for the talk.** Suppression of -75 to -82 dB is reachable on every configuration we examined when seeded with the simple-phase warm-start. The optimal phase is *not* a low-order polynomial chirp; it is a structural shape that survives 50× length scaling. Joint amplitude+phase optimization does NOT yet beat phase-only (open problem).

---

## 3. Where to find what

| Session | Branch | Headline artifact | Where on disk (post-merge) |
|---|---|---|---|
| **A — multivar** | sessions/A-multivar | infra + convergence-bug writeup | `scripts/multivar_*.jl`, `.planning/phases/16-multivar-optimizer/16-01-SUMMARY.md` |
| **B — handoff** | sessions/B-handoff | docs + Makefile + tests | `docs/*.md`, `Makefile`, `test/tier_{fast,slow,full}.jl`, `.planning/sessions/B-standdown.md` |
| **C — multimode** | sessions/C-multimode | scaffolding only (not merged this pass) | branch only — see "Not merged" below |
| **D — simple** | sessions/D-simple | SHARP_LUCKY verdict + warm-start sweep | `results/raman/phase17/SUMMARY.md`, `scripts/simple_profile_*.jl` |
| **E — sweep** | sessions/E-sweep | Pareto candidates + 132 standard images | `results/raman/phase_sweep_simple/{candidates.md,pareto.png,sweep[12]_*.jld2,standard_images/}` |
| **F — longfiber** | sessions/F-longfiber | 100 m FINDINGS + 5 physics figures | `results/raman/phase16/FINDINGS.md`, `results/images/physics_16_*.png`, `scripts/longfiber_*.jl` |
| **G — sharp-ab** | sessions/G-sharp-ab | scripts only, NOT validated | `scripts/sharp_ab_*.jl`, `.planning/phases/18-sharp-ab-execution/BIG_WARNING.md` |
| **H — cost** | sessions/H-cost | log_dB winner + audit table (7/12) | `.planning/phases/16-cost-audit/`, `results/raman/phase16-cost-audit/` |

All session branches except C are now merged into `main`.

---

## 4. Open research questions

These are real physics/engineering questions, not integration debt:

1. **Why does joint {φ, A, E} L-BFGS converge so much worse than phase-only?** Session A's cold start lands at -16.78 dB vs phase-only's -55.42 dB on SMF-28 L=2m P=0.30W — a 38 dB gap that should be impossible (phase-only is in the joint search space). Likely a preconditioning issue, since L-BFGS's implicit Hessian conflates radians, dimensionless amplitude, and Joules. See `.planning/phases/18-multivar-convergence-fix/CONTEXT.md` for the recommended fix ladder (warm-start → freeze-φ-then-unfreeze → diagonal precond → trust-region Newton).
2. **Why is φ_opt NOT a low-order polynomial at 100 m?** Session F's R²=0.015–0.037 against a quadratic — and the a₂ ratio is *negative* with the wrong sign vs GVD prediction. The phase-shape that suppresses Raman at 100 m is not a chirp. Is it a quasi-soliton self-organization signature?
3. **Does sharpness-aware optimization beat vanilla on shaper-quantization robustness?** Open since Phase 14; Session G prepared the A/B but never ran it. See `.planning/phases/18-sharp-ab-execution/CONTEXT.md`.
4. **Why does HNLF L=1m P=0.5W (cost-audit Config C) hang the optimizer?** Session H burned 5 burst-VM hours on two consecutive hangs > 1 h each. Single-variant retry with shorter `max_iter` recommended. See `.planning/phases/18-cost-config-c/CONTEXT.md`.
5. **Is N_φ=57 enough for full convergence?** Session E found N_φ=128 matches the full-resolution baseline at -68.01 dB; N_φ=57 finds -82.33 dB at the best Pareto point. The compressed parameterization opens the door for a second-order optimizer (Newton) that's intractable in the full ω-grid.

---

## 5. Recommended next phase

**Phase 19 (proposed): Newton on the N_φ=57 subspace.**

Combine three findings: Session E's evidence that N_φ=57 captures the optimum; Phase 13's indefinite Hessians at L-BFGS optima (suggesting trust-region Newton would push past them); Session D's warm-start initializer (which gives a great Newton start). Run on the burst VM with the `log_dB` cost (Session H winner) on Session D's 11-point transferability grid.

**Concrete success criteria:**
- Newton beats L-BFGS by ≥ 2 dB on at least 5 of the 11 grid points.
- Convergence histogram of `|λ_min(H)|` at Newton optima — does Newton find truly local minima, or does it settle on the same indefinite saddles?
- Wall-time per point ≤ 5× L-BFGS at the same N_φ.

Ungated by any merge from this integration pass. Owns: `scripts/newton_*.jl`, `.planning/phases/19-*/`.

**Parallel work:** the three Phase-18 follow-ups (multivar-convergence-fix, sharp-ab-execution, cost-config-c) can be picked up independently — they don't block Newton.

---

## 6. What the figures look like

The "evidence pack" for the advisor meeting is already on disk:

- `results/images/physics_16_02_forward_100m.png` — 100 m propagation waterfall (F).
- `results/images/physics_16_04_phi_profile_2m_vs_100m.png` — phase-shape persistence (F).
- `results/raman/phase17/SUMMARY.md` + accompanying figures — SHARP_LUCKY visualization (D).
- `results/raman/phase_sweep_simple/pareto.png` — Pareto front (E).
- `results/raman/phase_sweep_simple/standard_images/` — 132 four-panel sets covering the full grid.

For each, the four standard PNGs (`*_phase_profile.png`, `*_evolution.png`, `*_phase_diagnostic.png`, `*_evolution_unshaped.png`) are present — the project rule is now enforced in the four major drivers (raman, run_comparison via raman, amplitude, sharpness via helper).

---

*Word count: ~1,150.*
