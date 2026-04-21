# Phase 16: Long-Fiber Raman Suppression (100m+) - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Session F autonomous (research-backed defaults)
**Session owner:** sessions/F-longfiber

<domain>
## Phase Boundary

Push the spectral-phase Raman-suppression optimization from the known-good
L = 30 m SMF-28 / P_peak = 0.05 W / 185 fs sech² configuration (-57 dB at
best, established by Phase 12) to L = 100 m. This phase addresses the PI's
ask for "100 m+" operation and establishes the numerical infrastructure
(grid sizing, warm-starts, checkpointing) for an eventual L = 200 m push.

The value of this phase is twofold:
1. **Publication**: long-fiber Raman suppression with preserved phase-shape
   universality across 15×-60× the optimization horizon is one of the
   strongest publishable threads of the project (coordinate with Session G
   synthesis).
2. **Infrastructure**: establishes the long-fiber workflow — auto-sizing
   bypass wrapper, identity warm-start interpolation, (x, f, g)-checkpoint
   pattern — that any future 200 m / multimode / multi-parameter sweep
   inherits.

</domain>

<decisions>
## Implementation Decisions

See `.planning/sessions/F-longfiber-decisions.md` for full rationale. Summary:

### Grid and numerics
- **D-F-02:** L=100m uses Nt=2¹⁵=32768, T=160 ps (Δt≈4.88 fs), ODE reltol=1e-7, abstol=1e-9. Rationale from research brief: walk-off-dominated T_min=139 ps at L=100m (research §2), 15% margin. Global error for 5th-order adaptive RK scales O(L·tol), so dropping reltol 1e-6→1e-7 for 3× longer propagation holds end-accuracy constant.
- **D-F-02 stepping stone:** L=50m validation at Nt=16384, T=40 ps, reltol=1e-7.
- **D-F-02 deferred:** L=200m at Nt=65536, T=320 ps — optional follow-up, not in scope for Phase 16-01.

### Fiber and pulse
- **D-F-01:** SMF-28 at P_cont = 0.05 W, 185 fs sech² at 1550 nm, pulse_rep_rate = 80.5 MHz, β_order = 2. GVD-dominated regime (L_D=0.51 m, L_NL=15.4 km, N²=3.3e-5 at 100m). MI is a non-issue (g·L=0.013).

### Warm-start
- **D-F-03 primary:** Identity copy of φ@2m multi-start (from
  `results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2`) interpolated
  onto the L=100m grid via the `pr_interpolate_phi_to_new_grid` pattern.
- **D-F-03 parallel:** Continuation staircase 2→10→30→50→100m, each
  rung warm-started identity from the previous rung's result. Pick the
  lower-cost of {direct identity, staircase} as the 100m reference.

### Auto-sizing fix — in-scope wrapper
- **D-F-04:** Ship `scripts/longfiber_setup.jl::setup_longfiber_problem(...)`
  that mirrors Phase 12's bypass pattern (direct `MultiModeNoise` internals
  calls, honors passed Nt/tw exactly). Do NOT edit `scripts/common.jl`
  (owned shared file per P1). Shared-code patch deferred to integrator —
  proposed `auto_size::Symbol = :warn` kwarg on setup_raman_problem
  documented in D-F-04 for Session G synthesis to escalate.

### Checkpointing
- **D-F-05:** Save (x, f, g, iter, elapsed, config_hash) to JLD2 every 5
  L-BFGS iterations AND on convergence. Resume by loading x_last,
  starting a fresh L-BFGS — Optim.jl internal Hessian history is not
  cleanly persistable (research §6). config_hash binds the resume to the
  same (Nt, tw, L, P, fiber) problem.

### Run discipline
- **D-F-06:** Hold `/tmp/burst-heavy-lock` during 100m optimization; share
  burst VM for light forward solves. Wrap all tmux launches with
  `; rm /tmp/burst-heavy-lock ; burst-stop` tail for auto-cleanup.
  Phase 14 (sharpness-aware Hessian) also uses burst VM — coordinate
  via lock visibility.

### Scope boundaries
- Single-mode M=1 throughout. Do NOT extend to multimode in this phase
  (Session C owns multimode).
