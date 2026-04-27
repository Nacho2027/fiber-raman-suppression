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
