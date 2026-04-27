# Overnight Research Supervision

Created 2026-04-27 to keep the three unfinished research lanes moving without a
single monolithic fragile run.

## Operational fixes

- `scripts/research/multivar/multivar_variable_ablation.jl` now accepts
  `MV_ABLATION_CASES`, a comma-separated case list. This lets agents launch
  high-value variable-combination cases separately so one VM loss does not lose
  the whole ablation.
- `scripts/research/longfiber/longfiber_optimize_100m.jl` now accepts
  `LF100_L`, `LF100_P_CONT`, `LF100_NT`, `LF100_TIME_WIN`, `LF100_BETA_ORDER`,
  and `LF100_RUN_LABEL`. The default remains the existing 100 m run, but 50 m,
  200 m, or other planned single-mode lengths can run without overwriting the
  100 m artifacts.
- Local `~/bin/burst-spawn-temp` was updated outside git to retry result sync
  and preserve the ephemeral VM if all sync attempts fail. Overnight launches
  should also set `BURST_AUTO_SHUTDOWN_HOURS=14` or higher.

## Overnight lane intent

- Multivar: rerun the fixed-gradient full-combo ablation as segmented
  per-case jobs, prioritizing fixed-phase improvements:
  `amp_on_phase`, `energy_on_phase`, `amp_energy_on_phase`,
  `phase_energy_cold`, and `phase_amp_energy_warm`.
- MMF: rerun the threshold/aggressive GRIN-50 window validation on permanent
  burst with larger windows. Previous Phase 36 results are numerically
  interesting but marked `invalid-window`.
- Long fiber: launch a parameterized 200 m SMF exploratory run with checkpoints
  and standard images. The existing 100 m run is useful but not lab-ready.

## Completion criteria

- A lane is not complete until result JLD2/JSON artifacts, summaries, logs, and
  the standard image set are local.
- For any `phi_opt`, verify all four standard images exist before accepting the
  run:
  phase profile, optimized evolution, phase diagnostic, and unshaped evolution.
- If an ephemeral sync fails, recover from the preserved VM rather than trusting
  launcher exit status alone.
