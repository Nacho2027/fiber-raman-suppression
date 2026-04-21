# Phase 16: Multi-Variable Spectral Optimizer — Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** Autonomous (Session A)
**Owner:** `sessions/A-multivar` branch

## Phase Boundary

Build a **third, parallel optimization path** — `optimize_spectral_multivariable` —
that jointly optimizes a subset of {spectral phase φ(ω), spectral amplitude A(ω),
pulse energy E, mode coefficients c_m} through a single forward-adjoint solve per
iteration. The existing paths — `optimize_spectral_phase` (phase-only) and
`optimize_spectral_amplitude`/`optimize_spectral_amplitude_lowdim` — remain
**byte-for-byte unchanged**. All three paths must coexist so the user can A/B
compare them for the same config.

**Primary deliverable:** a working multi-variable optimizer in the new namespace
`scripts/multivar_*.jl`, with gradient-validation tests passing at 1e-6 tolerance
and a demonstration run where joint (φ, A) beats phase-only at the same fiber,
power, and iteration count.

**First-milestone default variable set:** `(:phase, :amplitude)` — jointly. Mode
coefficients and energy are API-stubbed for future extensions (see decisions
D3, D4 in `.planning/sessions/A-multivar-decisions.md`).

## Decisions

See the canonical decision log: `.planning/sessions/A-multivar-decisions.md`
(D1–D10 cover variable set, preconditioning, energy handling, output format,
regularization defaults, demo config).

See gradient derivations: `.planning/notes/multivar-gradient-derivations.md`.
See output schema: `.planning/notes/multivar-output-schema.md`.

## Existing Code Insights

### Reusable assets (NO modifications)
- `scripts/raman_optimization.jl :: cost_and_gradient` — reference for how phase
  gradient is assembled from λ₀ via the adjoint.
- `scripts/amplitude_optimization.jl :: cost_and_gradient_amplitude` — reference
  for amplitude gradient + regularizers.
- `scripts/common.jl :: setup_raman_problem`, `spectral_band_cost`,
  `check_boundary_conditions`, `recommended_time_window` — unchanged.
- `src/simulation/sensitivity_disp_mmf.jl` — adjoint ODE (no changes required;
  all multivar gradients are algebraic re-projections of the same λ₀).
- `Optim.jl` `LBFGS`, `Fminbox`, `only_fg!`, `Optim.Options` — existing stack.

### Established patterns to follow
- Include guard `if !(@isdefined _FOO_LOADED)`
- `@kwdef mutable struct` for parameter containers
- Script constant prefix `MV_` (MultiVariable) for this phase
- Output directory `results/raman/multivar/<config>/` and
  `results/images/multivar/`

### Integration points
- New `scripts/multivar_optimization.jl` loaded via `include()` in run scripts.
- No changes to `src/` or `scripts/common.jl`.
- Burst VM workflow identical to phases 13–14.

## Specific Ideas

- Share ONE forward-adjoint solve per iteration; compute all enabled-variable
  gradients from the same `λ₀` (derivations §7). This makes the added-variable
  cost roughly O(Nt) extra, not a full re-solve.
- Preconditioning via change-of-variables (derivations §8) keeps L-BFGS
  conditioning clean for mixed-scale params.
- Dual-file output (JLD2 + JSON sidecar) — see output schema doc.
- Demo config: SMF-28 L=2m P=0.30W. Already a canonical "strong Raman" run from
  `raman_optimization.jl :: Run 2`.

## Deferred / Out of scope (strict)

- **Mode coefficients `c_m` with M > 1** — Session C's domain. Stubbed API only.
- **Newton's full Hessian** — Phases 13/14/future.
- **Real experimental SLM integration** — simulation only. The output JSON
  sidecar is the hand-off point.
- **Auto-tuning λ_* regularization weights** — manual opt-in for now.

## Escalation triggers

Stop and ask the user (per autonomous-mode rules) if any of these happen:
- Adjoint gradient derivation forces a change to
  `src/simulation/sensitivity_disp_mmf.jl`. (Not hit as of decision close.)
- Gradient validation fails the 1e-6 rel.-error threshold for any variable.
- Collision with another session's owned namespace.
