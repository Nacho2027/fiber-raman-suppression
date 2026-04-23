# Phase Script Families

This file records the current archive grouping for older phase-oriented script
families. These directories are organizational copies, not the canonical live
entry points.

## Grouped families

- `phase13/` — Hessian, HVP, gauge, and early landscape tooling
- `phase14/` — sharpness and robustness-era comparison tooling
- `phase15/` — determinism benchmark artifacts
- `phase29/` — performance and roofline audit tooling
- `phase30/` — continuation demo driver
- `phase31/` — reduced-basis continuation and follow-up tooling
- `phase32/` — acceleration and extrapolation experiments
- `phase33/` — trust-region benchmark tooling
- `phase34/` — preconditioning follow-up tooling

## Transition rule

Do not repoint the top-level `scripts/phase*.jl` entry paths at these archived
copies until their include-path assumptions have been neutralized. Many older
drivers still assume sibling files via `@__DIR__`, so physical relocation of the
live implementation is not yet behavior-preserving.
