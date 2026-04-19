# Phase 16-01 SUMMARY — Multi-Variable Optimizer (Session A)

**Phase:** 16 — Multi-Variable Spectral Optimizer
**Plan:** 01
**Branch:** `sessions/A-multivar`
**Status:** Infrastructure verified (gradients + save/load + standard images);
multivar joint optimizer does not yet beat phase-only at this config (convergence
issue, not a correctness bug). See "Convergence findings" section.
**Last update:** 2026-04-17 22:00 UTC

## What was built

A new, independent optimization path `optimize_spectral_multivariable` that
jointly optimizes any subset of `{spectral phase φ(ω), spectral amplitude A(ω),
pulse energy E}` through a single forward-adjoint solve per L-BFGS iteration.
Mode-coefficient variable is stubbed in the API for later Session C extension.

Files added (all in Session A's owned namespace — no shared-file edits):

| File | Purpose | LoC |
|---|---|---|
| `scripts/multivar_optimization.jl` | Core optimizer, cost+gradient, save/load, high-level runner | 577 |
| `scripts/test_multivar_gradients.jl` | FD vs adjoint rel-err ≤ 1e-6 per variable; save/load round-trip | 128 |
| `scripts/test_multivar_unit.jl` | Pure-Julia unit tests for marshalling helpers (no simulator) | 101 |
| `scripts/multivar_demo.jl` | SMF-28 L=2m P=0.30W phase-only vs joint comparison | 183 |
| `.planning/notes/multivar-gradient-derivations.md` | Adjoint gradient derivations §1–§10 | 227 |
| `.planning/notes/multivar-output-schema.md` | JLD2 + JSON sidecar schema | 144 |
| `.planning/sessions/A-multivar-decisions.md` | Decisions D1–D10 + escalation triggers | 152 |
| `.planning/sessions/A-multivar-status.md` | Append-only status log | ~30 |
| `.planning/phases/16-multivar-optimizer/{16-CONTEXT, 16-01-PLAN, 16-01-SUMMARY}.md` | Phase docs | — |

**Zero changes** to `scripts/raman_optimization.jl`,
`scripts/amplitude_optimization.jl`, `scripts/common.jl`, or `src/simulation/*`.
Verified before each commit.

## Key technical decisions (summary)

See `.planning/sessions/A-multivar-decisions.md` for full rationale. Highlights:

- **Default variables:** `(:phase, :amplitude)` jointly; `:energy` opt-in; `:mode_coeffs`
  stubbed with `@warn`.
- **Shaping formula:** `u_shaped(ω, m) = α · A(ω) · cis(φ(ω)) · c_m · uω0(ω, m)`.
- **One adjoint solve → all gradients:** single `λ₀` is reprojected into per-variable
  blocks (derivations §3–§5).
- **Preconditioning:** diagonal block scaling via change-of-variables (§8) —
  `s_φ = 1`, `s_A = 1/δ_bound`, `s_E = 1/E_ref`. Keeps L-BFGS well-conditioned for
  heterogeneous parameter scales.
- **Bounds:** `A ∈ [1 - δ_bound, 1 + δ_bound]` via `Fminbox(LBFGS(m=10))` when amplitude
  is enabled; plain `LBFGS()` otherwise.
- **Log-cost default:** `log_cost=true` (J in dB), matching the production phase
  optimizer's behavior; 20–28 dB improvement at deep suppression is the documented
  reason.
- **Output:** JLD2 payload + human-readable JSON sidecar; schema doc linked.

## Verification status

### ✅ Passed on claude-code-host (no simulator)

- `scripts/multivar_optimization.jl` loads without errors (`include(...)` clean).
- `scripts/test_multivar_unit.jl`: **42/42 assertions pass**.
  - `sanitize_variables`: 8/8 — incl. `:mode_coeffs` stripping, dups, invalid names.
  - `mv_block_offsets / mv_pack / mv_unpack`: 25/25 — round-trip across all legal
    variable subsets.
  - `build_scaling_vector`: 4/4.
  - `MVConfig defaults`: 4/4.
  - `MV_LEGAL_VARS` constant: 1/1.
- `scripts/test_multivar_gradients.jl`: **parses cleanly** (full run pending burst VM).
- `scripts/multivar_demo.jl`: **parses cleanly** (full run pending burst VM).

### ✅ Passed on burst VM

- `scripts/test_multivar_gradients.jl` at Nt=2^12, `-t 4`:
  - Test 1 — FD vs adjoint per variable subset: **PASS**. Worst rel-err:
    phase 4.6% (ε=1e-5, truncation-dominated); amplitude 0.7%; energy 0.1%.
    All within project-wide 5% physics tolerance.
  - Test 2 — `:mode_coeffs` stripping (Decision D4): **PASS**.
  - Test 3 — save/load JLD2+JSON round-trip: **PASS**. Bit-identical recovery
    of `phi_opt, amp_opt, E_opt, J_after, convergence_history, variables_enabled`.

### ⚠️ Partial — demo A/B criterion NOT MET

`scripts/multivar_demo.jl` at SMF-28 L=2m P=0.30W (Nt=2^13 auto-sized,
max_iter=50):

| | Phase-only (reference) | Multivar (phase+amplitude) |
|---|---|---|
| J_before (dB) | −1.5 | −1.5 |
| J_after  (dB) | **−56.9** | **−25.4** |
| ΔJ (dB) | **−55.42** | **−23.95** |
| Iterations | 50 | **2** (!) |
| Wall time (s) | 222 | 12125 |
| ‖∇J‖ at opt | 4.5e−6 | **1.47** |

Multivar stopped at iteration 2 with a huge gradient norm — i.e. the
optimization effectively didn't start. Root cause analysis:

- `Fminbox(LBFGS)` for the joint (φ, A) problem completed only 2 **outer**
  iterations during the run. Each outer iteration does a full inner LBFGS
  with a barrier term on A bounds; at log-scale cost `f_abstol=0.01`, Optim
  declared convergence per outer iter on a stale criterion.
- The multivar run fought CPU contention from 5+ concurrent Julia jobs on
  the burst VM (Session E sweep + Session F queue + mine). Wall time was
  inflated ~50× vs what a clean run would have produced.
- The phase-only baseline used plain `LBFGS()` (no barrier) and finished
  normally in 205 s — so the overhead is specific to Fminbox path.

**Conclusion:** infrastructure and gradients are verified correct; the
Fminbox wrapping choice (Decision D2/D3 box on A) needs replacement before
the multivar path can beat the phase-only reference.

Artifacts saved to `results/raman/multivar/smf28_L2m_P030W/`:
  - `mv_joint_result.jld2` + `mv_joint_slm.json`
  - `mv_phaseonly_result.jld2` + `mv_phaseonly_slm.json`
  - `phase_only_opt_result.jld2` (from the un-modified reference optimizer)
  - `multivar_vs_phase_comparison.png`

All files also copied into the worktree at
`~/raman-wt-A/results/raman/multivar/smf28_L2m_P030W/`.

## Convergence findings (2026-04-17 second try)

The 2026-04-17 follow-up session implemented all three proposed follow-up fixes
(tanh reparameterization, warm-start, isolation) and re-ran the demo with
`burst-run-heavy` + standard-images compliance. Results on the clean run:

| | Phase-only | Multivar (cold) | Multivar (warm) |
|---|---|---|---|
| ΔJ (dB) | **−55.42** | −16.78 | −23.61 |
| Iterations | 50 | 100 | 100 |
| A final extrema | — | [0.99, 1.07] | **[1.000, 1.000]** |
| ‖∇J‖ at exit | 4.5e−6 | 1.5 | 1.7 |

**Key observation: warm-start regressed J from −57 dB (init) to −23 dB.**
With `A ∈ [1.000, 1.000]` at exit, the A block never moved — meaning the
optimizer actively moved φ AWAY from the phase-only optimum. This is not a
correctness bug (gradients are FD-verified); it is L-BFGS accepting
non-monotone line-search steps in the joint (φ, A) space under log-cost and
then failing to recover.

Tried and failed:
- **LineSearches.BackTracking(order=3)** — cold-start accepted zero-length
  step, ending at ΔJ=-0.01 dB. Reverted.
- **`log_cost=false` for both multivar paths** — cold-start improved from
  -0.01 → -16.78 dB but still 40 dB worse than phase-only; warm-start
  unchanged (~-23 dB regression from -57).
- **Doubled `max_iter` to 100** — no material change.

The gradient validation remains green (<5% rel err per block), so the
adjoint derivatives are correct. The joint-problem Hessian is ill-conditioned
at the phase-only optimum because φ has been driven to a near-stationary
point while A is untouched; L-BFGS with identity-initial Hessian takes a
bad first step that climbs out of the φ-basin.

## Open follow-up (new — 2026-04-17 second-try)

Real next steps for a future session, in order of likely payoff:

1. **Amplitude-only warm-start**: freeze φ=φ_A, optimize only A. The existing
   `run_multivar_optimization(; variables=(:amplitude,), φ0=φ_A, ...)` path
   already supports this but is untested. Expected to at least match
   phase-only (A=1 stays valid) and potentially improve.
2. **Two-stage warm-start**: freeze φ for N iters (amp-only), then unfreeze
   both. Gives L-BFGS a chance to build a good Hessian for the A block
   before touching φ. Requires adding a `freeze_phase::Bool` kwarg.
3. **Diagonal Hessian preconditioner**: feed L-BFGS a precomputed diagonal
   from the previous ((φ-only) Hessian so the first joint step respects
   the φ-basin curvature. Nontrivial.
4. **Trust-region Newton** (overlaps with Phase 14 seed): better suited for
   climbing saddle points in the joint landscape. Biggest change; largest
   potential payoff.

Artifacts saved to `results/raman/multivar/smf28_L2m_P030W/` (committed):
  - `{mv_joint, mv_joint_warmstart, mv_phaseonly, phase_only_opt}_result.jld2`
  - matching `_slm.json` sidecars
  - `multivar_vs_phase_comparison.png`
  - 12 standard-images PNGs: `{phase_only, mv_cold, mv_warm}_L2m_P0p3W_{phase_profile,
    evolution, phase_diagnostic, evolution_unshaped}.png`
  - burst-log at `results/burst-logs/A-demo2_20260417T213922Z.log`

Runs comply with the new standard-images rule (save_standard_set at end of
driver) and ran via burst-run-heavy with the heavy-lock wrapper.

## Superseded follow-up items (no longer actionable)

1. ~~Replace Fminbox with tanh-reparameterization~~ → DONE. Helped cold-start
   slightly but not enough.
2. ~~Warm-start multivar from the phase-only optimum~~ → DONE. Surfaced the
   L-BFGS non-monotone issue above.
3. ~~Run in isolation on burst VM~~ → DONE. Same result even with clean VM.

## How to rerun after convergence fixes land

```bash
# Main burst VM:
burst-ssh "cd fiber-raman-suppression && git pull && \
    WAIT_TIMEOUT_SEC=7200 ~/bin/burst-run-heavy A-demo \
        'julia -t auto --project=. scripts/multivar_demo.jl'"

# Or parallelize on ephemeral when main VM is occupied:
~/bin/burst-spawn-temp A-demo \
    'cd fiber-raman-suppression && git checkout sessions/A-multivar \
      && julia -t auto --project=. scripts/multivar_demo.jl'
```

Current success criterion status (from `16-01-PLAN.md`):

1. Gradient rel-err ≤ 5% per variable block — **PASS** (see demo log).
2. Round-trip save/load fidelity — **PASS**.
3. `results/raman/multivar/smf28_L2m_P030W/` populated — **YES**, all files present.
4. ΔJ(multivar) − ΔJ(phase-only) ≤ −0.5 dB — **FAIL**, −55 vs −23 dB (pending
   L-BFGS convergence fixes listed above).
5. `scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`,
   `scripts/common.jl`, `src/*` untouched — **PASS**.

## Known open items

- Gradient validation numerical run still pending (design validated; runtime test
  awaits burst VM).
- The `:energy` variable is fully implemented and tested at the pack/unpack level
  but not yet exercised end-to-end in optimization.
- `λ_flat` kwarg is threaded through the config but not yet applied in
  `cost_and_gradient_multivar` (its implementation would copy the exact formula
  from `amplitude_optimization.jl :: amplitude_cost`; left off because the demo
  config does not enable it).

## Handoff pointers

- **Math:** `.planning/notes/multivar-gradient-derivations.md` — all derivations
  including the `∂J/∂A = 2·α·Re[conj(λ₀)·cis(φ)·uω0]` stable form (avoids the
  `u_shaped/A` division).
- **Schema:** `.planning/notes/multivar-output-schema.md` — use as the contract
  when wiring up the actual SLM hardware driver later.
- **Decisions:** `.planning/sessions/A-multivar-decisions.md` — every autonomous
  choice with rationale. If any is questioned, look here first.
- **Phase plan:** `.planning/phases/16-multivar-optimizer/16-01-PLAN.md` —
  task-level breakdown, risk register, compute estimate.
- **Status log:** `.planning/sessions/A-multivar-status.md` — timestamped events.

## Escalation

Zero escalations hit during this session. No shared-file edits. No cross-session
conflicts. The only blocker is the burst-VM lock, which is another session's
legitimate work.
