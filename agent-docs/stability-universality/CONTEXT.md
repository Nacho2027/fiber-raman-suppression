---
topic: stability-universality
status: research-synthesis
created: 2026-04-23
scope: documentation-only
---

# Stability And Universality Context

## Mission

This pass asks what makes a Raman-suppression phase profile scientifically useful, not just numerically low-cost. The working question is:

> Which phase structures are simple, transferable, interpretable, robust to real perturbations, and worth turning into a publishable claim?

No heavy simulations were run in this pass. The output is a synthesis and test plan based on existing project artifacts plus literature anchors.

## Project Evidence Read

- `AGENTS.md`, `CLAUDE.md`, `README.md`
- `docs/recent-phase-synthesis-29-34.md`
- `agent-docs/current-agent-context/{INDEX,METHODOLOGY,NUMERICS}.md`
- `agent-docs/multi-session-roadmap/SESSION-PROMPTS.md`
- `agent-docs/phase31-reduced-basis/{FINDINGS,SUMMARY,candidates}.md`
- `docs/why-phase-31-changed-the-roadmap.md`
- `results/raman/phase13/FINDINGS.md`
- `results/raman/phase16/FINDINGS.md`
- `results/raman/phase17/SUMMARY.md`
- `results/raman/phase_sweep_simple/candidates.md`
- `docs/planning-history/phases/35-saddle-escape/35-REPORT.md`
- `docs/cost-function-physics.md`
- `docs/interpreting-plots.md`

## Current Repo State

At session start, the worktree already had unrelated local changes:

- `scripts/lib/common.jl`
- `test/tier_fast.jl`
- `.github/`

This pass does not touch those paths.

`rg` was unavailable in this shell, so search used `find` plus `grep`.

## Key Existing Findings To Preserve

### Depth, robustness, and transferability are different objectives

Phase 31 is the central evidence. On canonical SMF-28, `L = 2 m`, `P = 0.2 W`:

- cubic reduced-basis continuation at `N_phi = 128` reached `J = -67.60 dB`
- full-grid zero-init L-BFGS plateaued around `-57.75 dB`
- the best cubic solution had a narrow perturbation basin, `sigma_3dB = 0.072 rad`
- the same cubic solution transferred poorly to HNLF, with a `+21.5 dB` HNLF gap
- polynomial `N_phi = 3` was shallow, `-26.50 dB`, but nearly fiber-transferable, with HNLF gap about `+0.29 dB`

The project should therefore stop using "best J" as the only definition of "good".

### Reduced-basis continuation is a basin-discovery method

Phase 31 follow-up showed:

- `cubic32 -> full-grid` reached `-67.16 dB`, far deeper than `zero -> full-grid = -55.75 dB`
- `cubic128 -> full-grid` stayed at `-67.60 dB`
- full-grid polishing did not improve robustness or transferability; it collapsed promising seeds into the same narrow canonical family

Interpretation: reduced-basis continuation is not merely a visualization trick. It changes which ambient basin the optimizer reaches.

### Competitive solutions are often saddle-dominated

Phase 13 found full-grid canonical optima with indefinite Hessians. Phase 35 sharpened the story:

- `N_phi = 4` is minimum-like but only `-47.34 dB`
- by `N_phi = 8`, the canonical branch is already indefinite
- `N_phi = 128` reaches about `-68 dB` and is still indefinite
- negative-curvature escape improves depth by only `0.19-0.48 dB` and lands on other indefinite points

Interpretation: a high-performing profile can be a scientifically useful operating point without being a true local minimum, but the documentation must call it a saddle-rich branch, not a clean robust optimum.

### Simple-looking is not the same as stable

Phase 17's simple phase was visually attractive and deep, `-76.862 dB`, but sharp:

- `sigma_3dB = 0.025 rad`
- direct eval-only transfer failed on nearby SMF-28 targets
- warm-start reoptimization from that phase succeeded broadly, reaching `-70 ... -82 dB` across nearby targets

Interpretation: this profile is better described as a strong initialization prior than as a universal fixed mask.

### Long-fiber structure is not simply quadratic chirp

