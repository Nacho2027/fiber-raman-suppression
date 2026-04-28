# MMF High-Resolution Validation Status

Date: 2026-04-28

## Goal

Run the remaining threshold-only `GRIN_50` high-resolution MMF validation:

```bash
MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_gdd_nt8192_final \
MMF_VALIDATION_CASES=threshold \
MMF_VALIDATION_MAX_ITER=4 \
MMF_VALIDATION_THRESHOLD_TW=96 \
MMF_VALIDATION_THRESHOLD_NT=8192 \
MMF_VALIDATION_LAMBDA_BOUNDARY=0.05 \
MMF_VALIDATION_LAMBDA_GDD=1e-4 \
MMF_VALIDATION_F_CALLS_LIMIT=80 \
MMF_VALIDATION_TIME_LIMIT_SECONDS=10800 \
julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl
```

## Infrastructure Checks

- Start state: dirty worktree with many unrelated changes; no unrelated edits
  reverted.
- Syncthing: one peer connected, one peer disconnected.
- Initial GCE inventory: `fiber-raman-burst` terminated; no MMF ephemerals.
- `us-east5` C3 quota before launch attempts: `C3_CPUS usage=0 limit=50`.

## Attempts

- `M-mmfg8192final`, `c3-highmem-22`, `us-east5-a`: blocked by
  `ZONE_RESOURCE_POOL_EXHAUSTED_WITH_DETAILS`.
- `M-mmfg8192finalb`, `c3-highmem-22`, `us-east5-b`: blocked by stockout after
  brief staging.
- `M-mmfg8192finalc`, `c3-highmem-22`, `us-east5-c`: launched but failed
  immediately because the stale VM image did not contain
  `scripts/research/mmf/mmf_window_validation.jl`; no result directory.
- `M-mmfg8192finalc2`, `c3-highmem-22`, `us-east5-c`: launched with explicit
  source sync. It reached `iter 29`, stopped by `:time_limit`, but exposed a
  run-control bug: the limit catch returned the initial phase metadata
  (`J_final=Inf`, trust line `J_sum -17.37 -> -17.37 dB`) instead of the best
  observed phase. This run was stopped during invalid finalization and synced
  logs only.
- Local fix applied:
  `scripts/research/mmf/mmf_raman_optimization.jl` now sets `J_final = best_J`
  and `phi_opt = best_phi` in the `MMFOptimizationLimit` catch path. Local
  include check passed:
  `julia --project=. -e 'include("scripts/research/mmf/mmf_raman_optimization.jl"); println("mmf_raman_optimization include ok")'`.
- The default machine image entered a stale `DELETING` state. A one-off image
  was created:
  `fiber-raman-burst-template-mmf-20260428`.

## Active Run

Status as of 2026-04-28 20:34 UTC: running.

- Session: `M-mmfg8192s44c2`
- Local supervisor: `tmux` session `mmf-highres-final-s44c2`
- VM: `fiber-raman-temp-m-mmfg8192s44c2-20260428t194709z`
- Zone/type: `us-east5-c`, `c3-standard-44` (176 GB RAM)
- Remote log: `results/burst-logs/M-mmfg8192s44c2_20260428T194811Z.log`
- Local launcher log:
  `results/burst-logs/validation/20260428/mmf-highres-final-s44c2.log`
- Result path:
  `results/raman/phase36_window_validation_gdd_nt8192_final`
- Latest observed optimizer line: `iter 4: J = -2.400931e+01 (dB)`
- Latest observed memory: about 34 GB RSS, no swap, ample memory headroom.

## Completion Criteria Still Pending

- Wait for the patched run to stop through `time_limit` or complete.
- Confirm synced summary and artifacts under
  `results/raman/phase36_window_validation_gdd_nt8192_final`.
- Extract final `J_ref`, `J_opt`, improvement, edge diagnostics, and
  `boundary_ok`.
- Confirm the standard image set exists and visually inspect it before treating
  the lane as validated.
- Clean up the active VM and, if no longer needed, the temporary machine image.
