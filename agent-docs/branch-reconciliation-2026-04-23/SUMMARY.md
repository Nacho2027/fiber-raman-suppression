# Branch And Worktree Reconciliation Report

## Outcome

All non-`main` local worktrees were removed. All non-`main` local branches were deleted. All non-`main` `origin/*` branches were deleted. The only durable materials recovered into `main` were the missing Phase 25 numerics packet and the missing Phase 36 codex-adapter packet.

## Exact Recovered File List

- `docs/planning-history/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-01-PLAN.md`
- `docs/planning-history/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-CONTEXT.md`
- `docs/planning-history/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-REPORT.md`
- `docs/planning-history/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-RESEARCH.md`
- `docs/planning-history/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-REVIEWS.md`
- `docs/planning-history/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-01-PLAN.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-01-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-02-PLAN.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-02-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-03-PLAN.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-03-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-04-PLAN.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-CONTEXT.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-HANDOFF.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-RESEARCH.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/36-VALIDATION.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/adapter-lint.txt`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/codex_tools.txt`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/control/01-01-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/control/01-02-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched/01-01-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched/01-02-SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched/EXECUTION.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched/SUMMARY.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/patched_run1_readonly/FAIL.md`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/evidence/reproduction.txt`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/bootstrap_test_project.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/capture_tools.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/lint_adapter.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/reproduce.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/run_control.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/run_patched.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/verify_control_failed.sh`
- `docs/planning-history/phases/36-fix-gsd-codex-skill-adapter-spawn-agent-tool-mismatch-with-c/harness/verify_patched_passed.sh`
- `docs/planning-history/sessions/codex-adapter-fix-status.md`

## Per-Branch Reconciliation

| Branch | Linked worktree | Unique vs `main` at audit time | Result |
|---|---|---:|---|
| `sessions/A-multivar` | `raman-wt-A` | 0 | Clean worktree; durable planning/docs already represented on `main`; no recovery needed. |
| `sessions/B-handoff` | `raman-wt-B` | 0 | Clean worktree; handoff docs already represented on `main`; no recovery needed. |
| `sessions/C-multimode` | `raman-wt-C` | 0 | Clean worktree; multimode planning/results already represented on `main`; no recovery needed. |
| `sessions/D-docs` | `raman-wt-docs` | 0 | Clean worktree; docs update already reachable from `main`; no recovery needed. |
| `sessions/D-simple` | `raman-wt-D` | 0 | Clean worktree; representative `phase17` artifacts already present on `main`; no recovery needed. |
| `sessions/E-sweep` | `raman-wt-E` | 0 | Clean worktree; representative sweep summaries/artifacts already present on `main`; no recovery needed. |
| `sessions/F-longfiber` | `raman-wt-F` | 0 | Clean worktree; long-fiber docs/results already represented on `main`; no recovery needed. |
| `sessions/G-sharp-ab` | `raman-wt-G` | 0 | Clean worktree; sharpness execution changes already reachable from `main`; no recovery needed. |
| `sessions/H-cost` | `raman-wt-H` | 0 | Clean worktree; representative `results/cost_audit/**` summaries already present on `main`; no recovery needed. |
| `sessions/I-recovery` | `raman-wt-recovery` | 0 | Clean worktree; recovery outputs already represented on `main`; no recovery needed. |
| `sessions/bugsquash` | `raman-wt-bugsquash` | 0 | Clean worktree; bug-squash planning artifacts already represented on `main`; no recovery needed. |
| `sessions/numerics` | `raman-wt-numerics` | 3 | Recovered missing Phase 25 packet into `docs/planning-history/phases/25-...`; quick task and seed files were already on `main`. |
| `sessions/research` | `raman-wt-research` | 0 | Clean worktree; phase22/23 and synthesis materials already represented on `main`; no recovery needed. |
| `sessions/saddle-escape` | `raman-wt-saddle` | 0 | Clean worktree; representative `phase35` summaries/results already present on `main`; no recovery needed. |
| `origin/sessions/29-performance` | none | 1 reachable via `main` | Remote-only branch; no missing durable files detected beyond what `main` already contains; deleted. |
| `origin/sessions/M-matched100m` | none | 0 | Remote-only branch; representative phase23 results already present on `main`; deleted. |
| `origin/sessions/S-sharpness` | none | 0 | Remote-only branch; representative phase22 results already present on `main`; deleted. |
| `origin/sessions/codex-adapter-fix` | none | 15 | Recovered missing Phase 36 planning packet, selected evidence summaries, and reusable harness scripts into `docs/planning-history/`; raw execution logs intentionally omitted. |

## Duplicate And Already-Present Material

- All local auxiliary worktrees were clean, so there were no uncommitted local-only notes to rescue from disk.
- Historical `.planning/**` material from the merged branches was already migrated into `docs/planning-history/**` on `main`.
- Representative durable result summaries for the requested focus areas were already present on `main`:
  - `results/cost_audit/A/curvature_meta.txt`
  - `results/raman/phase17/SUMMARY.md`
  - `results/raman/phase23/matched_quadratic_run.md`
  - `results/raman/phase35/escape_summary.md`
  - `results/raman/phase_sweep_simple/candidates.md`

## Intentionally Left Behind

- Raw burst logs under `results/burst-logs/**`
- Bulk generated PNG/JLD2 output already present in worktree-local `results/**`
- Phase 36 raw execution logs and machine-capture text not needed once the durable plans, summaries, validation, reproduction note, and harness scripts were recovered

These were left behind because they were either already duplicated on `main`, were better treated as ephemeral run output, or would have been a blind bulk copy contrary to the recovery rules.

## Cleanup Performed

Removed worktrees:

- `/home/ignaciojlizama/raman-wt-A`
- `/home/ignaciojlizama/raman-wt-B`
- `/home/ignaciojlizama/raman-wt-C`
- `/home/ignaciojlizama/raman-wt-D`
- `/home/ignaciojlizama/raman-wt-E`
- `/home/ignaciojlizama/raman-wt-F`
- `/home/ignaciojlizama/raman-wt-G`
- `/home/ignaciojlizama/raman-wt-H`
- `/home/ignaciojlizama/raman-wt-bugsquash`
- `/home/ignaciojlizama/raman-wt-docs`
- `/home/ignaciojlizama/raman-wt-numerics`
- `/home/ignaciojlizama/raman-wt-recovery`
- `/home/ignaciojlizama/raman-wt-research`
- `/home/ignaciojlizama/raman-wt-saddle`

Deleted local branches:

- `sessions/A-multivar`
- `sessions/B-handoff`
- `sessions/C-multimode`
- `sessions/D-docs`
- `sessions/D-simple`
- `sessions/E-sweep`
- `sessions/F-longfiber`
- `sessions/G-sharp-ab`
- `sessions/H-cost`
- `sessions/I-recovery`
- `sessions/bugsquash`
- `sessions/numerics`
- `sessions/research`
- `sessions/saddle-escape`

Deleted remote branches:

- `sessions/29-performance`
- `sessions/A-multivar`
- `sessions/B-handoff`
- `sessions/C-multimode`
- `sessions/D-docs`
- `sessions/D-simple`
- `sessions/E-sweep`
- `sessions/F-longfiber`
- `sessions/G-sharp-ab`
- `sessions/H-cost`
- `sessions/I-recovery`
- `sessions/M-matched100m`
- `sessions/S-sharpness`
- `sessions/bugsquash`
- `sessions/codex-adapter-fix`
- `sessions/numerics`
- `sessions/research`
- `sessions/saddle-escape`

## Final State

After cleanup, the intended repo state is `main` only locally and `origin/main` only remotely.
