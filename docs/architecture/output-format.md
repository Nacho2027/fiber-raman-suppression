# Output Format

Canonical runs write a result directory under `results/raman/`.

## Core files

| File | Purpose |
|---|---|
| `*_result.jld2` | numerical payload |
| `*_summary.json` or sidecar JSON | machine-readable metrics |
| `run_manifest.json` | command, config, git state, artifact status |
| standard PNGs | human inspection of phase and propagation |
| export bundle | optional handoff files from `export_run.jl` |

## Standard PNGs

- `{tag}_phase_profile.png`
- `{tag}_evolution.png`
- `{tag}_phase_diagnostic.png`
- `{tag}_evolution_unshaped.png`

A run with `phi_opt` is incomplete without these images.

## Inspect

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
julia --project=. scripts/canonical/export_run.jl results/raman/<run_id>/
```

## Rule

Do not infer scientific validity from the schema alone. The files can be
complete while the run is still a smoke, an exploratory test, or a failed
physics claim.
