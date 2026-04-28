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

## 2026-04-27 08:25 UTC Multivar Supervisor Note

- Multivar-only supervision remained within quota discipline: one active
  multivar ephemeral,
  `fiber-raman-temp-v-mvpheng5-20260427t071137z`, while the long-fiber
  ephemeral continued separately.
- `phase_energy_cold` is still running rather than failed. The remote Julia
  process has been CPU-active for roughly 66 minutes, with RSS around 4.1 GB
  and no runaway memory. The heavy log has not grown since the case entered
  `phase_energy_cold`, which is expected to be much harder than the prior
  on-phase amplitude/energy cases because it is a cold-start 8193-variable
  phase+log-energy L-BFGS solve.
- Existing artifacts for the run are only the shared phase-only reference:
  JLD2/JSON/trust report plus the four standard phase-only images. No
  `phase_energy_cold_*` result files or standard images exist yet, so this
  case is not scientifically complete.
- Decision: do not kill or relaunch yet. Let the active run continue under
  10-20 minute polling unless it stops consuming CPU, fails, exhausts memory,
  or blocks the sequence for an unreasonable additional interval.
- Follow-up operational fix: pushed commit `07a53a6`
  (`Log multivar optimizer progress`) so future clean-worktree multivar runs
  emit INFO-level progress every five optimizer iterations by default. This
  does not affect the already-running `V-mvpheng5` process.

## 2026-04-27 09:25 UTC Multivar Supervisor Note

- `phase_energy_cold` was stopped intentionally after roughly two hours of
  CPU-active runtime with no first optimizer callback, no log growth after
  entering the case, and no `phase_energy_cold_*` artifacts. Treat this attempt
  as an incomplete/pathological cold-start optimizer result, not as accepted
  science.
- The helper synced the partial results and destroyed the VM cleanly. The only
  valid artifacts under
  `results/raman/multivar/variable_ablation_overnight_phase_energy_cold_20260427/`
  are the phase-only reference JLD2/JSON/trust report and four phase-only
  standard images.
- Pushed two instrumentation commits for future runs:
  `07a53a6` adds INFO-level optimizer iteration progress, and `e1ae5e7` adds
  INFO-level objective-evaluation progress so long line searches are visible
  before the first callback.
- Seq5 continued with exactly one multivar ephemeral:
  `phase_amp_energy_warm` as `V-mvphampe5` on
  `fiber-raman-temp-v-mvphampe5-20260427t092141z`. Remote clean worktree is
  `e1ae5e7`; the run is currently in Julia precompile.

## 2026-04-27 09:40 UTC Multivar Supervisor Note

- `phase_amp_energy_warm` completed and synced cleanly. Required artifacts are
  present: JLD2, SLM JSON, summary markdown, and all four standard images for
  both the phase-only reference and the case.
- Scientific status: accepted negative result. The warm full
  phase+amplitude+energy run reached `J_after = -31.04 dB`, which is
  `+9.75 dB` worse than phase-only. The standard images render correctly; the
  phase diagnostics show a high-curvature phase/GDD profile, consistent with
  the worse scalar objective.
- Seq5 launched the final planned case, `amp_energy_unshaped`, as
  `V-mvampeun5` on
  `fiber-raman-temp-v-mvampeun5-20260427t093636z`. It is the only active
  multivar ephemeral.

## 2026-04-27 10:40 UTC Multivar Supervisor Note

- The uncapped `amp_energy_unshaped` attempt (`V-mvampeun5`) reached iteration
  15/50, then spent more than 400 objective evaluations with essentially
  unchanged objective near `6.8343e-01`. It was stopped as a line-search
  pathology and is not accepted because no `amp_energy_unshaped_*` case
  artifacts were written.
- Stopping `V-mvampeun5` exposed an interrupted-run sync bug in
  `~/bin/burst-spawn-temp` (`remote_archive: unbound variable`). The VM was
  destroyed, so the interrupted attempt could not be manually recovered. The
  helper was hardened locally by renaming and guarding result archive paths in
  `sync_results`; `bash -n ~/bin/burst-spawn-temp` passes.
- Pushed commit `e617e05` adding `MV_OPT_F_CALLS_LIMIT` and
  `MV_OPT_TIME_LIMIT_S` to the multivar optimizer. Launched one capped retry,
  `V-mvampeun6`, with `MV_OPT_F_CALLS_LIMIT=220` and
  `MV_OPT_TIME_LIMIT_S=1800` under tag
  `overnight_amp_energy_unshaped_retry1_20260427`.
- `V-mvampeun6` confirmed that Optim's function-call cap does not interrupt
  this long line-search path early enough to write case artifacts. It was
  stopped after reproducing the same plateau and synced only phase-only
  artifacts.
- Launched final artifact-producing retry `V-mvampeun7` with
  `MV_ABLATION_MV_ITER=15` under tag
  `overnight_amp_energy_unshaped_retry2_20260427`, targeting the last useful
  optimizer state before the previously observed line-search pathology.

## 2026-04-27 11:50 UTC Multivar Supervisor Note

- `V-mvampeun7` also exited with launcher `rc=0` but wrote only the
  phase-only reference; no `amp_energy_unshaped_result.jld2`, SLM JSON, or
  standard images were produced. The heavy log ends during the multivar case
  after early eval/progress messages, with no explicit Julia exception.
- Status: `amp_energy_unshaped` remains scientifically incomplete and should
  not be accepted. Given the earlier uncapped plateau and two retries that
  failed to emit case artifacts, treat this as a low-priority optimizer/lane
  failure for now rather than spending more overnight VMs.
- No multivar ephemerals remain running after `V-mvampeun7`; the multivar
  overnight sequence is complete except for the explicitly incomplete
  `phase_energy_cold` and `amp_energy_unshaped` lanes.

## 2026-04-27 09:07 UTC MMF Recovery Result

- Reduced MMF threshold recovery `M-mmfthr4096` completed on permanent
  `fiber-raman-burst` with launcher `rc=0`. The remote log
  `M-mmfthr4096_20260427T082013Z.log` was pulled back locally together with
  `results/raman/phase36_window_validation/`.
- Local completion check passed for the reduced `Nt=4096`, `tw=96 ps`
  threshold run: `mmf_window_validation_summary.md`, the four standard images
  (`phase_profile`, `evolution`, `phase_diagnostic`,
  `evolution_unshaped`), and the baseline convergence/spectrum plots are
  present.
- Visual inspection of the four standard images found no blank or corrupt
  plots. The optimized spectrum overlays the input and reports strong Raman
  suppression, but the phase/group-delay diagnostic is extremely rough and the
  run summary marks the case `quality=invalid-window`, `boundary_ok=false`,
  `edge=1.00e+00`.
- Result: `J_ref=-17.96 dB`, `J_opt=-45.07 dB`, nominal improvement
  `27.12 dB`. Treat this as evidence that the current Phase 36 threshold MMF
  gain remains a numerical-window artifact at this enlarged window, not as an
  accepted MMF science result.

## 2026-04-27 09:32 UTC Supervisor Check

