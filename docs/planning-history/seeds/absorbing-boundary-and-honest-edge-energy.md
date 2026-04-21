# Seed: Absorbing-boundary audit and honest edge-energy metric

**Planted:** 2026-04-20
**Source:** Phase 25 Second-Opinion Addendum — quick task
`260420-oyg-independent-numerics-audit-of-fiber-rama`.

## Why this deserves a phase

The project's simulation core uses a **super-Gaussian order-30
attenuator** at 85% of the time-window half-width, built in
`src/helpers/helpers.jl:59-63` and applied inside the forward ODE RHS
at `src/simulation/simulate_disp_mmf.jl:34` (`@. ut = attenuator *
uω`) and similarly inside the adjoint. This is a **hard absorbing
boundary**: any energy that walks into the outer 15% of the temporal
window is silently attenuated inside the ODE.

`scripts/common.jl:289-298` (`check_boundary_conditions`) measures the
**surviving** edge energy (energy in the outer 5% *after* absorption).
That check does not see energy the attenuator has already removed.

Consequence: at long fiber / high power — exactly the regimes the
project cares most about (Session F long-fiber, Session D -80 dB
baseline) — the reported `J_dB` is the dB of a *partially-absorbed*
field, not of the physical field. `recommended_time_window` in
`scripts/common.jl` enlarges the window when walk-off or SPM predict
trouble, but the attenuator is still present inside that enlarged
window; the formula shifts the onset of absorption but does not
eliminate it.

This is a **physics-coupled numerical-honesty failure** distinct from
"the grid was too small". An honest pipeline must expose
*how much energy was absorbed by the boundary on this run*, at a
minimum as a scalar diagnostic, and ideally as a z-resolved trace.

## Why this belongs on the roadmap

Phase 25 correctly framed planning drift and trust governance as real
blockers. Absorbing-boundary mass loss is the same class of problem at
a lower level: a numerical surface that silently violates energy
conservation and whose violation is not tracked by any run report.
Without this metric, "got -80 dB" is not comparable across
`L_fiber` or `P_cont` regimes.

The project already accepted the lesson "good dB on a bad grid is not
acceptable" (Phase 21 recovery). The current attenuator is a more
subtle cousin: good dB on a *good-looking* grid that is quietly losing
mass at the boundary.

## Scope

- Add a running diagnostic: per ODE step (or at a regular `zsave`
  schedule), compute `E_absorbed(z) = ‖u_before_attenuator‖² −
  ‖u_after_attenuator‖²` and log it. Ideally expose as a `sim` field
  or as an `ode_sol` callback rather than a one-shot end-of-run scalar.
- Produce, per run, a single scalar
  `total_edge_absorption_fraction =
  ∫ E_absorbed(z) dz / E_input` that goes into the trust-report bundle
  alongside edge_fraction, energy_drift, and determinism status.
- Fail loud (not silently warn) when
  `total_edge_absorption_fraction > threshold` (e.g. 1e-3), since that
  is the condition under which reported dB numbers are unreliable.
- Investigate alternatives to the hard super-Gaussian: perfectly-matched
  layer (PML) in time, windowed convolution with a tapered mask that
  does *not* remove energy but reshapes it back to the interior, or an
  explicit energy-conserving absorber that puts removed energy into a
  tracked bucket rather than into `/dev/null`.
- Audit whether the attenuator is actually needed at all in some
  regimes — for short fibers where pulse walk-off is sub-fs, the
  attenuator may be pure numerical machinery with no physics role.

## Deliverables

- A per-run scalar `total_edge_absorption_fraction` added to the
  JLD2 payload of every `_result.jld2` and printed in the run
  summary box.
- A z-resolved absorption diagnostic accessible when `zsave` is set.
- A trust-report rule: any run with absorption fraction above a
  published threshold is flagged (not a soft `@warn` — a standing bar
  in the canonical `opt_result` validator).
- A short technical note comparing super-Gaussian attenuator,
  time-domain PML, and "no attenuator" on one or two hard regimes
  (Session F long-fiber, Session D deep suppression).
- Recommendation: keep, replace, or tune the attenuator per regime.

## Why not fold into the conditioning seed

Overlap: the trust-report utility is shared. Distinction: this seed
requires modifying (or shadowing) `src/simulation/*.jl` to expose
absorption telemetry, while the conditioning seed lives at the
optimizer / run-summary layer. They can ship together as one
"numerical-governance bundle" (see `25-REPORT.md#Second-Opinion
Addendum`) or as two sequential mini-phases; scoping them separately
keeps each tractable.

## Dependencies

- Can run concurrently with
  `cost-surface-coherence-and-log-scale-audit`.
- Informs the `performance-modeling-and-roofline-audit` seed (every
  absorption-telemetry call is a runtime cost that must be budgeted).
- Must precede any publication of long-fiber / high-power dB numbers
  that are compared across fiber regimes.

## Hypothesis

Some of the "hardest" regimes the project studies are partly hard
*because* they lose energy to the attenuator, not because the physics
is fundamentally harder. Exposing the absorption fraction will let the
project either (a) tighten the physical trustworthiness of its
published dB numbers, (b) re-allocate compute to regimes where the
attenuator is benign, or (c) redesign the boundary treatment.

## Success condition

A long-fiber canonical run produces a trust report that explicitly
says something like:

```
edge_fraction (surviving):      4.2e-7   ✓
total_edge_absorption_fraction: 3.1e-4   ✓ (below 1e-3 threshold)
energy_drift:                   1.1e-9   ✓
determinism_status:             BIT_IDENTICAL
```

…and fails the run when that absorption fraction exceeds the threshold
instead of silently reporting a dB that was measured on a field
missing 5% of its mass.
