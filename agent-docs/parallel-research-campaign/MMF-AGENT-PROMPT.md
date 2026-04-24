You are working in `/home/ignaciojlizama/fiber-raman-suppression`.

Read first:
- `AGENTS.md`
- `CLAUDE.md`
- `agent-docs/current-agent-context/INDEX.md`
- `agent-docs/current-agent-context/METHODOLOGY.md`
- `agent-docs/current-agent-context/PERFORMANCE.md`
- `agent-docs/parallel-research-campaign/COMMON-SUPERVISION-RULES.md`
- `agent-docs/multimode-baseline-stabilization/CONTEXT.md`
- `agent-docs/multimode-baseline-stabilization/PLAN.md`
- `agent-docs/multimode-baseline-stabilization/SUMMARY.md`
- `agent-docs/research-closure-audit/SUMMARY.md`
- `docs/status/multimode-baseline-status-2026-04-22.md`
- `docs/planning-history/sessions/C-multimode-status.md`
- `docs/planning-history/sessions/C-multimode-decisions.md`

Start with:
- `git status`
- `syncthing cli show connections`
- verify any code you need on burst is committed and pushed to `origin/main`

Mission:
Drive the multimode lane as a real research program, not just a one-off run.
Your job is to establish a scientifically trustworthy MMF baseline, then push
deeper only if the baseline proves the lane is real.

One-sentence goal:
Find the multimode regime and objective where shared spectral phase, and
possibly joint mode-launch control, genuinely suppress Raman across modes.

Primary questions:
1. Which MMF regimes actually have Raman headroom?
2. Is `:sum` still the correct primary objective?
3. Does joint `{φ, c_m}` optimization buy real physics beyond shared-phase-only?
4. Is the MMF lane strong enough to remain active after the baseline map?

Compute placement:
- Use the permanent `fiber-raman-burst` VM.
- Treat it as your owned heavy machine for this campaign.
- Do not spawn ephemerals unless the user later reallocates machines.

Operational rules:
- Prefer the clean-worktree lane launcher:
  - `scripts/ops/parallel_research_lane.sh --lane mmf --target permanent --tag M-mmfdeep --cmd 'julia -t auto --project=. scripts/research/mmf/baseline.jl' --log-file results/burst-logs/parallel/mmf.log`
- This launcher creates `~/research-runs/<TAG>` on burst from `origin/main`
  and symlinks `results/` back to the main remote checkout.
- If launching manually, heavy runs must still go through the remote wrapper:
  - `burst-start`
  - `burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy <TAG> '<CMD>'"`
- Always run Julia as:
  - `julia -t auto --project=. ...`
- Poll runs by checking:
  - remote tmux sessions
  - wrapper logs under `results/burst-logs/`
  - local synced results under `results/`
- If a run crashes, inspect logs, patch the bug, rerun, and continue.
- If a run completes but is numerically suspicious, do not treat it as a positive result. Diagnose and rerun.
- Visually inspect representative standard images before accepting a result.
- Every `phi_opt` result must have the canonical standard image set plus MMF
  human plots: total spectrum, per-mode spectrum, phase profile, convergence,
  and regime heatmaps for sweeps.
- Keep a live status log in `agent-docs/multimode-baseline-stabilization/SUMMARY.md` or a new run note, including commands, run tags, and decisions.

What you own:
- `scripts/research/mmf/**`
- `test/phases/test_phase16_mmf.jl`
- MMF result summaries under `docs/status/` or `docs/synthesis/` as needed
- agent notes under `agent-docs/multimode-baseline-stabilization/`

What you should avoid:
- broad shared-file refactors
- unrelated multivar or longfiber code
- using the permanent burst VM for multiple simultaneous heavy MMF jobs unless you have clear evidence the VM is underloaded

Execution plan:

Stage 1: baseline reality check
- Run `scripts/research/mmf/baseline.jl` on burst.
- Sync back `results/raman/phase36/`.
- Inspect:
  - best run
  - typical run
  - worst or suspicious run
- Decide whether the recommended aggressive regime
  `GRIN_50, L=2 m, P=0.5 W` is scientifically real and trustworthy.

Stage 2: if Stage 1 is positive
- Run a deeper focused exploration on the best regime:
  - 3-seed repeat for shared-phase-only
  - compare `:sum` vs `:fundamental`
  - then joint `{φ, c_m}` optimization
- Only keep joint `{φ, c_m}` active if it materially improves the Raman objective.

Stage 3: if Stage 2 is positive
- Run one fiber comparison:
  - `:GRIN_50` vs `:STEP_9`
- Keep this narrow and interpretive, not sprawling.

Decision rules:
- If the aggressive baseline still does not show convincing trustworthy headroom, close MMF as a weak lane for now.
- If `:sum` and `:fundamental` disagree, keep `:sum` as the headline and treat the others as diagnostics.
- If joint `{φ, c_m}` only improves optimizer behavior metrics but not final Raman suppression, close it as low-priority.

Persistence rule:
- Keep going without waiting for the user after each run.
- Poll the output, fix bugs, interpret the result, and decide the next run yourself.
- Do not end your session while your remote job is still running unless you have
  left an explicit handoff with the tmux session, log path, expected outputs,
  and next polling command.
- Stop only when you have either:
  - a strong MMF baseline plus a clear next science step, or
  - an honest negative conclusion that the lane should be parked.

Deliverables:
- updated agent notes in `agent-docs/multimode-baseline-stabilization/`
- durable result summary in `docs/status/` or `docs/synthesis/`
- clear statement of:
  - meaningful regimes
  - non-meaningful regimes
  - primary objective recommendation
  - whether joint `{φ, c_m}` remains active

Output style:
Think like a lane owner. Do not stop at “run started.” Keep supervising the
campaign, polling logs, fixing failures, and making the next research decision.
