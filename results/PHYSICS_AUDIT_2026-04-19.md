---
title: Physics Audit — 2026-04-19
audience: Rivera Lab (internal)
author: autonomous audit pass
inputs:
  - results/SYNTHESIS-2026-04-19.md
  - results/raman/phase{13,15,16,17}/**
  - scripts/longfiber_*.jl
  - src/simulation/{simulate,sensitivity}_disp_mmf.jl
  - docs/{companion_explainer,physics_verification,verification_document}.tex
scope: decide which post-2026-04-16 physics claims survive scrutiny for the canonical docs
---

# Physics audit — 2026-04-19

## Method

Every substantive physics claim in `SYNTHESIS-2026-04-19.md` (and the
session/phase summaries it cites) is classified into one of three
buckets below, with the evidence I relied on. A claim is **defensible**
if (a) a converged optimizer produced the number, (b) energy
conservation and standard-image sanity checks pass, and (c) the
physical interpretation is decoupled from any non-converged or
noise-dominated post-process. A claim is **shaky** if the number is
real but the framing overclaims. A claim is **wrong** if the stated
interpretation is inconsistent with the underlying fit quality or
optimizer state.

Only the `.tex` LaTeX sources under `docs/` are canonical; the markdown
under `results/raman/` is input-only and was not edited.

**Counts.** 8 defensible · 6 shaky · 3 wrong · 2 missing-data (keep out).

---

## Defensible

### D1. SMF-28 canonical re-baseline: **J = −76.86 dB** at L=0.5 m, P=0.05 W

Source: `results/raman/phase17/SUMMARY.md:41` (baseline), backed by
`results/raman/phase17/baseline.jld2`. 21 L-BFGS iter, 25 s, within
expected −77.6 ± 1 dB envelope from the earlier Phase 10 zresolved
baseline (CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md §2.2, L=0.5 m P=0.05 W,
J = −77.6 dB). Converged flag true. N_sol ≈ 1.3, Φ_NL = 1.63 rad,
P_peak = 2959 W — all internally consistent.

### D2. Perturbation tolerance σ_3dB = 0.025 rad (SHARP_LUCKY)

Source: `results/raman/phase17/SUMMARY.md:45`, 100-task (5 σ × 20
samples) Gaussian perturbation scan, interpolated at the 3 dB crossing.
Mechanism is independent of any polynomial fit. Passes the H-hypothesis
table at `SUMMARY.md:67`. Engineering relevance is real: an SLM with
≥ 0.05 rad rms calibration error already loses most of the −77 dB
advantage (source-cited at `SUMMARY.md:17–18`).

### D3. Simple-phase profile is a good *warm-start initialiser*, not a universal attractor

Source: `results/raman/phase17/SUMMARY.md:22–28`. Eval-only transfer
fails on 0/7 SMF-28 targets (≥ 3 dB gap), but L-BFGS re-optimised from
the baseline φ_opt reaches −70 to −82 dB in 6–40 iter on 11/11 nearby
configs including HNLF at −79.5 dB. This reframes the earlier
"simplicity = universal minimum" intuition, and is the cleanest
positive finding of the integration pass.

### D4. Pareto front at reduced parameterisation N_φ=57

Source: `results/raman/phase_sweep_simple/candidates.md:12–14`. Best
candidate SMF-28 L=0.25 m P=0.10 W → **−82.33 dB**, ΔJ within 3 dB of
the full-grid optimum at its operating point. Non-dominated on
(J_dB, N_eff). Standard images saved (132 four-panel sets). This opens
the door to second-order optimisation on a 57-dim subspace (tractable).

### D5. Hessian is indefinite at the canonical L-BFGS optima

Source: `results/raman/phase13/FINDINGS.md:113–120`. SMF-28
|λ_min|/λ_max = 2.6 %; HNLF = 0.41 %. Sign pattern is 100 % same-sign
on each wing over 20 eigenpairs. HVP Taylor-remainder slope ≈ 2
(`test/test_phase13_hvp.jl` at commit `b962091`). This is the strongest
quantitative evidence on main that L-BFGS stops at saddles, not minima.

### D6. Determinism cost of FFTW.ESTIMATE: +21.4 % wall time, bit-identical J

Source: `results/raman/phase15/benchmark.md:20–27,39`. Three independent
Julia processes converge to identical floating-point J (0 max-min) with
ESTIMATE vs. 1.06 × 10⁻¹³ under MEASURE. Tested at one config only
(SMF-28 L=2 m P=0.2 W) but the mechanism (deterministic plan choice vs.
timing-noise-driven selection) generalises. Now wired into the five
main driver entry points.

### D7. MMF (M=6) optimizer code-complete and numerically validated

Source: `.planning/phases/16-multimode-raman-suppression-baseline/16-01-SUMMARY.md`;
`test/test_phase16_mmf.jl`. 13/13 correctness tests pass: energy
conservation (thread-safe `deepcopy(fiber)` pattern), M=1-limit agreement
with the scalar optimizer, finite-difference gradient check rel-err <
0.5 % on 5 random indices at ε=10⁻⁵ (Nt=2^12). Caveat (see S3 below):
the single production run used a sub-soliton config (N_sol ≈ 0.9) so
ΔJ = 0 dB is correct physics, not a validation result.

### D8. Log-scale cost is the correct formulation

Source: `docs/verification_document.tex:650–656` + `MATHEMATICAL_FORMULATION.md:443–444`.
J_dB = 10 log₁₀(J) with gradient multiplier 10/(J ln 10) is
mathematically exact (Wirtinger chain rule). The 20–28 dB numerical
improvement over linear-scale L-BFGS is reproducible: Phase 7/8 sweeps
spread 28.6 dB → 10.9 dB on the 24-config grid.

---

## Shaky — real numbers, overclaimed framing

### S1. "log_dB is the project default — −75.8 dB in 10.6 s" (Session H)

Source: `results/cost_audit/wall_log.csv`. True on **Config A (SMF-28,
default canonical)**: log_dB 10.6 s → −75.79 dB; linear 16.9 s → −70.53
dB; sharp 537 s → −55.96 dB; curvature 14.2 s → −70.57 dB. **All four
variants DNF on Config B** (`wall_s=NaN, dnf=true` on rows 6–9). The
"winner" verdict is empirically supported on 1 of 2 configs. Doc
treatment: keep as the default with an explicit scope tag
("SMF-28 canonical"), flag the Config B hang as an open issue.

### S2. SMF-28 L=2 m P=0.2 W "canonical" suppression at −71.4 dB

Source: `results/raman/CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md:158`.
The originally-reported number was measured with the v1 time window.
`docs/verification_document.tex:1161` already concedes the honest
suppression at 2× wider window is **−65.8 dB** (14.4 % of energy was
parked at the time-window edges). The +5.5 dB delta is an artefact.
This is already acknowledged in the doc; the audit contribution is to
upgrade the caveat from a line item to a flag in the baseline table.

### S3. MMF production baseline (ΔJ = 0 dB at N_sol ≈ 0.9)

The ΔJ = 0 dB at M=6, L=1 m, P=0.05 W is **correct physics** (no Raman
to suppress in sub-soliton regime) but is presented in the synthesis as
a "result" of the MMF extension. It is a *negative control*, not a
science result. The aggressive-regime baseline (L=2 m P=0.5 W,
N_sol ≈ 2–3) has not been run. Doc treatment: describe the optimiser
as *validated but unexercised*, not as "extension complete."

### S4. 100 m L-BFGS "optimum" at −54.77 dB

Source: `results/raman/phase16/FINDINGS.md:21–34`. The number is real
and energy-conserved (photon-drift 4.9 × 10⁻⁴, edge-fraction 8.5 × 10⁻⁶)
but `converged = false`, 25 L-BFGS iter (fresh), **final ‖∇J‖ = 0.479**.
Cost is descending through iter 18–25 with ∼0.0001 dB per step but
gradient norm stays O(10⁻¹). This is a **lower bound**, not a
minimum. Doc treatment: report as "best J achieved in 25 iter from
the 2 m warm start," drop the word "optimum."

### S5. Warm-start φ@2 m delivers −51.50 dB at L=100 m (50× length scale)

Source: same `FINDINGS.md`. The number is defensible on the cost-function
side (energy-conserved, correctly computed). But the suppression
relative to J_flat = −0.20 dB is mostly explained by the warm-start
phase being *any* sufficiently-dispersive pre-chirp: a large input
chirp of either sign will broaden the pulse before it accumulates
nonlinear phase, depressing peak power below the Raman threshold along
most of the 100 m. The "transferability across 50× length" framing
overclaims unless a matched generic-quadratic-chirp baseline is also
run. Doc treatment: report the number, describe the mechanism as
"dispersive pre-chirp prevents soliton formation," flag the matched
baseline as an open experiment.

### S6. Gradient FD error 0.026 % and Taylor slope 2.00/2.04 as "strongest evidence" of adjoint correctness

Source: `docs/verification_document.tex:601–611`. The measurement itself
is fine at the reference points used (phi = 0, Δω shift). But the
Phase 18 numerical-trustworthiness audit (`git log` commits
`2c95f60`, `2de3caf`, `1a78cc8`) shows that Taylor-at-the-optimum
**fails** the slope-2 criterion because ‖∇J‖ is 3–5 orders of magnitude
above the ODE solver noise floor only at **unshaped** φ = 0, not at
the converged φ_opt where the gradient is below the noise floor.
Phase 18 had to validate the adjoint at a steepest-descent shifted
reference (ε = 10⁻³, shift = 2 rad) to beat the floor. Doc
treatment: retain the slope-2 claim but scope it to the unshaped
reference; add a §5-limitation that at a true optimum the test cannot
distinguish correct gradient from noise.

---

## Wrong

### W1. "a₂(100 m) / a₂(2 m) = −3.30 vs. pure-GVD-predicted +50" as evidence of nonlinear structural adaptation

Source of claim: `results/raman/phase16/FINDINGS.md:58–67`; fit code at
`scripts/longfiber_validate_100m_fix.jl:54–79`.

The fit is a weighted least-squares quadratic on the ±5 THz signal band
(2349 / 32768 = 7.2 % of bins) with weight = analytic sech² amplitude.
**The reported R² is 0.015 at 100 m and 0.037 at 2 m.** A fit that
explains < 4 % of the variance is noise-dominated; the extracted a₂ is
a ratio of two residual-noise-level coefficients, not a physical
quadratic component of the phase.

The ratio "−3.30 vs. +50" is therefore a comparison of (a) a ratio of
noise and (b) the L-scaling prediction of a model (pure-GVD
pre-compensation) that the phase visibly does not follow. The sign
flip is the tell — a real quadratic coefficient perturbed by noise
does not change sign unless the true coefficient is near zero, which
is exactly what R² → 0 says. Doc treatment: the finding "φ_opt is not
explained by a low-order polynomial over the signal band" is
**defensible on its own** (matches Phase 9 and Phase 13 at
`PHASE9_FINDINGS.md:19–29`). The GVD-scaling comparison should be
**removed**, not caveated.

### W2. "a₂ ratio signals publishable physics (D-F-07)"

Source: `FINDINGS.md:66`. Same reason as W1: when R² < 0.04 at both L
values, the a₂ ratio carries no signal. No publishable thread exists
from this comparison. (The *other* 100 m findings — the warm-start
persistence and the non-polynomial structure — remain, and are
defensible per S5 and the surviving half of W1.)

### W3. "Simple phase = 7 stationary points vs. Phase-13 canonical 16; Pearson r = 0.94, N = 4 optima"

Source: `results/raman/phase17/SUMMARY.md:24–27,46`. The correlation is
reported over **N = 4** optima. A Pearson r at n = 4 has a 95 %
confidence interval of roughly (−0.4, 0.995) — essentially
uninformative. The qualitative claim (fewer stationary points
correlates with better suppression) is plausible and worth pursuing,
but the r = 0.94 should not be quoted without the sample size, because
stated without n it reads as a strong statistical result. Doc
treatment: demote "Pearson r = 0.94" to "4-point trend consistent with
low-Φ_NL = simpler phase", or omit.

---

## Missing data — keep out of canonical docs

### M1. "Joint {φ, A, E} L-BFGS finding" (Session A)

The 38 dB gap between joint cold-start (−16.78 dB) and phase-only
(−55.42 dB) on SMF-28 L=2 m P=0.3 W is a **bug report** (L-BFGS
preconditioning fails under mixed-unit decision variables), not a
physics result. `16-01-SUMMARY.md:149–152` says as much. Stays out of
the docs until Phase 18-multivar-convergence-fix lands.

### M2. "Sharpness-aware A/B" (Session G)

Never ran (`BIG_WARNING.md`). No data. Stays out.

---

## Contradictions against existing doc claims

- `verification_document.tex:611` states slope-2 on the Taylor remainder
  is "the strongest evidence" of adjoint correctness. **This is true at
  the unshaped reference (φ = 0) and false at the converged optimum**
  (Phase 18 audit). The doc should add a scoped limitation. See S6.
- `verification_document.tex:1161` concedes honest suppression is −66 dB
  (v1 window too narrow). The canonical baseline table elsewhere in
  the doc (and in the presentation figures) quotes −71.4 dB without
  the flag. The audit contribution is to tighten that consistency.

---

## Docs update plan (Phase 2)

- **companion_explainer.tex**: append a short §16 "What 48 hours of
  parallel sessions added" — the four undergrad-accessible findings
  (D1, D2, D3, D8), one paragraph each, no new math. Do not mention
  a₂ ratios.
- **physics_verification.tex**: append §5 adjoint-verification
  limitation (S6) — one paragraph, scope the Taylor-slope-2 claim.
- **verification_document.tex**: (i) new §9 "Integration pass
  (April 2026)" reporting D1–D8 with their scope caveats; (ii) new
  §6.3 item recording the corrected framing of the 100 m result
  (S4 + S5 + W1); (iii) add `honest-suppression` flag to the
  baseline table row for SMF-28 L=2 m P=0.2 W.

---

*Inputs are listed in the front-matter. No simulations were run for
this audit; the claims were decided by inspection of existing artifacts
and against physical priors.*
