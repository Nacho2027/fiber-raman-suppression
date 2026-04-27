# MMF Window Validation Status - 2026-04-27

## Summary

The overnight MMF window-validation run did not produce a trustworthy positive
MMF result. The only completed validation case, threshold
`GRIN_50, L=2 m, P=0.2 W`, reported a large apparent suppression at reduced
grid size (`Nt=4096`, `tw=96 ps`) but failed the boundary trust check:
`boundary_ok=false`, `edge_fraction=1.00e+00`.

## Runs

- `M-mmfwin3`: threshold plus aggressive at `Nt=8192/16384` and large windows.
  The threshold case approached the memory limit on `c3-highcpu-22` and was
  interrupted before outputs were produced.
- `M-mmfthr4`: threshold-only at `Nt=8192`, `tw=96 ps`, `max_iter=4`.
  The VM became uninspectable under memory pressure and was reset.
- `M-mmfthr4096`: threshold-only at `Nt=4096`, `tw=96 ps`, `max_iter=4`.
  Completed with summary and standard images, but the result is invalid-window.

## Artifacts

Local copied artifacts:

- `results/raman/phase36_window_validation/mmf_window_validation_summary.md`
- `results/raman/phase36_window_validation/mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`
- `results/raman/phase36_window_validation/mmf_grin_50_l2m_p0p2w_seed42_evolution.png`
- `results/raman/phase36_window_validation/mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`
- `results/raman/phase36_window_validation/mmf_grin_50_l2m_p0p2w_seed42_evolution_unshaped.png`
- `results/raman/phase36_window_validation/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_total_spectrum.png`
- `results/raman/phase36_window_validation/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_per_mode_spectrum.png`
- `results/raman/phase36_window_validation/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_phase.png`
- `results/raman/phase36_window_validation/mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_convergence.png`

## Interpretation

The optimized spectrum and convergence curve show the optimizer can drive the
Raman-band objective downward, but the standard diagnostics show pathological
phase/group-delay structure and the trust summary marks the result as boundary
corrupted. This should be treated as evidence that the current MMF threshold
suppression is a numerical/window artifact, not a validated physical result.

The aggressive case remains unresolved scientifically, but it is not runnable
in the requested `Nt=16384`, `tw=160 ps` configuration on the current
`c3-highcpu-22` burst VM.

## Recommendation

Park deeper MMF follow-up for now. Reopen only if there is a concrete plan for
boundary-safe phase parameterization, stronger regularization, or a larger
memory validation machine.
