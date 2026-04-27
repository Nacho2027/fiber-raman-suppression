# Research Extensions

[<- docs index](../README.md) | [configurable experiments](./configurable-experiments.md)

This guide explains how the configurable front layer should support new
fiber-optic optimization research without turning science into a fixed menu.

Raman suppression is the first implemented objective family. It is not the
intended boundary of the system.

## UX Principle

Use three layers:

- Safe defaults: built-in, tested configs and objectives that a new lab user can
  run without understanding internals.
- Composable research configs: TOML files and sweeps that change parameters,
  variables, objectives, solver settings, artifacts, and compute plans.
- Research extensions: lab-owned objective, variable, diagnostic, or artifact
  contracts that make new science discoverable before it is promoted to
  executable status.

This avoids two bad outcomes:

- A closed menu that only supports the original author's research questions.
- Free-form config strings that silently run unverified physics.

## Objective Extensions

Lab-owned objective contracts live under:

```text
lab_extensions/objectives/
```

List built-in objectives and research extension contracts with:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-objectives
```

Start a new planning-only objective with:

```bash
julia -t auto --project=. scripts/canonical/scaffold_objective.jl my_objective \
  --description "What this objective measures and why."
```

The scaffold writes `lab_extensions/objectives/my_objective.toml` and
`lab_extensions/objectives/my_objective.jl`, then tells you to run
`--objectives` and `--validate-objectives`. It refuses to overwrite existing
files unless you pass `--force`.

The generated TOML declares the scientific contract:

```toml
kind = "pulse_compression_demo"
regime = "single_mode"
backend = "lab_extension"
description = "Demo non-Raman objective contract for pulse-compression research extension planning."
maturity = "research"
execution = "planning_only"
source = "lab_extensions/objectives/pulse_compression_demo.jl"
function = "pulse_compression_cost"
gradient = "pulse_compression_gradient"
validation = "Requires units, gradient check, artifact metrics, and a promoted backend before execution."
supported_variables = [["phase"]]
allowed_regularizers = ["gdd", "boundary"]
```

The current loader makes this visible and inspectable. The validation command
checks required metadata, source file presence, and declared cost/gradient
function names. It also reports promotion blockers such as `planning_only`
execution, unpromoted `lab_extension` backend, research maturity, and unmet
validation requirements.

This does not make the objective executable automatically. That is intentional:
passing metadata validation means the objective is findable and documented, not
that its physics, gradients, artifacts, or acceptance checks are complete.

## Promotion Checklist

Before a research objective becomes runnable from config, define:

- Physical quantity being optimized.
- Units and normalization.
- Input arrays and assumptions.
- Whether gradients are analytic, adjoint-based, automatic, finite-difference,
  or unavailable.
- Gradient/Taylor checks where applicable.
- Supported variables and parameterizations.
- Failure modes and validity range.
- Output metrics and plots needed to interpret results.
- One small smoke config.
- One regression test.

The promotion report should show `Promotable: 0` until those items have been
implemented and reviewed. That is a safety feature, not a limitation of future
research.

## Variable Extensions

New optimized variables/controls use the same rule: make the control visible
and inspectable first, then promote it only after the science and artifacts are
clear.

List built-in variables and planning-only variable contracts with:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --variables
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-variables
```

Start a new planning-only variable contract with:

```bash
julia -t auto --project=. scripts/canonical/scaffold_variable.jl my_variable \
  --description "What this control changes and why." \
  --units "physical units or normalization" \
  --bounds "bounds or projection behavior"
```

Variable contracts live under `lab_extensions/variables/`. They should define
units, bounds/projection behavior, compatible objectives, parameterizations, and
artifact semantics. A variable should not become executable just because it has
a name in TOML; it needs implementation, tests, and output meaning first.

## What This Means For Researchers

A researcher should not need to edit deep internals for every new idea. They
should be able to:

- declare a new research objective contract in `lab_extensions/objectives/`
- declare a new research variable contract in `lab_extensions/variables/`
- see it in `--objectives`
- see it in `--variables`
- document what validation is still missing
- run `--validate-objectives` or `--validate-variables` to see the promotion
  checklist
- implement the objective or variable in a lab-owned file
- promote it only after tests and output checks exist

That keeps the system open-ended without making it mysterious or unsafe.
