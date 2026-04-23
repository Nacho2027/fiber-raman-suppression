# Adding a Fiber Preset

[← docs index](../README.md) · [project README](../../README.md)

Extend `FIBER_PRESETS` in `scripts/lib/common.jl` with a new fiber type. This
guide focuses on what needs to be true for the preset to work cleanly with the
maintained workflows.

## What a preset contains

A `FIBER_PRESETS` entry is a `NamedTuple` keyed by a symbol. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `γ` | `Float64` | Nonlinear coefficient, W⁻¹·m⁻¹. |
| `β` | `Vector{Float64}` | Dispersion Taylor coefficients starting at β₂: `[β₂, β₃]` or `[β₂, β₃, β₄]`. |
| `λ0` | `Float64` | Center wavelength in meters (e.g., `1550e-9`). |
| `L_default` | `Float64` | A sensible default length in meters. |
| `P_default` | `Float64` | A sensible default CW power in watts. |

Example (current):

```julia
:SMF28 => (
    γ  = 1.3e-3,
    β  = [SMF28_BETAS[1], SMF28_BETAS[2]],
    λ0 = 1550e-9,
    L_default = 2.0,
    P_default = 0.2,
),
```

## How to add one

1. Pick a symbolic key (e.g., `:SMF_ESM`). Make it descriptive and SI-free.
2. Gather the fiber parameters from datasheet or measurement:
   - γ in W⁻¹·m⁻¹.
   - β₂ (and β₃, optionally β₄) at your operating wavelength.
3. Add the entry to `FIBER_PRESETS` in `scripts/lib/common.jl`.
4. **Important:** If your preset has exactly two β coefficients, you MUST set
   `β_order=3` when calling `setup_raman_problem` (Phase 10 gotcha). With
   three coefficients, use `β_order=4`. This applies to every entry-point
   script that consumes the preset.

## Testing a new preset

```bash
# Run the fast test suite to confirm nothing regressed:
make test

# Then run a canonical optimization with your new preset:
julia --project -t auto -e '
  include("scripts/lib/raman_optimization.jl")
  run_optimization(fiber_preset=:SMF_ESM, L_fiber=1.0, P_cont=0.1)
'
```

Expect: a `J_final_dB` between −40 and −80 for a reasonable fiber. If you see
`J_final_dB > -10`, your preset parameters are probably in the wrong units.

## Units sanity checklist

- γ in **W⁻¹·m⁻¹** (NOT W⁻¹·km⁻¹ — datasheets sometimes report the latter).
- β₂ in **s²/m** (NOT ps²/km).
- β₃ in **s³/m**.
- λ₀ in **meters** (NOT nm).

A common failure mode: datasheet `γ = 1.3 W⁻¹·km⁻¹` is `1.3e-3 W⁻¹·m⁻¹`.
Off by 1000 produces `J_final_dB ≈ 0` (optimizer has nothing to work with).

## See also

- [cost-function-physics.md](../architecture/cost-function-physics.md) — what γ and β₂ physically mean.
- [quickstart-optimization.md](./quickstart-optimization.md) — how to run a canonical test.
- [output-format.md](../architecture/output-format.md) — the `fiber_preset` field in saved results.
- `scripts/lib/common.jl` — the live `FIBER_PRESETS` dictionary.
