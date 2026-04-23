# Script Libraries

Shared include-based Julia helpers live here.

This is a transition layer for code that is reused by scripts but has not yet
been promoted into the package under `src/`.

## What belongs here

Use `scripts/lib/` for shared maintained helpers that are still workflow-shaped
or include-oriented.

Typical examples:

- problem/setup construction
- canonical optimization orchestration
- plotting and report helpers
- standard-image generation

## What should not go here

- thin public CLI wrappers
- one-off experiment drivers
- stable package-grade abstractions that belong in `src/`

If you are unsure whether a helper should live here or in `src/`, read
[`../../docs/architecture/repo-navigation.md`](../../docs/architecture/repo-navigation.md).
