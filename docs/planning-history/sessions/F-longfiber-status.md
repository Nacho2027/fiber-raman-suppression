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
| Phase 16 completed | DONE | 2026-04-17T17:42Z | 2026-04-17T18:52Z | T5b 25-iter fresh + T6 validate + auto-chain; artifacts + FINDINGS committed |
| Burst VM stopped | DONE | — | 2026-04-17T19:05Z | `gcloud compute instances stop` succeeded; `$0/hr` now |

## Final results headline (2026-04-17T19:05Z)

| Config | J (dB) |
|---|---|
| L=100m flat phase | -0.20 |
| L=100m phi@2m warm-start (no re-opt) | -51.50 |
| L=100m phi_opt (25 iter L-BFGS from warm) | **-54.77** |
| L=50m flat phase | -1.91 |
| L=50m phi@2m warm-start | -51.92 |
| L=50m phi_opt (4 iter L-BFGS from warm) | **-60.74** |

**Key physics thread for publication (per D-F-07):**
1. **Shape universality**: phi optimized at L=2m maintains -51.50 dB at L=100m (50× opt horizon) — extending Phase 12's 15× to 50×.
2. **Diminishing returns at long L**: at L=50m, L-BFGS yields +8.82 dB over warm-start; at L=100m only +3.26 dB. Optimization landscape flattens with L.
3. **Non-quadratic structure**: a₂(100m)/a₂(2m) = 0.672 vs pure-GVD prediction 50. Fit R² ≈ 0 — the phase is NOT a polynomial. Signal of intrinsic nonlinear structural adaptation that shaping *must* preserve for long-fiber suppression.

### Numerical discipline confirmed
- Nt=32768, T=160ps (13% above T_min=139ps derived in research); aliasing 6.75e-11.
- Energy drift at L=100m optimum: 4.91e-4 (well under 1% threshold).
- BC edge fraction at L=100m optimum: 8.46e-6 (well under 1e-3).
- Reltol=1e-8 (MultiModeNoise hardcode, tighter than 1e-7 target).

### Artifacts committed on `sessions/F-longfiber`
- `results/raman/phase16/FINDINGS.md` — headline summary (also above)
- `results/raman/phase16/logs/T5b.log`, `T6.log` — main run logs
- `results/raman/phase16/logs_run2/` — prior partial runs
- `results/images/physics_16_0{1..5}_*.png` — 5 figures at 300 DPI
- Source scripts (`scripts/longfiber_*.jl`, `scripts/longfiber_burst_launcher.sh`)

### Open issues for Phase 17 / integrator
1. Checkpoint callback `buf.iter` counts `fg!` evals, not Optim iterations — checkpoint stride is approximate. Fix: switch to Optim's own iter via `state[end].iteration` in the save path.
2. Checkpoint-resume parity demo failed — Phase B of resume_demo exited at iter 0 because `longfiber_resume_from_ckpt` didn't find the expected file schema. Needs debugging if resume_demo functionality is required (optional per D-F-05 success criteria).
3. Shared-code patch to `scripts/common.jl::setup_raman_problem` (auto_size kwarg) — proposed in D-F-04; still open for integrator.
4. β_order = 3 for long-fiber runs (Phase 12 precedent, β₃ accumulates over 100m) — could refine findings; flip kwarg in drivers.
5. L=200m continuation — staircase warm-start 2→10→30→50→100→200m is the textbook path (research §5). Deferred to Phase 17.
6. HNLF @ L=100m — Phase 12 showed HNLF reach collapses by z=15m; confirm at 100m as a negative-result control.
7. Multi-start at L=100m to test basin uniqueness.

## Burst VM state — 2026-04-17 ~03:22 UTC

Active tmuxes observed on fiber-raman-burst:
- `sweep` (Session E, since 01:42Z, ~1h 40min runtime) — holds `/tmp/burst-heavy-lock`
- `E-sweep1` (Session E secondary, since 03:10Z)
- `D-transfer` (Session D, since 03:20Z)
- `F-queue` (Session F launcher, since 03:22Z) — **ours**

Phase 14 `ab_comparison.jl` julia process also active (etime ~3h 45min).

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

## Incident — burst VM frozen (2026-04-17 ~04:28 UTC)

SSH to `fiber-raman-burst` hung at 15s and 60s timeouts. `gcloud compute instances describe` reports `status: RUNNING`. Serial console last activity at 03:43:54Z — session-1446 started but never deactivated; no further kernel log for 45+ min. Strong signal of a hard lockup (OOM with blocked logger, or CPU stall).

**Likely cause:** memory/CPU saturation from stacked heavy jobs —
- Phase 14 A/B (since 2026-04-16T23:34Z, ~5h etime)
- Session E `sweep` (since 01:42Z, ~3h etime)
- Session E `E-sweep1` (since 03:10Z)
- Session E `E-sweep1b` (since 03:32Z)
- Session A `A-demo` (since 03:34Z)
- Session D `D-transfer` (since 03:20Z)
- Session C `C-test` (since 03:06Z)
- Session F `F-queue` (since 03:40Z)

All 7+ heavy julia processes simultaneously on a 22-core VM with 88 GB is far over the "one heavy at a time" budget in CLAUDE.md Rule P5. The violation wasn't mine alone — multiple sessions ignored the lock — but the cumulative load froze the VM.

**Recovery options (not yet applied — cross-session impact):**
1. `gcloud compute instances reset fiber-raman-burst` — hard reboot, loses all in-flight julia state across all sessions (Phase 14 A/B, Session E sweep results, any uncheckpointed work).
2. `gcloud compute instances stop` + `start` — same effect, cleaner shutdown is not possible given kernel silence.
3. Wait longer (low probability of spontaneous recovery given 45 min silence).

Reset is the pragmatic path but the CLAUDE.md Executing-Actions-With-Care guidance explicitly flags this as needing user confirmation since it's destructive across session boundaries. Deferring to user.

## Remaining monitoring

- Awaiting user decision on VM reset.
- If reset: pull fresh on burst VM, re-add `~/raman-wt-F` worktree, symlink `Manifest.toml` and `results/`, relaunch `F-queue` tmux. Session F queue is idempotent — T4 will redo forward solves, T3/T5/T6 will run clean.
- Session F artifacts on claude-code-host and origin `sessions/F-longfiber` branch are intact regardless of VM state — no data loss local to Session F.

## Open items for integrator (Session G / user)

1. **Shared-code patch to `scripts/common.jl::setup_raman_problem`** — add `auto_size::Symbol = :warn` kwarg. Proposed in D-F-04 with backwards-compatible default. Session F wrapper (`scripts/longfiber_setup.jl`) can be deprecated once this lands.
2. **β_order = 3 for long-fiber runs** — Phase 12 precedent. Flip kwarg in three drivers if desired.
3. **Cross-session burst VM worktree discipline** — current pattern (`git checkout` on shared burst VM checkout) disrupts other sessions' code views. Future: per-session worktrees on burst VM.
