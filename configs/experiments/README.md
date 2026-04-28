# Experiment Configs

This directory is the thin researcher-facing front layer. The goal is to make
common fiber-optic optimization choices explicit in TOML, while keeping the
physics and optimizer implementations in Julia code.

The current approved configs are Raman-suppression oriented because that is the
first implemented research family. The interface is meant to grow beyond Raman
once new objective, variable, validation, and artifact contracts are added in
code.

For the full lab-user workflow, see
[`docs/guides/configurable-experiments.md`](../../docs/guides/configurable-experiments.md).

## Inspect Before Running

List available experiment configs:

```bash
./fiberlab configs
./fiberlab explore list
```

Dry-run a config without launching optimization:

```bash
./fiberlab plan research_engine_poc
```

The dry-run output shows the resolved execution mode and whether export is
currently supported for that mode. It also shows the promotion stage and
promotion blockers. Treat those lines as the lab-facing status contract:

- `planning`: inspectable config and compute plan only.
- `smoke`: executable small-run path with artifact checks, still experimental.
- `validated`: representative real-size checks completed on appropriate compute.
- `lab_ready`: ready for another lab user to run and verify from docs/config.

List objective/cost contracts available to configs:

```bash
./fiberlab objectives
```

This lists both built-in executable objective contracts and research extension
contracts from `lab_extensions/objectives/`. Extension contracts are
discoverable planning surfaces until promoted with tests and a real backend.

Validate research objective extension contracts:

```bash
./fiberlab objectives --validate
```

Start a new planning-only objective contract without editing deep internals:

```bash
./fiberlab scaffold objective my_objective \
  --description "What this objective measures, including units and normalization."
```

The scaffold creates a TOML contract and Julia stub under
`lab_extensions/objectives/`. It makes the idea visible to `--objectives` and
`--validate-objectives`, but it does not make the objective executable until the
physics, gradient strategy, artifact metrics, and tests have been promoted.

List the regime/variable/objective/artifact capabilities in one place:

```bash
./fiberlab capabilities
```

List optimized variable/control contracts available to configs:

```bash
./fiberlab variables
./fiberlab variables --validate
```

Create a planning-only variable/control contract without making it executable:

```bash
./fiberlab scaffold variable my_variable \
  --description "What this control changes and why." \
  --units "physical units or normalization" \
  --bounds "bounds or projection behavior"
```

Validate every approved experiment config without launching compute:

```bash
./fiberlab validate
```

Run a validated config:

```bash
./fiberlab run research_engine_poc
```

Run an experimental playground config intentionally:

```bash
./fiberlab explore plan research_engine_gain_tilt_smoke
./fiberlab check config research_engine_gain_tilt_smoke
./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke
./fiberlab explore compare results/raman/smoke --top 10
```

`check config` is the no-compute completeness check. It reports the correct run
path, artifact coverage, comparison metadata readiness, and missing pieces
before anyone launches optimization.

New front-layer runs write `run_manifest.json` in the output directory. This is
the durable per-run provenance record for later comparison and notebook work:
command, config hash, variables, objective, run context, artifact completion,
metrics, and git state.

Executable exploratory configs also write generic fallback artifacts:
`{tag}_explore_summary.json` and `{tag}_explore_overview.png`. These give novel
objectives or variables a baseline spectrum, temporal pulse, objective trace,
and control summary before custom diagnostics exist.

Optional first-inspection plot overrides are allowed in executable exploratory
configs:

```toml
[plots.temporal_pulse]
time_range = [-0.75, 0.75]
normalize = true

[plots.spectrum]
dynamic_range_dB = 55.0
```

These affect only `{tag}_explore_overview.png` and the metadata recorded in
`{tag}_explore_summary.json`; they do not change the physics calculation.

Inspect heavy/dedicated playground workflows without launching them:

```bash
./fiberlab explore plan grin50_mmf_phase_sum_poc
./fiberlab explore run grin50_mmf_phase_sum_poc --heavy-ok --dry-run
```

Inspect the latest completed run for a config:

```bash
./fiberlab latest research_engine_poc
```

Print provider-neutral compute guidance without launching anything:

```bash
./fiberlab compute-plan smf28_longfiber_phase_poc
```

After a run, the front layer validates the basic artifact contract before
returning control: copied config, JLD2 payload, JSON sidecar, standard image
set, exploratory fallback artifacts when requested, variable-specific artifacts
when requested, and the phase-only trust report when required.

The CLI completion summary prints the output directory, result artifact,
artifact-validation status, and standard-image status so the next inspection
step is obvious.

## Safe Starting Surfaces

- `research_engine_poc.toml` is the supported single-mode phase-only surface.
- `research_engine_smoke.toml` is the tiny phase-only smoke surface for
  CLI/artifact verification.
- `research_engine_export_smoke.toml` is the tiny phase-only smoke surface for
  validating the neutral CSV experimental handoff bundle.
- `research_engine_peak_smoke.toml` is the tiny phase-only smoke surface for
  the experimental peak-bin Raman objective.
- `research_engine_gain_tilt_smoke.toml` is the tiny phase plus gain-tilt
  smoke surface for experimental non-standard variable execution.
- `research_engine_gain_tilt_scalar_search_smoke.toml` is the tiny
  derivative-free bounded scalar-search surface for a gain-tilt-only control.
  It is useful for testing low-dimensional playground UX without requiring a
  full-grid phase gradient.
