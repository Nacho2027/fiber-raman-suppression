# Provisional Research Note Upgrade Worksheets

Evidence snapshot: 2026-04-28

These worksheets are for lanes whose final research artifacts are still moving.
They are not final scientific conclusions. They are a production checklist for
future note-writing agents once the runs finish.

## How To Use This File

Before upgrading a provisional note:

1. Read the lane's current agent context and README.
2. Confirm the final result artifacts exist.
3. Copy the required figures into the note under public-facing filenames.
4. Compile, render, inspect, and fix the PDF before promoting the note.
5. Update this worksheet with what was closed and what remains parked.

## `06-long-fiber`

Promotion status: promoted on 2026-04-28 as a completed 100--200 m
single-mode milestone note, with explicit non-convergence caveats.

### Current Intended Claim

The project has a real single-mode long-fiber path for roughly 100--200 m
exploratory SMF-style studies. The public note should present achieved,
image-backed milestones, not a converged global optimum.

### Final Result Inputs Needed

- Included: 100 m and 200 m scalar summary, no-shaping controls, optimized
  results, grids, convergence flags, and residual-gradient caveats.
- Included: explicit \(N_t\), time-window, length, power, and standard-image
  requirements.
- Parked: exact edge/energy table for every long-fiber artifact and multistart
  basin evidence.

### Required Figures

- Included: 100 m and 200 m no-shaping/optimized heat-map pairs.
- Included: 100 m and 200 m phase profile/diagnostic pages.
- Included: grid ladder, workflow diagram, and scalar result summary.

### Math And Method Sections Required

- Full Raman-band fraction and dB reporting convention.
- Input phase map `u_k(0; phi) = u_{0,k} exp(i phi_k)`.
- Short-to-long interpolation map on physical frequency.
- Gauge handling for constant and linear phase terms.
- L-BFGS warm-start strategy, including what changes between evaluation-only
  transfer and true long-target re-optimization.
- Explanation of why this is computational re-optimization, not automatically
  a physical in-line shaper experiment.

### Implementation And Provenance Inputs

- `scripts/research/longfiber/longfiber_setup.jl`
- `scripts/research/longfiber/longfiber_optimize_100m.jl`
- `scripts/research/longfiber/longfiber_validate_100m.jl`
- `scripts/research/longfiber/longfiber_regenerate_standard_images.jl`
- `scripts/research/propagation/matched_quadratic_100m.jl`
- final `results/raman/.../FINDINGS.md` or replacement public summary
- standard-image directory used for the figures

### Missing Or Parked Evidence

- Multi-start evidence for the 100 m/200 m basin.
- Converged long-fiber optimum claim.
- Mature multimode long-fiber extension.
- Physical segmented-reoptimization experiment.
- Cleaner lab-actuator-ready phase profile.

### Promotion Gate

Met for documentation quality on 2026-04-28. Do not promote the science beyond
the note's caveat without new convergence or lab-readiness evidence.

## `08-multimode-baselines`

Promotion status: promoted on 2026-04-28 as a qualified idealized GRIN-50 MMF
simulation note, with grid-refinement and launch/coupling gates still open.

### Current Intended Claim

The multimode lane explains which objective is meaningful, why the first large
gain was rejected, and why the boundary+GDD candidate is currently accepted as
a narrow simulation result.

### Final Result Inputs Needed

- Included: clean-window baseline table for the accepted constrained candidate.
- Included: summed, fundamental-mode, and worst-mode Raman fractions.
- Included: raw temporal-edge evidence separating rejected and accepted cases.
- Included: shared-phase gradient formula and mode-summed objective.
- Included: mode-coordinate work remains outside the accepted claim, with only
  preflight evidence available.

### Required Figures

- Included: no-shaping control heat map.
- Included: rejected unregularized diagnostic/heat map.
- Included: accepted boundary+GDD diagnostic/heat map.
- Included: total and per-mode spectra.
- Included: edge-trust chart and validation ladder.

### Math And Method Sections Required

- Multimode forward-model notation and what is actually included in the
  current code path.
- Exact multimode cost definition, including modal sums and any weights.
- Shared spectral phase map across modes:
  `u_{m,k}(0; phi) = a_{m,k} exp(i phi_k)`.
