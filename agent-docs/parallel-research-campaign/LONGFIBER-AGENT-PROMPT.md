You are working in `/home/ignaciojlizama/fiber-raman-suppression`.

Read first:
- `AGENTS.md`
- `CLAUDE.md`
- `agent-docs/current-agent-context/INDEX.md`
- `agent-docs/current-agent-context/LONGFIBER.md`
- `agent-docs/current-agent-context/METHODOLOGY.md`
- `agent-docs/parallel-research-campaign/COMMON-SUPERVISION-RULES.md`
- `agent-docs/research-closure-audit/SUMMARY.md`
- `docs/planning-history/sessions/F-longfiber-status.md`
- `docs/planning-history/sessions/F-longfiber-decisions.md`
- `results/raman/phase16/FINDINGS.md`
- `results/raman/phase21/longfiber100m/sessionf_100m_validation.md`
- `docs/status/phase-34-bounded-rerun-status.md`
- `docs/synthesis/why-phase-34-still-points-back-to-phase-31.md`

Start with:
- `git status`
- `syncthing cli show connections`
- verify any code you need on the ephemeral VM is committed and pushed to `origin/main`

Mission:
Explore longer-fiber single-mode Raman suppression while making the long-fiber
workflow more production-ready. Your job is to extend the physics envelope
carefully, not by random long-length cold starts.

One-sentence goal:
Extend and harden single-mode long-fiber continuation so 100-200 m results are
trustworthy, visualized, and production-ready.

Primary questions:
1. How strong and trustworthy is the current 100 m result?
2. Does continuation remain viable through 200 m?
3. What parts of the long-fiber workflow are mature enough to call supported?
4. What must be hardened to make long-fiber more production-ready?

Compute placement:
- Use an ephemeral burst VM.
- Default machine type target: `c3-highcpu-8`.
- Prefer the clean-worktree lane launcher:
  - `scripts/ops/parallel_research_lane.sh --lane longfiber --target ephemeral --tag L-longfiber --machine-type c3-highcpu-8 --cmd 'LF100_MODE=fresh LF100_MAX_ITER=25 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl' --log-file results/burst-logs/parallel/longfiber.log`
- This launcher uses `burst-spawn-temp`, then creates `~/research-runs/<TAG>`
  on the ephemeral VM from `origin/main` and symlinks `results/` back to the
  main remote checkout.
- If launching manually, use:
  - `~/bin/burst-spawn-temp <TAG> '<CMD>'`
- Use the dedicated long-fiber path, not ad hoc generic setup paths.

Operational rules:
- Use `julia -t auto --project=. ...`
- Respect the existing long-fiber setup / checkpoint / validation scripts.
- Poll via:
  - local launcher logs
  - synced result files
  - remote wrapper output if needed
- If a run fails, inspect logs, patch, rerun, and continue.
- If a run completes but is not scientifically trustworthy, validate it before
  claiming success.
- Every optimized length rung must have the canonical standard image set.
  Long-fiber runs must also produce human plots: length-ladder tables/heatmaps,
  `J(z)` validation curves, phase profiles by length, and comparison figures
  for β-order or multistart checks.
- Keep a live status log under `agent-docs/` with commands, run tags, length
  rungs, validation status, and next-rung decisions.

What you own:
- `scripts/research/longfiber/**`
- long-fiber status docs under `docs/status/` or `docs/synthesis/`
- agent notes under a longfiber-focused directory if you create one

What you should avoid:
- unrelated MMF or multivar code
- turning long-fiber into a broad refactor project
- cold-start long-length experiments when a continuation ladder is available

Execution plan:

Stage 1: harden the 100 m result
- Strengthen the current 100 m claim with one focused check:
  - either a `β_order = 3` comparison
  - or a small multistart check at 100 m
- Confirm validation + standard-image outputs are clean.
- Keep the supported claim narrow unless the new evidence justifies expansion.

Stage 2: continuation ladder
- Run a continuation ladder:
  - `2 -> 10 -> 30 -> 50 -> 100 -> 200 m`
- Warm-start each rung from the previous rung.
- At each rung:
  - validate
  - save standard images
  - decide whether the rung is:
    - continuation-held
    - improved by local reoptimization
    - numerically suspicious
    - physically interpretable

Stage 3: production-readiness pass
- Once the supported length envelope is clearer, improve workflow readiness:
  - stable entrypoint
  - stable validation path
  - stable checkpoint/resume expectations
  - one clear supported-range statement

Decision rules:
- If 200 m continuation works cleanly, extend the supported exploratory story.
- If 200 m fails or becomes numerically suspect, keep 50-100 m as the supported range.
- If `β3` changes the interpretation materially, say so explicitly and update the supported claim.
- Do not oversell non-converged long-fiber results as production benchmarks.

Persistence rule:
- Keep supervising the lane after each run.
- Poll the output, fix failures, choose the next rung or validation pass, and
  continue until you have either:
  - a stronger supported long-fiber envelope, or
  - an honest boundary that says where the workflow stops being trustworthy
- Do not end your session while your remote job is still running unless you have
  left an explicit handoff with the temp VM name, log path, expected outputs,
  and next polling command.

Deliverables:
- updated long-fiber notes
- durable result summary
- clear statement of:
  - supported range
  - exploratory extension range
  - workflow hardening still needed

Output style:
Think like a long-range propagation lead. Favor controlled continuation and
validation over heroic cold starts.
