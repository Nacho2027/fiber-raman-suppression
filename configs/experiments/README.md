# Experiment Configs

This directory is the thin researcher-facing front layer. The goal is to make
common run changes explicit in TOML, while keeping the physics and optimizer
implementations in Julia code.

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

Run a validated config:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
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
- `smf28_phase_amplitude_energy_poc.toml` is the experimental single-mode
  phase/amplitude/energy surface.

Use `research_engine_poc.toml` for baseline lab runs. Use
`research_engine_smoke.toml` for quick mechanical verification. Use the
experimental config when deliberately testing multivariable controls.

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
- The only implemented objective in this front layer is `raman_band`.
- The only implemented solver in this front layer is `lbfgs`.
- Objective names and allowed regularizers are code-defined in
  `scripts/lib/objective_registry.jl`; configs select from that registry.
- Export/SLM handoff is currently phase-only. Multivariable export requests are
  rejected during validation until the exporter can represent amplitude and
  energy controls explicitly.
- Artifact validation checks file presence and naming only. It does not replace
  numerical trust checks or visual inspection of the standard image set.

Do not add new objectives, regimes, or device export formats only by adding
TOML keys. Add the code contract first, then expose the validated config knob.