- Shared-phase gradient as a mode sum.
- Mode-coordinate derivative map if mode weights or launch coordinates are
  optimized.
- Explanation of any finite-difference block and why it is acceptable or only
  provisional.

### Implementation And Provenance Inputs

- `docs/status/multimode-baseline-status-2026-04-22.md`
- `agent-docs/multimode-baseline-stabilization/SUMMARY.md`
- `scripts/research/mmf/baseline.jl`
- `scripts/research/mmf/mmf_raman_optimization.jl`
- `src/mmf_cost.jl`
- active MMF validation logs/results once complete
- standard images for best, typical, and control cases

### Missing Or Parked Evidence

- Mature long-fiber MMF support.
- \(N_t=8192\), \(96\,\mathrm{ps}\) grid refinement with standard images.
- Launch-composition sensitivity matrix.
- Random/degenerate mode-coupling sensitivity.
- Phase-actuator realism or reduced/smoothed phase-basis test.

### Promotion Gate

Met for documentation quality on 2026-04-28. The accepted claim remains narrow
until the parked paper gates above are closed.

## `09-multi-parameter-optimization`

Promotion status: promoted on 2026-04-28 as an established simulated
refinement result, with the explicit caveat that it is not a lab-default
workflow yet.

### Current Intended Claim

The multiparameter lane should explain what happens when controls extend beyond
phase-only shaping, especially amplitude and energy-like variables. The final
note now makes the split claim: broad joint optimization underperformed, while
staged amplitude-on-fixed-phase refinement improved the phase-only result.

### Final Result Inputs Needed

- Included: result table comparing phase-only, amplitude-on-phase, energy-on-phase,
  amplitude+energy, warm joint, and cold joint cases.
- Included: optimizer-coordinate definitions for phase, bounded amplitude, and
  energy scaling.
- Included: gradient verification after the boundary-amplitude quotient fix.
- Included: final recommendation that staged amplitude refinement is the useful
  lane and broad joint optimization is a negative result.
- Partly parked: real hardware amplitude calibration and lab transfer.

### Required Figures

- Included: no-optimization control page.
- Included: phase-only reference phase diagnostic plus heat map.
- Included: amplitude-refined diagnostic plus corresponding heat map.
- Included: energy-refined diagnostic plus heat map.
- Included: objective/ablation summary and amplitude-bound sweep.
- Included: local robustness figure pair.

### Math And Method Sections Required

- Full physical objective and any regularizers.
- Complex input parameterization `a_k = A_k exp(i phi_k)`.
- Phase-gradient chain rule.
- Amplitude-gradient chain rule.
- Edge-energy quotient derivative, including denominator derivative.
- Coordinate transforms such as log-amplitude, bounded sigmoid/tanh maps, or
  scalar energy scaling.
- Explanation of why extra variables can help or hurt: more control authority,
  worse conditioning, and more ways to exploit numerical artifacts.

### Implementation And Provenance Inputs

- `agent-docs/current-agent-context/MULTIVAR.md`
- `scripts/research/multivar/multivar_optimization.jl`
- `scripts/research/multivar/multivar_amp_on_phase_ablation.jl`
- `scripts/research/multivar/multivar_variable_ablation.jl`
- `scripts/workflows/refine_amp_on_phase.jl`
- `scripts/dev/smoke/test_multivar_gradients.jl`
- `results/raman/multivar/smf28_L2m_P030W/`
- selected amplitude-on-phase, energy-on-phase, amplitude+energy, and warm-joint
  ablation directories under `results/raman/multivar/`
- `tables/multivar_comparison.md`
- `tables/multivar_comparison.csv`

### Missing Or Parked Evidence

- Hardware calibration for amplitude masks above unity.
- Wider sweep coverage beyond the canonical/local SMF-28 neighborhood.
- Convergence closure for runs that hit 50 iterations.
- Lab-ready handoff validation for amplitude-aware export bundles.

### Promotion Gate

Met for documentation quality on 2026-04-28. The note compiled, was rendered and
visually inspected, uses real standard images, includes the no-shaping control,
and cites the current unit/gradient smoke tests.
