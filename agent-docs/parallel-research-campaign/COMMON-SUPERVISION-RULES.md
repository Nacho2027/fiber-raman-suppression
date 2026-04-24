# Common Supervision Rules For Parallel Research Agents

These rules apply to the MMF, multivar, and long-fiber agents.

## Preflight

Before launching any remote simulation:

1. Check local state:
   - `git status`
   - `syncthing cli show connections`
2. Make sure any code needed by the remote VM is committed and pushed to
   `origin/main`.
3. Confirm the remote will be able to pull the code:
   - permanent burst and ephemerals both run from `origin/main`
   - uncommitted local edits on `claude-code-host` are invisible to them
4. Check compute placement:
   - MMF owns permanent `fiber-raman-burst`
   - multivar owns one ephemeral `c3-highcpu-8`
   - long-fiber owns one ephemeral `c3-highcpu-8`
5. Do not move another lane's machine assignment without updating your notes.

## Launch Discipline

- Heavy simulation commands must use:
  - `julia -t auto --project=. ...`
- Permanent burst jobs must use:
  - `burst-start`
  - `burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy <TAG> '<CMD>'"`
- Ephemeral jobs must use:
  - `~/bin/burst-spawn-temp <TAG> '<CMD>'`
- The provided parallel lane launcher creates a clean remote worktree at
  `~/research-runs/<TAG>` from `origin/main` and symlinks `results/` back to the
  main remote checkout. Prefer that launcher when using the campaign tmux tools.
- Do not stack multiple heavy jobs on one VM unless you have explicitly reduced
  thread counts and recorded why it is safe.

## Polling Cadence

While a job is active:

1. Poll every `10-20` minutes for long jobs, sooner during startup.
2. Check:
   - local launcher logs
   - remote wrapper logs under `results/burst-logs/`
   - expected result directories
   - active remote tmux sessions if needed
3. Record meaningful observations in your agent notes:
   - launch time
   - command
   - VM target
   - current stage
   - last visible metric or failure

Do not treat "tmux still exists" as proof of progress. Inspect the log tail.

## Failure Handling

If a run fails:

1. Read the last log section and identify the first real error.
2. Decide whether the failure is:
   - code bug
   - missing dependency / include path
   - numerical failure
   - quota / VM startup failure
   - stale remote code
3. Patch only the owned lane unless a shared-file fix is truly required.
4. Run the smallest relevant local or smoke test.
5. Commit and push required code before relaunching remotely.
6. Relaunch and keep polling.

Do not mark the lane blocked just because the first remote run fails.

## Result Handling

When a run completes:

1. Verify expected JLD2 / JSON / summary artifacts exist.
2. Verify standard images exist for every `phi_opt` run:
   - `{tag}_phase_profile.png`
   - `{tag}_evolution.png`
   - `{tag}_phase_diagnostic.png`
   - `{tag}_evolution_unshaped.png`
3. Visually inspect representative standard images:
   - best
   - typical
   - worst or suspicious
4. Produce or verify lane-specific human-readable summary plots. Raw arrays and
   JLD2 files are not enough for a completed research loop.
5. Check trust metrics:
   - boundary edge fraction
   - energy drift when available
   - recomputed or validation `J` when available
6. Decide and record the next experiment based on the result.

Plot expectations by lane:

- MMF: canonical standard image set for each `phi_opt`, plus total spectrum,
  per-mode spectrum, phase profile, convergence, and sweep/regime heatmaps when
  mapping regimes.
- Multivar: canonical standard image set for every optimized phase, plus
  phase-only vs multivar comparison spectra, convergence traces, amplitude-mask
  plots where amplitude is optimized, and ablation heatmaps or bar charts.
- Long-fiber: canonical standard image set for each optimized rung, plus
  length-ladder tables/heatmaps, `J(z)` validation plots, phase profiles by
  length, and any β-order or multistart comparison figures.

If a run produces a scientifically important result but lacks these plots,
write or run the smallest plotting/regeneration step needed before calling the
run complete.

The expected behavior is a research loop:

`run -> validate -> interpret -> choose next run -> repeat`

## Escalation Criteria

Escalate to the user only when:

- quota prevents the planned machine layout
- a required shared-file change would conflict with another lane
- a run suggests the scientific premise of the lane should be abandoned
- continuing would require materially more spend than the lane budget implies

Otherwise, keep working through bugs and ordinary negative results.

## Cleanup

- Ephemeral VMs should normally self-delete through `burst-spawn-temp`.
- If a temp VM appears stuck, check:
  - `~/bin/burst-list-ephemerals`
- Destroy stale ephemerals with:
  - `~/bin/burst-list-ephemerals --destroy`
- Stop the permanent burst VM when the MMF lane is done or idle:
  - `burst-stop`
