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

For new research objectives or optimized variables rather than safe built-ins, see
[research-extensions.md](./research-extensions.md).

Use `./fiberlab` for normal lab operation. It is a checkout-local Python CLI
that calls the maintained Julia scripts underneath, so it avoids forcing users
to remember `julia -t auto --project=...` while preserving the same backend.

## 1. List Available Experiments

```bash
./fiberlab configs
```

Start with these configs:

- `research_engine_poc`: supported single-mode phase-only baseline.
- `research_engine_smoke`: tiny supported smoke run for CLI/artifact checks.
- `research_engine_export_smoke`: tiny supported smoke run with neutral CSV
  handoff export enabled.
- `research_engine_peak_smoke`: experimental phase-only run for objective
  dispatch checks.
- `research_engine_gain_tilt_smoke`: experimental phase plus one-parameter
  gain-tilt smoke run for non-standard variable dispatch and artifacts.
- `research_engine_gain_tilt_scalar_search_smoke`: experimental
  derivative-free bounded scalar search over gain tilt only. This is the first
  low-dimensional playground backend: useful for scalar controls where a full
  adjoint-gradient path would be unnecessary or premature.
- `grin50_mmf_phase_sum_poc`: experimental GRIN-50 multimode planning surface;
  dry-run/validation only on local machines.
- `smf28_longfiber_phase_poc`: experimental long-fiber planning surface;
  dry-run/validation only on local machines.
- `smf28_phase_amplitude_energy_poc`: experimental multivariable run.

To see the whole front-layer support boundary in one command:

```bash
./fiberlab capabilities
```

Every plan also reports a promotion stage:

- `planning`: config validates and can produce a compute plan, but the front
  layer intentionally blocks execution.
- `smoke`: the path is executable for a small local run and has artifact checks,
  but it is still experimental science.
- `validated`: reserved for a promoted research surface after representative
  real-size checks pass on appropriate compute.
- `lab_ready`: supported path with local gates, artifacts, docs, and handoff
  expectations strong enough for another lab user to run.

Use the `Promotion blockers` line in `./fiberlab plan <id>` or
`./fiberlab compute-plan <id>` as the authoritative explanation of why a config
is not yet lab-ready. For example, MMF and long-fiber currently report planning
status because they require dedicated heavy workflows and some regime-specific
artifact hooks are still planned.

For intentional playground work, use `explore`:

```bash
./fiberlab explore list
./fiberlab explore plan research_engine_gain_tilt_smoke
./fiberlab check config research_engine_gain_tilt_smoke
./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke
./fiberlab explore plan grin50_mmf_phase_sum_poc
./fiberlab explore run grin50_mmf_phase_sum_poc --heavy-ok --dry-run
./fiberlab explore compare results/raman --top 10
```

`run` is conservative. `explore` is explicit research mode: it prints warnings,
promotion stage, blockers, and compute guidance before any risky path. Local
experimental runs require `--local-smoke`; heavy/dedicated workflows require
`--heavy-ok`. `explore compare` uses the shared result index so exploratory
runs can be ranked, filtered, and inspected from CLI or notebook workflows.

Use `check config` when you are unsure where a config sits. It does not launch
optimization. It reports the run path, whether the artifact plan is implemented,
whether outputs will be comparison-ready, and the concrete missing pieces.

New front-layer runs save `run_manifest.json` beside the result files. This is
the per-run provenance record for CLI and notebook users: command, config hash,
regime, variables, objective, run context, artifact status, key metrics, and
git state. It is intentionally metadata only; it does not hide or replace the
physics outputs. `explore compare` reads the manifest when available and
surfaces `Run Context`, `Compare Ready`, and `Manifest Missing` columns so a
researcher can tell which runs were exploratory smokes, ordinary supported runs,
or incomplete handoffs without opening every folder.

Executable exploratory configs also get two generic fallback artifacts:
`{tag}_explore_summary.json` and `{tag}_explore_overview.png`. The overview is a
first-inspection plot with input/shaped spectra, a zoomed temporal pulse,
objective trace when stored, and a compact control summary. This is the safety
net for novel objectives or variables; specialized diagnostics should still be
added as explicit artifact hooks when the physics demands them.

Exploratory overview plots expose a small config surface for first-inspection
views. These settings change only the generated overview artifact, not the
simulation or objective:

