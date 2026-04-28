# Equation And Code Closure

Evidence snapshot: 2026-04-28

This note records the current equation-verification status after the blind
derivation comparison, source-path inspection, and local smoke checks.

## Current Status

The active public equation reference is:

- `docs/reference/current-equation-verification.tex`
- `docs/reference/current-equation-verification.pdf`

The independent blind derivation comparison is:

- `agent-docs/equation-verification/BLIND_DERIVATION_COMPARISON.md`

Bottom line: no core equation mismatch is currently known in the checked active
paths. The remaining gap is fresh heavyweight physics verification, not an
identified analytic contradiction.

## Equation/Code Matches Already Checked

| Topic | Expected equation or rule | Checked implementation path | Status |
|---|---|---|---|
| Raman-band terminal derivative | `dJ/dU* = (chi - J) U / E` | `scripts/lib/raman_optimization.jl` and public equation reference | Matches with stated Wirtinger convention. |
| Phase chain rule | `dJ/dphi = 2 Re(lambda* i u)` | `scripts/lib/raman_optimization.jl` | Matches current adjoint convention. |
| dB chain rule | `grad_db = (10/log(10)) grad_linear / J_linear` | `apply_log_surface!` in `scripts/lib/regularizers.jl` | Matches. |
| GDD regularizer | `R = ||D2 phi||^2 / Delta_omega^3`, nonperiodic stencil | `add_gdd_penalty!` in `scripts/lib/regularizers.jl` | Matches. |
| Boundary phase penalty | Input temporal edge fraction; phase-only denominator is invariant | `add_boundary_phase_penalty!` in `scripts/lib/regularizers.jl` | Matches phase-only caveat. |
| Boundary amplitude derivative | Amplitude changes numerator and denominator | `scripts/research/multivar/multivar_optimization.jl` | Matches repaired path; broader reruns remain open. |
| Reduced-basis gradient | `grad_c = B^T grad_phi` | Public equation reference and reduced-basis note | Matches; result provenance still needed. |
| MMF shared phase | Sum modewise phase sensitivities | MMF public note and validation path | Matches conceptually; full MMF regression remains burst-gated. |
| HVP/trust region | HVP is finite-difference diagnostic for a named scalar objective | Trust-region notes/tests | Matches documented convention. |

## Local Smoke Test Run

Command run locally:

```bash
julia -t auto --project=. -e '<equation closure smoke for regularizers and objective surface>'
```

Result:

```text
Test Summary:                                              | Pass  Total  Time
equation closure smoke: regularizers and objective surface |    8      8  1.9s
```

Covered:

- GDD scalar and gradient against explicit dense-loop reference.
- Boundary phase penalty scalar and gradient against explicit FFT expression.
- dB chain-rule scaling.
- Objective-surface string construction for regularizers inside the log.

## Test Attempt Not Counted

Attempted:

```bash
julia -t auto --project=. test/tier_fast.jl
```

This run was terminated by signal 15 while entering
`test/core/test_repo_structure.jl`, after a PyPlot GUI-backend warning. It did
not produce a useful pass/fail result, so it is not counted as verification
evidence.

## Still Required Before Publication Freeze

- Run the heavyweight physics verification on burst:
  `julia -t auto --project=. scripts/research/analysis/verification.jl`
- Run or re-run the dedicated MMF gradient/regression checks on burst.
- Keep the multivariable gradient smoke suite in the release checklist; it has
  passed in this documentation cycle, but a final freeze should rerun it.
- Add source-path capsules to the individual notes where exact implementation
  provenance is still only summarized.
