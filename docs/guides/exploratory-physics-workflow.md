# Exploratory Physics Workflow

[<- docs index](../README.md) | [configurable experiments](./configurable-experiments.md)

This guide explains the intended lab workflow for trying new fiber-optic
optimization ideas without turning the repo into a black box.

The short version:

```text
If the repo already knows the physics, edit a config and run.
If the repo does not know the physics yet, add a research draft, implement it,
test it, then promote it.
```

## What A Researcher Chooses

A normal experiment should answer five questions:

- What system is being simulated?
- What knobs are optimized?
- What score or cost function is optimized?
- What solver/settings are used?
- What outputs are needed to trust the result?

Those map to the config sections:

```toml
[problem]
regime = "single_mode"
preset = "SMF28"
L_fiber = 2.0
P_cont = 0.30

[controls]
variables = ["phase"]

[objective]
kind = "raman_band"

[solver]
kind = "lbfgs"
max_iter = 50

[artifacts]
bundle = "standard"
```

## Easy Mode

If the controls and objective are already implemented, the researcher can use
config only:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run my_config
julia -t auto --project=. scripts/canonical/run_experiment.jl my_config
```

The dry-run now reports:

- execution mode
- active controls
- optimizer-vector layout
- objective backend
- artifact hooks requested by the regime/objective/variables
- whether the artifact plan is already implemented

For deeper inspection:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --control-layout my_config
julia -t auto --project=. scripts/canonical/run_experiment.jl --artifact-plan my_config
```

## New Objective

Example: optimize pulse compression instead of Raman leakage.

First create a research draft:

```bash
julia -t auto --project=. scripts/canonical/scaffold_objective.jl pulse_compression \
  --description "Minimize output pulse duration after propagation."
```

That creates:

```text
lab_extensions/objectives/pulse_compression.toml
lab_extensions/objectives/pulse_compression.jl
```

This is not runnable yet. It is a visible contract that says what needs to be
implemented before the objective can run.

To promote it, define:

- physical metric and units
- normalization
- cost function implementation
- gradient strategy or solver limitation
- compatible variables
- required metrics and plots
- regression tests
- one smoke config

Only after that should a config use:

```toml
[objective]
kind = "pulse_compression"
```

## New Variable

Example: optimize launch angle or modal weights.

First create a research draft:

```bash
julia -t auto --project=. scripts/canonical/scaffold_variable.jl mode_weights \
  --description "Optimize multimode launch weights." \
  --units "normalized modal power fractions" \
  --bounds "nonnegative and sum to one"
```

That creates:

```text
lab_extensions/variables/mode_weights.toml
lab_extensions/variables/mode_weights.jl
```

To promote it, define:

- units
- bounds/projection behavior
- optimizer-vector shape
- pack/unpack behavior
- how the simulator consumes the control
- compatible objectives
- variable-specific plots and metrics
- tests

This is the purpose of `ControlLayout`: make the optimized vector inspectable
instead of hidden inside optimizer internals.

## How Graphs Are Chosen

The engine should not guess plots from nowhere.

Each source requests artifact hooks:

- Regime requests physics/trust outputs.
- Objective requests success-metric outputs.
- Variable requests control-specific outputs.

Example: Raman plus phase.

```text
Regime hooks:
- standard_image_set
- trust_report

Objective hooks:
- spectrum_before_after
- raman_band_overlay
- convergence_trace

Variable hooks:
- phase_profile
- group_delay
```

The engine combines those into one artifact plan. If a hook is already
implemented, runs can produce it automatically. If a hook is planned only, the
dry-run shows that the workflow is not fully promoted yet.

## How Plot Zoom Defaults Work

Every artifact hook should define:

- default view rule
- expected filename
- config override key
- whether it is implemented

Examples:

- Phase plots default to meaningful spectral support and show wrapped,
  unwrapped, and group-delay views.
- Raman plots mark the Raman band and use normalized spectra.
- Temporal pulse plots should center around the pulse peak and include the
  high-energy region plus margin.
- Mode plots should show all modes for small mode counts, otherwise top/worst
  modes plus aggregate tables.

Future configs may override plot views:

```toml
[plots.spectrum]
dynamic_range_dB = 60
mark_bands = ["raman"]

[plots.temporal_pulse]
time_range_ps = [-2.0, 2.0]
normalize = true

[plots.modes]
modes = [1, 2, 5]
```

The default rule is:

```text
Automatic plots must be good enough for first inspection.
Config overrides are for unusual regimes and publication-quality tuning.
```

## What The System Cannot Do

It cannot safely run a new objective or variable just because someone writes a
new name in TOML.

This is invalid until implemented:

```toml
[controls]
variables = ["launch_angle"]

[objective]
kind = "magic_new_cost"
```

The repo must first be taught what `launch_angle` and `magic_new_cost` mean.
That is the difference between useful configurability and unsafe abstraction
theater.

## Professor-Friendly Mental Model

The repo should behave like a configurable scientific instrument:

```text
Choose system.
Choose knobs.
Choose score.
Choose solver.
Inspect plan.
Run.
Inspect standardized evidence.
```

New science is allowed, but it enters through explicit contracts so future lab
members can understand and trust what was run.
