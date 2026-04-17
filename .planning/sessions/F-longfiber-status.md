# Session F Status — Long-Fiber (100m+) Raman Suppression

| Stage | Status | Started | Ended | Notes |
|-------|--------|---------|-------|-------|
| Worktree setup | DONE | 2026-04-17 | 2026-04-17 | `~/raman-wt-F` on `sessions/F-longfiber` |
| Research brief | DONE | 2026-04-17 | 2026-04-17 | `.planning/notes/longfiber-research.md` |
| Decisions log | DONE | 2026-04-17 | 2026-04-17 | `F-longfiber-decisions.md` D-F-01..07 |
| Phase 16 CONTEXT + 01-PLAN | DONE | 2026-04-17 | 2026-04-17 | 6-task plan committed |
| Script implementation (6 files) | DONE | 2026-04-17 | 2026-04-17 | Executor agent delivered; all Julia scripts syntax-parsed + dry-include OK on burst VM |
| Launcher ship | DONE | 2026-04-17 | 2026-04-17 | `scripts/longfiber_burst_launcher.sh`; sequential T4→T3→T5→T6, heavy-lock aware, safe auto-stop |
| Burst VM queue launched | RUNNING | 2026-04-17T03:22Z | — | tmux `F-queue` on fiber-raman-burst |

## Burst VM state — 2026-04-17 ~03:22 UTC

Active tmuxes observed on fiber-raman-burst:
- `sweep` (Session E, since 01:42Z, ~1h 40min runtime) — holds `/tmp/burst-heavy-lock`
- `E-sweep1` (Session E secondary, since 03:10Z)
- `D-transfer` (Session D, since 03:20Z)
- `F-queue` (Session F launcher, since 03:22Z) — **ours**

Phase 14 `phase14_ab_comparison.jl` julia process also active (etime ~3h 45min).

**Queue plan** (per `scripts/longfiber_burst_launcher.sh`):
1. **T4** (L=100m forward solves, light) — starts immediately, no lock.
2. **T3** (L=50m validate, heavy because of L-BFGS) — waits for `/tmp/burst-heavy-lock` release, then claims. Likely blocks for hours behind Session E sweep.
3. **T5** (L=100m L-BFGS + checkpoint resume demo, very heavy, `LF100_MODE=resume_demo`, 2–8 h) — claims lock after T3 releases.
4. **T6** (validate + FINDINGS, moderate) — light, runs after T5.
5. **Cleanup** — releases any held lock, self-stops VM only if no other tmux/julia work remains.

Logs at `~/fiber-raman-suppression/results/raman/phase16/logs/` on burst VM:
- `queue.log` — launcher narration
- `T4-100m-forward.log`, `T3-50m-validate.log`, `T5-100m-optimize.log`, `T6-100m-validate.log`
- `queue_state.txt` — per-task started/done/rc

## Deviations from plan

- **β_order = 2 (not 3)**: executor followed plan's D-F-01 (β_order=2 with `:SMF28_beta2_only`). Phase 12 used β_order=3 (β₂+β₃). If PI asks for β₃, flip kwarg in three drivers (documented by executor).
- **Solver reltol = 1e-8 (not 1e-7)**: `MultiModeNoise.solve_disp_mmf` hardcodes 1e-8 internally — tighter than the 1e-7 target, strictly satisfies the research recommendation. Shared-file edit declined per Rule P1.
- **Task 5 modes via `LF100_MODE` env**: executor split into `fresh` / `resume` / `resume_demo` modes (default is `resume_demo` in launcher — covers the acceptance test in one run).
- **a₂ ratio reference**: baseline is phi@2m (only seed available locally), not phi@30m. Script computes both ratios — 100/2 (GVD-pred 50) and 100/30 (GVD-pred 3.33) — in FINDINGS.md. A dedicated phi@30m optimization would be a follow-up.

## Session rules checklist

- [x] Owned namespace only: `scripts/longfiber_*.jl`, `.planning/phases/16-longfiber-100m/`, `.planning/sessions/F-longfiber-*`, `.planning/notes/longfiber-*`
- [x] Shared `scripts/common.jl` / `scripts/raman_optimization.jl` / `src/*` untouched
- [x] Shared `.planning/ROADMAP.md` / `STATE.md` / `REQUIREMENTS.md` untouched
- [x] Branch `sessions/F-longfiber` pushed to origin; no push to main
- [x] Launcher holds `/tmp/burst-heavy-lock` for T3 and T5
- [ ] Burst VM TERMINATED at end of queue (launcher conditional on no-other-work)

## Warm-start seed verified

`~/fiber-raman-suppression/results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2` on burst VM, 207 KB, Session E sweep-generated. Loaded by T3 and T5 via `JLD2.@load`.

## Remaining monitoring

- Next checkpoint: ~30 min after launch (expect T4 result)
- Subsequent checks pace with lock release / T5 progress
- If T3 lock wait exceeds 12 h the launcher auto-times out — escalate then.
- T5 full run: expect 2–8 h wall clock once lock acquired.

## Open items for integrator (Session G / user)

1. **Shared-code patch to `scripts/common.jl::setup_raman_problem`** — add `auto_size::Symbol = :warn` kwarg. Proposed in D-F-04 with backwards-compatible default. Session F wrapper (`scripts/longfiber_setup.jl`) can be deprecated once this lands.
2. **β_order = 3 for long-fiber runs** — Phase 12 precedent. Flip kwarg in three drivers if desired.
3. **Cross-session burst VM worktree discipline** — current pattern (`git checkout` on shared burst VM checkout) disrupts other sessions' code views. Future: per-session worktrees on burst VM.
