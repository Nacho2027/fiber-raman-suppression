# Output Format — JLD2 payload + JSON sidecar

[← docs index](../README.md) · [project README](../../README.md)

Every canonical Raman-suppression optimization run produces TWO files:

- `<run_id>.jld2` — binary payload with arrays and nested dicts (Julia native).
- `<run_id>.json` — human-readable sidecar with scalar metadata (grep-able,
  diff-able, cross-language).

The canonical implementation now lives in
[`../../src/io/results.jl`](../../src/io/results.jl) and is exposed as
`MultiModeNoise.save_run` / `MultiModeNoise.load_run`.
[`../../scripts/workflows/polish_output_format.jl`](../../scripts/workflows/polish_output_format.jl)
remains as a compatibility shim for older include-based workflows.

Current schema version: **1.0**

## Why two files

JLD2 preserves `ComplexF64`, `Vector{Float64}`, dict nesting, and arbitrary
metadata natively — no serialization dance. But it's not human-readable, not
diff-friendly, and not consumable from Python or shell without a Julia
interpreter.

The JSON sidecar gives:
- `cat run_id.json` shows the run's scalar signature in one screenful.
- `jq '{J_final_dB, converged}' *.json` works across all runs.
- `git diff` on sidecars tells you what actually changed between runs.
- Cross-lab / cross-language tools can read the JSON without Julia.

## JLD2 payload fields

The canonical optimizer writes the historical `_result.jld2` payload fields
verbatim so existing analysis scripts keep working. Common fields include:

| Field | Type | Description |
|-------|------|-------------|
| `fiber_name`, `run_tag` | string | Human-facing run identity. |
| `L_m`, `P_cont_W`, `lambda0_nm`, `fwhm_fs` | scalars | Physical configuration. |
| `Nt`, `time_window_ps` | scalars | Grid metadata. |
| `J_before`, `J_after`, `delta_J_dB`, `grad_norm` | scalars | Optimization summary. |
| `converged`, `iterations`, `wall_time_s` | scalars | Run status. |
| `convergence_history` | `Vector{Float64}` | Cost history in dB. |
| `phi_opt` | array | Optimized spectral phase. |
| `uomega0` | array | Input field in frequency domain. |
| `band_mask` | array | Raman-band mask for reconstruction. |
| `sim_Dt`, `sim_omega0` | scalars | Minimal simulation context for downstream readers. |
| `trust_report`, `trust_report_md` | dict/string | Numerical trust diagnostics. |
| `metadata` | `Dict{String,Any}` | Sidecar-compatible scalar metadata synthesized by `save_run`. |

`save_run` still accepts the older package-centric payload shape
(`phi_opt`, `uω0`, `uωf`, `grid`, `fiber`, `metadata`, ...) for compatibility.
`load_run(...)` returns the JLD2 top-level fields plus `sidecar`.

## JSON sidecar example

```json
{
  "schema_version": "1.0",
  "payload_file": "smf28_L2.0m_P0.2W_20260417T153000.jld2",
  "run_id": "smf28_L2.0m_P0.2W_20260417T153000",
  "git_sha": "aa2e9b3",
  "julia_version": "1.12.4",
  "timestamp_utc": "2026-04-17T15:30:00Z",
  "fiber_preset": "SMF28",
  "L_m": 2.0,
  "P_W": 0.2,
  "lambda0_nm": 1550.0,
  "pulse_fwhm_fs": 185.0,
  "Nt": 8192,
  "time_window_ps": 12.0,
  "J_final_dB": -74.3,
  "J_initial_dB": -3.1,
  "n_iter": 47,
  "converged": true,
  "seed": 42,
  "phi_opt_rad": [0.0, 0.01]
}
```