- `grin50_mmf_phase_sum_poc.toml` is the experimental GRIN-50 multimode
  planning surface. Use it for dry-run and compute planning, not local
  front-layer execution.
- `smf28_longfiber_phase_poc.toml` is the experimental long-fiber planning
  surface. Use it for dry-run validation, not local execution.
- `smf28_phase_amplitude_energy_poc.toml` is the experimental single-mode
  direct-joint phase/amplitude/energy surface.
- `smf28_amp_on_phase_refinement_poc.toml` is the experimental staged
  multivar planning surface. It selects the `amp_on_phase` policy: optimize
  phase first, then run bounded amplitude refinement on the fixed phase.

Use `research_engine_poc.toml` for baseline lab runs. Use
`research_engine_smoke.toml` for quick mechanical verification. Use
`research_engine_export_smoke.toml` when checking the run-to-handoff path. Use
`research_engine_peak_smoke.toml` only when testing objective dispatch. Use
`research_engine_gain_tilt_smoke.toml` only when testing non-standard variable
dispatch and variable-specific artifacts. Use
`research_engine_gain_tilt_scalar_search_smoke.toml` when testing
bounded one-parameter search. Use the
MMF and long-fiber configs only to inspect the front-layer plan before staging
their dedicated heavy workflows. Use direct-joint multivariable configs only
when deliberately testing naive joint controls. Use `amp_on_phase` configs for
the staged multivar workflow that currently has the best evidence.

As of the current front layer, the supported phase-only export path reports
`lab_ready`, direct experimental multivariable smokes report `smoke`, and MMF,
long-fiber, and staged multivar planning configs report `planning` with explicit
promotion blockers.

## Templates

Templates live under `configs/experiments/templates/`. They are intentionally
not treated as approved runnable configs until copied to this directory and
given a real `id` / `output_tag`.

- `templates/single_mode_phase_template.toml` is the safest starting point for
  a supported local run.
- `templates/multimode_phase_planning_template.toml` is the safest starting
  point for MMF planning and compute-plan inspection.

After copying a template, run:

```bash
./fiberlab plan <new_config_id>
./fiberlab validate
```

For parameter sweeps over a base experiment, use
`configs/experiment_sweeps/` and:

```bash
./fiberlab sweep plan smf28_power_micro_sweep
./fiberlab sweep latest smf28_power_micro_sweep
```

## Knobs Researchers Can Change First

- `problem.preset`
- `problem.L_fiber`
- `problem.P_cont`
- `problem.Nt`
- `problem.time_window`
- `controls.variables`
- `controls.policy`, within the validated support boundary
- `objective.kind`, within the registered objective allowlist
- `objective.regularizer` weights
- `solver.max_iter`
- `solver.f_abstol`
- `solver.g_abstol`
- `solver.validate_gradient`
- `artifacts` bundle flags, within the validated support boundary

If a combination is not supported, validation should fail before compute.

## Current Boundaries

- Supported execution is `single_mode` with `controls.variables = ["phase"]`.
- Experimental direct-joint execution allows `["phase", "amplitude"]`,
  `["phase", "energy"]`, and `["phase", "amplitude", "energy"]`.
- Experimental staged multivar planning uses
  `controls.policy = "amp_on_phase"` with `controls.variables = ["phase",
  "amplitude"]`; run it through
  `scripts/canonical/refine_amp_on_phase.jl` from the compute plan.
- Experimental `long_fiber` configs are validation/dry-run only on local
  machines and must use `verification.mode = "burst_required"`. Their
  `controls.policy` selects the dedicated long-fiber workflow mode (`fresh`,
  `resume`, or `resume_check`) used in the generated `LF100_*` command.
- Experimental `multimode` configs are validation/dry-run only on local
  machines and must use `verification.mode = "burst_required"`. The first
  planning surface is GRIN-50, shared spectral phase, and mode-summed Raman
  leakage.
- Compute planning is provider-neutral. Rivera Lab burst commands are optional
  examples, not required infrastructure for outside users.
- Implemented single-mode objectives are `raman_band`, experimental
  `raman_peak`, and experimental non-Raman `temporal_width`; implemented
  multimode planning objectives are `mmf_sum`, `mmf_fundamental`, and
  `mmf_worst_mode`.
- The only implemented solver in this front layer is `lbfgs`.
- Objective names and allowed regularizers are code-defined in
  `scripts/lib/objective_registry.jl`; configs select from that registry.
- New research objectives can be scaffolded under `lab_extensions/objectives/`
  as planning-only contracts, then promoted after implementation and tests.
- New research variables/controls can be scaffolded under
  `lab_extensions/variables/` as planning-only contracts, then promoted after
  units, bounds, artifact semantics, implementation, and tests are clear.
- Export/SLM handoff is currently phase-only. Multivariable export requests are
  rejected during validation until the exporter can represent amplitude and
  energy controls explicitly.
- The current supported handoff profile is `neutral_csv_v1`: a simulation-axis
  CSV with wavelength/frequency, wrapped phase, unwrapped phase, and group
  delay plus JSON metadata/provenance. It is analysis-grade handoff, not a
  vendor-specific SLM loading file.
- Artifact validation checks file presence and naming only. It does not replace
  numerical trust checks or visual inspection of the standard image set.

Do not add new objectives, regimes, or device export formats only by adding
TOML keys. Add the code contract first, then expose the validated config knob.
That rule applies especially to non-Raman fiber-optic optimization objectives:
make the science explicit in code, then make it selectable in config.
