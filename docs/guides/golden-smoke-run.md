# Golden Smoke Run

[<- docs index](../README.md) | [configurable experiments](./configurable-experiments.md)

The golden smoke run is the smallest supported end-to-end lab workflow. It is
not a scientific benchmark. It exists to prove that a checkout can execute the
front layer, write the standard artifact bundle, validate the neutral export
handoff, and pass the lab-readiness gate.

Use:

```bash
make golden-smoke
```

The target expands to the explicit gate/run/gate sequence:

```bash
julia -t auto --project=. scripts/canonical/lab_ready.jl --config research_engine_export_smoke
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_export_smoke
julia -t auto --project=. scripts/canonical/lab_ready.jl --latest research_engine_export_smoke --require-export
```

The run is intentionally tiny:

- config: `configs/experiments/research_engine_export_smoke.toml`
- regime: `single_mode`
- variables: `phase`
- objective: `raman_band`
- solver: `lbfgs`
- iterations: `1`
- output root: `results/raman/smoke/`
- export: `neutral_csv_v1`

## Acceptance Criteria

A golden smoke run is mechanically valid only if all of these pass:

- `lab_ready.jl --config research_engine_export_smoke` reports `PASS`.
- `run_experiment.jl research_engine_export_smoke` reports artifact validation
  complete, standard images complete, and export validation complete.
- `lab_ready.jl --latest research_engine_export_smoke --require-export`
  reports `PASS`.
- `inspect_run.jl <run-dir>` reports standard image set complete and export
  handoff complete, with a valid `phase_profile.csv` row count.
- The four required standard images are visually inspected:
  `opt_phase_profile.png`, `opt_evolution.png`, `opt_phase_diagnostic.png`,
  and `opt_evolution_unshaped.png`.
- `export_handoff/phase_profile.csv`, `metadata.json`, `README.md`,
  `roundtrip_validation.json`, and `source_run_config.toml` are present.

## Verified Examples

Clean-clone rehearsal on 2026-04-28 from commit `0d4c4e7`:

```text
/tmp/fiber-raman-clean-rehearsal/results/raman/smoke/smf28_phase_export_smoke_20260428_1611741
```

Observed gate summary:

```text
Status: PASS
Blockers: none
Standard images complete: true
Variable artifacts complete: true
Export handoff complete: true
Export phase CSV valid: true
Export phase CSV rows: 1024
Converged: true
Quality: EXCELLENT
J_after_dB: -45.963546468444825
Delta_J_dB: -0.0006783608010110243
```

Visual inspection notes:

- `opt_phase_profile.png`: rendered before/after spectrum, pulse shape, and
  group delay panels; tiny one-iteration phase change is expected.
- `opt_evolution.png`: rendered optimized spectral evolution with sane axes.
- `opt_phase_diagnostic.png`: rendered wrapped/unwrapped phase and derivative
  diagnostics with no missing panels.
- `opt_evolution_unshaped.png`: rendered unshaped evolution for comparison.

Verified on 2026-04-27:

```text
results/raman/smoke/smf28_phase_export_smoke_20260427_0034806
```

Observed gate summary:

```text
Status: PASS
Blockers: none
Standard images complete: true
Export handoff complete: true
Export phase CSV valid: true
Export phase CSV rows: 1024
Converged: true
Quality: EXCELLENT
J_after_dB: -45.963546468444825
Delta_J_dB: -0.0006783608010110243
```

Visual inspection notes:

- `opt_phase_profile.png`: rendered before/after spectrum, pulse shape, and
  group delay panels; tiny one-iteration phase change is expected.
- `opt_evolution.png`: rendered optimized spectral evolution with sane axes.
- `opt_phase_diagnostic.png`: rendered wrapped/unwrapped phase and derivative
  diagnostics with no missing panels.
- `opt_evolution_unshaped.png`: rendered unshaped evolution for comparison.

Generated JLD2 and PNG artifacts are routine run outputs and should not be
committed unless deliberately promoted as fixtures.
