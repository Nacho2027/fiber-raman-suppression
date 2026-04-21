# Session F — Long-Fiber (100m+) Raman Suppression Decisions Log

**Opened:** 2026-04-17
**Branch:** sessions/F-longfiber
**Worktree:** ~/raman-wt-F
**Host:** claude-code-host (session running); burst VM used for all heavy solves

---

## D-F-01: Starting fiber + power

**Decision:** SMF-28 at P_cont = 0.05 W, 185 fs sech² pulse at 1550 nm.

**Why:** F prompt specifies "continuity with Phase 12." The burst VM sweep results directory contains a pre-computed `opt_result.jld2` at L=2m, P=0.05W SMF-28 — ready to use as a warm-start seed. (Note: Phase 12 itself used P=0.2W; the F prompt intentionally drops to 0.05W to stay in the low-peak-power regime where the physics is less prone to MI-driven grid instability over 100m.)

**How to apply:** All initial L=50m and L=100m runs use `:smf28` preset at P_cont=0.05 W. Defer power/fiber sweep to the optional final task.

---

## D-F-02: Grid (Nt, time window) at L=50m and L=100m — **finalized from research**

**Decision** (research-backed; see `.planning/notes/longfiber-research.md` §2, §7):

| L     | T (ps) | Δt (fs) | Nt (2^k)  | reltol | abstol | Notes                            |
|-------|--------|---------|-----------|--------|--------|----------------------------------|
| 30 m  | 20     | 2.44    | 8192 (13) | 1e-6   | 1e-8   | current known-good baseline      |
| 50 m  | 40     | 2.44    | 16384 (14)| 1e-7   | 1e-9   | stepping-stone validation        |
| 100 m | 160    | 4.88    | 32768 (15)| 1e-7   | 1e-9   | 1.14× T_min (139 ps) w/ margin   |
| 200 m | 320    | 4.88    | 65536 (16)| 1e-7   | 1e-10  | deferred (optional post-100m)    |

**Why (research derivation):**
- Time-window bound at long L is dominated by dispersive walk-off, NOT SPM. Research computed T_min(L) ≈ 2·|β₂|·Δω_20dB·L + 3·FWHM·safety ⇒ 139 ps at L=100m, 278 ps at L=200m. The current `recommended_time_window` formula uses the full 2π·13 THz Raman shift (conservative upper bound) which gives 163 ps one-sided walk-off at L=100m — compatible with but coarser than the research bound.
- Global error for 5th-order adaptive RK (Tsit5) with fixed reltol scales ≈ O(L·tol). 30m→100m is ~3× longer, so dropping reltol 1e-6→1e-7 holds end-of-fiber accuracy constant. Research cites Sinkin JLT 2003 + SciML FAQ.
- MI is a non-issue: g_max = 2γP = 1.3e-4 /m, exp(g·100m) = 1.013. Do not budget regularizer on MI suppression.

**Operative choice:**
- **L=50 m validation run (Task 1):** Nt=16384, T=40 ps, reltol=1e-7.
- **L=100 m first optimization (Task 4):** Nt=32768, T=160 ps, reltol=1e-7, abstol=1e-9.
- **L=200 m:** deferred to optional follow-up — needs a continuation staircase 30→50→75→100→200m per research §5.

**How to apply:** `setup_longfiber_problem(...)` wrapper (D-F-04) threads (Nt, time_window, reltol, abstol) through without auto-override. L=50m is the stepping-stone validation run (Task 1) before the L=100m heavy commit.

---

## D-F-03: Warm-start strategy — **research-informed**

**Decision:** Primary warm-start is IDENTITY copy of φ@2m (L=2m, P=0.05W SMF-28 multi-start) onto the L=100m grid. In parallel, run a continuation staircase 2→10→30→50→100 m as the likely-best-basin path (research §5, Allgower & Georg 1990). Keep whichever final cost is lower as the reference 100m optimum.

**Why:** Research ranked four options (identity, GVD-rescale, decomposed rescale, zero-start) — identity is the safest conservative pick, staircase is the textbook continuation strategy most likely to reach the global optimum (at 3-4× compute). GVD-rescale (φ×L_new/L_old) is plausible since the regime is GVD-dominated (L/L_D=196 at 100m, L/L_NL=0.0065), but over-corrects the non-polynomial structural part of φ — skip it.

**Interpolation:** Load φ_opt on its native grid, resample onto new (Nt, tw) grid via `pr_interpolate_phi_to_new_grid` (Phase 12 proven pattern: physical-frequency axis, linear interp, zero extrapolation).

**Backup if stall:** multi-start from 3 perturbed versions of φ@2m; or insert an extra staircase rung at L=75m.

**How to apply:** Seed path on burst VM: `~/fiber-raman-suppression/results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2`. The 100m script must load → interpolate → pass as `phi_init` to L-BFGS.

---

## D-F-04: Auto-sizing fix — scope decision

**Decision:** In-scope wrapper (`scripts/longfiber_setup.jl`). Do NOT modify `scripts/common.jl:setup_raman_problem` in this session. Instead write a new function that mirrors Phase 12's bypass pattern (direct calls to `MultiModeNoise.get_disp_sim_params` / `get_disp_fiber_params_user_defined` / `get_initial_state`) and honors user-supplied Nt and tw exactly.

**Why:** Per parallel-session Rule P1 (shared `scripts/common.jl` is off-limits without explicit go-ahead). The wrapper is self-contained and uses the exact same composition pattern the Phase 12 author settled on. Escalating a common.jl patch would block Session F for an integrator checkpoint.

