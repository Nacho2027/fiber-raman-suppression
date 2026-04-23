# Maintainability Refactor Pass Summary

Date: 2026-04-23

## Changed

- Added `setup_raman_problem_exact` in
  `scripts/lib/common.jl:464-501`.
- Generalized the private builder in `scripts/lib/common.jl:360-416` with an
  `auto_size` switch so auto-sized and exact reconstruction share the same
  preset resolution, validation, sim/fiber construction, launch-field
  creation, and Raman-band masking.
- Rewired exact-grid consumers to the shared helper:
  - `scripts/validation/validate_results.jl:117-141`
  - `scripts/lib/visualization.jl:1656-1668`
  - `scripts/research/simple_profile/simple_profile_stdimages.jl:48-61`
- Added a fast regression proving exact setup preserves the requested grid and
  auto-sized setup still expands unsafe grids:
  - `test/tier_fast.jl:147-184`
- Made `src/io/results.jl` the real canonical result writer/reader for the
  current Raman payload shape while remaining backward-compatible with the older
  package-centric `save_run` contract.
- Rewired canonical Raman result serialization in
  `scripts/lib/raman_optimization.jl` through `MultiModeNoise.save_run`.
- Moved canonical manifest authority into `src/io/results.jl` and exported:
  - `read_run_manifest`
  - `write_run_manifest`
  - `update_run_manifest_entry`
  - `upsert_run_manifest_entry!`
  - `load_canonical_runs`
- Converted `scripts/lib/manifest_io.jl` into a compatibility shim over the
  package-level manifest helpers.
- Rewired maintained readers to the canonical package helpers:
  - `scripts/workflows/run_comparison.jl`
  - `scripts/research/analysis/physics_insight.jl`
- Added fast coverage for both:
  - legacy package-style `save_run` payloads
  - canonical Raman `_result.jld2` payloads
- Grouped the test tree into:
  - `test/core/`
  - `test/cost_audit/`
  - `test/phases/`
  - `test/trust_region/`
  while keeping `test/runtests.jl` and tier files as the stable entrypoints.
- Cleaned up the worst include-boundary problems without changing behavior:
  - `scripts/workflows/run_comparison.jl` now includes `../lib` explicitly
    instead of relying on a broken same-directory include assumption
  - `scripts/workflows/generate_sweep_reports.jl` now exposes
    `generate_sweep_reports_main()`
  - `scripts/workflows/generate_presentation_figures.jl` now exposes
    `generate_presentation_figures_main()`
  - `scripts/canonical/generate_reports.jl` no longer depends on order-sensitive
    `main` rebinding across included workflow files
  - `scripts/research/simple_profile/simple_profile_driver.jl` now declares
    `standard_images.jl` at top level instead of function-local hidden includes
- Added a fast fresh-process include smoke check for the maintained scripts
  above, and cleaned stale test header paths after the test-tree move.
- Reorganized active human-facing docs into clearer buckets:
  - `docs/guides/`
  - `docs/architecture/`
  - `docs/synthesis/`
  - `docs/status/`
  - `docs/reference/`
- Rewrote the codebase visual map as renderer-safe plain-text diagrams instead
  of Mermaid so it works in minimal markdown viewers.
- Updated repo and script indexes to point at the new doc layout.

## Duplication And Ambiguity Audit

### Resolved now

- Exact single-mode reconstruction had multiple local implementations:
  - authoritative shared builder in `scripts/lib/common.jl:360-416`
  - validation-local rebuild in `scripts/validation/validate_results.jl:117-141`
  - visualization-local rebuild in `scripts/lib/visualization.jl:1656-1668`
  - simple-profile reconstruction in
    `scripts/research/simple_profile/simple_profile_stdimages.jl:48-61`
- This now has one obvious authority:
  `scripts/lib/common.jl::setup_raman_problem_exact`.

### High-value active ambiguity still present

