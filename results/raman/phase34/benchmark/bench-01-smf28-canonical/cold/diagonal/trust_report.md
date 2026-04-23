# Trust Report — bench-01-smf28-canonical / cold / diagonal

- Pre-flight edge fraction: `9.088e-33` (PASS)
- Warm-start source: `results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2`
- Warm-start note: pre-audit canonical (bc_input_ok=false — baseline contrast)
- Preconditioner: `diagonal` (M-kwarg wiring: NOT active — see driver header)

## Optimizer (Trust-Region)

- Exit code: **`RADIUS_COLLAPSE`**
- Iterations: `10`
- J final: `7.746118e-01`
- ‖g‖ final: `3.953e-02`
- λ_min final: `-4.679e+02`
- λ_max final: `2.825e+02`

### Budget
- HVPs: `60`
- Gradient calls: `1`
- Forward-only calls: `11`
- Wall time: `569.35 s`

### ρ statistics (accepted iterations)
- No accepted iterations.

### Rejection breakdown
- `accepted`: `0`
- `rho_too_small`: `0`
- `negative_curvature`: `10`
- `boundary_hit`: `0`
- `cg_max_iter`: `0`
- `nan_at_trial_point`: `0`

