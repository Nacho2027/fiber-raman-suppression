# Seed: Make fiber/sim solve inputs thread-safe without caller-side `deepcopy`

**Planted:** 2026-04-20 by Phase 25
**Trigger:** promote when another parallel optimization/sweep/MMF phase needs new threaded drivers or when a race bug is suspected.

## Problem

The codebase still relies on callers remembering to `deepcopy(fiber)` before any threaded solve that might mutate `fiber["zsave"]`. That is a process rule, not a program guarantee.

## Why this is seed-sized, not bug-sized

- The mutation pattern is spread across many scripts and helper paths.
- A real fix likely changes solver signatures or the `fiber` container model.
- A partial patch would just add more caller discipline without removing the footgun.

## Candidate directions

1. Make `zsave` an explicit solve keyword instead of a mutable `fiber` field.
2. Split immutable fiber physics from per-run solve options.
3. Add regression tests asserting solve entry points do not mutate their input dictionaries.
