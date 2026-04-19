# Multi-Variable Optimizer Output Schema

**Session A** — owned by `sessions/A-multivar`.
Purpose: define the serialization format for `optimize_spectral_multivariable` so
that downstream consumers (analysis scripts, plotting, eventual SLM hardware
driver) can load the result reliably.

## Design goals

- **Julia-native fidelity:** preserve complex arrays, types, and convergence
  history without precision loss.
- **Polyglot readability:** downstream Python / MATLAB analysis should be able
  to read the structure and units without needing Julia.
- **Self-describing:** no magical key names; each array documents units, shape,
  physical meaning.
- **Round-trippable:** save then load must produce bit-identical arrays.

## Dual-file layout

Each multivar run produces TWO files:

1. **`<prefix>_result.jld2`** — dense numerical arrays (JLD2 = HDF5-compatible).
2. **`<prefix>_slm.json`** — human-readable sidecar with axes, units, and
   pointers into the JLD2.

## JLD2 payload schema (`<prefix>_result.jld2`)

| Key | Type | Shape | Units | Meaning |
|---|---|---|---|---|
| `run_tag`            | `String` | —        | —            | Timestamp or descriptor for this run |
| `fiber_name`         | `String` | —        | —            | e.g. "SMF-28", "HNLF" |
| `variables_enabled`  | `Vector{String}` | (≤4,) | — | e.g. `["phase", "amplitude"]` |
| `L_m`                | `Float64` | —       | m            | Fiber length |
| `P_cont_W`           | `Float64` | —       | W            | Continuous-wave power |
| `lambda0_nm`         | `Float64` | —       | nm           | Carrier wavelength |
| `fwhm_fs`            | `Float64` | —       | fs           | Input pulse FWHM |
| `gamma`              | `Float64` | —       | W⁻¹·m⁻¹      | Fiber nonlinearity |
| `betas`              | `Vector{Float64}` | (B,) | s^{n+1}/m | Dispersion coefficients β₂,β₃,… |
| `Nt`                 | `Int`    | —        | —            | Spectral grid size |
| `M`                  | `Int`    | —        | —            | Number of spatial modes |
| `time_window_ps`     | `Float64`| —        | ps           | Simulation time window |
| `omega_grid_rad_per_ps` | `Vector{Float64}` | (Nt,) | rad/ps | Spectral grid (fftshift'd) |
| `phi_opt`            | `Matrix{Float64}` | (Nt, M) | rad | Optimal spectral phase |
| `amp_opt`            | `Matrix{Float64}` | (Nt, M) | dimensionless | Optimal spectral amplitude factor |
| `E_opt`              | `Float64` | —       | arb.         | Optimal pulse energy (if optimized; else == E_ref) |
| `E_ref`              | `Float64` | —       | arb.         | Reference (un-shaped) pulse energy |
| `c_opt`              | `Vector{ComplexF64}` | (M,) | dimensionless | Mode coefficients (identity if stubbed) |
| `uomega0`            | `Matrix{ComplexF64}` | (Nt, M) | √W or arb. | Un-shaped reference input |
| `J_before`           | `Float64` | —       | linear       | Cost with all shaping = identity |
| `J_after`            | `Float64` | —       | linear       | Cost after optimization |
| `delta_J_dB`         | `Float64` | —       | dB           | 10·log10(J_after/J_before) |
| `grad_norm`          | `Float64` | —       | —            | ‖∇J‖ at optimum |
| `converged`          | `Bool`   | —        | —            | Optim.converged flag |
| `iterations`         | `Int`    | —        | —            | LBFGS iterations |
| `wall_time_s`        | `Float64`| —        | s            | Total runtime |
| `convergence_history`| `Vector{Float64}` | (iters,) | dB or linear | J trajectory |
| `band_mask`          | `Vector{Bool}` | (Nt,) | —         | Raman-band frequency mask |
| `sim_Dt`             | `Float64`| —        | ps           | Temporal grid step |
| `sim_omega0`         | `Float64`| —        | rad/ps       | Carrier angular frequency |
| `regularizers`       | `Dict`   | —        | —            | `{:λ_gdd => 1e-4, :λ_energy => 1.0, …}` |
| `preconditioning_s`  | `Dict`   | —        | —            | Scaling factors used per block |

All array keys that represent **field** quantities (`uomega0`, `phi_opt`, `amp_opt`)
use the fftshift'd ordering that matches `omega_grid_rad_per_ps`. To apply to the
physical input: reverse the fftshift before multiplying into the FFT-domain field.

## JSON sidecar schema (`<prefix>_slm.json`)

Human-readable, ~2 KB. Describes the JLD2 payload's content for non-Julia
consumers. Example:

```json
{
  "schema_version": "1.0",
  "generator": "scripts/multivar_optimization.jl (sessions/A-multivar)",
  "generated_at": "2026-04-17T18:42:00Z",
  "result_file": "opt_multivar_L2m_SMF28_result.jld2",
  "fiber": {
    "name": "SMF-28",
    "L_m": 2.0,
    "gamma_W_inv_m_inv": 1.1e-3,
    "betas": [-2.17e-26, 1.2e-40]
  },
  "pulse": {
    "lambda0_nm": 1550.0,
    "P_cont_W": 0.3,
    "fwhm_fs": 185.0,
    "rep_rate_Hz": 80.5e6
  },
  "grid": {
    "Nt": 8192,
    "M": 1,
    "time_window_ps": 20.0,
    "omega_grid": {
      "units": "rad/ps",
      "ordering": "fftshift",
      "storage_key": "omega_grid_rad_per_ps"
    }
  },
  "variables_enabled": ["phase", "amplitude"],
  "shaped_input_formula": "u_shaped(omega) = alpha * A(omega) * exp(i*phi(omega)) * c_m * uomega0(omega)",
  "outputs": {
    "phase": {"storage_key": "phi_opt", "shape": [8192, 1], "units": "rad"},
    "amplitude": {"storage_key": "amp_opt", "shape": [8192, 1], "units": "dimensionless"},
    "energy_scale_alpha": {"storage_key": "E_opt", "formula": "alpha = sqrt(E_opt / E_ref)"},
    "mode_coeffs": {"storage_key": "c_opt", "shape": [1], "units": "dimensionless complex"}
  },
  "metrics": {
    "J_before": 0.15,
    "J_after": 0.012,
    "delta_J_dB": -11.0,
    "converged": true,
    "iterations": 47,
    "wall_time_s": 82.3
  },
  "provenance": {
    "git_branch": "sessions/A-multivar",
    "git_commit": "<sha>",
    "julia_version": "1.12.4",
    "threads": 22
  }
}
```

## Round-trip test

Required acceptance test in `scripts/test_multivar_gradients.jl` or a companion
test file:

```julia
result = optimize_spectral_multivariable(...)
save_multivar_result("/tmp/rt_test", result)
loaded = load_multivar_result("/tmp/rt_test")
@assert loaded.phi_opt == result.phi_opt
@assert loaded.amp_opt == result.amp_opt
@assert loaded.E_opt  ≈ result.E_opt
@assert loaded.J_after == result.J_after
# Both files must exist:
@assert isfile("/tmp/rt_test_result.jld2")
@assert isfile("/tmp/rt_test_slm.json")
```

## Why not HDF5-native (bypassing JLD2)?

Considered. Decision: stay on JLD2 because
- it is already a project dependency (used by `raman_optimization.jl`),
- its byte format IS HDF5 (Python `h5py` can open JLD2 files), so we get the
  polyglot benefit for free,
- adding `HDF5.jl` would require a second native library and is redundant.

## Future extensions (not milestone-1)

- Complex `A(ω)` field for a polar (|A|, arg(A)) SLM hardware (unlikely — SLMs
  usually give amplitude OR phase, not both in a single channel).
- Mode-coefficient output for a real spatial SLM once Session C unstubs that
  variable. Schema above already reserves the key.
- Compressed storage for long-fiber sweep sets (Zstd via JLD2's HDF5 option).
