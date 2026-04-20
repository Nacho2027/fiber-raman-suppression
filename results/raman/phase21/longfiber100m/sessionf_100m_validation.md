# Session F 100m schema validation

Summary source: `/home/ignaciojlizama/fiber-raman-suppression/scripts/../results/raman/phase16/100m_validate_fixed.jld2`
Full-state source: `/home/ignaciojlizama/fiber-raman-suppression/scripts/../results/raman/phase16/100m_opt_full_result.jld2`

## Summary keys

- `E_drift_flat`
- `E_drift_opt`
- `E_drift_warm`
- `J_flat_dB`
- `J_opt_dB`
- `J_warm_dB`
- `a2_deviation_pct`
- `a2_ratio_100_vs_2`
- `bc_flat`
- `bc_opt`
- `bc_warm`
- `converged`
- `grad_norm`
- `gvd_ratio_100_vs_2`
- `n_active_bins`
- `n_iter`
- `opt_R2`
- `opt_a0`
- `opt_a1`
- `opt_a2`
- `saved_at`
- `total_bins`
- `wall_fresh_s`
- `warm_R2`
- `warm_a0`
- `warm_a1`
- `warm_a2`

## Full-state keys

- `J_final`
- `J_final_lin`
- `L_m`
- `Nt`
- `P_cont_W`
- `config_hash`
- `converged`
- `g_residual`
- `n_iter`
- `phi_opt`
- `phi_warm`
- `saved_at`
- `time_window_ps`
- `trace_f`
- `trace_g`
- `trace_iter`
- `wall_s`
- `β_order`

## Honest validation

- Honest J: -54.77 dB
- Edge fraction: 8.468e-06
- Energy drift: 4.908e-04
- Stored converged flag: false
- Stored J_opt_dB: -54.76581847340812

Verdict note: `100m_validate_fixed.jld2` is a scalar summary, not a standalone validation container. Honest validation must pair it with `100m_opt_full_result.jld2` to recover the actual phase state.
