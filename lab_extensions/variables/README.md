# Variable Extensions

This directory is for lab-owned optimization variable/control contracts that
should be visible to the configurable front layer before they are executable.

Built-in variables such as spectral phase are safe defaults, not the research
boundary. Future fiber-optic controls should start here when their physics,
units, bounds, artifact meaning, or output handoff are not yet ready for
validated execution.

## Scaffold

Create a planning-only variable contract plus Julia stub with:

```bash
julia -t auto --project=. scripts/canonical/scaffold_variable.jl my_variable \
  --description "What this control changes and why." \
  --units "physical units or normalization" \
  --bounds "bounds or projection behavior"
```

Then inspect and validate:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --variables
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-variables
```

The scaffold refuses to overwrite existing files unless `--force` is supplied.

## Contract Shape

```toml
kind = "my_variable"
regime = "single_mode"
backend = "lab_extension"
description = "What this control changes and why."
maturity = "research"
execution = "planning_only"
source = "lab_extensions/variables/my_variable.jl"
build_function = "build_my_variable_control"
projection_function = "project_my_variable_control"
units = "physical units or normalization"
bounds = "bounds or projection behavior"
parameterizations = ["full_grid"]
compatible_objectives = ["raman_band"]
artifact_semantics = "What outputs, plots, or handoff files mean for this control."
validation = "Required checks before promotion."
```

Use `execution = "planning_only"` until the control has:

- documented physical units and normalization
- explicit bounds/projection behavior
- objective compatibility and gradient behavior
- artifact metrics that make the result interpretable
- one config example and one regression test

## Current Examples

- `gain_tilt_planning`: single-mode smooth spectral gain/attenuation tilt. This is
  a non-standard control example for future pulse-shaping, gain-shaping, or
  hardware-transfer research. It is metadata-valid but planning-only.
- `mode_weights_planning`: multimode modal-weight control. This remains
  planning-only while MMF promotion work is still separate.

If a config references either extension today, the front layer should recognize
the extension and reject execution with explicit promotion blockers rather than
silently treating it as an unknown control.
