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

## Current Interpretation

- Threshold validation at `max_iter=8` was alive but crossed into imminent
  memory failure before producing outputs. The active recovery path is
  threshold-only at `max_iter=4`.
- Memory pressure is the main risk. The threshold case nearly saturated the
  `c3-highcpu-22` memory budget, so the queued aggressive case (`Nt=16384`,
  `tw=160 ps`) should not be run in the same configuration on this VM.
- Do not launch another permanent-burst heavy job while `M-mmfwin3` holds the
  heavy lock.
- Do not interpret the transient `-41 dB` evaluation as science until the
  script writes `mmf_window_validation_summary.md`, JLD2 artifacts, and the
  required standard image set.

## Recovery Criteria

- If the process exits cleanly, inspect
  `results/raman/phase36_window_validation/mmf_window_validation_summary.md`
  and verify standard image sets before deciding next steps.
- If `M-mmfthr4` OOMs or is killed before writing outputs, relaunch threshold
  with a smaller memory footprint, for example `MMF_VALIDATION_THRESHOLD_NT=4096`
  while keeping `MMF_VALIDATION_THRESHOLD_TW=96` if the science goal remains
  window validation.
- If threshold completes but aggressive OOMs, preserve threshold outputs and
  relaunch aggressive separately with a lower-memory configuration rather than
  rerunning threshold.
- After final completion, pull burst results back explicitly before relying on
  local `results/`.