```toml
[plots.temporal_pulse]
time_range = [-0.75, 0.75]
normalize = true

[plots.spectrum]
dynamic_range_dB = 55.0
```

Leave these unset for automatic energy-window zoom and a 70 dB spectral view.
Use them when a pulse is too wide/narrow for the default view or when a meeting
plot needs a tighter dynamic range without editing Julia plotting code.

To inspect how the optimizer vector and output plots will be assembled:

```bash
./fiberlab layout research_engine_poc
./fiberlab artifacts research_engine_poc
```

To check every approved experiment config without launching optimization:

```bash
./fiberlab validate
./fiberlab ready config research_engine_poc
```

Before handoff, run the simulation-free research-engine acceptance
harness:

```bash
make acceptance
```

This checks the front-layer UX as one instrument: config validation, dry-run
surfaces, control/artifact plans, a synthetic completed phase/export run,
artifact validation, result indexing, lab-ready gates, Python wrappers, and
black-box gating for experimental MMF, multivariable, and long-fiber surfaces.
It does not replace a real smoke run or visual inspection of generated plots.

For parameter-space questions, use the front-layer sweep command. It expands a
base experiment across a list of values, validates every generated case, and
prints the plan without launching optimization:

```bash
./fiberlab sweep list
./fiberlab sweep plan smf28_power_micro_sweep
./fiberlab sweep validate
./fiberlab sweep latest smf28_power_micro_sweep
```

## 2. Inspect Objective Contracts

```bash
./fiberlab objectives
./fiberlab objectives --validate
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

Use `--validate-objectives` before trying to promote a new objective. It reports
whether extension metadata is valid and which blockers still prevent execution,
such as planning-only status, unpromoted backend, research maturity, or missing
validation work.

## 3. Inspect Variable Contracts

```bash
./fiberlab variables
./fiberlab variables --validate
```

Current executable variable support is intentionally narrow:

- `phase`: supported single-mode spectral phase control.
- `amplitude`: experimental single-mode multivariable control.
- `energy`: experimental single-mode multivariable control.
- `gain_tilt`: experimental one-parameter bounded spectral transmission slope
  either coupled to phase through the multivariable path or optimized alone
  through `solver.kind = "bounded_scalar"`; smoke-tested, not lab-promoted
  science.
- `phase` for `long_fiber` and `multimode`: planning/dry-run surfaces until
  those regimes are promoted.

Research variable contracts under `lab_extensions/variables/` are visible
planning contracts. They document proposed controls, units, bounds/projection
behavior, compatible objectives, parameterizations, and artifact semantics.
They are not executable until promoted with implementation and tests.

## 4. Dry-Run Before Compute

```bash
./fiberlab plan research_engine_poc
```

The dry-run should answer:

- which config is being run
- whether it is `supported` or `experimental`
- which regime and preset are active
- which variables are optimized
- which objective backend will run
- whether export is requested and supported
- which artifact and verification policies are active

For low-dimensional derivative-free exploration, the current executable smoke
shape is:

```toml
[controls]
variables = ["gain_tilt"]

[solver]
kind = "bounded_scalar"
scalar_lower = -0.09
scalar_upper = 0.09
scalar_x_tol = 1.0e-3
```

This backend is deliberately narrow. It is for scalar controls such as the
current gain-tilt smoke, not for full-grid phase or amplitude controls.

If validation fails here, fix the config before launching compute.

For heavier configs, print a provider-neutral compute plan:

```bash
./fiberlab compute-plan smf28_longfiber_phase_poc
```

This does not launch anything. It explains the portable path first: use any
sufficiently provisioned workstation, cluster node, or cloud VM, sync/clone the
repo, instantiate Julia, dry-run the config there, then run the relevant
workflow. Rivera Lab burst helper commands are shown only as optional examples
for people who already have that environment configured.

## 5. Edit Safe Knobs

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

## 6. Run

```bash
./fiberlab run research_engine_poc
```

For quick mechanical checks, use a smoke config:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_smoke
```

