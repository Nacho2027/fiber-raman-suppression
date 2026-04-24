# Maintainability Refactor Pass Summary

Date: 2026-04-23

## Changed In This Follow-On Slice

- Added a shared canonical five-run registry in
  `scripts/lib/canonical_runs.jl`.
- Rewired both maintained users of that suite definition:
  - `scripts/lib/raman_optimization.jl`
  - `scripts/workflows/run_comparison.jl`
- Added `peak_power_from_average_power(...)` in `scripts/lib/common.jl` as the
  one obvious maintained helper for average-power → peak-power conversion.
- Rewired maintained callers onto that helper:
  - `scripts/lib/common.jl::_auto_size_single_mode_grid`
  - `scripts/lib/common.jl::print_fiber_summary`
  - `scripts/lib/common.jl::setup_amplitude_problem`
  - `scripts/workflows/run_sweep.jl`
  - `scripts/workflows/run_comparison.jl`
  - `scripts/workflows/generate_presentation_figures.jl`
- Rewired maintained workflows that read canonical per-run artifacts to prefer
  package-level canonical loading where safe:
  - `scripts/workflows/run_sweep.jl`
  - `scripts/workflows/generate_presentation_figures.jl`
- Replaced the highest-value broken same-directory include chains in research
  scripts with explicit shared-library or neighboring-research includes:
  - `scripts/research/analysis/physics_insight.jl`
  - `scripts/research/analysis/phase_analysis.jl`
  - `scripts/research/analysis/verification.jl`
  - `scripts/research/propagation/propagation_reach.jl`
  - `scripts/research/propagation/propagation_z_resolved.jl`
  - `scripts/research/propagation/matched_quadratic_100m.jl`
  - `scripts/research/benchmarks/benchmark_threading.jl`
  - `scripts/research/benchmarks/benchmark_optimization.jl`
- Turned two heavyweight standalone scripts into explicit entrypoints instead of
  include-time script bodies:
  - `scripts/research/analysis/verification.jl`
  - `scripts/workflows/run_benchmarks.jl`
- Removed the remaining live duplicate of the canonical five-run suite from
  `scripts/research/analysis/verification.jl` by deriving its VERIF-02 config
  table from `canonical_raman_run_specs()`.
- Tightened canonical run metadata slightly by exposing `fiber_preset` directly
  in `scripts/lib/canonical_runs.jl` so downstream consumers do not need to
  reverse-engineer preset identity from names or physical coefficients.
- Added one shared artifact-summary adapter in `scripts/lib/run_artifacts.jl`
  so maintained report/inspection workflows consume canonical `_result.jld2`
  payloads through the same field mapping and suppression-quality logic.
- Added a shared sweep-aggregate row adapter in `scripts/lib/run_artifacts.jl`
  so maintained reports interpret aligned L x P aggregate grids in one place.
- Rewired maintained artifact readers onto that adapter where safe:
  - `scripts/workflows/inspect_run.jl`
  - `scripts/workflows/generate_presentation_figures.jl`
  - `scripts/workflows/generate_sweep_reports.jl`
  - `scripts/workflows/run_sweep.jl`
- Added fast regression coverage for:
  - the shared average→peak-power conversion helper
  - the canonical five-run registry contract
  - the shared canonical artifact-summary adapter
  - the shared sweep-aggregate row adapter

## Duplication And Ambiguity Audit

### Resolved now

- The maintained five-run canonical Raman suite no longer has two competing
  live definitions.
  Before:
  - `scripts/lib/raman_optimization.jl:803-906`
  - `scripts/workflows/run_comparison.jl:57-155`
  - `scripts/research/analysis/verification.jl` local `PRODUCTION_CONFIGS`
  Now:
  - shared authority in `scripts/lib/canonical_runs.jl`
  - maintained runners and VERIF-02 consume that registry instead of
    open-coding it