Phase 16, `L = 100 m`, found strong suppression from a warm-start and refinement, but the weighted quadratic fit on the signal band had very low `R^2`:

- 2 m warm phase: `R^2 = 0.037`
- 100 m optimized phase: `R^2 = 0.015`
- observed quadratic coefficient ratio had the wrong sign and magnitude relative to pure-GVD scaling

Interpretation: for long fiber, a pure low-order chirp story is likely misspecified. Non-polynomial structure may be real physics, but it still needs stability checks.

## Literature Anchors

These sources were used as external grounding, not as proof that the exact project result is already known.

1. J. P. Gordon, "Theory of the soliton self-frequency shift," Optics Letters 11, 662-664 (1986), DOI `10.1364/OL.11.000662`.
   Source: <https://opg.optica.org/abstract.cfm?uri=ol-11-10-662>

   Relevance: Raman effects red-shift soliton mean frequency; the effect scales strongly with pulse width. This supports testing phase masks by whether they reduce peak intensity, delay compression, or avoid soliton-like Raman transfer.

2. F. M. Mitschke and L. F. Mollenauer, "Discovery of the soliton self-frequency shift," Optics Letters 11, 659-661 (1986), DOI `10.1364/OL.11.000659`.
   Source found via citation metadata: <https://www.scirp.org/reference/referencespapers?referenceid=579262>

   Relevance: establishes the experimental soliton self-frequency shift phenomenon that this project is trying to suppress or avoid.

3. J. M. Dudley, G. Genty, and S. Coen, "Supercontinuum generation in photonic crystal fiber," Reviews of Modern Physics 78, 1135-1184 (2006), DOI `10.1103/RevModPhys.78.1135`.
   Source: <https://journals.aps.org/rmp/abstract/10.1103/RevModPhys.78.1135>

   Relevance: reviews femtosecond anomalous-dispersion fiber dynamics, including soliton fission, stimulated Raman scattering, dispersive waves, and stability/coherence. Good phase masks should be judged by how they alter these propagation mechanisms, not only by final-band energy.

4. D. Strickland and G. Mourou, "Compression of amplified chirped optical pulses," Optics Communications 56, 219-221 (1985), DOI `10.1016/0030-4018(85)90120-8`.
   Source: <https://doi.ericoc.com/?doi=10.1016%2F0030-4018%2885%2990120-8>

   Relevance: chirped-pulse amplification is the canonical example of using spectral phase to stretch a pulse and lower nonlinear damage/peak-power effects. It motivates quadratic and higher-order chirp as simple test families.

5. A. M. Weiner, "Femtosecond pulse shaping using spatial light modulators," Review of Scientific Instruments 71, 1929-1960 (2000).
   Source: <https://engineering.purdue.edu/~fsoptics/articles/Femtosecond_pulse_shaping-Weiner.pdf>

   Relevance: phase-only and programmable spectral pulse shaping are experimentally meaningful only if masks are implementable under finite resolution, calibration error, wrapping, and bandwidth limits.

6. R. Kormokar, M. F. Nayan, and M. Rochette, "In-amplifier soliton self-frequency shift optimization by pre-chirping - experimental demonstration," Optics Letters, revised manuscript 2025.
   Source: <https://opg.optica.org/ol/upcoming_pdf.cfm?id=551176>

   Relevance: recent experimental evidence that pre-chirp can deliberately tune SSFS. This project is optimizing the opposite direction, suppression rather than enhancement, but the control lever is closely related.

7. D. Turke et al., "Chirp-Controlled Soliton Fission in Tapered Optical Fibers," CLEO/QELS 2005, paper CWC7.
   Source: <https://opg.optica.org/abstract.cfm?uri=cleo-2005-CWC7>

   Relevance: input chirp can modify soliton fission timing. Raman suppression profiles should therefore be tested for delayed compression/fission, not just reduced final Raman energy.

## Working Definition Of Scientific Usefulness

A phase profile is scientifically useful if it satisfies most of these:

