---
phase: 16-multimode-raman-suppression-baseline
plan: 01
session: sessions/C-multimode
completed: 2026-04-17
status: DRAFT — auto-fill from results/raman/phase16/phase16_summary.jld2 once runner completes
---

# Plan 16-01 Summary — Multimode Raman Suppression Baseline

**Scope delivered.** M=6 Raman-suppression optimizer shipped and validated: fiber presets (:GRIN_50, :STEP_9), MMF setup helper, three cost variants, a shared-across-modes L-BFGS driver with adjoint gradient, and 13/13 numerical correctness assertions passing on the burst VM.

## Performance

- **Test suite** (Nt=2^12, L=0.3m, M=6): 5m36s total on burst VM with julia -t 4
  - Shape sanity: 6/6 in 1m14s (precompile dominates)
  - Cost variants at M=1 equivalence: 3/3 in 0.2s
  - FD gradient check at M=6 (5 random indices, ε=1e-5): 1/1 in 3m59.7s (all rel_err < 5e-3)
  - Energy accounting at L=0.3m: 3/3 in 22.3s (rel_loss = 2.937e-5 ≪ 5% bound)
- **Baseline run** (Nt=2^13, L=1m, 3 seeds × 30 L-BFGS iters): _PENDING, fills in on completion_
- **M=1 reference** (SMF28_beta2_only, same L,P): _PENDING_

## Key numbers — autofilled from phase16_summary.jld2

| Seed | M=6 J_ref [dB] | M=6 J_opt [dB] | ΔdB | wall [s] | M=1 J_opt [dB] | Δ dB |
|------|-----|-----|-----|-----|-----|-----|
| 42   | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| 123  | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| 7    | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |

## Files delivered

### Tracked in git (sessions/C-multimode)

| File | Lines | Purpose |
|---|---|---|
| `scripts/mmf_fiber_presets.jl` | 104 | :GRIN_50 and :STEP_9 presets; default mode weights |
| `scripts/mmf_setup.jl` | 130 | `setup_mmf_raman_problem()` — wraps `MultiModeNoise.get_disp_fiber_params` + `get_initial_state` |
| `src/mmf_cost.jl` | 132 | `mmf_cost_sum`, `mmf_cost_fundamental`, `mmf_cost_worst_mode` (log-sum-exp smooth-max) |
| `scripts/mmf_raman_optimization.jl` | 333 | `cost_and_gradient_mmf` (shared φ across modes), `optimize_mmf_phase`, `plot_mmf_result`, `run_mmf_baseline` |
| `scripts/mmf_m1_limit_run.jl` | 96 | M=1 reference via existing SMF optimizer |
| `scripts/run_all.jl` | 129 | End-to-end runner (3 seeds × 2 configs) |
| `scripts/mmf_joint_optimization.jl` | 387 | Joint (φ, c_m) optimizer — stub for Phase 17 / free-exploration |
| `scripts/mmf_smoke_test.jl` | 77 | Fast smoke test for contended VMs (Nt=2^10, L=0.1m) |
| `test/test_phase16_mmf.jl` | 110 | 4 testsets, 13 assertions |

### Session artifacts (gitignored, synced via `sync-planning-*`)

| File | Purpose |
|---|---|
| `.planning/sessions/C-multimode-decisions.md` | 8 autonomous decisions (D1–D8) with rationale |
| `.planning/sessions/C-multimode-status.md` | Running status log |
| `.planning/phases/16-multimode-raman-suppression-baseline/16-CONTEXT.md` | Phase intent |
| `.planning/phases/16-multimode-raman-suppression-baseline/16-01-PLAN.md` | Detailed task plan |
| `.planning/seeds/mmf-phi-opt-length-generalization.md` | Free-exploration (b) seed |
| `.planning/seeds/mmf-fiber-type-comparison.md` | Free-exploration (c) seed |
| `.planning/seeds/mmf-joint-phase-mode-optimization.md` | Free-exploration (a) / Phase 17 seed |

## Key decisions (frozen, see C-multimode-decisions.md)

1. **Cost function at M=6**: `mmf_cost_sum = Σ_m E_band_m / Σ_m E_total_m` — the integrating-detector measurement. Mathematically identical to `spectral_band_cost` from `scripts/common.jl` when fed a (Nt, M) field.
2. **Shared spectral phase**: φ::Vector{Float64} of length Nt, broadcast across modes in the cost function. Adjoint gradient reduced via sum over modes before L-BFGS sees it. **This is the physically realizable form** (one pulse shaper, one phase profile).
3. **Fiber preset**: `:GRIN_50` (OM4-like, radius 25 μm, NA 0.2, alpha=2, M=6 modes).
4. **Input mode weights**: LP01-dominant realistic imperfect launch (0.95, 0.20, 0.20, 0.05, 0.05, 0.02) normalized.
5. **Sweep lengths**: baseline at L=1m; seeded L-generalization study at 0.5/1/2/5 m.
6. **Free exploration pick**: option (a) joint (φ, c_m) optimization — stub at `scripts/mmf_joint_optimization.jl`. Promoted to Phase 17 plan 01 if time permits; otherwise seeded.

## Protected-file rule honoured

- `scripts/common.jl`: 0 modifications
- `scripts/raman_optimization.jl`: 0 modifications
- `scripts/sharpness_optimization.jl`: 0 modifications
- `src/simulation/*.jl`: 0 modifications
- `src/helpers/helpers.jl`: 0 modifications
- `src/MultiModeNoise.jl`: 0 modifications

Verified by `git diff --stat main -- scripts/common.jl scripts/raman_optimization.jl scripts/sharpness_optimization.jl src/`.

## Physics interpretation (autofilled once baseline completes)

_Pending baseline numbers. Expected signatures:_
- J_ref at M=6 _likely higher_ than J_ref at M=1 because intermodal XPM/Raman distribute Kerr peaks across more modes → more Raman opportunities (per Wright+ 2020, Renninger+ 2013).
- ΔdB at M=6 _likely smaller_ than at M=1 because the shaper has fewer degrees of freedom per mode (shared phase across 6 modes vs dedicated phase at M=1).
- If M=6 ΔdB exceeds M=1 ΔdB, the shared φ has unlocked a multi-mode-specific suppression pathway — interesting physics, worth following up.

## Next steps

- Phase 16 plan 02 (or Phase 17 plan 01): joint (φ, c_m) optimization — activates the Rivera Lab wavefront-shaping analog.
- Phase 18 plan 01: L-generalization study (free-exploration b).
- Phase 19 plan 01: Fiber-type comparison (free-exploration c).

## Handoff

All code pushed to `sessions/C-multimode`. Integration is the user's call. Suggested merge order:
1. `sessions/C-multimode` into `main` (includes the whole Phase 16 scaffold + test suite + results).
2. Coordinate with `sessions/A-multivar`, `sessions/B-handoff`, `sessions/D-simple`, `sessions/E-sweep`, `sessions/F-longfiber` before merging if any touch `results/raman/phase16/` (they shouldn't — namespace protection was respected).