For neutral handoff checks:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_export_smoke
```

For the complete mechanical acceptance procedure, including the strict
`--require-export` gate, run `make golden-smoke` or see
[golden-smoke-run.md](./golden-smoke-run.md).

For long-fiber playground planning:

```bash
./fiberlab explore plan smf28_longfiber_phase_poc
./fiberlab explore run smf28_longfiber_phase_poc --heavy-ok --dry-run
```

For multimode playground planning:

```bash
./fiberlab explore plan grin50_mmf_phase_sum_poc
./fiberlab explore run grin50_mmf_phase_sum_poc --heavy-ok --dry-run
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
- variable-artifact status when the selected controls request extra outputs
- export-handoff status when export was requested

## 7. Inspect The Saved Run

Use the output directory printed by the run command:

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
```

Or inspect the latest completed run for a config:

```bash
./fiberlab latest research_engine_poc
./fiberlab ready latest research_engine_poc
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
artifact/error path. Executed sweeps also write `SWEEP_SUMMARY.json` and
`SWEEP_SUMMARY.csv` next to the Markdown summary; comparison tooling prefers
the JSON sidecar when it is present and falls back to Markdown for older sweeps.

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
run config path, headline metrics, standard-image completeness, and
variable-artifact completeness. For multivariable runs, this lets a lab user
see whether the amplitude mask, energy metrics, and pulse metrics promised by
the artifact plan are present without opening the folder manually. Use it as a
meeting/re-entry map, then inspect the underlying run folder before making
scientific claims. CSV output is intended for notebook, pandas, spreadsheet,
and meeting-table workflows. `--compare` ranks runs by mechanical lab readiness
and then objective value; it is a triage view, not a scientific acceptance
decision. `--compare-sweeps` summarizes completed sweep summaries by cases,
failure count, best case, best achieved objective, and median achieved
objective, using `SWEEP_SUMMARY.json` when available.

The inspection command is a checklist aid, not a substitute for reading the
trust report or visually checking the standard images.

For a strict pass/fail mechanical gate on a specific run directory or artifact,
use:

```bash
julia -t auto --project=. scripts/canonical/lab_ready.jl --run results/raman/<run_id>/
julia -t auto --project=. scripts/canonical/lab_ready.jl --run results/raman/<run_id>/ --require-export
```

The gate checks the result artifact, JSON sidecar, copied config, trust report,
standard image set, variable-specific artifacts requested by the artifact plan,
generic exploratory artifacts requested by the artifact plan, convergence flag,
and objective metric. Trust reports are required only for run modes whose
artifact plan includes a trust-report hook; experimental phase/amplitude/energy
runs instead require their amplitude, energy, pulse metric, and exploratory
fallback artifacts. With `--require-export`, it also requires a complete
`export_handoff/` bundle.

## 8. Check Outputs

A complete supported phase-only run should contain:

- `opt_result.jld2`
- `opt_result.json`
- `run_config.toml`
- `opt_trust.md`
- `opt_phase_profile.png`
- `opt_evolution.png`
- `opt_phase_diagnostic.png`
- `opt_evolution_unshaped.png`

A complete experimental phase/amplitude/energy run should also contain the
variable-specific artifacts requested by its artifact plan:

- `opt_amplitude_mask.png`
- `opt_energy_metrics.json`
- `opt_pulse_metrics.json`

These files are now part of front-layer artifact validation. If one is missing,
the run is mechanically incomplete even if the main JLD2 result exists.

If neutral handoff export was enabled, it should also contain:

- `export_handoff/phase_profile.csv`
- `export_handoff/metadata.json`
- `export_handoff/README.md`
- `export_handoff/source_run_config.toml`

The neutral CSV handoff contains the simulation-axis wavelength/frequency grid,
wrapped phase, unwrapped phase, and group delay. It is meant for lab conversion
scripts and discussion, not direct loading into an arbitrary SLM.

## 9. Lab-Ready Gate

Before using a run as a lab reference:

- `lab_ready.jl --config <id>` passes for the intended config.
- `lab_ready.jl --run <dir>` passes for the completed run.
- `inspect_run.jl` reports the standard image set complete.
- The trust report passes the relevant checks.
- The four standard images have been visually inspected.
- Any variable-specific artifacts requested by the artifact plan are complete.
- The config copy matches the intended experiment.
- Any neutral handoff bundle is complete and generated from the intended run.
- For a real baseline, the optimizer status and final objective are scientifically
  acceptable, not just mechanically present.

## Rule Of Thumb

Use config for common scientific choices. Use code for new scientific
definitions. That keeps the system configurable without hiding the physics.
