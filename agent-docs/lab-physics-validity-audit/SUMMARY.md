# Lab Physics Validity Audit Summary

Date: 2026-04-28

Human-facing report:

- `docs/reports/lab-physics-validity-2026-04-28/REPORT.md`

Core conclusion:

- The repo uses a real GNLSE/GMMNLSE modeling class and has meaningful numerical
  trust machinery.
- The repo is not yet a calibrated lab digital twin.
- The first lab path should be SMF phase-only with calibrated SLM replay and
  measured fiber/pulse inputs.
- Deep full-grid masks are especially risky because hardware-like probes show
  tens-of-dB losses under pixelation/wrapping for many candidates.

Most important follow-up:

1. Build a hardware replay layer for `phi_sim -> phi_loaded -> rerun`.
2. Attach real SLM calibration assets and measured pulse/fiber metadata.
3. Use simple/replay-surviving masks as first lab candidates, not the deepest
   ideal full-grid masks.

2026-04-28 implementation follow-up:

- Added `scripts/lib/slm_replay.jl` as the device-agnostic replay library.
- Added `configs/slm_profiles/generic_128px_phase.toml` and
  `configs/slm_profiles/generic_256px_phase.toml`.
- Added `scripts/canonical/replay_slm_mask.jl` with optional `--evaluate`.
- Added `docs/guides/slm-replay.md`.
- Added fast tests in `test/core/test_slm_replay.jl`.