- Average-power → peak-power conversion no longer has multiple maintained
  formulas with conflicting semantics.
  Before:
  - correct sech²-factor path in `scripts/lib/common.jl:338-341`
  - local wrappers in `scripts/workflows/run_sweep.jl:129-136`,
    `scripts/workflows/run_comparison.jl:193-195`,
    `scripts/workflows/generate_presentation_figures.jl:72-75`
  - inconsistent no-factor diagnostics in `scripts/lib/common.jl:138` and
    `scripts/lib/common.jl:547`
  Now:
  - shared authority in `scripts/lib/common.jl::peak_power_from_average_power`

### Still active ambiguity

- Maintained sweep/report workflows now share per-run artifact mapping and the
  main sweep-aggregate grid-to-row mapping. Remaining report-layer duplication
  is mostly formatting and legacy multistart summary handling.

- Same-directory include chains still exist in maintained research code and can
  still obscure whether a dependency is study-local or shared:
  - trust-region helpers that intentionally compose locally:
    `scripts/research/trust_region/*.jl`
  - deeper phase-study chains such as `scripts/research/phases/phase31/*.jl`
  - recovery/MMF orchestration that still mixes local and shared research code
    by design

- Regeneration/reconstruction helpers remain split by schema family:
  - canonical generic regeneration in
    `scripts/workflows/regenerate_standard_images.jl`
  - long-fiber schema bridge in
    `scripts/research/longfiber/longfiber_regenerate_standard_images.jl`
  - simple-profile artifact bridge in
    `scripts/research/simple_profile/simple_profile_stdimages.jl`
  This remains justified for now, but the adapter boundary is still implicit.

- Research-local power helpers still exist in multiple files. They were not
  normalized in this pass because the active requirement was to fix the
  maintained/canonical surface first.

## Prioritized Refactor Plan

### Now

- keep `scripts/lib/common.jl` as the authority for single-mode setup and
  shared power conversion
- keep `scripts/lib/canonical_runs.jl` as the authority for the maintained
  five-run canonical suite
- avoid adding new maintained copies of either concept

### Next

- consider whether legacy multistart aggregate handling should get the same
  adapter treatment as per-run and sweep-grid artifacts
- clean up the next maintained same-directory include chains in research
  analysis / propagation scripts
- decide which research manifests deserve promotion and which should remain
  explicit local provenance

### Later

- promote stable single-mode setup interfaces into `src/` once the public
  contract is settled
- revisit standard-image regeneration as explicit schema adapters around a
  shared core if more maintained families appear
- normalize driver boilerplate only where multiple active maintained users make
  the abstraction worth carrying

## Risks Deferred

- No solver, adjoint, or cost-function numerics were changed.
- No long-fiber or MMF setup behavior was changed.
- No research-local power helper was force-normalized just for symmetry.
- Maintained report-generation still has some direct payload-shape knowledge.
- Historical planning-history docs still contain older power-conversion text
  that should not be treated as the maintained authority.
- `scripts/research/analysis/verification.jl` is now an explicit entrypoint,
  but it still remains a fairly thick research harness rather than a thin
  orchestration wrapper over smaller helpers.

## Tests Run

- `julia -t auto --project=. test/tier_fast.jl`
- `julia -t auto --project=. -e 'using MultiModeNoise; include("scripts/lib/raman_optimization.jl"); include("scripts/workflows/run_comparison.jl"); include("scripts/workflows/run_sweep.jl"); include("scripts/workflows/generate_presentation_figures.jl"); println("include smoke ok")'`
- `julia -t auto --project=. -e 'using MultiModeNoise; include("scripts/research/analysis/physics_insight.jl"); include("scripts/research/analysis/phase_analysis.jl"); include("scripts/research/propagation/propagation_reach.jl"); include("scripts/research/propagation/propagation_z_resolved.jl"); include("scripts/research/propagation/matched_quadratic_100m.jl"); include("scripts/research/benchmarks/benchmark_threading.jl"); include("scripts/research/benchmarks/benchmark_optimization.jl"); println("research include smoke ok")'`
- `julia -t auto --project=. -e 'using MultiModeNoise; include("scripts/workflows/run_benchmarks.jl"); include("scripts/research/analysis/verification.jl"); println("entrypoint include smoke ok")'`
