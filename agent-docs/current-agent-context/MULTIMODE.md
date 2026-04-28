# Multimode MMF Status

Date: 2026-04-28

Status: **closed / exploring**.

## Decision

The MMF lane is not a supported front-layer execution workflow. It remains a
dedicated research lane under `scripts/research/mmf/`, with configurable
front-layer support limited to validation, dry-run planning, and compute-plan
inspection.

The current accepted candidate is the constrained E5 run:

- `GRIN_50`, six scalar modes, shared spectral phase
- `L=2 m`, `P=0.20 W`, `Nt=4096`, `TW=96 ps`
- `λ_boundary=0.05`, `λ_gdd=1e-4`
- raw `J_sum -17.96 -> -49.69 dB`
- raw input/output temporal-edge fractions near `2e-11`
- standard images visually inspected

This supports a qualified simulation claim only:

> Spectral phase shaping suppresses Raman-band generation in an idealized
> GRIN-50 MMF simulation under strict temporal-edge diagnostics.

Do not claim generic experimental MMF Raman suppression from this result.

## Integration Boundary

- Front-layer MMF configs must remain `experimental`,
  `verification.mode = "burst_required"`, and dry-run/planning only.
- Real MMF execution should use `scripts/research/mmf/mmf_window_validation.jl`
  or the dedicated MMF scripts on burst/cluster-class compute.
- Every MMF run that produces `phi_opt` must leave the standard image set and
  must be visually inspected before acceptance.
- Do not promote MMF into `run_supported_experiment` until the memory/grid,
  launch, and coupling gates below are reopened and resolved.

## Current Run Commands

Planning-only front-layer check:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run grin50_mmf_phase_sum_poc
```

Accepted E5 reproduction on burst or equivalent heavy compute:

```bash
MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_gdd \
MMF_VALIDATION_CASES=threshold \
MMF_VALIDATION_MAX_ITER=4 \
MMF_VALIDATION_THRESHOLD_TW=96 \
MMF_VALIDATION_THRESHOLD_NT=4096 \
MMF_VALIDATION_LAMBDA_BOUNDARY=0.05 \
MMF_VALIDATION_LAMBDA_GDD=1e-4 \
julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl
```

Parked grid-refinement command, only after larger-memory compute or a
memory-reduced solver is available:

```bash
MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_gdd_nt8192_bounded \
MMF_VALIDATION_CASES=threshold \
MMF_VALIDATION_MAX_ITER=4 \
MMF_VALIDATION_THRESHOLD_TW=96 \
MMF_VALIDATION_THRESHOLD_NT=8192 \
MMF_VALIDATION_LAMBDA_BOUNDARY=0.05 \
MMF_VALIDATION_LAMBDA_GDD=1e-4 \
MMF_VALIDATION_F_CALLS_LIMIT=80 \
MMF_VALIDATION_TIME_LIMIT_SECONDS=10800 \
julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl
```

## Parked Paper Gates

- `Nt=8192`, `TW=96 ps` refinement with standard images. Current
  `c3-highcpu-22` attempts hit the memory ceiling before a valid artifact;
  larger-memory C3 shapes were blocked by stock/quota on 2026-04-28.
- Launch-composition sensitivity: default, LP01-only, balanced low-order, and
  reduced-LP01 launch.
- Random or degenerate mode-coupling sensitivity, or an explicit deterministic
  controlled-launch limitation.
- Phase-actuator realism: smoother/reduced phase basis or stronger curvature
  constraints.

## Source Of Record

- `agent-docs/multimode-baseline-stabilization/SUMMARY.md`
- `agent-docs/multimode-baseline-stabilization/ONLINE-RESEARCH.md`
- `docs/reports/mmf-raman-readiness-2026-04-28/REPORT.md`
- `docs/reports/mmf-raman-readiness-2026-04-28/PRESENTATION.md`
- `scripts/research/mmf/README.md`
