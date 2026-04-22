---
status: complete
created_at: 2026-04-20T19:58:25Z
---

Fix numerics-audit regressions in the single-mode Raman optimizer and boundary diagnostics.

Scope:
- Measure temporal edge fraction before the super-Gaussian attenuator absorbs it.
- Make `cost_and_gradient(...; log_cost=true)` return a gradient consistent with the full regularized scalar objective seen by L-BFGS.
- Stop chirp-sensitivity plotting from double-logging already-dB values.
- Add dedicated regression coverage in the `test/` tree and wire it into the slow tier.
