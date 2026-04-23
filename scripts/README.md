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

## Supported interface

If you are looking for the maintained command-line workflow, start in
[`canonical/`](./canonical/README.md).

That is the interface the project docs and `Makefile` are intended to expose.

## Rule

Do not add new files directly under `scripts/`. Put them in the appropriate
subdirectory, or promote stable reusable code into `src/`.
