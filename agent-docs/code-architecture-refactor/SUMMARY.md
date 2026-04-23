# Code Architecture Refactor Summary

Date: 2026-04-23

## Scope

This pass audited duplicated implementation patterns across Raman setup,
optimization objectives, output writing, trust reports, and research drivers.
The code changes were intentionally small and behavior-preserving:

- extract the duplicated single-mode setup path shared by
  `setup_raman_problem` and `setup_amplitude_problem`
- extract shared objective-regularization primitives used by SMF, MMF, and
  multivariable cost paths
- extract shared objective-surface metadata and manifest update helpers

## Duplication And Abstraction Audit

### Stable enough to extract now

- Single-mode setup in `scripts/lib/common.jl` had duplicated validation,
  preset resolution, SPM-aware grid auto-sizing, `sim`/`fiber` construction,
  initial state creation, and Raman mask construction across phase and
  amplitude setup functions.
- This is stable project infrastructure: both functions already shared the
  tuple return shape `(uω0, fiber, sim, band_mask, Δf, raman_threshold)` and
  both use `MultiModeNoise.get_disp_fiber_params_user_defined`.
- Extracted private helpers:
  - `_validate_single_mode_setup`
  - `_auto_size_single_mode_grid`
  - `_setup_single_mode_problem`

### Extracted after setup cleanup

- Regularizer implementations were repeated across SMF, MMF, and multivariable
  cost paths:
  - second-difference GDD penalty
  - input-edge boundary penalty
  - log scaling after the full linear surface
- Extracted private script-library helpers in `scripts/lib/regularizers.jl`:
  - `add_gdd_penalty!`
  - `add_boundary_phase_penalty!`
  - `add_shared_boundary_phase_penalty!`
  - `apply_log_surface!`
- Rewired:
  - `scripts/lib/raman_optimization.jl`
  - `scripts/research/mmf/mmf_raman_optimization.jl`
  - `scripts/research/multivar/multivar_optimization.jl`

### Extracted after regularizer cleanup

- Objective-surface metadata construction was duplicated across:
  - `scripts/lib/raman_optimization.jl::raman_cost_surface_spec`
  - `scripts/research/mmf/mmf_raman_optimization.jl::mmf_cost_surface_spec`
  - `scripts/research/multivar/multivar_optimization.jl::multivar_cost_surface_spec`
  - fallback spec construction in `scripts/research/analysis/numerical_trust.jl`
- Extracted `scripts/lib/objective_surface.jl`:
  - `active_linear_terms`
  - `build_objective_surface_spec`
- Canonical manifest append/replace behavior was inline in `run_optimization`.
  Extracted `scripts/lib/manifest_io.jl`:
  - `read_manifest`
  - `upsert_manifest_entry!`
  - `write_manifest`
  - `update_manifest_entry`

### Stable, but deferred

- Result payload construction in `run_optimization` is still bulky and could be
  split into a canonical result-record builder, but that touches JLD2 schema
  expectations and should wait.

### Legacy but valuable

- `scripts/research/longfiber/longfiber_setup.jl` repeats some single-mode
  setup logic deliberately to bypass `setup_raman_problem` auto-sizing for
  long-fiber research grids. Do not fold this into the generic helper without
  preserving the explicit no-auto-size contract.
- Phase/research drivers still contain many direct `JLD2.jldsave` payloads.
  They are valuable research records, but should not be treated as canonical
  output schema implementations.

### Research-local

- Phase-specific sweep, transfer, trust-region, and propagation scripts under
  `scripts/research/` and `scripts/archive/` often preserve study-specific
  metadata and file names. They should remain local unless a pattern is reused
  by canonical workflows.

### Garbage / low-value cleanup candidates

- Ad hoc manifest writing and direct JSON payload construction repeat in
  several workflows. These are cleanup candidates only after deciding which
  manifests are durable public outputs versus one-off study provenance.
- Direct `common.jl` inclusion previously depended on caller-side `using Printf`
  for macro expansion. This pass fixed that include hygiene.

## Refactor Plan

Immediate:

