# Output Format

Canonical runs write a result directory under `results/raman/`.

## Core files

| File | Purpose |
|---|---|
| `*_result.jld2` | numerical payload |
| `*_summary.json` or sidecar JSON | machine-readable metrics |
| `*_trust.md` | numerical boundary, conservation, determinism, and optional gradient verdicts |
| `run_manifest.json` | command, config, git state, artifact status |
| standard PNGs | human inspection of phase and propagation |
| export bundle | optional handoff files from `export_run.jl` |

## Standard PNGs

- `{tag}_phase_profile.png`
- `{tag}_evolution.png`
- `{tag}_phase_diagnostic.png`
- `{tag}_evolution_unshaped.png`

A run with `phi_opt` is incomplete without these images.

Run manifests and exploratory summaries record both the requested grid and the
resolved runtime grid. Scientific comparisons must use the resolved values.
`compare_ready=true` requires a valid overall `PASS` trust verdict when the
experiment requests trust evidence; `MARGINAL`, `SUSPECT`, `NOT_RUN`, missing,
and malformed reports fail closed.

An export handoff is portable evidence, not a copy of the full numerical
payload. `metadata.json` records only scalar run facts, the source result
filename, and its SHA-256; it does not store absolute source paths or duplicate
phase arrays. The bundle copies the run config and available trust/run
manifests, records SHA-256 values for those copies and every profile CSV, and
recomputes them during inspection. The external JLD2 result is intentionally
not copied, so its recorded digest is the link back to archived raw evidence.

## Inspect

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
julia --project=. scripts/canonical/export_run.jl results/raman/<run_id>/
```

## Rule

Do not infer scientific validity from the schema alone. The files can be
complete while the run is still a smoke, an exploratory test, or a failed
physics claim.