## JSON sidecar fields

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Starts at `"1.0"`. Bumped on breaking change. |
| `payload_file` | string | Relative filename of the sibling `.jld2`. |
| `run_id` | string | Unique identifier, typically `<preset>_L<x>m_P<y>W_<ts>`. |
| `git_sha` | string | Short commit hash at run time. |
| `julia_version` | string | `VERSION` at run time (e.g., `"1.12.4"`). |
| `timestamp_utc` | string | ISO 8601 UTC timestamp. |
| `fiber_preset` | string | One of `"SMF28"`, `"HNLF_normal"`, `"HNLF_anomalous"`, … |
| `L_m` | number | Fiber length in meters. |
| `P_W` | number | Continuous-wave power in watts. |
| `lambda0_nm` | number | Center wavelength in nanometers. |
| `pulse_fwhm_fs` | number | Pulse FWHM in femtoseconds. |
| `Nt` | integer | Number of temporal grid points (power of 2). |
| `time_window_ps` | number | Temporal window in picoseconds. |
| `J_final_dB` | number | Converged cost in dB (more negative = more suppression). |
| `J_initial_dB` | number | Starting cost in dB (flat phase). |
| `n_iter` | integer | L-BFGS iteration count. |
| `converged` | boolean | Whether the optimizer hit a convergence criterion. |
| `seed` | integer | Random seed used for initial conditions. |
| `phi_opt_rad` | `number[]` (optional) | Optimized phase inlined; present only when `Nt < 8192`. For larger runs, the sidecar includes `phi_opt_rad_note` instead. |

## Round trip with save_run / load_run

```julia
using MultiModeNoise: load_run, save_run

# Save
save_run("results/raman/my_run.jld2", result)
# → writes my_run.jld2 and my_run.json side by side

# Load (either path works)
loaded_via_jld2 = load_run("results/raman/my_run.jld2")
loaded_via_json = load_run("results/raman/my_run.json")

@assert loaded_via_jld2.phi_opt == loaded_via_json.phi_opt
```

See [quickstart-optimization.md](../guides/quickstart-optimization.md#step-3--inspect-the-results)
for a concrete load example against a real run.

## Experimental handoff export

`scripts/canonical/export_run.jl` converts a saved result into an
experiment-facing handoff directory. The default phase-only bundle contains:

- `phase_profile.csv` with simulation-grid frequency, wavelength, wrapped
  phase, unwrapped phase, and group delay.
- `metadata.json` with source artifact, scalar run summary, sidecar metadata,
  and export file names.
- `roundtrip_validation.json` with reload checks for row counts and export
  bounds.
- `README.md` with the human-readable handoff summary.
- `source_run_config.toml` when the source run directory contains it.

When the source artifact contains `amp_opt`, the exporter also writes
`amplitude_profile.csv`. This file is intentionally device-agnostic. It records
both the simulated dimensionless amplitude multiplier and a conservative
loss-only hardware column:

```text
index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,amplitude_multiplier,normalized_transmission_loss_only
```

The loss-only column is computed by dividing the simulated multiplier by its
maximum value. This guarantees transmission values in `[0, 1]`, records the
required global attenuation factor in `metadata.json`, and avoids pretending
that a loss-only shaper can realize relative gain. Lab hardware software should
use this as a calibrated starting contract, not as a vendor-specific pixel file.

The exporter supports both canonical `save_run` pairs
(`<prefix>.jld2` + `<prefix>.json`) and the current multivar research pair
(`<prefix>_result.jld2` + `<prefix>_slm.json`) so reproduced
amplitude-on-phase artifacts can be handed off without rewriting historical
results.

## Schema versioning

- `schema_version` is checked on load. A mismatch prints a warning but the
  load still succeeds.
- Bumping the schema requires: (a) updating `OUTPUT_FORMAT_SCHEMA_VERSION` in
  `src/io/results.jl`, (b) documenting the diff in this file's
  changelog below, (c) adding a migration note or helper if old files need to
  be readable.

### Changelog

- **1.0** (Phase 16, 2026-04-17): Initial format.

## Cross-language reading (Python)

```python
import json, h5py

with open("my_run.json") as f:
    meta = json.load(f)
# JLD2 is HDF5-compatible; h5py reads array fields directly:
with h5py.File(meta["payload_file"], "r") as h:
    phi_opt = h["phi_opt"][()]
```

## See also

- [quickstart-optimization.md](../guides/quickstart-optimization.md) — inspect results
  after a single run.
- [quickstart-sweep.md](../guides/quickstart-sweep.md) — how sweeps produce many of
  these files under `results/raman/sweeps/`.
- [adding-an-optimization-variable.md](../guides/adding-an-optimization-variable.md)
  — when extending the schema with new optimization variables.
