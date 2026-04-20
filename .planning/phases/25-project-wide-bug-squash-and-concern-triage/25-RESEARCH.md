# Phase 25 Research

**Phase:** 25 — Project-wide bug squash and concern triage
**Date:** 2026-04-20
**Mode:** implementation

## Standard Stack

- Use the existing Julia + PyPlot stack only.
- Verify fixes with the existing fast-tier test file instead of inventing a new harness.
- Treat `grep`/code search as the source of truth over stale planning notes.

## Architecture Patterns

- For constructor/input bugs, fail fast with `ArgumentError` instead of silently producing nonsense state.
- For dead code that is not included anywhere, delete it and then repair any tooling/docs that still point at it.
- Keep historical phase records intact where possible; update only canonical living docs.

## Don't Hand-Roll

- Do not create a new gain path to replace the dead placeholder file. The live gain implementation already exists in `simulate_disp_gain_mmf.jl`.
- Do not solve architecture debt with additional comments or warnings if the underlying issue needs a dedicated phase.
- Do not classify analysis/post-processing scripts as optimization drivers just because they mention `phi_opt`.

## Common Pitfalls

- `.planning/STATE.md` and `.planning/codebase/CONCERNS.md` are not guaranteed to match live code.
- A fresh worktree may fail tests until `Pkg.instantiate()` has been run.
- `save_standard_set(...)` compliance applies to scripts that produce a new `phi_opt`, not to scripts that only read stored results.

## Code Examples

### Constructor validation

```julia
if pulse_form == "gauss"
    # ...
elseif pulse_form == "sech_sq"
    # ...
else
    throw(ArgumentError("unsupported pulse_form=$(repr(pulse_form)); expected \"gauss\" or \"sech_sq\""))
end
```

### Dead-file cleanup

```text
1. Delete the dead source file.
2. Fix benchmarks or scripts that still reference it.
3. Update living docs that still describe it as active.
```
