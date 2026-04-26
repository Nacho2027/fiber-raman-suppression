# Analytic Equation Verification Summary

Date: 2026-04-26

## Scope

This note records the current audit of analytically derived equations that can
affect the active research lanes: single-mode phase optimization, multivariable
phase/amplitude/energy optimization, MMF shared-phase optimization, MMF
phase-plus-mode-coordinate optimization, regularizers, and Hessian-vector
products.

## Verification Matrix

| Path | Equation status | Verification status | Action |
|---|---|---|---|
| SMF phase adjoint `cost_and_gradient` | analytic adjoint phase gradient | existing FD and Taylor tests; production verification script covers slope-2 Taylor behavior | keep using; rerun burst verification before publication-grade claims |
| GDD regularizer | analytic discrete second-difference gradient | covered through regularized-surface FD/Taylor tests | keep using |
| Boundary phase regularizer | analytic phase gradient | covered in SMF/MMF regularized-surface tests | keep using |
| Multivar phase gradient | analytic adjoint chain rule | covered by multivar gradient smoke tests | keep using |
| Multivar amplitude gradient | analytic adjoint chain rule plus tanh parameterization | covered by multivar gradient smoke tests | keep using |
| Multivar energy gradient | analytic scalar-energy chain rule | covered by multivar gradient smoke tests | keep using |
| Multivar boundary-amplitude gradient | analytic quotient-rule derivative | fixed in this pass; regression test added against central FD | rerun on burst before trusting new full-combo ablation results |
| MMF shared-phase gradient | analytic adjoint chain rule summed over modes | covered by `test/phases/test_phase16_mmf.jl` FD checks | keep using |
| MMF mode-coordinate block | intentionally **not analytic** | central finite difference over `2(M-1)` packed variables; local preflight passed exactly | keep FD default unless a future analytic derivation passes preflight |
| HVP / Hessian paths | finite-difference HVP, not analytic second adjoint | covered by symmetry and Taylor tests | describe as FD Hessian diagnostics, not analytic Hessian |

## Findings

The audit found one real equation-level bug in the active multivar path.
`λ_boundary > 0` added the scalar temporal-edge penalty, but when amplitude was
enabled the gradient only included the phase derivative. Because the boundary
penalty is an edge-fraction quotient, amplitude changes affect both numerator
and denominator. This pass added the missing amplitude quotient-rule gradient
and a central-FD regression check.

The MMF phase-plus-mode-coordinate path is now intentionally conservative:
shared phase remains analytic, but the mode-coordinate block is finite
differenced. This is scientifically acceptable for current mode-launch studies
because the block is small (`2(M-1)`, ten variables for `M=6`) and the previous
hand-derived complex chain failed preflight.

## Required Before Calling The Active Runs Final

- Rerun `scripts/dev/smoke/test_multivar_gradients.jl` on burst with the new
  boundary-amplitude regression.
- Rerun or confirm `test/phases/test_phase16_mmf.jl` for MMF shared-phase
  gradient health.
- Confirm the clean remote MMF mode-coordinate preflight generated after the
  finite-difference patch.
- Treat any multivar result produced before this fix with `λ_boundary > 0` and
  amplitude enabled as potentially affected. The amplitude-on-fixed-phase
  trend is still useful evidence, but final tables should be regenerated after
  this fix if boundary regularization was active.

