# src/_archived/

Historical Julia source files that are intentionally excluded from the
`MultiModeNoise` module namespace.

## Why "_archived/" (with a leading underscore)

The leading underscore signals two things:

1. These files are NOT included by `src/MultiModeNoise.jl`. `using
   MultiModeNoise` will never import anything from this directory.
2. The content is preserved for intellectual history — skeletons of abandoned
   refactors, broken-but-promising prototypes, and intentionally parked code
   that future work may want to resurrect or reference.

## Archival policy

A file lands here when all three of the following are true:

- It is not correct Julia (compiles but errors at runtime, or does not compile).
- Fixing it is out of scope for the current milestone.
- Deleting it would lose useful context (original intent, comments, mathematical
  structure) that the git history alone does not make obvious.

Files MUST carry a top-of-file header block that records: (a) original
location, (b) why it is broken, (c) original intent, (d) the commit /
phase that archived it. See `analysis_modem.jl` for the reference format.

## Resurrection protocol

To revive an archived file:

1. Fix the runtime errors.
2. Add tests.
3. Move the file out of `_archived/` into its logical source subdirectory
   (e.g. `src/analysis/`).
4. Add the `include(...)` line to `src/MultiModeNoise.jl`.
5. Remove the archival header, preserving the history discussion in the
   commit message.

## Current contents

- `analysis_modem.jl` — broken `compute_noise_map_modem` (empty `@tullio`,
  undefined variables). Original location: `src/analysis/analysis.jl`.
  Archived in Phase 16 (Session B handoff).
