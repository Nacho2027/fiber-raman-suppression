# Seed: GRIN vs step-index vs larger-core GRIN — what changes qualitatively for Raman?

**Planted:** 2026-04-17 by Session C (sessions/C-multimode)
**Trigger:** after Phase 16 baseline gives a clean `J_dB` reduction at M=6 in GRIN-50, so the effect of fiber type becomes interpretable.

## Hypothesis

Raman-band energy transfer is preset-dependent in a physically-predictable way:

1. **GRIN with Kerr self-cleaning** (Wright, Krupa+ 2020): Kerr redirects energy toward low-order modes → Raman grows preferentially on LP01 → `mmf_cost_fundamental` ≈ `mmf_cost_sum`.
2. **Step-index, no self-cleaning**: without the GRIN's parabolic attractor, mode content stays closer to the launch distribution → `mmf_cost_fundamental` < `mmf_cost_sum` (Raman spread across modes). The optimizer has *more* handles (a single shaped phase can leverage intermodal dispersion differently) but also *worse* detection metric if the experiment reads only LP01.
3. **Larger-core GRIN (100 μm)**: more modes, weaker self-cleaning per mode, potentially stronger SRS gain per unit length (larger effective area → lower intensity so LOWER gain, actually — but more modes to split among). Competing effects; sign of `J_dB` improvement uncertain.

## Suggested protocol

Three-preset comparison holding (L, P_cont, pulse_fwhm, N_sol) matched as closely as possible:

- `:GRIN_50` (M=6, already done in baseline)
- `:STEP_9`  (M=4, already in `MMF_FIBER_PRESETS`)
- `:GRIN_100` (M=12) — NEW preset, define radius=50μm, NA=0.19, alpha=2.0, nx=151, spatial_window=160μm.

For each: setup + 30 L-BFGS iters + save.

Report:
- `J_dB_zero` and `J_dB_opt` side-by-side.
- Per-mode energy distribution at output (histogram) before/after opt.
- `mmf_cost_fundamental / mmf_cost_sum` ratio — large separation = strong self-cleaning.

## Why this matters

Rivera Lab's experimental fiber is 50-μm GRIN (OM4). A prediction that GRIN-100 gives dramatically different Raman dynamics would motivate a different fiber purchase for the next experiment. The comparison also calibrates whether `mmf_cost_sum` (integrating detector) or `mmf_cost_fundamental` (mode-stripped detector) is the right choice for the experimental question.

## Dependencies

- Phase 16 baseline passing numerical correctness.
- Definition of `:GRIN_100` preset (one-line addition to `scripts/mmf_fiber_presets.jl`).
- GRIN eigensolver at nx=151 takes ~30 seconds (Arpack on 22801×22801 sparse matrix — fine).
- Total compute ~90 min on burst VM.

## Out of scope for Phase 16 Plan 01

This is option (c) from the free-exploration budget. Option (a) was picked. Promote to Phase 19+.
