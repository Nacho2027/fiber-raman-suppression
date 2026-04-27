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

## 2026-04-27 Multivar Supervisor Notes

- Took over `overnight-multivar-seq3` at approximately 06:10 UTC.
- Confirmed local `HEAD` and `origin/main` are both `708db14`; the multivar
  driver history includes `9262f6c`, which added the segmented
  `MV_ABLATION_CASES` support.
- Current sequence command is sequential over:
  `energy_on_phase`, `amp_on_phase`, `amp_energy_on_phase`,
  `phase_energy_cold`, `phase_amp_energy_warm`, `amp_energy_unshaped`.
- The sequence is designed to wait while any `fiber-raman-temp-v-mv*`
  multivar ephemeral is active, then launch the next case with one
  `c3-highcpu-8` VM.
- At takeover there were no active multivar ephemeral VMs. The only active
  ephemeral was long-fiber:
  `fiber-raman-temp-l-200mhc8-20260427t060246z`.
- Earlier overnight multivar attempts before `seq3` are operational failures,
  not accepted science:
  `multivar-amp_on_phase.log` failed on stale SSH host-key handling/sync, and
  `multivar-energy_on_phase.log` stalled at SSH startup before the current
  `seq3` supervisor took over.
- Completion checks for each accepted case remain:
  local JLD2, JSON/SLM sidecar, `variable_ablation_summary.md`, and all four
  standard images for both the phase reference and the case result.
- `V-mvengoph3` launched `energy_on_phase` at 06:10 UTC but failed before
  Julia started. The failure was another GCP SSH host-key mismatch during the
  final `burst-run-heavy` SSH:
  `compute.724204692602831656`.
- Removed that stale known-host entry and patched local
  `~/bin/burst-spawn-temp` to pass gcloud's native
  `--strict-host-key-checking=no` to both SSH and SCP calls, in addition to
  the raw `-o StrictHostKeyChecking=no`/`UserKnownHostsFile=/dev/null` flags.
- The original `overnight-multivar-seq3` session exited after the failed case;
  resume should relaunch `energy_on_phase` first with a new tag, not advance to
  `amp_on_phase`.
- `V-mvengoph4` was launched by the overnight sequence at 06:15 UTC as the
  `energy_on_phase` retry. It passed SSH, acquired the heavy lock, and is
  running on `fiber-raman-temp-v-mvengoph4-20260427t061540z`.
- At approximately 06:19 UTC it was still in the clean-worktree
  `Pkg.instantiate()`/precompile phase (`131/142` packages), so no scientific
  output was expected yet.
- `V-mvengoph4` completed with `rc=0` and synced results, but the actual
  `energy_on_phase` case is not scientifically complete. It saved only the
  phase-only reference artifacts; the energy case row is
  `energy_on_phase__FAILED` because the optimizer stepped to invalid negative
  raw energy. Local and current remote `origin/main` now contain the
  log-energy-coordinate fix (`4d426df Stabilize overnight multivar energy
  runs`), so this case should be rerun later with a fresh tag after the active
  multivar VM finishes.
- `V-mvampoph4` launched `amp_on_phase` at approximately 06:29 UTC and is the
  only active multivar VM. At approximately 06:32 UTC it was still in
  dependency precompile (`116/142` packages).
- `V-mvampoph4` completed with `rc=0` and synced results. Local completion
  check passed: `amp_on_phase_result.jld2`, `amp_on_phase_slm.json`,
  `variable_ablation_summary.md`, and the phase/case standard image sets are
  present under
  `results/raman/multivar/variable_ablation_overnight_amp_on_phase_20260427/`.
  Result: `amp_on_phase` reached `J_after=-46.91 dB`, beating the phase-only
  reference by `-6.12 dB`.
- Relaunched the failed energy case as `V-mvengoph5` with
  `MV_ABLATION_TAG=overnight_energy_on_phase_retry1_20260427` and launcher log
  `results/burst-logs/overnight/20260427/multivar-energy_on_phase-retry1.log`.
  This is the only active multivar launch at the time of relaunch.
- `V-mvengoph5` passed SSH, acquired the heavy lock, and is running from clean
  worktree `e441f8e`. Verified the remote worktree has the log-energy
  coordinate (`E = exp(...)`) before optimization starts. At approximately
  06:45 UTC it was still in package precompile.
