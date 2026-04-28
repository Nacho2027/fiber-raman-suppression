# Follow-up Multivar and Long-Fiber Runs

Created 2026-04-27 after the overnight closure pass. MMF is intentionally
delegated to a separate agent; this note tracks only multivar and long-fiber
follow-up work.

## Active Runs

- Long-fiber continuation:
  - Local tmux: `followup-longfiber-200resume`
  - VM tag: `L-200resume1`
  - Machine: `c3-highcpu-8` ephemeral
  - Launcher log:
    `results/burst-logs/followup/20260427/longfiber-200resume1.log`
  - Remote command:
    `LF100_MODE=resume LF100_L=200 LF100_NT=65536 LF100_TIME_WIN=320 LF100_RUN_LABEL=200m_overngt LF100_MAX_ITER=450 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl`
  - Input pushed to VM:
    `results/raman/phase16/200m_overngt_optim`
  - Purpose: continue the non-converged 200 m result from the final checkpoint
    to see whether `J`, gradient norm, and phase diagnostics improve.

- Multivar robustness at wider amplitude bound:
  - Local tmux: `followup-multivar-delta015`
  - VM tag: `V-ampd015rob`
  - Machine: `c3-highcpu-8` ephemeral
  - Launcher log:
    `results/burst-logs/followup/20260427/multivar-delta015-robust.log`
  - Remote command:
    `MV_AMP_ROBUST_TAG_PREFIX=20260427_delta015_robust MV_AMP_PHASE_DELTA_BOUND=0.15 MV_AMP_PHASE_PHASE_ITER=35 MV_AMP_PHASE_AMP_ITER=50 bash scripts/research/multivar/run_amp_on_phase_robustness.sh`
  - Purpose: test whether the `amp_on_phase` positive result remains useful
    at nearby `(L, P)` points when the amplitude bound is widened to `δ=0.15`.

## Notes

- An initial multivar launch command was misquoted and briefly started a local
  Julia process. It was killed immediately, and the partial local result
  directory was removed:
  `results/raman/multivar/amp_on_phase_20260427T165232Z_robust_L1p8_P0p30`.
- Do not use the permanent `fiber-raman-burst` VM for these follow-ups unless
  the MMF agent is idle. It is reserved for dedicated MMF debugging/recovery.
- Expected multivar outputs are one `amp_on_phase_*` directory per robustness
  point, each with summary, JLD2/SLM sidecar, and standard images.
- Expected long-fiber outputs are `200m_overngt_opt_resume_result.jld2`,
  resumed checkpoints, and `standard_images_F_200m_overngt_resume/`.

## 2026-04-28 Status Update

- Long-fiber `L-200resume1` is still running on
  `fiber-raman-temp-l-200resume1-20260427t165232z` (`c3-highcpu-8`). Latest
  observed checkpoint was `ckpt_iter_1563.jld2`; the run is plateauing near
  `J=-53.454 dB` but the Julia process is active.
- The separate MMF agent VM
  `fiber-raman-temp-m-mmfg8192-20260428t022858z` is also running. This note
  does not supervise or mutate that VM.
- Multivar front-layer organization was updated to encode the scientific
  decision directly: `policy=direct` is the naive joint path, while
  `policy=amp_on_phase` is the staged refinement path supported by the current
  robustness results.
- New staged config:
  `configs/experiments/smf28_amp_on_phase_refinement_poc.toml`. Its compute
  plan points to `scripts/canonical/refine_amp_on_phase.jl` and requires
  standard-image inspection before closure.