1. It suppresses Raman energy relative to flat phase in an honest numerical setup.
2. It is not mainly a time-window, attenuator, plotting, or objective-scale artifact.
3. It has a low-complexity description after removing gauge modes: constant phase and linear group delay.
4. It is stable to plausible shaper errors: quantization, phase noise, smoothing, finite resolution, wrapping, and calibration drift.
5. It transfers, or fails to transfer in an interpretable way, across nearby `L`, `P`, pulse width, dispersion, and fiber presets.
6. It has a physical story visible in propagation diagnostics: lower peak power, delayed compression, delayed fission, weaker Raman-band growth, or controlled dispersive-wave/Raman coupling.
7. It lies on a Pareto front: no alternative is both simpler and deeper under the same trust checks.
8. It can be specified compactly enough for another group to reproduce.

By this definition, the project currently has several useful classes, not one winner.

## Promising Existing Profiles

### Most publishable simple baseline: polynomial / quadratic chirp

Candidate: Phase 31 polynomial `N_phi = 3`, `J = -26.50 dB`, HNLF gap about `+0.29 dB`.

Why promising:

- very simple
- physically interpretable as chirp/stretching
- highly transferable across fiber choice in the measured probe
- robust enough that `sigma_3dB` did not cross inside the tested ladder

Limit:

- too shallow to be the headline suppression result by itself

Best claim:

> A low-order chirp gives a transferable first-order Raman-reduction mechanism, but it does not access the deep suppression branch.

### Best deep canonical branch: cubic continuation / local spline family

Candidates:

- Phase 31 cubic `N_phi = 128`, `J = -67.60 dB`, `sigma_3dB = 0.072 rad`, HNLF gap `+21.5 dB`
- Phase 31 `cubic32 -> full-grid`, `J = -67.16 dB`, `sigma_3dB = 0.070 rad`, HNLF gap `+22.31 dB`

Why promising:

- strongest well-documented canonical depth
- reduced-basis continuation reaches a real full-grid basin
- local spline support works much better than global DCT at the same nominal dimensionality

Limit:

- narrow and canonical-specific
- likely saddle-rich

Best claim:

> Local, piecewise-smooth phase structure can access a deep suppression branch unreachable from zero-start full-grid L-BFGS, but this branch is not yet universal.

### Best warm-start prior: Phase 17 simple phase

Candidate: Phase 17 simple profile, `J = -76.862 dB`, `sigma_3dB = 0.025 rad`.

Why promising:

- very deep in its native setting
- reoptimization from it succeeded across 11 nearby targets

Limit:

- direct mask transfer failed
- too sharp for an experimental fixed mask without further robustness work

Best claim:

> Some simple masks are excellent initialization priors, even when they are poor fixed universal masks.

### Long-fiber structural profile

Candidate: Phase 16 100 m profile, `J_opt = -54.77 dB`.

Why promising:

- suppresses a regime where flat phase is essentially unsuppressed
- quadratic-fit failure suggests nonlinear structural adaptation rather than trivial GVD compensation

Limit:

- expensive and not yet multistart-verified
- non-polynomial structure may be fragile or path-dependent

Best claim:

> Long-fiber suppression likely requires structural phase features beyond simple GVD precompensation; this is a hypothesis needing controlled family tests.

## Probably Not Useful As Final Fixed Masks

### Full-grid zero-start saddle optima

Phase 13 and Phase 35 indicate many full-grid L-BFGS optima are saddle-like, start-dependent, and contain high-frequency structure. They are useful for diagnosing the landscape, but not good final scientific objects unless they pass smoothing, quantization, and transfer tests.

### High-penalty Branch B degenerates

Phase 31 Branch B high-penalty rows often converge toward `phi approx 0`, so any apparent transfer gap can be numerically misleading. These should not be counted as useful Raman-suppression masks.

### Deep but razor-sharp profiles without robustness

The Phase 17 profile is scientifically interesting, but a `sigma_3dB = 0.025 rad` mask is not robust enough to call experimentally transferable. It should be treated as an initializer until it passes hardware-error tests.

### Over-interpreted quadratic fits on non-quadratic profiles

For Phase 16-style long-fiber results, low `R^2` means quadratic coefficient ratios are not reliable physics. The residual structure is the object to study.