- Active quota mix is within plan: exactly two `c3-highcpu-8` ephemerals are
  running, `fiber-raman-temp-l-200mhc8-20260427t060246z` for long-fiber and
  `fiber-raman-temp-v-mvphampe5-20260427t092141z` for multivar. The permanent
  `fiber-raman-burst` VM is terminated after the reduced MMF recovery.
- Long-fiber `L-200mhc8` is alive and CPU-active. The 200 m run reached
  optimizer iteration 14 of 15 with `f=-52.97757 dB` and checkpointed through
  `ckpt_iter_0310.jld2`; no intervention was needed.
- Multivar `phase_amp_energy_warm` is alive on clean worktree `e1ae5e7`, which
  includes the log-energy fix and progress instrumentation. The phase-only
  reference completed and standard images were written; the multivar case is
  still running.
- MMF is not relaunched because
  `results/raman/phase36_window_validation/mmf_window_validation_summary.md`
  exists and the reduced threshold recovery result is already accepted only as
  an `invalid-window` caveat.
- Patched `scripts/ops/overnight_research_watchdog.sh` so the deterministic
  watchdog recognizes any `overnight-multivar-seq*` supervisor, including the
  active `overnight-multivar-seq5`. This prevents an older seq4 relaunch after
  the active multivar VM exits.

## 2026-04-27 10:03 UTC Supervisor Check

- Active quota mix is below the intended maximum: permanent
  `fiber-raman-burst` is terminated and the only running C3 ephemeral is
  `fiber-raman-temp-v-mvampeun5-20260427t093636z` for multivar.
- Syncthing still reports both configured peers disconnected as of
  `2026-04-27T10:03Z`; local execution and GCE result recovery are unaffected,
  but Mac-side result visibility may lag.
- Long-fiber 200 m completed its 15-iteration fresh run and was finalized by
  recovery job `L-200rec1` after the original launcher hit a local
  `burst-spawn-temp` quoting error. The recovery job exited `rc=0`, synced
  `200m_overngt_opt_full_result.jld2`, checkpoints through
  `ckpt_iter_0381_final.jld2`, and all four standard images under
  `results/raman/phase16/standard_images_F_200m_overngt_opt/`.
- Visual inspection of the 200 m standard image set found no blank or corrupt
  plots. Scientific caveat: the result is non-converged (`J=-52.98 dB`,
  gradient norm `9.55e-01`) and the phase/group-delay diagnostics are very
  rough, so treat it as exploratory 200 m evidence rather than a validated
  long-fiber workflow result.
- Stopped stale local tmux session `overnight-longfiber-hc8`; it was only
  polling the destroyed original long-fiber VM after successful recovery.
- Multivar `amp_energy_unshaped` is alive on clean commit `cc4458d`, which
  contains the `4d426df` log-energy fix. Remote Julia is CPU-active, the
  phase-only reference artifacts are written, and the case is emitting
  progress/evaluation logs; no intervention was needed.
- MMF remains closed as the reduced threshold `invalid-window` caveat from
  `M-mmfthr4096`; no relaunch was performed.

## 2026-04-27 11:45 UTC Supervisor Check

- Active quota mix ended below the intended maximum: permanent
  `fiber-raman-burst` is terminated and no `c3-highcpu-8` ephemerals are
  running after the multivar retry completed.
- Stopped `V-mvampeun7` (`overnight_amp_energy_unshaped_retry2_20260427`)
  after it reproduced the `amp_energy_unshaped` line-search pathology: one
  accepted step, then repeated objective evaluations at essentially unchanged
  `J≈7.0126e-01` with only phase-only artifacts written. The helper synced
  partial artifacts and destroyed the VM cleanly.
- Relaunched the same final planned multivar case as `V-mvampeun8` with
  `MV_ABLATION_MV_ITER=1` under tag
  `overnight_amp_energy_unshaped_retry3_20260427`, intentionally capturing the
  last useful accepted state before the pathological second line search. The
  launcher exited `rc=0` and synced results.
- Local completion check passed for
  `results/raman/multivar/variable_ablation_overnight_amp_energy_unshaped_retry3_20260427/`:
  `amp_energy_unshaped_result.jld2`, `amp_energy_unshaped_slm.json`,
  `variable_ablation_summary.md`, and all four standard images for both the
  phase reference and the case are present.
- Visual inspection of the phase reference and one-step case standard images
  found no blank or corrupt plots. Scientific status: accepted negative/caveat
  result, not a useful optimizer outcome. The one-step unshaped
  amplitude+energy case reached `J_after=-1.54 dB`, only `-0.04 dB` better
  than unshaped and `+39.25 dB` worse than phase-only.

## 2026-04-27 12:00 UTC Multivar Final Status

- No multivar ephemeral VMs are running. The final VM inventory returned
  `no ephemeral burst VMs found`, so there is no quota leak or orphan to clean
  up.
- Accepted positive multivar results: `amp_on_phase` (`J_after=-46.91 dB`,
  `vs_phase=-6.12 dB`), `energy_on_phase` retry
  (`J_after=-44.89 dB`, `vs_phase=-4.10 dB`), and
  `amp_energy_on_phase` (`J_after=-43.99 dB`, `vs_phase=-3.19 dB`).
- Accepted negative multivar results: `phase_amp_energy_warm`
  (`J_after=-31.04 dB`, `vs_phase=+9.75 dB`) and
  `amp_energy_unshaped` retry3 (`J_after=-1.54 dB`,
  `vs_phase=+39.25 dB`). `amp_energy_unshaped` is scientifically closed as a
  negative/caveat result because the artifact-producing one-step retry captures
  the last useful accepted state before the repeated line-search pathology.
- Incomplete/not accepted: `phase_energy_cold` remains a pathological
  cold-start optimizer case. It produced only the phase-only reference and was
  manually stopped after remaining CPU-active for roughly two hours with no
  multivar artifacts or progress callback.
- Standard image/artifact status: all accepted results have local JLD2, SLM
  JSON, `variable_ablation_summary.md`, and standard images for the case and
  phase reference. The incomplete `phase_energy_cold` directory intentionally
  has only phase-reference artifacts.

## 2026-04-27 14:31 UTC Supervisor Check

- GCE inventory is clean for the research lanes: `fiber-raman-burst` is
  `TERMINATED`, and no `fiber-raman-temp-*` C3 ephemerals are running.
- Local process check found no active Julia, `burst-spawn-temp`,
  `burst-run-heavy`, `rsync`, VM-create, or `parallel_research_lane` jobs.
- Closed two stale local multivar tmux sessions,
  `overnight-multivar-energy-retry` and `overnight-multivar-seq5`, after
  verifying both were sitting at shell prompts from completed jobs.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  was not modified. The optional Codex watchdog cron also remains installed.
- No relaunch was needed. MMF remains closed as the documented reduced
  threshold `invalid-window` caveat, long-fiber 200 m artifacts and standard
  images are present, and the accepted multivar result directories each have
  the expected case/phase standard images.

## 2026-04-27 15:05 UTC Supervisor Check

