# Configurable Experiments

[<- docs index](../README.md) · [project README](../../README.md)

This guide is the lab-user entry point for the configurable front layer. It is
for changing common research choices without editing optimizer internals.

Use this path when you want to change:

- fiber preset
- fiber length or input power
- grid size or time window
- optimized variables
- objective/cost variant
- regularizer weights
- solver iteration budget
- artifact or neutral handoff output

The front layer is intentionally thin. Config files select from approved
contracts; Julia code still owns the physics, gradients, objective formulas,
solver behavior, and artifact validation.

## 1. List Available Experiments

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
```

Start with these configs:

- `research_engine_poc`: supported single-mode phase-only baseline.
- `research_engine_smoke`: tiny supported smoke run for CLI/artifact checks.
- `research_engine_export_smoke`: tiny supported smoke run with neutral CSV
  handoff export enabled.
- `research_engine_peak_smoke`: experimental phase-only run for objective
  dispatch checks.
- `smf28_phase_amplitude_energy_poc`: experimental multivariable run.

## 2. Inspect Objective Contracts

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives
```

Current single-mode objectives:

- `raman_band`: supported integrated Raman-band leakage objective.
- `raman_peak`: experimental peak-bin Raman leakage objective.

Do not add new objective names only by editing TOML. Add the objective formula
and gradient in code, register the contract, then expose it to config.

## 3. Dry-Run Before Compute

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_poc
```

The dry-run should answer:

- which config is being run
- whether it is `supported` or `experimental`
- which regime and preset are active
- which variables are optimized
- which objective backend will run
- whether export is requested and supported
- which artifact and verification policies are active

If validation fails here, fix the config before launching compute.

## 4. Edit Safe Knobs

Make a copy of a nearby config in `configs/experiments/`, then edit only the
knobs that are part of the current support boundary.

Safe first knobs:

- `problem.preset`
- `problem.L_fiber`
- `problem.P_cont`
- `problem.Nt`
- `problem.time_window`
- `controls.variables`
- `objective.kind`
- `objective.regularizer` weights
- `solver.max_iter`
- `solver.validate_gradient`
- `artifacts.export_phase_handoff`
- `export.enabled`

Keep these constraints in mind:

- `single_mode` plus `["phase"]` is the supported path.
- Multivariable controls are experimental.
- `raman_peak` is experimental and phase-only.
- Export handoff is phase-only.
- Neutral handoff is not a vendor-specific SLM loading file.

## 5. Run

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
```

For quick mechanical checks, use a smoke config:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_smoke
```

For neutral handoff checks:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_export_smoke
```

The command prints a completion summary with:

- output directory
- result artifact path
- artifact-validation status
- standard-image status
- export-handoff status when export was requested

## 6. Inspect The Saved Run

Use the output directory printed by the run command:

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
```

Inspection reports:

- run artifact and artifact directory
- fiber, length, power, grid, and objective summary
- convergence and iteration count
- copied `run_config.toml`
- trust report path
- standard image completeness
- neutral handoff completeness when present

The inspection command is a checklist aid, not a substitute for reading the
trust report or visually checking the standard images.

## 7. Check Outputs

A complete supported phase-only run should contain:

- `opt_result.jld2`
- `opt_result.json`
- `run_config.toml`
- `opt_trust.md`
- `opt_phase_profile.png`
- `opt_evolution.png`
- `opt_phase_diagnostic.png`
- `opt_evolution_unshaped.png`

If neutral handoff export was enabled, it should also contain:

- `export_handoff/phase_profile.csv`
- `export_handoff/metadata.json`
- `export_handoff/README.md`
- `export_handoff/source_run_config.toml`

The neutral CSV handoff contains the simulation-axis wavelength/frequency grid,
wrapped phase, unwrapped phase, and group delay. It is meant for lab conversion
scripts and discussion, not direct loading into an arbitrary SLM.

## 8. Lab-Ready Gate

Before using a run as a lab reference:

- `inspect_run.jl` reports the standard image set complete.
- The trust report passes the relevant checks.
- The four standard images have been visually inspected.
- The config copy matches the intended experiment.
- Any neutral handoff bundle is complete and generated from the intended run.
- For a real baseline, the optimizer status and final objective are scientifically
  acceptable, not just mechanically present.

## Rule Of Thumb

Use config for common scientific choices. Use code for new scientific
definitions. That keeps the system configurable without hiding the physics.
