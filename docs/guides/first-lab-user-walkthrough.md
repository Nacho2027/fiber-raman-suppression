# First Lab User Walkthrough

[<- docs index](../README.md) | [lab readiness](./lab-readiness.md) | [supported workflows](./supported-workflows.md)

This walkthrough is the shortest honest path for a new lab member. It uses the
supported front layer only. Do not start with the historical research scripts
unless you are explicitly promoting an experimental lane.

## Goal

By the end, the user should know how to:

- check that the repo is locally healthy
- inspect a supported config before running it
- run the smallest real supported workflow
- inspect the generated artifacts
- find the neutral export handoff for experimental use
- understand which research lanes are still planning or experimental

## 1. Install And Check The Environment

From a clean checkout:

```bash
make install
make lab-ready
```

`make lab-ready` is the simulation-light local gate. It proves that the
supported front layer, config validation, Python wrapper, artifact contracts,
result indexing, and fast tests are coherent.

Expected result:

```text
Local lab-readiness gate passed for the supported front-layer surface.
```

The common headless warning is acceptable:

```text
No working GUI backend found for matplotlib
```

It means there is no interactive Matplotlib display backend. PNG generation is
still the relevant check for this repo.

## 2. List And Inspect Supported Configs

Use the wrapper when teaching a new user:

```bash
./fiberlab configs
```

For the canonical handoff smoke, inspect before running:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_export_smoke
```

The dry run must show:

- `Maturity: supported`
- `Promotion stage: lab_ready`
- `Promotion blockers: none`
- `Execution: mode=phase_only`
- `Artifacts: bundle=standard export_enabled=true`

If a config says `planning`, `experimental`, `burst_required`, or has promotion
blockers, it is not the first-line lab workflow.

## 3. Run The Golden Smoke

Run:

```bash
make golden-smoke
```

This launches the smallest real supported workflow:

- single-mode SMF-28
- phase-only control
- Raman-band objective
- one L-BFGS iteration
- standard image bundle
- trust report
- neutral CSV export handoff

Expected result:

```text
Status: PASS
Blockers: none
Standard images complete: true
Variable artifacts complete: true
Export handoff complete: true
Export phase CSV valid: true
Quality: EXCELLENT
```

This is not a research benchmark. It is an end-to-end checkout and handoff test.

## 4. Inspect The Run

Find the newest smoke directory:

```bash
ls -td results/raman/smoke/smf28_phase_export_smoke_* | head -1
```

Then inspect the generated bundle:

```bash
julia -t auto --project=. scripts/canonical/lab_ready.jl --latest research_engine_export_smoke --require-export
julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 10 results/raman/smoke
```

Visually inspect all four standard images before calling the run valid:

- `opt_phase_profile.png`
- `opt_evolution.png`
- `opt_phase_diagnostic.png`
- `opt_evolution_unshaped.png`

File existence alone is not enough. The plots should render with sane axes,
finite curves or heatmaps, and no missing panels.

## 5. Use The Export Handoff

The neutral handoff bundle lives under:

```text
<run-dir>/export_handoff/
```

The lab-facing files are:

- `phase_profile.csv`
- `metadata.json`
- `roundtrip_validation.json`
- `source_run_config.toml`
- `README.md`

Use the CSV and metadata in notebooks, spreadsheets, hardware-control scripts,
or other lab tooling. Do not require downstream users to parse JLD2 files for
the first supported handoff.

## 6. Notebook Pattern

Notebook work should consume committed interfaces and generated artifacts, not
private script internals.

Recommended notebook flow:

1. Run `make golden-smoke` or a supported config from the shell.
2. Read `<run-dir>/opt_result.json` for metrics and status.
3. Read `<run-dir>/export_handoff/phase_profile.csv` for the phase profile.
4. Embed the four standard PNGs for visual review.
5. Record the exact config ID and run directory in the notebook.

Avoid notebook-authored optimization loops as the default lab workflow. If a
notebook needs a new objective, variable, or sweep axis, add it through the
front-layer config/extension contracts first.

## 7. What Not To Promote Yet

These are visible for planning and research continuity, but not first-line lab
handoff workflows:

- MMF
- long-fiber
- broad direct phase/amplitude/energy optimization
- Newton or preconditioning work
- arbitrary notebook-defined objectives

The current supported lab workflow is intentionally narrow because trust is
more valuable than exposing every research branch at once.

## 8. Demo Script

For a live demo, use this sequence:

```bash
make lab-ready
./fiberlab configs
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_export_smoke
make golden-smoke
julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 10 results/raman/smoke
julia -t auto --project=. scripts/canonical/index_telemetry.jl --sort elapsed --desc --top 10
```

Then show the newest smoke directory, the four standard images, and
`export_handoff/`.