- The deterministic watchdog restarted `overnight-multivar-seq4` at 14:45 UTC
  because it did not recognize the already accepted retry/caveat multivar
  outputs. This produced a duplicate `energy_on_phase` run under the original
  `overnight_energy_on_phase_20260427` tag; it completed with `rc=0` from
  commit `d1c7fc0`, which contains the log-energy coordinate fix. Local
  artifacts now include `energy_on_phase_result.jld2`, SLM JSON, summary
  markdown, and the phase/case standard image sets; PNG statistics show the
  images are nonblank.
- The same restarted sequence began `phase_energy_cold` as `V-mvpheng4` on
  `fiber-raman-temp-v-mvpheng4-20260427t145606z`. Because this case was
  already documented as a pathological cold-start caveat and the active seq4
  body would later relaunch the already-closed original `amp_energy_unshaped`
  case, the redundant remote tmux job was stopped before it reached the
  multivar case. `burst-spawn-temp` synced partial logs/results and destroyed
  the VM cleanly.
- Patched `scripts/ops/overnight_research_watchdog.sh` so it recognizes the
  accepted multivar retry/caveat outputs: `energy_on_phase_retry1`,
  `phase_energy_cold` as an accepted incomplete caveat, and
  `amp_energy_unshaped_retry3`. `bash -n` passed, per-case completion checks
  returned success, and a manual watchdog pass reported
  `multivar sequence already closed by accepted results/caveats; not
  restarting`.
- Final inventory after cleanup: `fiber-raman-burst` is `TERMINATED`, no
  `fiber-raman-temp-*` ephemerals are running, and no overnight tmux supervisor
  sessions or burst helper processes remain active.

## 2026-04-27 17:35 UTC Supervisor Check

- Active quota mix is within limits: permanent `fiber-raman-burst` is running
  for MMF recovery, and the only `c3-highcpu-8` ephemeral is
  `fiber-raman-temp-l-200resume1-20260427t165232z` for the 200 m long-fiber
  continuation. No multivar ephemeral is running.
- MMF recovery `M-mmffix` is alive on permanent burst with
  `MMF_VALIDATION_CASES=threshold`, `MMF_VALIDATION_MAX_ITER=4`,
  `MMF_VALIDATION_THRESHOLD_TW=96`, and `MMF_VALIDATION_THRESHOLD_NT=4096`.
  The remote log `M-mmffix_20260427T171823Z.log` reached optimizer iteration
  2; no intervention was needed.
- Long-fiber continuation `L-200resume1` is alive on commit `6240464`, which is
  newer than the multivar log-energy fix. It resumed from
  `ckpt_iter_0381.jld2` with `f=-52.97751 dB` and improved to
  `f=-53.18840 dB` by optimizer step 2. The run emitted the expected
  interpolation caveat that the `Nt=65536`, `tw=320 ps` resume grid drops much
  of the previous spectral range; keep this caveat when interpreting final
  artifacts.
- Follow-up multivar robustness `V-ampd015rob` completed with `rc=0`, synced
  results, and destroyed its VM. All four nearby `δ=0.15` amplitude-on-phase
  points passed the 3 dB threshold, with gains vs phase-only from `8.41 dB` to
  `10.84 dB`; each directory has JLD2, SLM JSON, summary markdown, and the
  phase/case standard image sets. Representative weakest/best image sets were
  visually inspected and were not blank or corrupt; diagnostics remain rough
  but interpretable.

## 2026-04-27 18:05 UTC Supervisor Check

- Active quota mix is below limit after cleanup: `fiber-raman-burst` is
  `TERMINATED`, and the only active C3 ephemeral is
  `fiber-raman-temp-l-200resume1-20260427t165232z` for the 200 m long-fiber
  continuation. No multivar ephemeral is running.
- MMF recovery `M-mmffix` completed and synced local artifacts. The summary
  reports `quality=invalid-window`, `boundary_ok=false`, `J_ref=-17.96 dB`,
  `J_opt=-45.07 dB`, nominal `27.12 dB` improvement, and edge fraction
  `5.02e-02`. The four standard images were visually inspected and were not
  blank or corrupt, but the phase/group-delay diagnostic is extremely rough;
  keep this closed as a numerical-window caveat rather than accepted MMF
  science. Permanent burst was stopped after verifying no remote MMF Julia,
  tmux, or heavy-lock process remained.
- Long-fiber continuation `L-200resume1` is still alive and CPU-active. It has
  checkpointed through `ckpt_iter_0480.jld2` and improved from the resumed
  `f=-52.97751 dB` to `f=-53.44527 dB` by optimizer step 5. The prior
  interpolation caveat still applies: the `Nt=65536`, `tw=320 ps` resume grid
  drops about 68% of the stored spectral range.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  was not modified.

## 2026-04-27 18:35 UTC Supervisor Check

- Active quota mix remains controlled: `fiber-raman-burst` is `TERMINATED`,
  the 200 m long-fiber continuation is running on one `c3-highcpu-8`
  ephemeral, and MMF boundary follow-up `M-mmfbnd` is running on one
  `c3-highcpu-22` ephemeral. No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active on commit `8b14314`. The
  run remains non-final and has checkpointed through `ckpt_iter_0547.jld2`;
  latest logged optimizer value is still near `f=-53.44522 dB` at step 6. Keep
  the existing caveat that the resume grid drops about 68% of the stored
  spectral range.
- MMF boundary follow-up `M-mmfbnd` is alive and CPU-active on commit
  `e2ba301` with `MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_boundary`,
  threshold-only `Nt=4096`, `tw=96 ps`, `MMF_VALIDATION_MAX_ITER=4`, and
  `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05`. The clean worktree contains
  `scripts/research/mmf/mmf_window_validation.jl`; the active remote log
  `M-mmfbnd_20260427T182906Z.log` has reached MMF setup with no failure yet.
  Treat this as a boundary-diagnostic follow-up to the invalid-window MMF
  caveat, not accepted MMF science until artifacts and standard images are
  synced and inspected.
- Multivar remains closed with the previously documented accepted/caveat
  outputs. The 15 minute deterministic watchdog cron remains installed and was
  not modified.

## 2026-04-27 19:02 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`, long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF boundary follow-up `M-mmfbnd` is running on one
  `c3-highcpu-22`. No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active on commit `8b14314`. It
  has checkpointed through `ckpt_iter_0611.jld2`; latest logged optimizer value
  is `f=-53.44516 dB` at step 7. The prior resume-grid caveat still applies:
  about 68% of the stored spectral range is dropped by the `Nt=65536`,
  `tw=320 ps` continuation grid.
- MMF boundary follow-up `M-mmfbnd` is alive and CPU-active on commit
  `8b14314` with `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05`. The run has progressed
  through objective evaluation 19, with the latest logged boundary-penalized
  objective `J=-31.92284 dB`; no artifacts are synced yet because the remote
  job is still running.
- Multivar remains closed. The deterministic watchdog cron is still installed
  at the 15 minute cadence and is reporting `multivar sequence already closed
  by accepted results/caveats; not restarting`.

## 2026-04-27 19:33 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`, long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF follow-up `M-mmfgdd` is running on one
  `c3-highcpu-22`. No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active on commit `47546d3`, which
  contains the `4d426df` multivar log-energy fix. It has checkpointed through
  `ckpt_iter_0677.jld2`; latest logged optimizer value is `f=-53.44511 dB` at
  step 8. Keep the existing caveat that the `Nt=65536`, `tw=320 ps` continuation
  grid drops about 68% of the stored spectral range.
