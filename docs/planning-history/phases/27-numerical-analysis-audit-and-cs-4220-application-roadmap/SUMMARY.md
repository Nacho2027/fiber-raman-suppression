# Phase 27 Summary — Numerical analysis audit and CS 4220 / NMDS application roadmap

## Top Findings

1. The most valuable CS 4220 / NMDS ideas for this repo are
   conditioning/scaling, forward-backward error, globalization,
   Krylov/Lanczos, regularization, continuation, and performance modeling.
2. The repo's biggest remaining numerical gap is not "lack of advanced
   optimization" in the abstract; it is the absence of a coherent conditioning +
   trust framework that future optimizer work can rely on.
3. The project already has strong numerical assets — especially determinism,
   forward/adjoint validation, and matrix-free HVP infrastructure — that should
   be extended rather than replaced.
4. The NMDS book strengthened the case for a dedicated roofline/Amdahl-style
   performance phase and added extrapolation/acceleration as a plausible
   backlog item for study families.
5. Planning drift is now a practical blocker to clean numerical progress.

## Deliverables

- `27-CONTEXT.md` — scope and locked decisions
- `27-RESEARCH.md` — numerics crosswalk and prescriptive guidance
- `27-REPORT.md` — main report
- 7 total seeds under `.planning/seeds/` after the NMDS additions

## Recommended Next Steps

1. Promote the conditioning/backward-error seed first.
2. Treat globalization as mandatory before any serious Newton/Hessian rollout.
3. Use the existing HVP/Lanczos path as the base for future second-order work.
4. Add a performance-modeling phase before assuming more hardware or threads
   will solve runtime pain.

## Verdict

Phase 27 is complete as a research-and-mapping phase. It did not modify
`src/**`, and it converted the CS 4220 + NMDS material into concrete,
repo-specific numerical recommendations plus future-phase seeds.

---

## Second-Opinion Addendum (2026-04-20)

Skeptical code-verified re-audit completed in quick task
`260420-oyg-independent-numerics-audit-of-fiber-rama`. Full trail in
`.planning/quick/260420-oyg-.../260420-oyg-NOTES.md`. See
`27-REPORT.md#Second-Opinion Addendum`,
`27-RESEARCH.md#Second-Opinion Addendum`, and
`27-REVIEWS.md#Second-Opinion Addendum` for per-document updates.

### What's new after code verification

- **Two new seeds planted** (total now 9):
  - `cost-surface-coherence-and-log-scale-audit.md`
  - `absorbing-boundary-and-honest-edge-energy.md`
- **One seed reframed**, not rewritten: `reduced-basis-phase-regularization`
  should extend the existing DCT machinery at
  `scripts/amplitude_optimization.jl:180-209`, not start greenfield.
- **Overall risk raised** from LOW-MEDIUM to **MEDIUM** — two
  previously-uncaught medium-severity issues (cost-surface incoherence,
  untracked boundary absorption) plus one latent bug
  (`plot_chirp_sensitivity` applying `lin_to_dB` to dB values).

### Top 5 numerical risks (code-verified ranking)

1. **Cost-surface incoherence** across `cost_and_gradient`,
   `phase13_hvp::build_oracle`, regularizer gradients, and
   `chirp_sensitivity` — different files differentiate different
   surfaces.
2. **Absorbing-boundary mass loss is untracked** — super-Gaussian
   attenuator silently absorbs edge energy; no running metric.
3. **Chirp sensitivity latent bug** at
   `raman_optimization.jl:361` — `lin_to_dB` on already-dB values.
4. **Planning drift** (unchanged from original).
5. **Scaling / conditioning of full-grid φ with mixed-unit `sim` dict**
   (`src/helpers/helpers.jl:51-57`).

### Top 5 highest-leverage improvements

1. Cost-surface coherence + log-scale unification
   (one short phase, fixes risks 1 and 3 together).
2. Extend DCT reduced-basis from amplitude to phase.
3. Trust-report bundle with running edge-absorption metric +
   condition-number probe (reuse Arpack).
4. Adaptive FD-HVP step size tied to `‖∇J‖`.
5. Taylor-remainder-2 slope tests for all gradient-validation paths.

### Single most important next numerics phase

**Numerical-governance bundle** — a refinement of Phase 27's
`numerics-conditioning-and-backward-error-framework` seed to explicitly
include log/linear cost unification, adaptive FD-HVP ε, running
edge-absorption metric, per-run condition-number probe, and Taylor-
remainder-2 slope checks. Without this bundle, truncated-Newton /
globalization / sharpness phases will be comparing methods on an
unstable objective surface. With it, each downstream phase inherits a
clear contract.

### Status

Phase 27 stays **complete as a research-and-mapping phase**. The
second-opinion addendum sharpens framings and adds evidence but does not
reopen the phase. The two new seeds and the single-most-important-next-
phase refinement are the actionable outputs of this second pass.
