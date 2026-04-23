# Candidate Standard Images

These are the familiar `save_standard_set(...)` bundles for the main masks discussed in the stability/universality work.

How to read each bundle:
- `_phase_profile.png`: the main 6-panel phase/spectrum sheet.
- `_evolution.png`: optimized spectral-evolution heatmap.
- `_phase_diagnostic.png`: wrapped, unwrapped, and group-delay views of the phase alone.
- `_evolution_unshaped.png`: unshaped comparison heatmap.

Short reading rule:
- Start with `_phase_profile.png`.
- Then compare `_evolution.png` against `_evolution_unshaped.png` to see whether the mask changed the Raman growth in a clean way.
- Use `_phase_diagnostic.png` only after that, to judge whether the phase looks smooth/simple or dense/fine-scale.

## `poly3_transferable`

Simple transferable polynomial baseline

- `poly3_transferable_phase_profile.png`
- `poly3_transferable_evolution.png`
- `poly3_transferable_phase_diagnostic.png`
- `poly3_transferable_evolution_unshaped.png`

## `cubic32_reduced`

Reduced-basis cubic N=32

- `cubic32_reduced_phase_profile.png`
- `cubic32_reduced_evolution.png`
- `cubic32_reduced_phase_diagnostic.png`
- `cubic32_reduced_evolution_unshaped.png`

## `cubic128_reduced`

Reduced-basis cubic N=128

- `cubic128_reduced_phase_profile.png`
- `cubic128_reduced_evolution.png`
- `cubic128_reduced_phase_diagnostic.png`
- `cubic128_reduced_evolution_unshaped.png`

## `cubic32_fullgrid`

Full-grid continuation from cubic32

- `cubic32_fullgrid_phase_profile.png`
- `cubic32_fullgrid_evolution.png`
- `cubic32_fullgrid_phase_diagnostic.png`
- `cubic32_fullgrid_evolution_unshaped.png`

## `zero_fullgrid`

Full-grid zero-start reference

- `zero_fullgrid_phase_profile.png`
- `zero_fullgrid_evolution.png`
- `zero_fullgrid_phase_diagnostic.png`
- `zero_fullgrid_evolution_unshaped.png`

## `simple_phase17`

Phase 17 simple baseline optimum

- `simple_phase17_phase_profile.png`
- `simple_phase17_evolution.png`
- `simple_phase17_phase_diagnostic.png`
- `simple_phase17_evolution_unshaped.png`

## `longfiber100m_phase16`

Phase 16 long-fiber 100 m optimum

- `longfiber100m_phase16_phase_profile.png`
- `longfiber100m_phase16_evolution.png`
- `longfiber100m_phase16_phase_diagnostic.png`
- `longfiber100m_phase16_evolution_unshaped.png`

Related summary heatmap:
- `../figures/robustness_heatmap.png`
