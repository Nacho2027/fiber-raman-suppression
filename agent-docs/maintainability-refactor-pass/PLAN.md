# Maintainability Refactor Pass Plan

## Now

- keep `scripts/lib/common.jl` as the authoritative owner of single-mode setup
- expose an exact-grid shared entry point for reconstruction use cases
- rewire live callers that should not be reimplementing exact reconstruction
- add fast regression tests proving the difference between auto-sized and exact
  setup
- make `src/io/results.jl` the actual canonical JLD2+JSON writer for canonical
  Raman runs while preserving the historical payload keys analysis code reads
- move canonical manifest read/write/update helpers into `src/io/results.jl`
- rewire maintained readers onto package-level canonical run loading
- group tests by concern while keeping tier entrypoints stable
- remove the worst include-graph ambiguities by:
  - making workflow scripts include `../lib` explicitly
  - replacing order-sensitive `main` aliasing with named workflow entrypoints
  - moving hidden function-local includes to explicit top-level dependencies

## Next

- decide which research manifests such as
  `scripts/research/phases/phase31/run.jl` should adopt shared manifest helpers
  versus stay intentionally local provenance
- clean up the next tier of same-directory include chains in maintained
  research analysis / propagation scripts
- extract a small shared helper for "rebuild run from saved metadata" if more
  result-inspection tools appear

## Later

- promote the stable single-mode setup interface from script-library code into
  `src/` once the desired public type/interface is clear
- revisit standard-image regeneration as a family of schema adapters around one
  shared regeneration core
- normalize experiment-driver boilerplate only where there are multiple active
  maintained users, not one-off study scripts
- do a deeper module/package pass only if the remaining include webs continue
  to cause order sensitivity or duplicated load logic