- MMF boundary-only follow-up `M-mmfbnd` completed and synced local artifacts.
  Summary status is now `quality=meaningful`, `boundary_ok=true`,
  `J_ref=-17.96 dB`, `J_opt=-45.04 dB`, nominal `27.09 dB` improvement, and
  edge fraction `2.74e-07`. The four standard images were visually inspected
  and were not blank or corrupt; the phase/group-delay diagnostic remains very
  rough, so treat this as a promising MMF follow-up result that still needs the
  active GDD regularization check before promotion.
- MMF GDD-regularized follow-up `M-mmfgdd` is alive and CPU-active on commit
  `47546d3` with `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05` and
  `MMF_VALIDATION_LAMBDA_GDD=1e-4`. The remote log has reached MMF setup and the
  objective surface announcement; no local artifacts are synced yet because the
  job is still running.
- Multivar remains closed with accepted/caveat outputs, and the deterministic
  watchdog cron remains installed at the 15 minute cadence.

## 2026-04-27 20:33 UTC Supervisor Check

- Active C3 quota is back down to `C3_CPUS usage=8 limit=50`: only long-fiber
  `L-200resume1` is running on one `c3-highcpu-8`. `fiber-raman-burst` is
  `TERMINATED`, the MMF GDD `c3-highcpu-22` ephemeral is gone, and no multivar
  ephemeral is running.
- MMF GDD follow-up `M-mmfgdd` completed and synced local artifacts under
  `results/raman/phase36_window_validation_gdd/`. Summary status is
  `quality=meaningful`, `boundary_ok=true`, `J_ref=-17.96 dB`,
  `J_opt=-49.69 dB`, nominal `31.73 dB` improvement, and edge fraction
  `2.07e-11`. The four standard images were visually inspected and are
  nonblank; the GDD regularization cleaned up the temporal-edge issue, but the
  optimized phase/GDD diagnostics remain oscillatory, so keep this as a
  promising follow-up result rather than final MMF science.
- Long-fiber `L-200resume1` is alive and CPU-active. The active run worktree is
  commit `6240464`, which contains the `4d426df` multivar log-energy fix. It
  has checkpointed through `ckpt_iter_0800.jld2`; latest logged optimizer value
  is `f=-53.45438 dB` at step 11. The previous caveat still applies: the
  `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- Multivar remains closed with accepted/caveat outputs. No relaunch was needed,
  and the deterministic watchdog cron remains installed at the 15 minute
  cadence.

## 2026-04-27 21:05 UTC Supervisor Check

- Active C3 quota remains controlled: only
  `fiber-raman-temp-l-200resume1-20260427t165232z` is running as a
  `c3-highcpu-8` ephemeral. `fiber-raman-burst` is `TERMINATED`, and no MMF or
  multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active. Remote Julia has been
  running for about four hours on commit `6240464`; the optimizer reached step
  12 with `f=-53.45484 dB` and checkpointed through
  `ckpt_iter_0810.jld2`. The existing resume-grid caveat still applies: the
  `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- MMF remains closed with the documented GDD follow-up artifacts under
  `results/raman/phase36_window_validation_gdd/`; the expected summary and
  standard image files are still present. Multivar remains closed with the
  accepted positive/negative results and the documented incomplete
  `phase_energy_cold` caveat.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  continues to report the multivar sequence closed by accepted
  results/caveats. No failure, patch, or relaunch was needed during this
  check.

## 2026-04-27 21:32 UTC Supervisor Check

- Active C3 quota remains controlled: only
  `fiber-raman-temp-l-200resume1-20260427t165232z` is running as a
  `c3-highcpu-8` ephemeral. `fiber-raman-burst` is `TERMINATED`, and no MMF or
  multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active on commit `6240464`, which
  contains the `4d426df` multivar log-energy fix. The optimizer has advanced to
  step 13 with `f=-53.45479 dB` and checkpointed through
  `ckpt_iter_0872.jld2`. The existing resume-grid caveat still applies: the
  `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- MMF remains closed with the GDD follow-up artifacts under
  `results/raman/phase36_window_validation_gdd/`. Multivar remains closed with
  accepted/caveat outputs, and no active multivar VM is present.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  reports the multivar sequence closed by accepted results/caveats. No failure,
  patch, or relaunch was needed during this check.

## 2026-04-27 22:02 UTC Supervisor Check

- Active quota mix remains controlled: only
  `fiber-raman-temp-l-200resume1-20260427t165232z` is running as a
  `c3-highcpu-8` ephemeral. `fiber-raman-burst` is `TERMINATED`, and no MMF or
  multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on run
  worktree commit `6240464`, which is newer than the `4d426df` multivar
  log-energy fix. The optimizer has advanced to step 14 with
  `f=-53.45474 dB` and checkpointed through `ckpt_iter_0942.jld2`. The existing
  resume-grid caveat still applies: the `Nt=65536`, `tw=320 ps` continuation
  grid drops about 68% of the stored spectral range.
- MMF remains closed with the GDD follow-up artifacts under
  `results/raman/phase36_window_validation_gdd/`; the summary reports
  `quality=meaningful`, `boundary_ok=true`, and `J_opt=-49.69 dB`. Multivar
  remains closed with accepted/caveat outputs and no active multivar VM.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  continues to report the multivar sequence closed by accepted
  results/caveats. No failure, patch, or relaunch was needed during this
  check.

## 2026-04-28 01:05 UTC Supervisor Check

- Active quota mix remains controlled: only
  `fiber-raman-temp-l-200resume1-20260427t165232z` is running as a
  `c3-highcpu-8` ephemeral. `fiber-raman-burst` is `TERMINATED`, and no MMF or
  multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on run
  worktree commit `6240464`, which contains the `4d426df` multivar log-energy
  fix. The optimizer has advanced to step 20 with `f=-53.45442 dB` and
  checkpointed through `ckpt_iter_1340.jld2`. Objective movement is now small,
  but the process is still consuming CPU and writing checkpoints, so it was
  left running. The existing resume-grid caveat still applies: the `Nt=65536`,
  `tw=320 ps` continuation grid drops about 68% of the stored spectral range.
- MMF remains closed with the GDD follow-up artifacts under
  `results/raman/phase36_window_validation_gdd/`; the expected summary and
  standard image files are present. Multivar remains closed with the accepted
  positive/negative results and documented `phase_energy_cold` caveat, and no
  active multivar VM is present.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  continues to report the multivar sequence closed by accepted
  results/caveats. No failure, source patch, or relaunch was needed during this
  check.

## 2026-04-28 01:35 UTC Supervisor Check

- Active quota mix remains controlled: only
  `fiber-raman-temp-l-200resume1-20260427t165232z` is running as a
  `c3-highcpu-8` ephemeral. `fiber-raman-burst` is `TERMINATED`, and no MMF or
  multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on run
  worktree commit `6240464`, which contains the `4d426df` multivar log-energy
  fix. The optimizer has advanced to step 21 with `f=-53.45437 dB` and
  checkpointed through `ckpt_iter_1395.jld2`. Objective movement remains small,
  but the process is still consuming CPU and writing checkpoints, so it was
  left running. The existing resume-grid caveat still applies: the `Nt=65536`,
  `tw=320 ps` continuation grid drops about 68% of the stored spectral range.
- MMF remains closed with the GDD follow-up artifacts under
  `results/raman/phase36_window_validation_gdd/`; the expected summary and
  standard image files are present. Multivar remains closed with accepted/caveat
  outputs and no active multivar VM.
- Deterministic watchdog cron remains installed at the 15 minute cadence and
  continues to report the multivar sequence closed by accepted
  results/caveats. No failure, source patch, test run, commit, or relaunch was
  needed during this check.

## 2026-04-28 02:35 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF `M-mmfg8192` is running on one `c3-highcpu-22`.
  No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on commit
  `6240464`, which contains the `4d426df` multivar log-energy fix. The
  optimizer has advanced to step 23 with `f=-53.45426 dB` and checkpointed
  through `ckpt_iter_1508.jld2`. The existing resume-grid caveat still applies:
  the `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- MMF follow-up `M-mmfg8192` was launched on
  `fiber-raman-temp-m-mmfg8192-20260428t022858z` for the GDD-regularized
  threshold case at `Nt=8192`, `tw=96 ps`, writing to
  `results/raman/phase36_window_validation_gdd_nt8192/`. The remote worktree
  is commit `738a98c`. At inspection it was still in
  `Pkg.instantiate()`/precompile, with no scientific artifacts expected yet.
