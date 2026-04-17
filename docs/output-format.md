# Output Format — JLD2 payload + JSON sidecar

[← back to docs index](./README.md) · [project README](../README.md)

Every Raman-suppression optimization run produces TWO files:

- `<run_id>.jld2` — binary payload with arrays and nested dicts (Julia native).
- `<run_id>.json` — human-readable sidecar with scalar metadata (grep-able,
  diff-able, cross-language).

The reference implementation lives at
[`../scripts/polish_output_format.jl`](../scripts/polish_output_format.jl) —
it is the single source of truth; this doc describes the schema.

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

| Field | Type | Description |
|-------|------|-------------|
| `phi_opt` | `Vector{Float64}` | Optimized spectral phase, length `Nt` (radians). |
| `uω0` | `Vector{ComplexF64}` | Input field in frequency domain, length `Nt`. |
| `uωf` | `Vector{ComplexF64}` | Output field (after fiber) in frequency domain, length `Nt`. |
| `convergence_history` | `Vector{Float64}` | Cost history in **dB** per iteration. |
| `grid` | `Dict{String,Any}` | Simulation grid: keys `Nt`, `Δt`, `ts`, `fs`, `ωs`. |
| `fiber` | `Dict{String,Any}` | Fiber parameters (matches `FIBER_PRESETS` value shape). |
| `metadata` | `Dict{String,Any}` | Scalar metadata — mirrors the sidecar fields below. |

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
include("scripts/polish_output_format.jl")

# Save
save_run("results/raman/my_run.jld2", result)
# → writes my_run.jld2 and my_run.json side by side

# Load (either path works)
loaded_via_jld2 = load_run("results/raman/my_run.jld2")
loaded_via_json = load_run("results/raman/my_run.json")

@assert loaded_via_jld2.phi_opt == loaded_via_json.phi_opt
```

See [quickstart-optimization.md](./quickstart-optimization.md#step-3--inspect-the-results)
for a concrete load example against a real run.

## Schema versioning

- `schema_version` is checked on load. A mismatch prints a warning but the
  load still succeeds.
- Bumping the schema requires: (a) updating `OUTPUT_FORMAT_SCHEMA_VERSION` in
  `scripts/polish_output_format.jl`, (b) documenting the diff in this file's
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

- [quickstart-optimization.md](./quickstart-optimization.md) — inspect results
  after a single run.
- [quickstart-sweep.md](./quickstart-sweep.md) — how sweeps produce many of
  these files under `results/raman/sweeps/`.
- [adding-an-optimization-variable.md](./adding-an-optimization-variable.md)
  — when extending the schema with new optimization variables.
