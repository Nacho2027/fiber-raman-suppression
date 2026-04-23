# Seed: Cost-surface coherence and log-scale unification audit

**Planted:** 2026-04-20
**Source:** Phase 25 Second-Opinion Addendum — quick task
`260420-oyg-independent-numerics-audit-of-fiber-rama`.

## Why this deserves a phase

The repo's optimization, HVP, regularization, and diagnostic paths each
differentiate a *different* cost surface. Verified in-code:

| File:line | Surface being differentiated | Regularizer scaled? |
|---|---|---|
| `scripts/raman_optimization.jl:121-129` (log_cost=true, default) | 10·log₁₀(J_linear) | **No** — GDD/boundary gradients added linearly |
| `scripts/raman_optimization.jl:127-128` (log_cost=false) | J_linear | N/A |
| `scripts/amplitude_optimization.jl:402-446` | J_linear + regs | Yes, flat weights |
| `scripts/hvp.jl:74` (HVP oracle) | J_linear, no regularizers | N/A |
| `scripts/raman_optimization.jl:332` (chirp sensitivity) | dB (default) | N/A |
| `scripts/raman_optimization.jl:361` (plot_chirp_sensitivity) | **applies 10·log₁₀ a second time → DomainError** | N/A |

Consequences verified by reading code:

1. In `raman_optimization.jl`, the physics gradient is multiplied by
   `10/(J·ln 10)` but the GDD penalty gradient (line 143) and boundary
   penalty gradient (line 171) are **not**. Effective regularizer
   weight therefore drops ~1 dB per dB of suppression. The user-facing
   knob `λ_gdd = 1e-4` is not a fixed weight.

2. `hvp.jl::build_oracle` constructs its Hessian-probe cost
   from `cost_and_gradient` with `log_cost=false, λ_gdd=0,
   λ_boundary=0`. So the **Hessian analyzed by
   `hessian_eigspec.jl`** is the Hessian of the **linear
   physics-only** cost — not the Hessian of the **regularized dB cost**
   that L-BFGS is actually minimizing. Every Arpack eigenvalue in the
   existing analysis is on a related-but-distinct surface.

3. `plot_chirp_sensitivity` at `scripts/raman_optimization.jl:361`
   runs `J_gdd_dB = lin_to_dB.(J_gdd)`. With `cost_and_gradient`
   defaulting to log_cost=true, `J_gdd` is already in dB → the line
   is `10·log10(-40.0)` → `DomainError`. Either this path is dead or
   canonical runs throw silently. Either way a regression test is
   missing.

This is not a physics bug. It is a **numerical architecture bug**: the
cost surface being minimized, the cost surface being curvature-probed,
and the cost surface being plotted are three different surfaces. CS
4220's conditioning framing and NMDS's mixed-error taxonomy both
require these to be one coherent object before comparing methods.

## Why this belongs before truncated-Newton / sharpness work

Phase 25 correctly prioritizes conditioning / backward-error framework
before 2nd-order optimizer work. This seed is the concrete, code-
locatable sub-piece of that priority: *what cost are we actually
differentiating, where, and with what scaling?*

Without this, a truncated-Newton rollout that reuses `hvp.jl`
inherits a Hessian on surface A while being evaluated on surface B, and
every "Newton improved by ΔdB" comparison becomes ambiguous.

## Scope

- Pick one canonical `cost_and_gradient_*` contract for the whole
  project — explicit args for (i) log vs linear, (ii) which regularizers
  are included, (iii) whether log-scaling applies to the full
  `J_total` or only to the physics piece.
- Make the HVP oracle (`hvp.jl::build_oracle`) and
  `chirp_sensitivity` take the same cost-convention args.
- Fix the `plot_chirp_sensitivity` latent bug; add a unit test that
  covers both `log_cost=true` and `log_cost=false` paths end-to-end.
- Document the cost convention in `CLAUDE.md` at the same priority level
  as the determinism convention.
- Add a Taylor-remainder-2 slope test (`‖J(φ+εv) − J(φ) − ε∇J·v‖`
  decays like ε²) to the standard gradient-validation harness —
  ratio checks cannot catch uniformly-mis-scaled gradients.

## Deliverables

- One `cost_convention` spec in the project docs, cited by at least four
  scripts.
- Unit tests for each gradient path that verify *both* the O(ε²) slope
  and the ratio against FD.
- A canonical Hessian-probe cost (log / linear choice) documented in
  `hvp.jl` and reflected in the Arpack-analysis run summaries.
- Fixed chirp-sensitivity path with a regression test.
- A run-summary line that says which cost surface was used, which the
  next seed (absorbing-boundary) and the existing conditioning seed
  both consume.

## Hypothesis

Once cost-surface coherence is fixed, the comparison between L-BFGS,
truncated-Newton, and sharpness-aware variants becomes well-posed;
reported dB numbers across phases become cross-commensurable; and
Phase 13's Hessian eigenspectrum acquires an unambiguous interpretation.

## Why not do this inside the conditioning seed

Scope. The existing
`numerics-conditioning-and-backward-error-framework` seed targets
*variables and stopping criteria*. This seed targets the *cost-function
surface itself and its derivatives*. They overlap at the trust-report
utility but diverge on implementation. Folding them together is also
acceptable — in that case this seed should be merged into the
conditioning seed as a numbered sub-objective, and the conditioning
seed should explicitly inherit the verification notes in
`.planning/quick/260420-oyg-.../260420-oyg-NOTES.md`.

## Dependencies

- Can run concurrently with `absorbing-boundary-and-honest-edge-energy`.
- Must precede any truncated-Newton or sharpness-aware-optimization phase
  that uses `hvp.jl`.
- Must precede any comparison study of L-BFGS vs. other optimizers.

## Success condition

Running the full Raman-suppression driver produces:
(i) no DomainError from the chirp-sensitivity path,
(ii) a documented cost-convention line in each run summary,
(iii) a Taylor-remainder-2 slope column in gradient-validation output,
(iv) an Arpack eigenspectrum explicitly labeled with which cost was
     differentiated.