- Keep single-mode setup centralized in `_setup_single_mode_problem`.
- Keep objective regularizer formulas centralized in `scripts/lib/regularizers.jl`.
- Add focused tests around public setup parity, regularizer formulas, and
  include/load hygiene.
- Leave long-fiber setup separate because its no-auto-size behavior is a
  scientific-method constraint, not accidental duplication.

Next:

- Consider a canonical result-record builder for `run_optimization`, keeping
  the current JLD2 keys unchanged.
- Audit whether research-side manifests should use `manifest_io.jl` or remain
  study-local provenance files.

Later:

- Promote stable problem-construction code from script helpers into `src/`
  once the desired typed interface is clear.
- Introduce a reusable objective-surface descriptor that all cost/HVP/trust
  paths can serialize without ad hoc strings.
- Normalize research output payloads only after deciding which historical
  schemas must remain readable.

## Changed

- `scripts/lib/common.jl`
  - Added explicit top-level `using Printf` for include safety.
  - Added private single-mode setup helpers.
  - Rewired `setup_raman_problem` and `setup_amplitude_problem` through the
    shared builder while preserving their public signatures and return tuples.
- `scripts/lib/regularizers.jl`
  - Added shared GDD, boundary, and log-surface helpers.
- `scripts/lib/objective_surface.jl`
  - Added shared objective-surface metadata helpers.
- `scripts/lib/manifest_io.jl`
  - Added JSON manifest read/upsert/write helpers.
- `scripts/lib/raman_optimization.jl`
  - Replaced duplicated SMF regularizer blocks with shared helpers.
  - Replaced objective-surface construction and manifest update logic with
    shared helpers.
- `scripts/research/analysis/numerical_trust.jl`
  - Replaced fallback cost-surface spec construction with shared helper.
- `scripts/research/mmf/mmf_raman_optimization.jl`
  - Replaced duplicated MMF shared-phase regularizer blocks with shared helpers.
  - Replaced objective-surface construction with shared helper.
- `scripts/research/multivar/multivar_optimization.jl`
  - Replaced duplicated phase regularizer and log-surface blocks with shared
    helpers while preserving multivariable diagnostics.
  - Replaced objective-surface construction with shared helper.
- `test/tier_fast.jl`
  - Added a `Single-mode setup contract` test proving phase and amplitude setup
    produce identical core objects when called with the same parameters.
  - Added simulation-free tests for the regularizer helper formulas.
  - Added simulation-free tests for objective-surface and manifest helpers.

## Tests Run

- `julia -t auto --project=. test/tier_fast.jl`
- `julia -t auto --project=. test/test_phase27_numerics_regressions.jl`
- `julia -t auto --project=. scripts/dev/smoke/test_multivar_unit.jl`
- `julia -t auto --project=. scripts/dev/smoke/test_multivar_gradients.jl`
- `julia -t auto --project=. test/test_phase16_mmf.jl`
- `julia -t auto --project=. test/test_phase28_trust_report.jl`
- `julia -t auto --project=. test/test_phase13_hvp.jl`
- Fresh-process include checks:
  - `scripts/lib/objective_surface.jl`
  - `scripts/lib/manifest_io.jl`
  - `scripts/lib/regularizers.jl`
  - `scripts/lib/common.jl`
  - `scripts/lib/raman_optimization.jl`
  - `scripts/research/analysis/numerical_trust.jl`
  - `scripts/research/multivar/multivar_optimization.jl`
  - `scripts/workflows/run_sweep.jl`
  - `scripts/research/longfiber/longfiber_setup.jl`
  - `scripts/research/mmf/mmf_setup.jl`
  - `scripts/research/mmf/mmf_raman_optimization.jl`

## Risky Areas Not Touched

- Forward/adjoint solver internals in `src/simulation/`.
- Base physics cost and adjoint gradient formulas in SMF, MMF, and multivariable
  paths.
- HVP/trust-region oracle behavior.
- Long-fiber no-auto-size setup.
- JLD2 payload schemas and historical research outputs.
- Standard image generation behavior.
