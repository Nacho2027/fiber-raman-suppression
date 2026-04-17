# Session F Status — Long-Fiber (100m+) Raman Suppression

| Stage | Status | Started | Ended | Notes |
|-------|--------|---------|-------|-------|
| Worktree setup | DONE | 2026-04-17 | 2026-04-17 | `~/raman-wt-F` on `sessions/F-longfiber` |
| Read internal phase 7.1 + 12 artifacts | DONE | 2026-04-17 | 2026-04-17 | Phase 12 bypass pattern understood |
| Research (SSFM numerics, warm-start, checkpoint) | IN PROGRESS | 2026-04-17 | — | Background agent `a016b969df1625cb9` |
| Decisions log | DONE (initial) | 2026-04-17 | 2026-04-17 | Grid numbers pending research agent confirm |
| `/gsd-discuss-phase --auto` | PENDING | — | — | — |
| `/gsd-add-phase` + `/gsd-plan-phase` | PENDING | — | — | — |
| `/gsd-execute-phase` | PENDING | — | — | Burst VM contended w/ Phase 14 — coordinate via lock |

## Coordination notes

- Phase 14 (sharpness-aware Hessian) owns burst VM for A/B + robustness runs. Session F heavy runs must hold `/tmp/burst-heavy-lock` explicitly.
- No `.planning/` writes outside `.planning/sessions/F-longfiber-*`, `.planning/phases/<N>-longfiber-*`, `.planning/notes/longfiber-*`.
- No `scripts/common.jl` edits — Session F ships `scripts/longfiber_setup.jl` wrapper. Shared-code patch proposed in decisions doc D-F-04 for later integrator review.
- Branch `sessions/F-longfiber` — NEVER push to main.