- Do NOT modify shared files (scripts/common.jl, scripts/visualization.jl,
  src/simulation/*, scripts/raman_optimization.jl).
- All new scripts prefixed `longfiber_` (session F owned namespace).
- All new results go to `results/raman/phase16/` (parallel to existing
  phase directories). This directory is gitignored (pattern from prior
  phases); tracked artifacts go in `.planning/phases/16-longfiber-100m/`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Session F artifacts (mandatory)
- `.planning/sessions/F-longfiber-decisions.md` — full rationale for D-F-01..07
- `.planning/notes/longfiber-research.md` — SSFM error analysis, MI
  assessment, warm-start rank, Optim.jl checkpoint idiom, grid table

### Prior phase work
- `.planning/phases/12-suppression-reach/12-01-SUMMARY.md` — the -57 dB
  at L=30m result; documents the Phase 12 bypass pattern in
  `scripts/propagation_reach.jl::pr_repropagate_at_length` which Session F
  imitates.
- `.planning/phases/07.1-*/07.1-01-SUMMARY.md` — Nt floor precedent
  (minimum 2¹³ for optimization quality). At L=100m we push to 2¹⁵.
- `scripts/propagation_reach.jl` (789 lines, Phase 12) — reuse the
  `pr_interpolate_phi_to_new_grid` function for warm-start φ resampling.

### Existing infrastructure (read-only for Phase 16)
- `scripts/common.jl` — `setup_raman_problem` (has auto-sizing override;
  Session F ships a wrapper around it), `recommended_time_window`
  (conservative formula using Raman shift; Session F uses research-derived
  160 ps directly).
- `scripts/raman_optimization.jl::optimize_spectral_phase` — underlying
  L-BFGS driver; Session F adds a checkpoint-capable wrapper around it.
- `src/simulation/simulate_disp_mmf.jl` — forward ODE solver with zsave
  hook (used directly via MultiModeNoise module).

### Data sources
- Burst VM: `~/fiber-raman-suppression/results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2` — warm-start seed (MUST pull via git on burst VM before run).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- `pr_interpolate_phi_to_new_grid(phi_old, Δf_old, Δf_new)` — Phase 12,
  physical frequency axis, linear interpolation, zero extrapolation.
  Drop-in for warm-start grid resampling.
- `MultiModeNoise.get_disp_sim_params(λ0, M, Nt, time_window, β_order)`
  — direct access that bypasses auto-sizing.
- `MultiModeNoise.get_disp_fiber_params_user_defined(L, sim; fR, gamma_user, betas_user)` — builds fiber dict without wrapper override.
- `MultiModeNoise.get_initial_state(u0_modes, P_cont, pulse_fwhm, pulse_rep_rate, pulse_shape, sim)` — pulse generator.
- `Optim.only_fg!(fg!)` closure idiom — lets the `fg!` function capture
  (x, f, g) into a `mutable struct CheckpointBuf` via closure, which the
  callback then serializes.

### Known pitfalls
- `setup_raman_problem` silently overrides Nt / time_window when
  `recommended_time_window > passed tw`. At L=100m P=0.05W this may
  trigger (tw_rec ≈ 163 ps > 160 ps passed). Session F wrapper bypasses.
- Optim.jl `OptimizationState.metadata["x"]` is unreliable post-v1.7 —
  capture `x` in the `fg!` closure instead (research §6).
- `.planning/` is globally gitignored — use `git add -f` for tracked
  phase artifacts (established precedent in phases 4–13, 15).
- Phase 14 (not in git yet) is actively running on burst VM in another
  session. Heavy lock coordination mandatory.

### Established patterns
- Scripts prefix: `longfiber_` for all Session F scripts.
- JLD2 data: `results/raman/phase16/` (gitignored).
- Figure prefix: `physics_16_XX_` (if plotting) — prior phases use
  `physics_NN_` format.
- Julia launch: `julia -t auto --project=.` always.
- Boundary condition check: 5% tail energy threshold (Phase 12
  `check_boundary_conditions`). For shaped long-fiber runs, bc_frac=1.0
  is a valid physics outcome (temporal spreading), not a failure.

</code_context>

<specifics>
## Specific Ideas

### Physics questions this phase answers
1. **Does φ@2m identity warm-start reach a competitive 100m optimum?**
   Phase 12 already showed -57 dB suppression at L=30m without
   re-optimization. Re-optimizing at L=100m starting from φ@2m should
   match or exceed.
2. **How does the optimal J_dB scale with L from 30m to 100m?** More
   headroom (more phase to play with) or more accumulated Raman (hitting
   a ceiling)?
3. **Is the identity warm-start in the same basin as the global
   optimum?** Staircase comparison (2→10→30→50→100) vs direct identity
   answers this. If staircase wins by > 3 dB, the direct-identity
   basin is sub-optimal and continuation must be the default protocol
   for L > 30 m.
4. **Does the optimal φ(ω) quadratic coefficient a₂ scale as L?**
   Pure-GVD pre-compensation predicts a₂(100m) = 3.33·a₂(30m). Any
   departure is a fingerprint of nonlinear structural adaptation —
   publishable physics.

### Numerical validation items
1. L=50m forward solve energy conservation: ΔE/E < 1%.
2. L=50m boundary condition: edge energy < 1e-6 in flat-phase case
   (shaped case may exceed per Phase 12 — not a failure).
3. L=100m forward solve repeatability: identical (Nt, tw, reltol) config
   gives identical J to within 1e-8 (deterministic numerical environment
   from Phase 15).
4. L=100m optimization checkpointing demo: interrupt at iter 15, resume,
   confirm convergence within a few extra iterations relative to an
   uninterrupted 30-iter run.

</specifics>

<deferred>
## Deferred Ideas

- L = 200 m campaign — requires continuation staircase, ~8 h burst VM
  budget. Scope for Phase 17 if 100m succeeds.
- Power sweep at L = 100 m (P ∈ {0.01, 0.05, 0.1, 0.2 W}) — optional
  task 6 if time permits, but lower priority than 100m convergence.
- HNLF at L = 100 m — Phase 12 showed HNLF reach collapses by z=15m.
  Do NOT spend Session F budget on HNLF 100m; the physics says it will
  fail.
- Multimode (M>1) long fiber — Session C owns.
- Trust-region optimizer as fallback if L-BFGS ill-conditions at 100 m
  — deferred to Phase 17 or explicit /gsd-debug if needed.

</deferred>

---

*Phase: 16-longfiber-100m*
*Context gathered: 2026-04-17 by Session F autonomous*
