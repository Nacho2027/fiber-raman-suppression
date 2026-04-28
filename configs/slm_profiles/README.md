# Generic SLM Replay Profiles

These TOML files describe device-agnostic replay profiles. They are not vendor
exports. They define how an ideal simulation phase is cropped, resampled,
wrapped, quantized, and reconstructed before rerunning or handing off to a
vendor-specific adapter.

The first profiles are intentionally generic:

- `generic_128px_phase.toml`
- `generic_256px_phase.toml`

Replace the calibration fields with real lab files when the SLM, 4f axis, LUT,
polarization convention, and correction assets are measured.
