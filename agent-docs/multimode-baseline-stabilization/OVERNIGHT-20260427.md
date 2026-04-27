# Overnight MMF Supervision - 2026-04-27

## Active Run

- Supervisor session: `overnight-mmf`
- Permanent burst session: `M-mmfwin3`
- Launcher log: `results/burst-logs/overnight/20260427/mmf-window-validation3.log`
- Remote wrapper log: `results/burst-logs/M-mmfwin3_20260427T055841Z.log`
- Output directory on burst: `results/raman/phase36_window_validation`
- Command:
  `MMF_VALIDATION_CASES=threshold,aggressive MMF_VALIDATION_MAX_ITER=8 MMF_VALIDATION_THRESHOLD_TW=96 MMF_VALIDATION_THRESHOLD_NT=8192 MMF_VALIDATION_AGGRESSIVE_TW=160 MMF_VALIDATION_AGGRESSIVE_NT=16384 julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl`

## Poll Log

- `2026-04-27T06:07Z`: run active on threshold case. Setup reports
  `Nt=8192`, `tw=96 ps`, `L=2 m`, `P=0.2 W`, reference `J=-17.37 dB`.
- `2026-04-27T06:17Z`: objective evaluation 1 at `-17.371 dB`; Julia RSS
  about `38.8 GB` on a `43 GiB` host, no swap.
- `2026-04-27T06:28Z`: evaluation 2 at `-17.376 dB`; memory about
  `40.9 GB RSS`, with about `3.0 GiB` available.
- `2026-04-27T06:38Z`: evaluation 3 at `-18.193 dB`; memory about
  `41.4 GB RSS`, with about `2.6 GiB` available.
- `2026-04-27T06:44Z`: evaluation 4 at `-41.394 dB`; memory dropped to about
  `36.8 GB RSS`. Treat as a candidate/line-search point until final trust
  metrics and images exist.
- `2026-04-27T06:54Z`: evaluation 5 at `-18.352 dB`; candidate improvement
  did not yet appear stable.
- `2026-04-27T07:04Z`: evaluation 6 at `-17.375 dB`; memory back near
  `41.2 GB RSS`, with about `2.8 GiB` available.
- `2026-04-27T07:05Z`: memory collapsed to about `154 MiB` available, process
  reached `44.3 GB RSS` and entered `D` state. This was treated as an imminent
  memory failure on a no-swap VM.
- `2026-04-27T07:06Z`: interrupted `M-mmfwin3` with `tmux send-keys C-c`.
  The wrapper released the heavy lock and memory recovered. No
  `phase36_window_validation` outputs had been written.
- `2026-04-27T07:06Z`: relaunched a narrower threshold-only recovery run:
  `M-mmfthr4`, launcher log
  `results/burst-logs/overnight/20260427/mmf-window-threshold4.log`, remote log
  `results/burst-logs/M-mmfthr4_20260427T070623Z.log`.
- `2026-04-27T07:10Z`: `M-mmfthr4` entered threshold setup normally with
  `max_iter=4`, `Nt=8192`, `tw=96 ps`; memory about `16.2 GB RSS`.
- `2026-04-27T07:31Z`: `M-mmfthr4` reached evaluation 1 at `-17.371 dB`;
  memory about `39.6 GB RSS`.
- `2026-04-27T07:45Z` and `2026-04-27T08:00Z`: the old local
  `overnight-mmf` supervisor retried the original high-risk `M-mmfwin3`
  command. The remote heavy lock rejected those attempts while `M-mmfthr4` was
  active. The local retry tmux session was then killed to prevent unsafe
  relaunch after recovery completion.
- `2026-04-27T07:31Z` onward: new SSH probes began timing out after connect,
  while the original `M-mmfthr4` launcher stayed attached and serial output
  showed no clean completion or new OOM message.
- `2026-04-27T08:19Z`: treated `M-mmfthr4` as a memory-failed/uninspectable run,
  reset `fiber-raman-burst`, and verified SSH/memory recovery.
- `2026-04-27T08:20Z`: relaunched threshold-only at smaller grid:
  `M-mmfthr4096`, launcher log
  `results/burst-logs/overnight/20260427/mmf-window-threshold4096.log`, remote
  log `results/burst-logs/M-mmfthr4096_20260427T082013Z.log`, command
  `MMF_VALIDATION_CASES=threshold MMF_VALIDATION_MAX_ITER=4 MMF_VALIDATION_THRESHOLD_TW=96 MMF_VALIDATION_THRESHOLD_NT=4096 julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl`.
- `2026-04-27T09:02Z`: `M-mmfthr4096` exited cleanly with rc=0. Results were
  copied back from burst to local `results/raman/phase36_window_validation/` and
  `results/burst-logs/M-mmfthr4096_20260427T082013Z.log`.
- `2026-04-27T09:04Z`: visual inspection completed for the standard image set
  and MMF-specific plots. Figures rendered correctly, but the optimized result
  is a boundary artifact: summary reports `quality=invalid-window`,
  `boundary_ok=false`, `edge_fraction=1.00e+00`, and the phase diagnostics show
  extreme noisy group delay/GDD.

## Current Interpretation

- Threshold validation at `Nt=8192` crossed into memory failure twice: once
  near evaluation 6 and again as an uninspectable host after evaluation 1 in the
  lower-iteration recovery run.
- Threshold validation at `Nt=4096`, `tw=96 ps`, `max_iter=4` completed, but
  the apparent `27.12 dB` suppression is invalid because `boundary_ok=false`.
- Memory pressure is the main risk. Neither the queued aggressive case
  (`Nt=16384`, `tw=160 ps`) nor another `Nt=8192` threshold run should be
  attempted on this VM without reducing memory footprint.
- Do not interpret the `-45.07 dB` optimized threshold result as physical
  Raman suppression. It is a numerical/window artifact under the current trust
  criteria.
- Aggressive validation was not attempted after the memory failures; on the
  current `c3-highcpu-22` VM, it should be considered blocked pending a
  larger-memory machine or lower-memory implementation.

## Recovery Criteria

- If the process exits cleanly, inspect
  `results/raman/phase36_window_validation/mmf_window_validation_summary.md`
  and verify standard image sets before deciding next steps.
- Close this overnight MMF validation loop as a negative/trust-failed result on
  current compute.
- If MMF is reopened, do not use this result as positive physics. Reopen only
  with a plan for boundary-safe parameterization, stronger phase regularization,
  or a larger-memory validation path.
- Stop permanent burst after notes are committed.
