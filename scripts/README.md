# Scripts

This directory is organized by role. The root intentionally contains no loose
script files.

- canonical entry points in [`canonical/`](./canonical/README.md)
- shared include-based libraries in [`lib/`](./lib/README.md)
- workflow implementations in [`workflows/`](./workflows/README.md)
- active research and experimental drivers in [`research/`](./research/README.md)
- historical, benchmark, recovery, and phase-specific scripts destined for [`archive/`](./archive/README.md)
- internal developer helpers in [`dev/`](./dev/README.md)
- operational machine/launcher helpers in [`ops/`](./ops/README.md)

## How to navigate this tree

Use this rule before editing:

- supported CLI surface: [`canonical/`](./canonical/README.md)
- maintained workflow implementation: [`workflows/`](./workflows/README.md)
- shared script-library code: [`lib/`](./lib/README.md)
- active but not-yet-canonical experiments: [`research/`](./research/README.md)
- historical material you should usually not extend: [`archive/`](./archive/README.md)

The broader repo-level boundary map lives in
[`../docs/architecture/repo-navigation.md`](../docs/architecture/repo-navigation.md).

## Supported interface

If you are looking for the maintained command-line workflow, start in
[`canonical/`](./canonical/README.md).

That is the interface the project docs and `Makefile` are intended to expose.

## Rule

Do not add new files directly under `scripts/`. Put them in the appropriate
subdirectory, or promote stable reusable code into `src/`.