- Result writing and canonical manifest I/O now have one authority for
  maintained Raman workflows: `src/io/results.jl`.
- The remaining ambiguity is now narrower:
  what subset of research outputs should also be normalized onto this
  interface versus remain explicitly study-local.

- Same-directory include chains still exist in maintained research scripts and
  remain easy to misread because they hide whether a dependency is local,
  shared-library, or transitively pulled in:
  - `scripts/research/analysis/phase_analysis.jl:40-42`
  - `scripts/research/analysis/verification.jl:36-37`
  - `scripts/research/propagation/propagation_reach.jl:49-51`
  - `scripts/research/propagation/matched_quadratic_100m.jl:33-36`
- These are the next include-boundary candidates if another pass is warranted.

- Optimization entrypoints are conceptually similar but still separate:
  - canonical SMF runner in `scripts/lib/raman_optimization.jl:553-760`
  - multivariable runner in
    `scripts/research/multivar/multivar_optimization.jl:897-979`
  - MMF baseline runner in
    `scripts/research/mmf/mmf_raman_optimization.jl:500-600`
- Shared helpers now cover regularizers and objective metadata, but run-level
  orchestration, diagnostics assembly, and persistence remain partly bespoke.

- Manifest writing remains split between canonical shared helpers and
  study-local implementations:
  - shared canonical helpers in `src/io/results.jl`
  - custom Phase 31 manifest in
    `scripts/research/phases/phase31/run.jl:287-321`
- This is not automatically wrong, but it still forces a choice about whether a
  manifest is public infrastructure or local study provenance.

- Standard-image regeneration still has multiple rebuild paths:
  - canonical generic regen in
    `scripts/workflows/regenerate_standard_images.jl:82-115`
  - long-fiber schema bridge in
    `scripts/research/longfiber/longfiber_regenerate_standard_images.jl:43-87`
- The long-fiber split is justified by schema and scientific-method
  constraints, but the adapter boundary is still implicit rather than explicit.

### Justified separations to keep

- Long-fiber setup should remain separate:
  `scripts/research/longfiber/longfiber_setup.jl`
  exists specifically to bypass auto-sizing and preserve research-controlled
  grids.
- MMF setup should remain separate:
  `scripts/research/mmf/mmf_setup.jl`
  owns GRIN/MMF-specific fiber construction and window heuristics, not a mere
  variant of SMF setup.

## Prioritized Refactor Plan

### Now

- keep exact and auto-sized single-mode setup centralized in `common.jl`
- use `setup_raman_problem_exact` for saved-grid reconstruction paths
- avoid adding new ad hoc exact-grid rebuild helpers elsewhere

### Next

- decide which research manifests should adopt shared manifest helpers
- clean up the next maintained same-directory include chains in research
  analysis / propagation code
- consider a small shared "run reconstruction from saved metadata" helper if
  more validation/report tooling appears

### Later

- promote the stable single-mode setup interface into `src/` once its public
  shape is settled
- unify repeated run-orchestration pieces only after repeated active use across
  canonical and research workflows clearly justifies it
- introduce explicit schema adapters for regeneration/report tools instead of
  growing more format-detection branches inline

## Risks Deferred

- No solver, adjoint, or cost-function numerics were changed.
- No long-fiber or MMF behavior was changed.
- Research-local JLD2 schemas remain intentionally heterogeneous.
- The biggest remaining maintainability risks are:
  - deciding which research schemas deserve promotion versus explicit local
    isolation
  - deciding which research include webs deserve cleanup versus intentional
    locality
  - adding an automated link/path checker if doc moves become more frequent

## Tests Run

- `julia -t auto --project=. test/tier_fast.jl`
- `julia -t auto --project=. -e 'using MultiModeNoise; include("scripts/workflows/run_comparison.jl"); include("scripts/canonical/generate_reports.jl"); include("scripts/research/simple_profile/simple_profile_driver.jl"); println("include smoke ok")'`
