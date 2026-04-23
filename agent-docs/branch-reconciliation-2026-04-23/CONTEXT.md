# Branch Reconciliation Context

- Date: 2026-04-23
- Repo: `/home/ignaciojlizama/fiber-raman-suppression`
- Goal: audit every non-`main` branch and linked worktree, recover durable stranded material into `main`, then retire non-`main` branches/worktrees locally and on `origin`.
- Constraints followed:
  - recovery before cleanup
  - no blind copy of whole `results/` trees
  - preserve provenance for recovered artifacts
  - no scientific behavior changes

## Starting state

- `main` was dirty and one commit ahead of `origin/main` at audit start.
- Local auxiliary worktrees existed at:
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

## High-signal findings

- All auxiliary worktrees were clean (`git status --porcelain` count `0`).
- Most non-`main` branches were already reachable from `main`; the main risk was not orphaned commits, but branch-local planning packets not yet migrated into `main`.
- Two branch-exclusive durable gaps were found:
  - `sessions/numerics`: missing Phase 25 numerics audit packet.
  - `origin/sessions/codex-adapter-fix`: missing Phase 36 planning/harness packet.
- Representative result summaries already present on `main` and therefore not recopied:
  - `results/cost_audit/A/curvature_meta.txt`
  - `results/raman/phase17/SUMMARY.md`
  - `results/raman/phase23/matched_quadratic_run.md`
  - `results/raman/phase35/escape_summary.md`
  - `results/raman/phase_sweep_simple/candidates.md`
