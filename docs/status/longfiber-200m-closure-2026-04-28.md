# Long-Fiber 200 m Closure Status - 2026-04-28

## Summary

The 200 m long-fiber continuation completed and produced a standard result
payload plus the required four-image standard set. Treat this as a completed
long-fiber milestone, not as a fully converged optimizer solution.

## Result Artifact

- Result: `results/raman/phase16/200m_overngt_opt_resume_result.jld2`
- Checkpoint directory:
  `results/raman/phase16/200m_overngt_optim/`
- Standard images:
  `results/raman/phase16/standard_images_F_200m_overngt_resume/`
- Final checkpoint:
  `results/raman/phase16/200m_overngt_optim/ckpt_iter_2895_final.jld2`

## Metrics

From the result payload:

- `L_m = 200.0`
- `P_cont_W = 0.05`
- `Nt = 65536`
- `time_window_ps = 320.0`
- `J_final = -55.16482931639846 dB`
- `converged = false`
- `g_residual = 0.5648841056107406`
- `n_iter = 69` in the resume call
- `resume_iter = 381`
- `wall_s = 75997.0`

## Visual Inspection

Inspected standard image set:

- `F_200m_overngt_resume_phase_profile.png`
- `F_200m_overngt_resume_evolution.png`
- `F_200m_overngt_resume_phase_diagnostic.png`
- `F_200m_overngt_resume_evolution_unshaped.png`

Inspection notes:

- The phase-profile image reports the expected large reduction from about
  `-0.2 dB` before shaping to about `-55.2 dB` after shaping.
- The optimized spectrum suppresses the Raman-side feature and keeps the output
  primarily near the input spectral support.
- The temporal panel shows peak-power reduction and pulse restructuring after
  shaping.
- The phase and group-delay diagnostics are finite and render correctly, but
  the optimized phase remains complex and high-structure; this is not a simple
  lab-actuator-ready phase.
- The optimized and unshaped evolution plots both render coherently. The
  optimized evolution is strongly structured across the first half of the fiber;
  the unshaped evolution shows the expected strong long-wavelength Raman growth.

## Interpretation

This result supports the claim that the project can run and checkpoint a
200 m long-fiber reoptimization and reach a deep Raman-band suppression result
near `-55.16 dB`. Because `converged=false` and the residual gradient is still
nontrivial, do not claim a final optimizer optimum.

## Recommendation

Close the active long-fiber exploration lane for now. Use this result in the
project findings package with the caveat that it is a completed, image-backed
milestone rather than a converged optimum.