- `V-mvengoph5` completed with `rc=0` and synced results. Local completion
  check passed under
  `results/raman/multivar/variable_ablation_overnight_energy_on_phase_retry1_20260427/`:
  `energy_on_phase_result.jld2`, `energy_on_phase_slm.json`,
  `variable_ablation_summary.md`, and both phase/case standard image sets are
  present. Result: `energy_on_phase` reached `J_after=-44.89 dB`, beating the
  phase-only reference by `-4.10 dB`.
- Restarted the remaining sequence as `overnight-multivar-seq5`, beginning
  with `amp_energy_on_phase` and leaving already-completed `energy_on_phase`
  and `amp_on_phase` out of the sequence.
- `V-mvampeoph5` completed `amp_energy_on_phase` with `rc=0` and synced
  results. Local completion check passed under
  `results/raman/multivar/variable_ablation_overnight_amp_energy_on_phase_20260427/`.
  Result: `J_after=-43.99 dB`, beating phase-only by `-3.19 dB` but not
  matching amplitude-only's `-6.12 dB` gain.

## 2026-04-27 06:36 UTC Supervisor Check

- Active quota mix is correct: permanent `fiber-raman-burst` plus two
  `c3-highcpu-8` ephemerals:
  `fiber-raman-temp-l-200mhc8-20260427t060246z` and
  `fiber-raman-temp-v-mvampoph4-20260427t062900z`.
- Deterministic watchdog cron is still installed at 15 minute cadence and was
  not modified.
- MMF `M-mmfwin3` is alive on permanent burst. Remote log reached the
  threshold case, iteration 3, with Julia still running.
- Long-fiber `L-200mhc8` is alive on the 200 m ephemeral. Remote log shows the
  200 m fresh run reached iteration 5 with `f=-5.290051e+01`; checkpoints were
  written through `ckpt_iter_0005.jld2`.
- `V-mvengoph4` completed and synced results, but the `energy_on_phase` case is
  still not accepted. The remote run used stale commit `708db14`, not
  `4d426df`, and failed with the old negative-energy assertion. Only the
  phase-only reference artifacts exist under
  `results/raman/multivar/variable_ablation_overnight_energy_on_phase_20260427/`.
  Because no `energy_on_phase_result.jld2` exists, the watchdog/sequence can
  safely retry this case later.
- Current `V-mvampoph4` was verified on commit `4d426df` and includes the
  log-energy fix. It is running `amp_on_phase`; no intervention needed.

## 2026-04-27 Codex Cron Supervisor

- Added `scripts/ops/codex_overnight_check.sh`, a `flock`-guarded wrapper
  around `/home/ignaciojlizama/.npm-global/bin/codex exec`.
- Installed cron alongside the deterministic watchdog:
  deterministic checks run every 15 minutes, and Codex research-supervisor
  checks run every 30 minutes.
- Codex supervisor prompt:
  `agent-docs/overnight-research-supervision/CODEX_WATCHDOG_PROMPT.md`.
- Logs:
  `results/burst-logs/overnight/20260427/codex-watchdog.log`,
  `results/burst-logs/overnight/20260427/codex-cron.log`, and
  `results/burst-logs/overnight/20260427/codex-watchdog-last-message.md`.
- The wrapper uses a 25 minute timeout so the 30 minute cron cadence cannot
  accumulate overlapping Codex agents. If an older check is still active, the
  next check skips due to the lock.

## 2026-04-27 07:04 UTC Supervisor Check

- Active quota mix remains within plan: permanent `fiber-raman-burst` plus
  exactly two `c3-highcpu-8` ephemerals,
  `fiber-raman-temp-l-200mhc8-20260427t060246z` and
  `fiber-raman-temp-v-mvampeoph5-20260427t065658z`.
- Deterministic watchdog cron is still installed at 15 minute cadence and was
  not modified.
- Syncthing health check showed both configured peers disconnected at
  `2026-04-27T07:00Z`; this does not block remote execution, but Mac-side
  result visibility may lag until a peer reconnects.
- MMF `M-mmfwin3` is alive on permanent burst. Remote log reached the
  threshold case, iteration 6, with Julia still running.
