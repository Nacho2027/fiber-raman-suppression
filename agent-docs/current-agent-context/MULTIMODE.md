# Multimode Context

MMF phase optimization is a promoted experimental capability. Old baseline,
window-validation, and analysis drivers were archived with the other retired
research drivers.

Current API surface:

- `scripts/lib/mmf_fiber_presets.jl`
- `scripts/lib/mmf_setup.jl`
- `scripts/lib/mmf_raman_optimization.jl`
- Front-layer MMF experiment configs.

Verdict:

- Shared phase optimization across modes is retained.
- Mode-coefficient and aggressive recovery scripts are not in the main
  pipeline.
- High-resource MMF configs should run only on appropriate compute.

See `docs/research-verdicts.md` for the human-facing lane summary.
