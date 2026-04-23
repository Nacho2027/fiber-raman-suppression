# Maintainability Refactor Pass Context

Date: 2026-04-23

## Mission Slice

Continue the repo refactor without a rewrite, focusing on:

- long-term maintainability
- extension safety
- agent legibility
- explicit boundaries between canonical, research, and legacy code
- disciplined include/import architecture

## What This Pass Targeted

The highest-confidence active ambiguity after the previous refactor was the
single-mode problem-construction boundary:

- `scripts/lib/common.jl` already owned the authoritative auto-sized setup path
- `scripts/validation/validate_results.jl` reimplemented exact-grid rebuilds
- `scripts/lib/visualization.jl` reimplemented exact-grid fiber/sim rebuilds
- `scripts/research/simple_profile/simple_profile_stdimages.jl` relied on the
  auto-sizing setup even though it was reconstructing persisted runs

That left future maintainers with two competing patterns:

1. "Use `setup_raman_problem`."
2. "Inline exact reconstruction locally when the grid matters."

The second pattern had become active enough to justify a shared interface.

The next high-confidence ambiguity was the canonical result-output boundary:

- docs and package exports presented `src/io/results.jl` as canonical
- the actual canonical Raman workflow still wrote its own payload directly in
  `scripts/lib/raman_optimization.jl`
- readers and maintainers therefore had two plausible places to extend result
  writing

This pass therefore also targeted:

- result-authority unification
- canonical manifest authority
- a clearer test-tree layout
- a narrow include-architecture cleanup for the worst active dependency-web
  cases

## Deliberate Non-Goals

- no changes to solver physics
- no long-fiber setup unification
- no MMF setup unification
- no broad module conversion of the `scripts/` tree
- no attempt to flatten all research-local include webs in one pass