**Proposed shared-code patch (for integrator, post-session):** Add `auto_size::Symbol = :warn` kwarg to `setup_raman_problem`:
- `:warn` (default) — current behavior but emit `@warn` on override (silent override is the UX problem)
- `:off` — honor passed `Nt`/`time_window`, no override
- `:strict` — raise `ArgumentError` if tw < tw_rec (forces user to think)

Backwards-compatible (default keeps existing behavior plus a log line). Would obsolete the Phase 12 and Session F wrapper workarounds. Captured here for Session G synthesis to escalate.

**How to apply:** Session F ships `scripts/longfiber_setup.jl::setup_longfiber_problem(...)` returning the same tuple as `setup_raman_problem` — drop-in replacement for long-L callers.

---

## D-F-05: Checkpoint cadence + optimizer state handling

**Decision:** Save x (phi vector), f (cost), g (gradient), and iteration counter to JLD2 every 5 iterations AND on convergence/abort. Also emit a wall-clock-gated checkpoint at ≥ 10 minutes since last save (guards against long iterations burning time).

**Why:** Optim.jl L-BFGS Hessian-approximation history (`state.metadata["~inv(H)"]`) is not cleanly serializable for exact resume, per my read of Optim.jl docs. The practical approach is: checkpoint (x, f, g, iter) only, resume by starting a fresh L-BFGS from x_last. This loses ~m iterations of Hessian warmup (m=LBFGS memory, default 10) but is robust — an 8-hour crash at iter 90 is recoverable.

**How to apply:** Optim.optimize callback: `callback = state -> longfiber_checkpoint(state, out_path)`. Returns `false` always (do not short-circuit convergence). Checkpoint file schema: `{x, f_trace, g_norm_trace, iter, elapsed, config_hash}`. Config hash from (Nt, tw, L, P, fiber) ensures resumes only happen against the same problem.

**Resume demo:** Task 4 of the plan will deliberately kill the optimizer mid-run, restart, and confirm continued convergence — this is the success-criteria item.

---

## D-F-06: Burst VM discipline + run duration budget

**Decision:** All Julia simulation work on burst VM. Heavy lock (`/tmp/burst-heavy-lock`) held by Session F during 100m optimization. `burst-stop` invoked from the same tmux session that launches the run (via `; burst-stop` tail on the command) so an overnight run cleans up automatically.

**Why:** Per CLAUDE.md Running Simulations rules 1–3. Phase 14 is also using burst VM (its plan 02 requires burst VM) — coordinate by checking `/tmp/burst-heavy-lock` and `burst-ssh "tmux ls"` before starting. Light forward solves (Task 3 — per-solve cost measurement) can share the VM with Phase 14 light work as long as no heavy lock is held.

**How to apply:** Before every heavy run: `ls /tmp/burst-heavy-lock 2>/dev/null && echo LOCKED || touch /tmp/burst-heavy-lock`. On completion: `rm /tmp/burst-heavy-lock && burst-stop`. Use `tmux new -d -s F-100m-opt '... ; rm /tmp/burst-heavy-lock ; burst-stop'`.

**Run duration estimates (to be validated by Task 3):** per-solve cost at L=100m Nt=32768 extrapolated from Phase 12 L=30m Nt=65536 (~40 s/solve) → ~70 s/solve at L=100m Nt=32768. L-BFGS 30 iter × 2 solves/iter ≈ 70 min for a clean convergence. 100 iter worst case ≈ 4 h. Budget: 8 h hard stop.

---

## D-F-07: Integration with Session G (synthesis) and Session C (multimode)

**Decision:** Session F publishes its findings to `.planning/notes/longfiber-findings.md` (its own namespace) and `.planning/sessions/F-longfiber-status.md`. Session G monitors session files on next integration checkpoint. Session C (multimode) is unaffected — Session F stays single-mode M=1 throughout.

**Why:** Per parallel-session Rule P3 (append-only to shared `.planning/`) and P7 (integration via user checkpoint).

**How to apply:** No direct cross-session file writes. Session F branches commit only within its owned namespace: `scripts/longfiber_*.jl`, `.planning/phases/<N>-longfiber-*/`, `.planning/notes/longfiber-*.md`, `.planning/sessions/F-longfiber-*.md`.

---

## Open questions — pre-research resolved ✓, post-research remaining

Resolved by research brief (`.planning/notes/longfiber-research.md`):
- [x] Time-window bound at L=100m: 139 ps minimum, use 160 ps with 15% margin (research §2).
- [x] MI is a non-issue at P=0.05W (g·L = 0.013 at 100m, research §4). Do not budget regularizer on MI.
- [x] Optim.jl L-BFGS Hessian-history persistence is NOT feasible — internal fields unexported/unstable. Use (x, f, g) checkpointing and restart fresh from x_last (research §6).

Remaining for Task 3 (forward-solve profiling) and Task 5 (validation):
- [ ] Does `recommended_time_window` formula over-estimate at L=100m? (It's conservative — uses Raman shift not signal bandwidth. T=160 ps > formula's T_min=163 ps one-sided or 330 ps two-sided × safety=2. Our wrapper honors the research-derived 160 ps.)
- [ ] Identity warm-start vs staircase 2→10→30→50→100m — which converges deeper? Task 4 runs both; Task 5 compares.
- [ ] Per-solve cost at L=100m, Nt=32768 — drives the 30 iter, 100 iter, 200 iter budgets. Task 3 measures.
- [ ] Does optimal φ(ω) at L=100m have a quadratic coefficient ≈ 3.33× the L=30m value (pure GVD scaling) or does it carry new structural features? Task 5 extracts a₂ fit and reports.

*Log open. Additional decisions will append below this line.*