- Long-fiber `L-200mhc8` is alive on the 200 m ephemeral. Remote log reached
  optimizer iteration 7 with `f=-5.290096e+01`; checkpoints have been written
  through `ckpt_iter_0094.jld2`.
- Multivar advanced to `overnight-multivar-seq5`, launching
  `amp_energy_on_phase` as `V-mvampeoph5`. The VM is running from commit
  `b68e6f3`, which contains the `4d426df` log-energy fix. The run passed
  package precompile, created
  `V-mvampeoph5_20260427T065748Z.log`, and started the phase-only reference.
- No failure, patch, or relaunch was needed during this check.

## 2026-04-27 07:34 UTC Supervisor Check

- Active quota mix remains within plan: permanent `fiber-raman-burst` plus
  exactly two `c3-highcpu-8` ephemerals,
  `fiber-raman-temp-l-200mhc8-20260427t060246z` and
  `fiber-raman-temp-v-mvpheng5-20260427t071137z`.
- Deterministic watchdog cron remains installed at 15 minute cadence and was
  not modified.
- Syncthing still reports both configured peers disconnected as of the local
  check at `2026-04-27T07:30Z`; remote runs are unaffected, but Mac-side result
  visibility may lag.
- `amp_energy_on_phase` completed and synced before this check. The result
  files and standard images are present under
  `results/raman/multivar/variable_ablation_overnight_amp_energy_on_phase_20260427/`.
  Visual inspection of the four `amp_energy_on_phase` standard images found no
  blank/corrupt plots; keep the usual caveat that the phase/group-delay
  diagnostic is rough rather than lab-ready.
- Multivar `phase_energy_cold` launched as `V-mvpheng5` at approximately
  07:11 UTC and is running from commit `b68e6f3`. Verified the remote
  `multivar_optimization.jl` contains the log-energy coordinate
  (`E = exp(...)`), so the known negative-energy line-search bug is not present.
  The run has completed its phase-only reference and is in the multivar case.
- Long-fiber `L-200mhc8` is alive on the 200 m ephemeral. Remote log reached
  optimizer iteration 10 with `f=-5.291271e+01`; checkpoints exist through
  `ckpt_iter_0100.jld2`. No intervention needed.
- MMF `M-mmfwin3` ended with launcher `rc=0`, but the remote log stops during
  the threshold case and no `phase36_window_validation` artifacts were present
  on permanent burst. The deterministic watchdog correctly noticed the missing
  summary and restarted MMF, but the full `M-mmfwin3` relaunch is currently
  blocked by a live threshold-only recovery job `M-mmfthr4` holding the burst
  heavy lock. `M-mmfthr4` is consuming CPU and memory, so it was left running.
- No source patch, commit, or relaunch was performed during this check.

## 2026-04-27 08:05 UTC Supervisor Check

- Active quota mix remains within plan: permanent `fiber-raman-burst` plus
  exactly two `c3-highcpu-8` ephemerals,
  `fiber-raman-temp-l-200mhc8-20260427t060246z` and
  `fiber-raman-temp-v-mvpheng5-20260427t071137z`.
- Deterministic watchdog cron remains installed at 15 minute cadence and was
  not removed. Syncthing still reports both configured peers disconnected as of
  `2026-04-27T08:00Z`.
- Long-fiber `L-200mhc8` is alive on the 200 m ephemeral. The remote log has
  reached optimizer iteration 12 with `f=-5.297767e+01`; checkpoints synced
  locally through `ckpt_iter_0181.jld2`.
- Multivar `phase_energy_cold` is alive on
  `fiber-raman-temp-v-mvpheng5-20260427t071137z`. The clean worktree is
  `b68e6f3`, which includes the log-energy fix; the phase-only reference and
  standard images were written, and the multivar case is running.
- MMF remains the only operational concern. Permanent-burst SSH inspection
  timed out during banner exchange, while local `M-mmfthr4` threshold recovery
  and the watchdog-started `M-mmfwin3` launcher were both still attached. No
  `phase36_window_validation` artifacts are local yet.
- Patched `scripts/ops/overnight_research_watchdog.sh` so it detects active
  local MMF launchers (`parallel_research_lane.sh --lane mmf` or
  `burst-run-heavy M-mmf*`) before starting another full `overnight-mmf`
  supervisor. This prevents repeated full-MMF relaunch attempts while the
  threshold-only recovery is still active.
