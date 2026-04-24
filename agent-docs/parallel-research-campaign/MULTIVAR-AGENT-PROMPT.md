You are working in `/home/ignaciojlizama/fiber-raman-suppression`.

Read first:
- `AGENTS.md`
- `CLAUDE.md`
- `agent-docs/current-agent-context/INDEX.md`
- `agent-docs/current-agent-context/MULTIVAR.md`
- `agent-docs/current-agent-context/METHODOLOGY.md`
- `agent-docs/parallel-research-campaign/COMMON-SUPERVISION-RULES.md`
- `agent-docs/research-closure-audit/SUMMARY.md`
- `docs/planning-history/sessions/A-multivar-status.md`
- `docs/planning-history/phases/16-multivar-optimizer/16-01-SUMMARY.md`
- `docs/planning-history/phases/18-multivar-convergence-fix/CONTEXT.md`
- `results/validation/multivar_mv_joint.md`
- `results/validation/multivar_mv_joint_warmstart.md`
- `results/validation/multivar_mv_phaseonly.md`

Start with:
- `git status`
- `syncthing cli show connections`
- verify any code you need on the ephemeral VM is committed and pushed to `origin/main`

Mission:
Run multivariable optimization as a serious science lane. Your job is to find
out whether extra control variables produce real Raman-suppression gains, or
whether the lane should be narrowed to a small set of useful add-ons to
phase-only shaping.

One-sentence goal:
Determine whether amplitude and energy controls add real Raman suppression
beyond phase-only shaping, and identify the staged recipe that makes them useful.

Primary questions:
1. Does amplitude help once phase is already good?
2. Does energy matter enough to keep?
3. Can a staged or continuation-style multivar workflow beat phase-only?
4. Is multivar a real lane or just an implemented but low-value extension?

Compute placement:
- Use an ephemeral burst VM.
- Default machine type target: `c3-highcpu-8`.
- Prefer the clean-worktree lane launcher:
  - `scripts/ops/parallel_research_lane.sh --lane multivar --target ephemeral --tag V-multivar --machine-type c3-highcpu-8 --cmd 'julia -t auto --project=. scripts/research/multivar/multivar_demo.jl' --log-file results/burst-logs/parallel/multivar.log`
- This launcher uses `burst-spawn-temp`, then creates `~/research-runs/<TAG>`
  on the ephemeral VM from `origin/main` and symlinks `results/` back to the
  main remote checkout.
- If launching manually, use:
  - `~/bin/burst-spawn-temp <TAG> '<CMD>'`
- The ephemeral helper already wraps the remote run in `burst-run-heavy`.

Operational rules:
- Heavy runs belong on the ephemeral burst VM, not on `claude-code-host`.
- Use `julia -t auto --project=. ...`
- Poll via:
  - local launcher logs
  - synced result files
  - remote wrapper output if needed
- If a run fails, inspect logs, patch, rerun, and continue.
- If a run completes but does not answer the scientific question, design the
  next ablation and continue.
- Every optimized phase must have the canonical standard image set. Multivar
  runs must also produce human comparison plots: phase-only versus multivar
  spectra, convergence traces, amplitude-mask plots when amplitude is active,
  and ablation heatmaps or bar charts.
- Keep a live status log under `agent-docs/` with commands, run tags, result
  paths, and the reason for each next experiment.

What you own:
- `scripts/research/multivar/**`
- `scripts/dev/smoke/test_multivar_unit.jl`
- `scripts/dev/smoke/test_multivar_gradients.jl`
- multivar result summaries under `docs/status/` or `docs/synthesis/`
- agent notes under a multivar-focused directory if you create one

What you should avoid:
- unrelated MMF or longfiber code
- broad shared-file refactors unless blocked
- generic optimizer fiddling without a clear ablation purpose

Execution plan:

Stage 1: rescue the lane with narrow ablations
- Use the canonical SMF point first.
- Run:
  1. phase-only reference
  2. amplitude-only warm-start from `φ_phase_only`
  3. energy-only warm-start if practical
  4. two-stage phase+amplitude:
     - amplitude-only first
     - then joint release
  5. only then phase+amplitude+energy if the earlier steps are promising

Stage 2: if Stage 1 is positive
- build a small regime map across a few lengths and powers
- compare:
  - phase-only
  - amplitude-only warm-start
  - two-stage phase+amplitude
  - optionally energy on top

Stage 3: if Stage 2 is positive
- do a 3-seed repeat on the best regime
- produce a durable recommendation for what variables and initialization
  strategy are actually worth keeping

Decision rules:
- If amplitude-only and two-stage do not clearly beat phase-only, stop calling
  generic joint multivar a main positive result.
- If energy adds little, say so explicitly and narrow the supported variable set.
- If the only way multivar works is with strong staging, record that as a real
  methodological finding rather than a weakness to hide.

Persistence rule:
- Keep going after each run.
- Poll the run, inspect the output, fix failures, choose the next ablation, and
  continue until you have either:
  - a scientifically credible positive multivar recipe, or
  - an honest negative conclusion about the current multivar path
- Do not end your session while your remote job is still running unless you have
  left an explicit handoff with the temp VM name, log path, expected outputs,
  and next polling command.

Deliverables:
- updated multivar status notes
- durable result summary
- clear statement of:
  - which variables help
  - which initialization strategy is required
  - whether multivar remains an active science lane

Output style:
Think like a controls researcher. Your job is not to merely make the optimizer
run. Your job is to determine what extra control freedom actually buys.