- Multivar remains closed with accepted/caveat outputs, and the deterministic
  watchdog cron remains installed at the 15 minute cadence. No failure, source
  patch, test run, commit, or relaunch was performed during this check.

## 2026-04-28 03:01 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF `M-mmfg8192` is running on one `c3-highcpu-22`.
  No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on commit
  `6240464`, which contains the `4d426df` multivar log-energy fix. The
  optimizer has advanced to step 24 with `f=-53.45421 dB` and checkpointed
  through `ckpt_iter_1563.jld2`. The existing resume-grid caveat still applies:
  the `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- MMF follow-up `M-mmfg8192` is alive and CPU-active on commit `738a98c`. It
  has moved beyond package precompile into the GDD-regularized threshold
  optimization at `Nt=8192`, `tw=96 ps`, with early logged objective values
  `J=-17.37102 dB` and `J=-17.37495 dB`. No local artifacts are synced yet
  because the remote job is still running.
- Multivar remains closed with accepted/caveat outputs, and the deterministic
  watchdog cron remains installed at the 15 minute cadence. No failure, source
  patch, test run, commit, or relaunch was performed during this check.

## 2026-04-28 05:32 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF `M-mmfg8192` is running on one `c3-highcpu-22`.
  No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on commit
  `6240464`, which contains the `4d426df` multivar log-energy fix. The
  optimizer advanced from the earlier plateau to step 36 with
  `f=-54.47083 dB`; checkpoints are present through `ckpt_iter_1870.jld2`.
  The existing resume-grid caveat still applies: the `Nt=65536`, `tw=320 ps`
  continuation grid drops about 68% of the stored spectral range.
- MMF follow-up `M-mmfg8192` is alive and CPU-active on commit `738a98c` with
  `MMF_VALIDATION_THRESHOLD_NT=8192`, `MMF_VALIDATION_THRESHOLD_TW=96`,
  `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05`, and
  `MMF_VALIDATION_LAMBDA_GDD=1e-4`. The remote log reached objective
  evaluation 26 with latest logged `J=-30.24598 dB`. Memory use is high
  (`38 GB RSS` on a 43 GiB VM, about 5.9 GiB available) but not failed; no
  local artifacts are synced yet because the job is still running.
- The deterministic watchdog cron remains installed at the 15 minute cadence
  and continues to report the multivar sequence closed by accepted
  results/caveats. No failure, source patch, test run, commit, or relaunch was
  performed during this check.

## 2026-04-28 07:02 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF `M-mmfg8192` is running on one `c3-highcpu-22`.
  No multivar ephemeral is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux on commit
  `6240464`, which contains the `4d426df` multivar log-energy fix. The
  optimizer has advanced to step 45 with `f=-54.51083 dB` and checkpointed
  through `ckpt_iter_2047.jld2`. The existing resume-grid caveat still applies:
  the `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- MMF follow-up `M-mmfg8192` is alive and CPU-active on commit `738a98c` with
  `MMF_VALIDATION_THRESHOLD_NT=8192`, `MMF_VALIDATION_THRESHOLD_TW=96`,
  `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05`, and
  `MMF_VALIDATION_LAMBDA_GDD=1e-4`. The remote log is still at objective
  evaluation 41 with latest logged `J=-30.38022 dB`. Memory remains high but
  stable at about `34 GiB` used on a `43 GiB` VM, with about `8.7 GiB`
  available.
- Multivar remains closed with accepted/caveat outputs, including the
  documented incomplete `phase_energy_cold` caveat. The deterministic watchdog
  cron remains installed at the 15 minute cadence. No failure, source patch,
  test run, commit, or relaunch was performed during this check.

## 2026-04-28 08:35 UTC Supervisor Check

- Active C3 quota was initially below limit: only long-fiber
  `L-200resume1` was running on one `c3-highcpu-8`; `fiber-raman-burst` was
  `TERMINATED`, and no multivar VM was active.
- The prior MMF 8192-bin GDD follow-up
  `fiber-raman-temp-m-mmfg8192-20260428t022858z` was deleted at
  `2026-04-28T08:06:40Z` from the local host before any local
  `M-mmfg8192` log or
  `results/raman/phase36_window_validation_gdd_nt8192/` artifacts were
  present. Treat that attempt as an infrastructure/sync-loss failure, not an
  accepted MMF result.
- Patched and pushed commit `429a831` (`Fix MMF ephemeral result sync paths`)
  so MMF ephemeral jobs pull `results/raman/phase36_window_validation*`
  directories in addition to the older `phase36`/`mmf` result roots.
  `bash -n scripts/ops/parallel_research_lane.sh` passed.
- Relaunched the same MMF follow-up as `M-mmfg8192r1` on
  `fiber-raman-temp-m-mmfg8192r1-20260428t083514z` with
  `MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_gdd_nt8192`,
  `MMF_VALIDATION_THRESHOLD_NT=8192`, `MMF_VALIDATION_THRESHOLD_TW=96`,
  `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05`, `MMF_VALIDATION_LAMBDA_GDD=1e-4`,
  and `BURST_AUTO_SHUTDOWN_HOURS=16`. Remote worktree verification showed
  commit `429a831` and the widened MMF pull path; the job acquired the remote
  heavy lock and is in `Pkg.instantiate()`/precompile.
- Long-fiber `L-200resume1` remains alive and CPU-active on commit `6240464`.
  It has advanced to step 48 with `f=-54.51067 dB` and checkpointed through
  `ckpt_iter_2234.jld2`; the existing 200 m resume-grid caveat still applies.
- Stopped one stale local full MMF phase test that was consuming CPU on
  `claude-code-host`; a second small local MMF hard-stop smoke ended before it
  needed intervention. Heavy lane work remains on the remote VMs.

