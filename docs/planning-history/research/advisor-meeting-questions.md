---
title: Advisor Meeting Questions — Multimode Extension Direction
date: 2026-04-16
meeting: Today (approx. 1 hour from 2026-04-16 exploration session)
priority: high
purpose: Resolve blockers that determine the shape of multimode Raman suppression optimization
---

# Advisor Meeting Questions (2026-04-16)

Each answer steers a concrete decision in the multimode extension plan. Priority-ordered.

## 1. SLM setup — spectral only, or also spatial?

> Does the Rivera Lab experimental setup have one SLM or two?
>
> - **Spectral SLM (pulse shaper)**: placed in the Fourier plane of a 4f geometry, controls `φ(ω)` of the pulse. This is what generates the spectral phases we optimize. Doesn't touch spatial mode content.
> - **Spatial SLM (mode shaper)**: placed in the beam path near the fiber launch, shapes the spatial wavefront to control which LP modes get excited at the fiber input.

**Why it matters:** determines whether input mode coefficients `{c_m}` are optimization parameters (spatial SLM present) or fixed boundary conditions (only spectral SLM — input is whatever a bare Gaussian beam couples into).

**If spatial SLM present:** unlocks a genuinely novel research question — does jointly optimizing spectral phase + mode content give fundamentally better multimode Raman suppression than phase-only?

## 2. If spatial SLM: phase-only or complex amplitude?

> Is the spatial SLM a standard phase-only LCoS device, or does it support complex (amplitude + phase) modulation?

**Why it matters:** phase-only SLMs can still synthesize any target mode superposition via computer-generated holograms, but with power loss to diffraction orders. Complex-amplitude SLMs are efficient but much rarer. Affects how we parameterize `{c_m}` in the optimizer (unit-norm constraint vs free complex) and how realistic we should be about achievable mode purity.

## 3. What does the current multimode experiment actually launch?

> When you've run multimode fiber experiments in the past, what's the input mode content?
>
> - Controlled superposition tuned via SLM?
> - Fiber-end LP01-matched launch, with LP11/LP21 spillage from imperfect alignment?
> - Something else (e.g., tapered SMF → MMF adiabatic launch)?

**Why it matters:** determines the baseline against which "optimized launch" is compared. If the lab routinely does LP01-only launches, the comparison is "phase-only optimization with LP01 input" vs "phase + mode-coefficient optimization." If launches are already tuned, the comparison is different.

## 4. Multimode cost function target

> When you say "reduce Raman in multimode," what's the intended measurement downstream?
>
> - **(a)** "Suppression across all output modes equally" — cost = sum over modes, `(Σ_m E_band_m) / (Σ_m E_total_m)`
> - **(b)** "Suppression only in the mode being detected" — cost = `E_band_signal / E_total_signal` for a specific output mode
> - **(c)** "Worst-case suppression across modes" — cost = `max_m (E_band_m / E_total_m)` for robustness
> - **(d)** "Detection-weighted" — cost weighted by the actual detection's mode selectivity

**Why it matters:** these give different optima. (b) is natural if the detector is single-mode-selective (LP01 via fiber coupler). (a) is natural if detection is bucket-integrated over a large-area detector. Current single-mode code implicitly uses (b) with M=1.

## 5. Long-fiber scope for multimode

> Phase 12 (suppression-reach) pushed L out to 30 m for SMF-28 and validated that phi@2m maintains -57 dB suppression at 15× the optimization horizon. For multimode, what length scales matter?
>
> - Short (0.5–5 m): quantum-noise squeezer regime
> - Intermediate (5–50 m): the current "suppression reach" regime
> - Long (50+ m): classical / telecom relevance
> - All of the above as a parametric study?

**Why it matters:** affects simulation cost estimates. Longer fibers = more ODE steps per solve = longer Newton iterations. Dictates whether we should target one length or build a length-sweep into the design.

## 6. Any physics constraints we haven't surfaced?

Open-ended question — often where the most useful information comes out:

> Is there any physics (modal walk-off, random mode coupling from fiber imperfections, polarization mixing, Raman-induced mode-specific loss, pump depletion in a cascaded amplifier, etc.) that you want us to account for in the multimode simulation that isn't in the single-mode code?

**Why it matters:** surfaces hidden requirements before they become rework. The current multimode code is "clean" — no random mode coupling, no modal noise, idealized dispersion. If the PI wants any of these effects modeled, better to know now.

## 7. Timeline check

> Given the 4-week remaining window, are there specific deliverables expected from the multimode work (conference abstract, paper figure, group meeting presentation)? What level of result satisfies the sprint goal — "first multimode simulation showing phase-shaped Raman suppression working" vs "parametric study across fiber length / input mode content"?

**Why it matters:** aligns ambition with time. Prevents either over-scoping (attempting a paper-worthy result in 4 weeks) or under-scoping (finishing too early without a follow-on plan).

---

## What I'll do with the answers

Each answer routes to a concrete plan update:
- Q1 (SLM setup) → decides whether `.planning/seeds/launch-condition-optimization.md` becomes an active phase or stays a seed.
- Q2 (SLM type) → affects parameterization in the joint-optimization implementation.
- Q3 (current launch) → sets the baseline simulation configuration.
- Q4 (cost function) → picked as the M>1 cost in the multimode forward/adjoint ODE setup.
- Q5 (fiber length) → determines sweep axes in the benchmark / results plan.
- Q6 (hidden physics) → may add new phases to the roadmap, or at minimum requirements to existing phases.
- Q7 (deliverable) → calibrates the week-by-week plan.
