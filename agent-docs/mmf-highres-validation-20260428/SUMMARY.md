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

## Completed Run

Status as of 2026-04-29 01:20 UTC: completed and synced.

- Session: `M-mmfg8192s44c2`
- Local supervisor: `tmux` session `mmf-highres-final-s44c2`
- VM: `fiber-raman-temp-m-mmfg8192s44c2-20260428t194709z`
- Zone/type: `us-east5-c`, `c3-standard-44` (176 GB RAM)
- Remote log: `results/burst-logs/M-mmfg8192s44c2_20260428T194811Z.log`
- Local launcher log:
  `results/burst-logs/validation/20260428/mmf-highres-final-s44c2.log`
- Result path:
  `results/raman/phase36_window_validation_gdd_nt8192_final`
- Runtime: launched 2026-04-28 19:48 UTC; wrapper synced results at
  2026-04-28 23:41 UTC.
- The wrapper destroyed the ephemeral VM after syncing. Current VM inventory
  shows only `fiber-raman-burst` in `TERMINATED` state.
- Peak observed memory stayed safe: about 34-43 GB RSS on a 176 GB VM, no swap,
  ample memory headroom.

## Result

- Config: threshold-only `GRIN_50`, `L=2.0 m`, `P=0.20 W`, `Nt=8192`,
  `time_window=96 ps`, `lambda_gdd=1e-4`, `lambda_boundary=0.05`.
- Summary:
  `results/raman/phase36_window_validation_gdd_nt8192_final/mmf_window_validation_summary.md`.
- Accepted metric: `J_ref=-17.37 dB`, `J_opt=-41.25 dB`, improvement
  `23.88 dB`.
- Boundary diagnostics: max edge fraction `3.59e-13`; `boundary_ok=true`.
- Per-mode summary from log: `J_fund=-41.00 dB`, `J_worst=-41.00 dB`.
- The optimizer stopped through the driver-side time limit, but after the
  run-control fix it returned the best observed phase instead of the initial
  phase.

## Artifacts Checked

Required standard images exist and were visually inspected:

- `mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution.png`
- `mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution_unshaped.png`

Additional summary plots exist:

- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt8192_tw96_convergence.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt8192_tw96_total_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt8192_tw96_per_mode_spectrum.png`

Visual inspection: the optimized standard images are readable and nonblank; the
optimized spectrum suppresses the Raman-side feature relative to the unshaped
evolution, and the boundary metric is clean. The phase/GD profile is structured
and should still be treated as an optimized simulation waveform, not a simple
SLM-ready actuator claim without additional smoothing/pixelization checks.

## Remaining Cleanup

- Delete the temporary machine image `fiber-raman-burst-template-mmf-20260428`
  after confirming no further MMF reruns need that exact patched image.
