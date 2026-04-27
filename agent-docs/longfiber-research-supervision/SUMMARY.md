# Long-Fiber Research Supervision

Campaign: `20260424T033354Z`

## Scope

This note tracks the long-fiber lane only. The active scientific objective is
to harden the 100 m single-mode result first, then decide whether a controlled
continuation ladder toward 200 m is trustworthy.

## Startup Incidents

- `L-longfiber` failed at VM startup because multivar and long-fiber raced to
  refresh/create `fiber-raman-burst-template`.
- The helper-level image race cleared; no result from this attempt is
  scientifically accepted.
- `L-longfiber2` used the fixed result-archive helper but failed at Julia
  package load because the clean remote worktree environment was not
  instantiated. The archived run log shows missing `FFTW`.
- The ops launcher fix `b449ae2` adds `Pkg.instantiate()` before executing the
  lane command in the clean remote worktree.
- `L-longfiber3` failed before simulation because the initial instantiate fix
  used single quotes inside the single-quoted `burst-spawn-temp` command path.
  Commit `cc4089a` corrected the launcher bootstrap to use double quotes.
- Rapid `L-longfiber4` and `L-longfiber5` relaunch attempts hit GCE source
  machine-image operation-rate limits. Treat these as operational failures
  only; no long-fiber science was run.

## Active Run

- Active tag: `L-200mhc8`
- Active VM: `fiber-raman-temp-l-200mhc8-20260427t060246z`
- Local supervisor tmux: `overnight-longfiber-hc8`
- Launcher log:
  `results/burst-logs/overnight/20260427/longfiber-200mhc8.log`
- Remote log:
  `results/burst-logs/L-200mhc8_20260427T060342Z.log`
- Command:
  `LF100_MODE=fresh LF100_L=200 LF100_NT=65536 LF100_TIME_WIN=320 LF100_RUN_LABEL=200m_overngt LF100_MAX_ITER=15 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl`
- Current observation at `2026-04-27T06:07Z`: VM is running, heavy lock is held
  by `L-200mhc8`, and Julia is still instantiating/precompiling packages before
  the scientific script starts.
- Observation at `2026-04-27T06:12:57Z`: precompile finished, the 200 m
  optimization started, iteration 0 reported `J = -33.94595 dB` with gradient
  norm `2.250432`, and checkpoint
  `results/raman/phase16/200m_overngt_optim/ckpt_iter_0001.jld2` was written.
- Safety copy pulled locally at `2026-04-27T06:13Z`: the checkpoint directory
  and `results/burst-logs/L-200mhc8_20260427T060342Z.log`.
- Observation at `2026-04-27T06:18:53Z`: optimizer reached displayed
  iteration 3 with visible `J = -48.00428 dB`, gradient norm `3.546717e-02`.
  Remote checkpoints now include `ckpt_iter_0001.jld2` and
  `ckpt_iter_0005.jld2`. Julia RSS was about 10 GB on `c3-highcpu-8`.
- Safety copy pulled locally at `2026-04-27T06:19Z`: checkpoint directory
  through `ckpt_iter_0005.jld2` and the remote run log.
- Observation at `2026-04-27T06:24:41Z`: optimizer still active. Visible
  iteration 5 reached `J = -52.90051 dB`, gradient norm `2.602734e-01`.
  No final JLD2 or standard images yet; latest checkpoint remained
  `ckpt_iter_0005.jld2`.
- Observation at `2026-04-27T06:30Z`: no new log line after visible iteration
  5, but the Julia process was active (`~112%` CPU, `~10 GB` RSS) with about
  `5.7 GB` memory available, so treat this as a long solve/line-search, not a
  hang.
- Observation at `2026-04-27T06:40Z`: still no new log line after visible
  iteration 5, but Julia remained CPU-active (`~112%`) and the remote tmux
  session was alive. No final artifacts yet; latest preserved checkpoint is
  still `ckpt_iter_0005.jld2`.
- Do not launch another long-fiber ephemeral while this VM is active. Respect
  C3 quota so multivar can keep one `c3-highcpu-8`.

## Verification Requirements

- Confirm `results/raman/phase16/100m_opt_full_result.jld2` is updated by the
  accepted run.
- Confirm canonical standard images under
  `results/raman/phase16/standard_images_F_100m_opt/`.
- For the active 200 m run, expected outputs are:
  `results/raman/phase16/200m_overngt_optim/`,
  `results/raman/phase16/200m_overngt_opt_full_result.jld2`,
  `results/images/physics_16_03_optimization_trace_200m_overngt.png`, and
  `results/raman/phase16/standard_images_F_200m_overngt_opt/`.
- Confirm long-fiber human plots exist or regenerate them:
  `physics_16_03_optimization_trace_100m.png`,
  `physics_16_04_phi_profile_2m_vs_100m.png`,
  `physics_16_05_Jz_comparison.png`.
- Record `J_final`, iteration count, convergence flag, gradient residual,
  energy drift, boundary fraction, and whether this strengthens or merely
  reproduces the existing 100 m claim.

## Next Decision

If `L-longfiber3` reproduces or improves the 100 m result cleanly, run one
validation pass before any 200 m extension. If it fails for a code or workflow
reason, patch the smallest longfiber-owned or ops fix and relaunch only after
the fix is committed/pushed.