## 2026-04-28 09:02 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF `M-mmfg8192b1` is running on one
  `c3-highcpu-22`. No multivar ephemeral is running.
- The documented MMF retry `M-mmfg8192r1` exited `rc=0` at
  `2026-04-28T08:41:40Z` after syncing only startup logs and no
  `phase36_window_validation_gdd_nt8192` science artifacts. A bounded retry,
  `M-mmfg8192b1`, is now the active MMF lane with
  `MMF_VALIDATION_F_CALLS_LIMIT=80` and
  `MMF_VALIDATION_TIME_LIMIT_SECONDS=10800`; remote commit `4412050` contains
  both `4d426df` and `429a831`, and the widened MMF pull path is present.
  The job is CPU-active with high but currently nonfatal memory use
  (`36 GB RSS`, about `7.6 GiB` available) and has reached MMF setup/reference
  logging, but no result files are present yet.
- Long-fiber `L-200resume1` remains alive and CPU-active on commit `6240464`,
  which contains the `4d426df` multivar log-energy fix. It has advanced to
  step 49 with `f=-54.51062 dB` and checkpointed through
  `ckpt_iter_2290.jld2`; the existing 200 m resume-grid caveat still applies.
- The deterministic watchdog cron remains installed at the 15 minute cadence
  and continues to report the multivar sequence closed by accepted
  results/caveats. No source patch, test run, commit, or additional relaunch
  was performed during this check.

## 2026-04-28 09:33 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=30 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is running on
  one `c3-highcpu-8`, and MMF `M-mmfg8192b2` is running on one
  `c3-highcpu-22`. No multivar ephemeral is running.
- MMF bounded retry `M-mmfg8192b1` ended with launcher `rc=0` at
  `2026-04-28T09:13:55Z`, but the Julia log ends with `Terminated` inside
  `simulate_disp_mmf.jl` and no science artifacts were synced under
  `results/raman/phase36_window_validation_gdd_nt8192/`. Treat `b1` as an
  incomplete resource/termination attempt, not an accepted result.
- The active MMF retry `M-mmfg8192b2` is running from commit `4412050`, which
  contains the `4d426df` log-energy fix and the widened MMF sync-path commit
  `429a831`. It uses bounded settings
  `MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_gdd_nt8192_bounded`,
  `MMF_VALIDATION_F_CALLS_LIMIT=80`, and
  `MMF_VALIDATION_TIME_LIMIT_SECONDS=10800`. Remote Julia is CPU-active and
  memory-heavy (`~37 GB RSS`, about `6.6 GiB` available); the log has reached
  setup/reference logging but no objective evaluations or result files yet.
- Long-fiber `L-200resume1` remains alive and CPU-active on commit `6240464`,
  which contains the `4d426df` multivar log-energy fix. It has advanced to
  step 50 with `f=-54.51057 dB` and checkpointed through
  `ckpt_iter_2355.jld2`; the existing 200 m resume-grid caveat still applies.
- The deterministic watchdog cron remains installed at the 15 minute cadence
  and continues to report the multivar sequence closed by accepted
  results/caveats. No source patch, test run, commit, or additional relaunch
  was performed during this check.

## 2026-04-28 10:03 UTC Supervisor Check

- Active C3 quota is back to only the long-fiber `c3-highcpu-8` VM:
  `fiber-raman-burst` is `TERMINATED`, no MMF VM is running, and no multivar
  ephemeral is running. The deterministic watchdog cron remains installed at
  the 15 minute cadence.
- MMF bounded retry `M-mmfg8192b2` ended with launcher `rc=0` at
  `2026-04-28T09:49:17Z`, but the Julia log shows `signal 15: Terminated`
  inside `simulate_disp_mmf.jl` after only two objective evaluations
  (`J=-17.37102 dB`, `J=-17.37495 dB`). The widened result sync path worked,
  but no science artifacts or standard images were produced under
  `results/raman/phase36_window_validation_gdd_nt8192_bounded/`.
- Treat the `Nt=8192`, `tw=96 ps` MMF GDD refinement as a compute/memory gate
  under current quota/stock, not accepted evidence. The accepted MMF result
  remains the visually inspected `Nt=4096`, `tw=96 ps`, GDD+boundary run in
  `results/raman/phase36_window_validation_gdd/` with `J_opt=-49.69 dB`,
  `Delta=31.73 dB`, and `boundary_ok=true`. No further same-shape MMF relaunch
  was started.
- Long-fiber `L-200resume1` remains alive and CPU-active on commit `6240464`,
  which contains the `4d426df` multivar log-energy fix. It has advanced to
  step 52 with `f=-54.75256 dB` and checkpointed through
  `ckpt_iter_2413.jld2`; the existing 200 m resume-grid caveat still applies.
- Multivar remains closed by accepted results/caveats, including the documented
  `phase_energy_cold` caveat. No source patch, test run, commit, or relaunch
  was performed during this check.

## 2026-04-28 11:01 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=8 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is the only
  running ephemeral (`fiber-raman-temp-l-200resume1-20260427t165232z` on
  `c3-highcpu-8`). No MMF or multivar VM is running.
- Long-fiber `L-200resume1` remains alive and CPU-active in remote tmux on
  commit `6240464`, which contains the `4d426df` multivar log-energy fix. The
  optimizer has advanced to step 54 with `f=-54.78405 dB` and checkpointed
  through `ckpt_iter_2489.jld2`; the existing 200 m resume-grid caveat still
  applies.
- MMF remains closed on the accepted `Nt=4096`, `tw=96 ps` GDD+boundary result
  under `results/raman/phase36_window_validation_gdd/`; the attempted
  `Nt=8192`, `tw=96 ps` follow-ups remain treated as compute/memory-gated and
  were not relaunched. Multivar remains closed by accepted results/caveats.
- The deterministic watchdog cron remains installed at the 15 minute cadence.
  No source patch, test run, commit, or relaunch was performed during this
  check.

## 2026-04-28 11:31 UTC Supervisor Check

