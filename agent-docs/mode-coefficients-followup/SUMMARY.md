# MMF Mode-Coefficient Follow-Up

Date: 2026-04-26

## Why This Matters

Mode coefficients are not just another numerical knob. In MMF they represent
launch composition across spatial modes, which is a physically meaningful
experimental control and a likely advisor-facing question.

Keep this separate from the single-mode multivar path:

- SMF multivar supports `:phase`, `:amplitude`, and `:energy`.
- SMF multivar does not support `:mode_coeffs` end-to-end.
- MMF mode coefficients live in
  `scripts/research/mmf/mmf_joint_optimization.jl`.

## Current Status

- The code for joint shared phase plus mode coefficients exists.
- The original custom complex gradient for packed mode amplitudes/phases failed
  finite-difference preflight with order-one relative errors.
- The current implementation therefore uses an adjoint gradient for the large
  shared-phase block and central finite differences for the small
  `2(M-1)`-parameter mode-coefficient block.
- This is slower per optimizer iteration, but it is the correct conservative
  choice for advisor-facing mode-launch studies until an analytic
  mode-coefficient gradient is re-derived.
- The current MMF physics result is still blocked by window validation; do not
  interpret mode-coefficient optimization scientifically until MMF
  `boundary_ok=true` is established.

## Required Order

1. Finish `scripts/research/mmf/mmf_window_validation.jl`.
2. Run `scripts/research/mmf/mmf_mode_coeff_gradient_check.jl`.
3. If both pass, run the small mode-coefficient science ladder:
   - phase-only baseline
   - mode-coefficients-only with fixed phase
   - phase then mode release
   - cold joint phase+mode only as a diagnostic

## Interpretation Rules

- If window validation fails, mode coefficients remain interesting but parked;
  do not spend heavy compute optimizing a contaminated MMF objective.
- If the gradient check fails, fix the gradient before any science run.
- If both pass, prioritize `phase then mode release` over cold joint. The SMF
  multivar lesson is that sequential control can beat naive joint cold starts.
