# Configurable Experiments

[<- docs index](../README.md) · [project README](../../README.md)

This guide is the lab-user entry point for the configurable front layer. It is
for changing common fiber-optic optimization choices without editing optimizer
internals.

Raman suppression is the first implemented research family in this interface,
not the intended ceiling. The same front-layer contracts should eventually
support other fiber-optic optimization questions once their objectives,
variables, validation checks, and outputs are implemented in code.

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

For new research objectives rather than safe built-ins, see
[research-extensions.md](./research-extensions.md).

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
- `grin50_mmf_phase_sum_poc`: experimental GRIN-50 multimode planning surface;
  dry-run/validation only on local machines.
- `smf28_longfiber_phase_poc`: experimental long-fiber planning surface;
  dry-run/validation only on local machines.
- `smf28_phase_amplitude_energy_poc`: experimental multivariable run.

To see the whole front-layer support boundary in one command:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --capabilities
```

To check every approved experiment config without launching optimization:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-all
```

For parameter-space questions, use the front-layer sweep command. It expands a
base experiment across a list of values, validates every generated case, and
prints the plan without launching optimization:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --list
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --dry-run smf28_power_micro_sweep
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --latest smf28_power_micro_sweep
```

## 2. Inspect Objective Contracts

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives
```

Current single-mode objectives are Raman-focused because that is the first
implemented objective family:

- `raman_band`: supported integrated Raman-band leakage objective.
- `raman_peak`: experimental peak-bin Raman leakage objective.

Current long-fiber objectives:

- `raman_band`: experimental phase-only planning contract.

Current multimode objectives:

- `mmf_sum`: experimental mode-summed Raman leakage planning contract.
- `mmf_fundamental`: experimental fundamental-mode diagnostic contract.
- `mmf_worst_mode`: experimental worst-mode diagnostic contract.

Do not add new objective names only by editing TOML. Add the objective formula
and gradient in code, register the contract, then expose it to config. That is
the intended path for non-Raman fiber-optic objectives too.

Research extension contracts under `lab_extensions/objectives/` are listed by
the same command. They are visible planning contracts, not automatically
executable objectives.

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

For heavier configs, print a provider-neutral compute plan:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --compute-plan smf28_longfiber_phase_poc
```

This does not launch anything. It explains the portable path first: use any
sufficiently provisioned workstation, cluster node, or cloud VM, sync/clone the
repo, instantiate Julia, dry-run the config there, then run the relevant
workflow. Rivera Lab burst helper commands are shown only as optional examples
for people who already have that environment configured.

## 4. Edit Safe Knobs

Make a copy of a nearby config in `configs/experiments/`, then edit only the
knobs that are part of the current support boundary.

For a clean starting point, copy a template from
`configs/experiments/templates/`:

- `single_mode_phase_template.toml`: supported local phase-only optimization.
- `multimode_phase_planning_template.toml`: experimental MMF dry-run and
  compute-plan surface.

Templates are not approved runnable configs while they remain under the
`templates/` subdirectory. Copy one level up, give it a real `id` and
`output_tag`, then run `--dry-run` and `--validate-all`.

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

Safe first sweep parameters:

- `problem.L_fiber`
- `problem.P_cont`
- `problem.Nt`
- `problem.time_window`
- `solver.max_iter`
- `objective.kind`

Keep these constraints in mind:

- `single_mode` plus `["phase"]` is the supported path.
- Multivariable controls are experimental.
- `long_fiber` configs are experimental and marked `burst_required`.
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

For long-fiber planning, dry-run only on local machines:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run smf28_longfiber_phase_poc
```

For multimode planning, dry-run only on local machines:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run grin50_mmf_phase_sum_poc
```

Long-fiber execution remains burst territory and should use the dedicated
long-fiber workflow until the front layer has a generic execution contract.
Multimode execution follows the same rule for now and should use the dedicated
MMF baseline workflow. The repo does not require Google Cloud; use whatever
local, cluster, or cloud machine satisfies the run's memory/time needs.

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

Or inspect the latest completed run for a config:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --latest research_engine_poc
```

Inspection reports:

- run artifact and artifact directory
- fiber, length, power, grid, and objective summary
- convergence and iteration count
- copied `run_config.toml`
- trust report path
- standard image completeness
- neutral handoff completeness when present

For front-layer sweeps, inspect the latest completed sweep summary:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --latest smf28_power_micro_sweep
```

The sweep summary reports each case's execution status, artifact status,
trust-report status, standard-image status, headline objective metrics, and
artifact/error path.

To scan completed runs and sweep summaries without manually opening timestamped
folders:

```bash
julia -t auto --project=. scripts/canonical/index_results.jl
julia -t auto --project=. scripts/canonical/index_results.jl results/raman/sweeps/front_layer
julia -t auto --project=. scripts/canonical/index_results.jl --kind run --regime single_mode --objective raman_band --fiber SMF-28 --complete-images results/raman
julia -t auto --project=. scripts/canonical/index_results.jl --csv --kind run --config-id smf28_phase_smoke --contains power results/raman/sweeps/front_layer
julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 5 --lab-ready results/raman
julia -t auto --project=. scripts/canonical/index_results.jl --compare-sweeps --top 5 results/raman/sweeps/front_layer
```

The index is read-only. It reports discovered run artifacts and sweep summaries
with metadata from `run_config.toml` and `opt_result.json` when available:
config id, regime, objective, variables, solver, timestamp, trust report path,
run config path, headline metrics, and standard-image completeness. Use it as
a meeting/re-entry map, then inspect the underlying run folder before making
scientific claims. CSV output is intended for notebook, pandas, spreadsheet,
and meeting-table workflows. `--compare` ranks runs by mechanical lab readiness
and then objective value; it is a triage view, not a scientific acceptance
decision. `--compare-sweeps` summarizes completed sweep summaries by cases,
failure count, best case, best achieved objective, and median achieved
objective.

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
