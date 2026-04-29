# MMF Raman Readiness

Date: 2026-04-28

## Bottom line

The MMF evidence is one corrected, regularized simulation. It does not show
launch-robust, coupling-robust, or experimentally validated multimode Raman
suppression.

## Accepted current candidate

- Corrected high-resolution GRIN-50 run with boundary and GDD regularization.
- Summary: `results/raman/mmf_window_validation_gdd_nt8192_final/mmf_window_validation_summary.md`
  (public alias for the accepted high-resolution validation artifact).
- Reported raw Raman metrics: `J_ref = -17.37 dB`, `J_opt = -41.25 dB`, improvement `23.88 dB`.
- Best regularized objective observed by the optimizer: about `-32.29 dB`.
- Edge diagnostic passed with max edge fraction `3.59e-13`.
- Standard image set and per-mode/convergence summary plots were visually inspected.

## Open gates

- Launch and coupling robustness are not established.
- MMF plotting and validation still need more code than the single-mode run.
- Phase-actuator realism is not established; the optimized phase remains a
  simulation waveform, not a hardware-ready SLM mask.
- Present it as simulation evidence only.

## Safe claim

A corrected, regularized six-mode GRIN-50 simulation shows strong Raman-band
suppression at the accepted `Nt=8192`, `TW=96 ps` setting.

## Unsafe claim

The repo has demonstrated general MMF Raman suppression suitable for lab use.