- Active C3 quota remains within limits: `C3_CPUS usage=8 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; long-fiber `L-200resume1` is the only
  running ephemeral (`fiber-raman-temp-l-200resume1-20260427t165232z` on
  `c3-highcpu-8`). No MMF or multivar VM is running.
- Long-fiber `L-200resume1` remains alive and CPU-active in remote tmux from
  run worktree commit `6240464`, which contains the `4d426df` multivar
  log-energy fix. The optimizer has advanced to step 57 with
  `f=-55.11351 dB` and checkpointed through `ckpt_iter_2550.jld2`; the
  existing 200 m resume-grid caveat still applies.
- MMF remains closed on the accepted `Nt=4096`, `tw=96 ps` GDD+boundary result
  under `results/raman/phase36_window_validation_gdd/`. The attempted
  `Nt=8192`, `tw=96 ps` retries remain compute/memory-gated terminations
  without accepted science artifacts, so no same-shape relaunch was started.
- Multivar remains closed by accepted results/caveats, including the documented
  incomplete `phase_energy_cold` caveat. The deterministic watchdog cron
  remains installed at the 15 minute cadence. No source patch, test run,
  commit, or relaunch was performed during this check.

## 2026-04-28 13:01 UTC Supervisor Check

- Active GCE inventory remains within limits: `fiber-raman-burst` is
  `TERMINATED`, long-fiber `L-200resume1` is the only running research
  ephemeral (`fiber-raman-temp-l-200resume1-20260427t165232z` on
  `c3-highcpu-8`), and no MMF or multivar VM is running.
- Long-fiber `L-200resume1` is alive and CPU-active in remote tmux. The run
  worktree is commit `6240464`, which contains the `4d426df` multivar
  log-energy fix. The objective improved materially since the prior check,
  reaching optimizer step 63 with `f=-55.16503 dB`; checkpoints are present
  through `ckpt_iter_2753.jld2`. The 200 m resume-grid caveat still applies:
  the `Nt=65536`, `tw=320 ps` continuation grid drops about 68% of the stored
  spectral range.
- MMF remains closed on the accepted `Nt=4096`, `tw=96 ps` GDD+boundary result
  under `results/raman/phase36_window_validation_gdd/`; the attempted
  `Nt=8192`, `tw=96 ps` follow-ups remain compute/memory-gated and were not
  relaunched. Multivar remains closed by accepted results/caveats.
- The deterministic watchdog cron remains installed at the 15 minute cadence.
  No failure, source patch, test run, commit, or relaunch was needed during
  this check.

## 2026-04-28 13:32 UTC Supervisor Check

- Active GCE inventory remains within limits: `C3_CPUS usage=8 limit=50` in
  `us-east5`. `fiber-raman-burst` is `TERMINATED`; long-fiber
  `L-200resume1` is the only running research VM
  (`fiber-raman-temp-l-200resume1-20260427t165232z` on `c3-highcpu-8`). No MMF
  or multivar VM is running.
- Long-fiber `L-200resume1` remains alive and CPU-active in remote tmux on
  commit `6240464`, which contains the `4d426df` multivar log-energy fix. The
  optimizer has advanced to step 64 with latest logged `f=-55.16498 dB`, and
  remote checkpoints are present through `ckpt_iter_2812.jld2`. Local result
  sync has not occurred yet because the ephemeral job is still running; local
  files only show checkpoints through `ckpt_iter_1684.jld2`. The existing
  200 m resume-grid caveat still applies.
- MMF remains closed on the accepted `Nt=4096`, `tw=96 ps` GDD+boundary result
  under `results/raman/phase36_window_validation_gdd/`. The attempted
  `Nt=8192`, `tw=96 ps` follow-ups remain compute/memory-gated and were not
  relaunched. Multivar remains closed by accepted results/caveats, including
  the documented incomplete `phase_energy_cold` caveat.
- Syncthing currently reports both peers disconnected, so local-to-Mac result
  propagation should not be assumed. The deterministic watchdog cron remains
  installed at the 15 minute cadence. No source patch, test run, commit, or
  relaunch was performed during this check.

## 2026-04-28 14:12 UTC Supervisor Check

- Long-fiber `L-200resume1` completed and the ephemeral VM
  `fiber-raman-temp-l-200resume1-20260427t165232z` was destroyed after result
  sync. Active C3 usage is now `C3_CPUS usage=0 limit=50`; `fiber-raman-burst`
  remains `TERMINATED`, and no MMF or multivar ephemeral is running.
- The 200 m resume run stopped cleanly at optimizer step 69 with
  `J=-55.16 dB`, `converged=false`, and gradient norm `5.65e-01`. It wrote
  `results/raman/phase16/200m_overngt_opt_resume_result.jld2`, final
  checkpoint `ckpt_iter_2895_final.jld2`, and the full standard image set under
  `results/raman/phase16/standard_images_F_200m_overngt_resume/`.
- Visually inspected all four standard images. The spectrum shows strong Raman
  suppression (`J_before=-0.2 dB`, `J_after=-55.2 dB`, `Delta-J=55.0 dB`) and
  the optimized/unshaped evolution images are present. Accepted caveats: the
  run is not optimizer-converged, the optimized phase/group-delay diagnostic is
  very rough, and the existing 200 m resume-grid warning still applies
  (`Nt=65536`, `tw=320 ps` continuation dropped about 68% of the stored
  spectral range).
- MMF remains closed on the accepted `Nt=4096`, `tw=96 ps` GDD+boundary result;
  the attempted `Nt=8192`, `tw=96 ps` retries remain compute/memory-gated and
  were not relaunched. Multivar remains closed by accepted results/caveats. No
  source patch, test run, commit, or relaunch was performed during this check.

## 2026-04-28 16:03 UTC Supervisor Check

- Active GCE inventory remains within quota: `C3_CPUS usage=22 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; the only active research VM is MMF
  `M-mmfg8192finalc2` on
  `fiber-raman-temp-m-mmfg8192finalc2-20260428t155233z`
  (`c3-highmem-22`, `us-east5-c`). No long-fiber or multivar VM is running.
- The MMF 8192-bin final high-memory relaunch is CPU-active in remote tmux.
  Earlier high-memory attempts hit stockout in `us-east5-a`/`us-east5-b`, and
  `M-mmfg8192finalc` failed without science artifacts because the stale image
  copy lacked `scripts/research/mmf/mmf_window_validation.jl`. The active
  `finalc2` launch uploaded `Project.toml`, `Manifest.toml`, `src`,
  `scripts/lib`, and `scripts/research/mmf`; remote Julia reached the
  threshold validation setup with `Nt=8192`, `tw=96 ps`,
  `lambda_boundary=0.05`, `lambda_gdd=1e-4`, `max_iter=4`, and
  `f_calls_limit=80`.
- Remote memory currently has wide headroom on the highmem machine
  (`~38 GiB RSS`, `~134 GiB available`). No objective evaluations or result
  files are present yet. The remote repo HEAD reports `8b14314` and contains
  the `4d426df` multivar log-energy fix, although this MMF launch is using
  pushed local input paths rather than relying solely on a fresh remote pull.
- Long-fiber 200 m remains completed with accepted caveats from the 14:12 UTC
  check. Multivar remains closed by accepted results/caveats. The deterministic
  watchdog cron remains installed at the 15 minute cadence. No source patch,
  test run, commit, or additional relaunch was performed during this check.

## 2026-04-28 16:38 UTC Supervisor Check

- Active GCE inventory remains within quota: `C3_CPUS usage=22 limit=50`.
  `fiber-raman-burst` is `TERMINATED`; the only active research VM is MMF
  `M-mmfg8192finalc2` on
  `fiber-raman-temp-m-mmfg8192finalc2-20260428t155233z`
  (`c3-highmem-22`, `us-east5-c`). No long-fiber or multivar VM is running.
- MMF `M-mmfg8192finalc2` remains CPU-active in remote tmux with wide memory
  headroom (`~44 GiB` used, `~128 GiB` available). The log has advanced to
  objective iteration 3 with latest `J=-18.14853 dB`; no result files or
  standard images have been written yet.
