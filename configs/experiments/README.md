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
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
```

Dry-run a config without launching optimization:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_poc
```

The dry-run output shows the resolved execution mode and whether export is
currently supported for that mode.

List objective/cost contracts available to configs:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --objectives
```

This lists both built-in executable objective contracts and research extension
contracts from `lab_extensions/objectives/`. Extension contracts are
discoverable planning surfaces until promoted with tests and a real backend.

List the regime/variable/objective/artifact capabilities in one place:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --capabilities
```

Validate every approved experiment config without launching compute:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-all
```

Run a validated config:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
```

Inspect the latest completed run for a config:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --latest research_engine_poc
```

Print provider-neutral compute guidance without launching anything:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --compute-plan smf28_longfiber_phase_poc
```

After a run, the front layer validates the basic artifact contract before
returning control: copied config, JLD2 payload, JSON sidecar, standard image
set, and the phase-only trust report when required.

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
- `grin50_mmf_phase_sum_poc.toml` is the experimental GRIN-50 multimode
  planning surface. Use it for dry-run and compute planning, not local
  front-layer execution.
- `smf28_longfiber_phase_poc.toml` is the experimental long-fiber planning
  surface. Use it for dry-run validation, not local execution.
- `smf28_phase_amplitude_energy_poc.toml` is the experimental single-mode
  phase/amplitude/energy surface.

Use `research_engine_poc.toml` for baseline lab runs. Use
`research_engine_smoke.toml` for quick mechanical verification. Use
`research_engine_export_smoke.toml` when checking the run-to-handoff path. Use
`research_engine_peak_smoke.toml` only when testing objective dispatch. Use the
MMF and long-fiber configs only to inspect the front-layer plan before staging
their dedicated heavy workflows. Use the
experimental multivariable config when deliberately testing multivariable
controls.

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
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run <new_config_id>
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-all
```

For parameter sweeps over a base experiment, use
`configs/experiment_sweeps/` and:

```bash
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --dry-run smf28_power_micro_sweep
```

## Knobs Researchers Can Change First

- `problem.preset`
- `problem.L_fiber`
- `problem.P_cont`
- `problem.Nt`
- `problem.time_window`
- `controls.variables`
- `objective.kind`, within the registered objective allowlist
- `objective.regularizer` weights
- `solver.max_iter`
- `solver.validate_gradient`
- `artifacts` bundle flags, within the validated support boundary

If a combination is not supported, validation should fail before compute.

## Current Boundaries

- Supported execution is `single_mode` with `controls.variables = ["phase"]`.
- Experimental execution allows `["phase", "amplitude"]`, `["phase", "energy"]`,
  and `["phase", "amplitude", "energy"]`.
- Experimental `long_fiber` configs are validation/dry-run only on local
  machines and must use `verification.mode = "burst_required"`.
- Experimental `multimode` configs are validation/dry-run only on local
  machines and must use `verification.mode = "burst_required"`. The first
  planning surface is GRIN-50, shared spectral phase, and mode-summed Raman
  leakage.
- Compute planning is provider-neutral. Rivera Lab burst commands are optional
  examples, not required infrastructure for outside users.
- Implemented single-mode objectives are `raman_band` and experimental
  `raman_peak`; implemented multimode planning objectives are `mmf_sum`,
  `mmf_fundamental`, and `mmf_worst_mode`.
- The only implemented solver in this front layer is `lbfgs`.
- Objective names and allowed regularizers are code-defined in
  `scripts/lib/objective_registry.jl`; configs select from that registry.
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
