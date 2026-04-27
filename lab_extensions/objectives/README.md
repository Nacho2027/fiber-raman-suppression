# Objective Extensions

This directory is for lab-owned objective/cost contracts that should be visible
to the configurable front layer without editing deep optimizer internals.

The current extension loader is metadata-only. It makes research objectives
discoverable in:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives
```

It does not make a new objective executable automatically. That is intentional:
a real objective needs units, normalization, gradient/adjoint behavior,
validation checks, output metrics, and artifact meaning.

## Scaffold

Create a planning-only objective contract plus Julia stub with:

```bash
julia -t auto --project=. scripts/canonical/scaffold_objective.jl my_objective \
  --description "What this objective measures and why."
```

The scaffold refuses to overwrite existing files unless `--force` is supplied.
After scaffolding, run:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-objectives
```

## Contract Shape

Create a TOML file in this directory:

```toml
kind = "my_objective"
regime = "single_mode"
backend = "lab_extension"
description = "What this objective measures and why."
maturity = "research"
execution = "planning_only"
source = "lab_extensions/objectives/my_objective.jl"
function = "my_objective_cost"
gradient = "my_objective_gradient"
validation = "Required checks before promotion."
supported_variables = [["phase"]]
allowed_regularizers = ["gdd", "boundary"]
```

Use `execution = "planning_only"` until the objective has tests and a real
backend path. Promotion to executable status should require:

- documented physical units and normalization
- explicit input arrays and assumptions
- gradient or derivative-free solver decision
- gradient/Taylor checks where applicable
- artifact metrics that make the result interpretable
- one config example and one regression test

## Why This Exists

Built-in objectives are safe defaults, not a research boundary. New fiber-optic
optimization ideas should be added here first as explicit lab-owned contracts,
then promoted into executable code once the science and verification are clear.