- Correction to the 16:03 UTC note: the VM's stale image checkout at commit
  `8b14314` does not contain `4d426df`, although the `4d426df` object is
  present locally on the VM. This does not affect the active MMF job, which was
  launched from uploaded MMF input paths, and no multivar ephemeral is active.
  If multivar is relaunched, ensure it runs from current `main` or explicitly
  uploads `scripts/research/multivar`.
- Long-fiber 200 m remains completed with the accepted 14:12 UTC caveats.
  Multivar remains closed by accepted results/caveats. The deterministic
  watchdog cron remains installed at the 15 minute cadence. No source patch,
  test run, commit, or relaunch was performed during this check.

## 2026-04-28 20:12 UTC Supervisor Check

- Active GCE inventory remains within quota but near the intended C3 ceiling:
  `C3_CPUS usage=44 limit=50`. `fiber-raman-burst` is `TERMINATED`; the only
  active research VM is MMF `M-mmfg8192s44c2` on
  `fiber-raman-temp-m-mmfg8192s44c2-20260428t194709z`
  (`c3-standard-44`, `us-east5-c`). No long-fiber or multivar VM is running.
- Previous MMF high-memory attempt `M-mmfg8192finalc2` ended without accepted
  artifacts. Its log stopped by the driver-side 10800 s time limit after 29
  objective evaluations, with best logged objective about `-30.37 dB`, but the
  stale optimizer path reported `J_final = Inf` and produced no standard images
  under `results/raman/phase36_window_validation_gdd_nt8192_final/`. Treat this
  as an incomplete run.
- The local MMF time-limit fallback fix is already present and pushed as
  commit `76a768b` (`Fix MMF optimizer time-limit fallback`). Verified the
  active `M-mmfg8192s44c2` VM has the uploaded fixed
  `scripts/research/mmf/mmf_raman_optimization.jl` despite its stale image git
  HEAD (`8b14314`): the file contains `_select_mmf_reported_optimum` and sets
  `J_final = best_J` when `MMFOptimizationLimit` is caught.
- A manual high-memory relaunch attempt `M-mmfg8192finald` failed before VM
  work because the machine-image refresh raced an existing
  `fiber-raman-burst-template` image. The active replacement `M-mmfg8192s44c2`
  is running the same `Nt=8192`, `tw=96 ps`, `lambda_boundary=0.05`,
  `lambda_gdd=1e-4`, `max_iter=4`, `f_calls_limit=80`,
  `time_limit=10800` case with pushed `Project.toml`, `Manifest.toml`, `src`,
  `scripts/lib`, and `scripts/research/mmf`.
- Current `M-mmfg8192s44c2` status: remote tmux is alive, Julia is running on
  44 threads, memory headroom is wide (`~33 GiB` used, `~139 GiB` available),
  and the log has reached objective iteration 1 (`J=-17.37102 dB`). No result
  files or standard images are present yet.
- Verification: `julia --project=. test/phases/test_phase16_mmf.jl` passed
  locally, including the hard-stop and best-observed fallback regression. No
  source patch or commit was performed in this check. Long-fiber 200 m remains
  completed with the accepted 14:12 UTC caveats; multivar remains closed by
  accepted results/caveats; the deterministic watchdog cron remains installed.

## 2026-04-28 20:31 UTC Supervisor Check

- Active GCE inventory remains within quota but at the intended MMF retry
  ceiling: `C3_CPUS usage=44 limit=50`. `fiber-raman-burst` is `TERMINATED`;
  the only active research VM is MMF `M-mmfg8192s44c2` on
  `fiber-raman-temp-m-mmfg8192s44c2-20260428t194709z` (`c3-standard-44`,
  `us-east5-c`). No long-fiber or multivar VM is running.
- The original overnight tmux sessions are absent, and the active local
  launcher is `mmf-highres-final-s44c2`. The remote tmux session
  `M-mmfg8192s44c2` is alive, Julia is CPU-active on 44 threads, and memory
  remains comfortable (`~44 GiB` RSS, `~128 GiB` available).
- MMF `M-mmfg8192s44c2` has advanced to objective iteration 3 with latest
  logged `J=-18.14853 dB`. No result files or standard images are present yet
  under `results/raman/phase36_window_validation_gdd_nt8192_final/`, so there
  is nothing to validate or accept yet.
- Local `HEAD` is `76a768b` and contains the prior `4d426df` multivar
  log-energy fix; no multivar ephemeral is active. Long-fiber 200 m remains
  completed with the accepted 14:12 UTC caveats and the expected four standard
  images are present locally. The deterministic watchdog cron remains installed
  at the 15 minute cadence. No source patch, test run, commit, or relaunch was
  performed during this check.

## 2026-04-28 23:10 UTC Supervisor Check

- Active GCE inventory remains within quota but still at the MMF retry ceiling:
  `C3_CPUS usage=44 limit=50`. `fiber-raman-burst` is `TERMINATED`; the only
  active research VM is MMF `M-mmfg8192s44c2` on
  `fiber-raman-temp-m-mmfg8192s44c2-20260428t194709z` (`c3-standard-44`,
  `us-east5-c`). No long-fiber or multivar VM is running, and no multivar
  relaunch was attempted because an additional `c3-highcpu-8` would exceed the
  regional C3 quota while the MMF retry is active.
- MMF `M-mmfg8192s44c2` is alive in remote tmux and Julia remains CPU-active
  with wide memory headroom. The run hit the intended driver-side time limit
  after 28 objective evaluations and used the fixed best-observed fallback:
  best regularized objective `J_final=-32.28527 dB`, unregularized Raman report
  `J_lin=7.502e-05` (`-41.25 dB`). The job is still in post-run diagnostics /
  image generation, and no result files or standard images are present yet
  under `results/raman/phase36_window_validation_gdd_nt8192_final/`.
- Local `HEAD` is `eea7368` and contains the prior `4d426df` multivar
  log-energy fix. The active MMF VM's stale image checkout remains at
  `8b14314`, but this MMF run was launched with uploaded source paths and is
  demonstrably running the fixed MMF time-limit fallback. Multivar is not
  active, so the stale checkout does not currently affect a multivar job.
- Long-fiber 200 m remains completed with the accepted 14:12 UTC caveats. The
  deterministic watchdog cron remains installed at the 15 minute cadence. No
  source patch, test run, commit, or relaunch was performed during this check.

## 2026-04-28 23:16 UTC Supervisor Check

- MMF `M-mmfg8192s44c2` remains alive and CPU-active in post-run diagnostics.
  The threshold case has now logged the full baseline trust report after the
  time-limit fallback: `J_sum=-17.37 -> -41.25 dB` (`Delta=23.88 dB`),
  `J_fund=-41.00 dB`, `J_worst=-41.00 dB`, and boundary edge fraction
  `3.59e-13`. This is a promising high-resolution MMF result, but it is not yet
  acceptable as complete because the result files and mandatory standard image
  set have not appeared under
  `results/raman/phase36_window_validation_gdd_nt8192_final/`.
- GCE state is otherwise unchanged: `C3_CPUS usage=44 limit=50`,
  `fiber-raman-burst` is `TERMINATED`, long-fiber 200 m remains completed with
  caveats, and no multivar VM is active. No source patch, test run, or relaunch
  was performed during this check.
