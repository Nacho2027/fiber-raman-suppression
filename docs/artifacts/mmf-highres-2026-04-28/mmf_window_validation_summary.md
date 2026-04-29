# MMF Window Validation

Generated 2026-04-28 23:41:22 UTC from `scripts/research/mmf/mmf_window_validation.jl`.

Purpose: decide whether the Phase 36 threshold/aggressive MMF gains survive larger temporal windows.

| Config | Status | Quality | L [m] | P [W] | Nt | TW used [ps] | TW rec [ps] | lambda_gdd | lambda_boundary | J_ref [dB] | J_opt [dB] | Delta [dB] | Max edge frac | Input edge | Output edge | Boundary ok |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| threshold | ok | meaningful | 2.0 | 0.20 | 8192 | 96.0 | 11.0 | 1.00e-04 | 5.00e-02 | -17.37 | -41.25 | 23.88 | 3.59e-13 | 3.12e-13 | 3.59e-13 | true |

Decision rule:
- If suppression remains large and `boundary_ok=true`, keep MMF active for cost/mode-launch follow-up.
- If gains vanish or stay `invalid-window`, close the current Phase 36 MMF result as a numerical-window artifact and park deeper MMF.
