# Configurable Experiments

Use `./fiberlab` when you want to run or inspect a TOML-defined experiment
without editing optimizer code.

## List configs

```bash
./fiberlab configs
./fiberlab capabilities
```

Good starting points:

| Config | Status | Use |
|---|---|---|
| `research_engine_poc` | supported | single-mode phase baseline |
| `research_engine_smoke` | supported smoke | quick CLI/artifact check |
| `research_engine_export_smoke` | supported smoke | export handoff check |
| `research_engine_gain_tilt_smoke` | experimental | phase plus gain-tilt smoke |
| `research_engine_gain_tilt_scalar_search_smoke` | experimental | one-parameter scalar search |
| `grin50_mmf_phase_sum_poc` | planning | MMF dry-run only |
| `smf28_longfiber_phase_poc` | planning | long-fiber dry-run only |
| `smf28_phase_amplitude_energy_poc` | experimental | direct multivariable research |

## Plan and run

```bash
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
./fiberlab ready latest research_engine_poc
```

For experimental work:

```bash
./fiberlab explore list
./fiberlab explore plan research_engine_gain_tilt_smoke
./fiberlab check config research_engine_gain_tilt_smoke
./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke
./fiberlab explore compare results/raman --top 10
```

`run` is conservative. `explore` is for research work and requires explicit
flags such as `--local-smoke` or `--heavy-ok` when a path is risky.

## Inspect contracts

```bash
./fiberlab objectives
./fiberlab objectives --validate
./fiberlab variables
./fiberlab variables --validate
./fiberlab layout research_engine_poc
./fiberlab artifacts research_engine_poc
```

Do not create a new objective or variable by only editing TOML. Add the formula,
gradient or fallback, validation, artifact hooks, and tests in code first.

## Sweeps

```bash
./fiberlab sweep list
./fiberlab sweep plan smf28_power_micro_sweep
./fiberlab sweep validate
./fiberlab sweep latest smf28_power_micro_sweep
```

Large sweeps should run through the burst workflow.

## Artifacts

Front-layer runs write `run_manifest.json` beside the result payload. Exploratory
runs also write a generic summary JSON and overview PNG when specialized plots
are not available.

The manifest is metadata. It does not replace the JLD2 result or standard
images.
