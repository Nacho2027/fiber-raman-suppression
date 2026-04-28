# Multi-Parameter Optimization Beyond Phase-Only Shaping

- status: `established research result; not lab-default workflow`
- evidence snapshot: `2026-04-28`

## Purpose

Explain the joint control space, the negative broad-joint result, and the positive two-stage amplitude-on-fixed-phase refinement result.

## Primary sources

- `agent-docs/current-agent-context/MULTIVAR.md`
- `scripts/research/multivar/multivar_optimization.jl`
- `scripts/research/multivar/multivar_amp_on_phase_ablation.jl`
- `scripts/research/multivar/multivar_variable_ablation.jl`
- `scripts/workflows/refine_amp_on_phase.jl`
- `results/raman/multivar/smf28_L2m_P030W/`
- selected amplitude-on-phase, energy-on-phase, and warm-joint ablation results
  under `results/raman/multivar/`

## Verification

- Compiled `09-multi-parameter-optimization.pdf` on 2026-04-28.
- Rendered and visually inspected all 14 pages after compilation.
- Ran `scripts/dev/smoke/test_multivar_unit.jl`: passed.
- Ran `scripts/dev/smoke/test_multivar_gradients.jl`: passed, including phase, amplitude, energy, mixed-variable, Taylor, mode-coeff stripping, and save/load checks.
- Scanned source/PDF text for internal milestone labels and placeholders: clean.

## Writing rule

Keep the note presentation-ready but honest: amplitude-on-fixed-phase is the main positive result, broad joint optimization is a negative result, and lab handoff remains limited by amplitude calibration and convergence checks.
