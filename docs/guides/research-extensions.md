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
```

An extension TOML declares the scientific contract:

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

The current loader makes this visible and inspectable. It does not make it
executable automatically.

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

## What This Means For Researchers

A researcher should not need to edit deep internals for every new idea. They
should be able to:

- declare a new research objective contract in `lab_extensions/objectives/`
- see it in `--objectives`
- document what validation is still missing
- implement the objective in a lab-owned file
- promote it only after tests and output checks exist

That keeps the system open-ended without making it mysterious or unsafe.
