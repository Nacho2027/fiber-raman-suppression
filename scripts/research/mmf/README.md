# MMF Research Scripts

This directory contains the multimode Raman optimization workflow, its setup
helpers, baseline runners, and associated analysis scripts.

This is **closed / exploring** research tooling. It is part of the production
CLI as an experimental planning and user-exploration surface, but it is not
promoted to the default supported local execution backend. The configurable
front layer may validate and dry-run MMF configs; real MMF propagation should
stay in this directory and run on burst/cluster-class compute.

## Current Status

The accepted current candidate is the constrained E5 result:

- `GRIN_50`, six scalar modes, shared spectral phase
- `L=2 m`, `P=0.20 W`, `Nt=4096`, `TW=96 ps`
- `MMF_VALIDATION_LAMBDA_BOUNDARY=0.05`
- `MMF_VALIDATION_LAMBDA_GDD=1e-4`
- raw `J_sum -17.96 -> -49.69 dB`
- raw input/output temporal-edge fractions near `2e-11`
- standard images visually inspected

The original unregularized window-validating run is rejected as a temporal-edge
artifact. The E5 constrained result is accepted as a qualified simulation
candidate, not a broad experimental MMF claim.

Paper-grade follow-up is parked because the `Nt=8192`, `TW=96 ps` refinement is
currently compute-limited: `c3-highcpu-22` reaches the memory ceiling before
producing standard images, while larger-memory C3 shapes were blocked by stock
or quota during the April 28 run.

## Supported Ways To Use This Lane

### Front-Layer Planning Only

Use the research-engine config to validate intent and inspect the generated
plan through the production CLI. This should not execute MMF propagation
locally:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run grin50_mmf_phase_sum_poc
```

### Reproduce The Accepted E5 Candidate

Use the dedicated MMF validation driver on burst or equivalent heavy compute:

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

This emits the standard image set through `run_mmf_baseline` and writes the
validation summary under the selected save directory.

### Parked Grid Refinement

Only rerun this when larger-memory compute or a memory-reduced solver path is
available:

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

The `MMF_VALIDATION_F_CALLS_LIMIT` and
`MMF_VALIDATION_TIME_LIMIT_SECONDS` guards are intentionally part of the
contract. They prevent open-ended line-search behavior from consuming burst
quota without producing a clean artifact.

## Historical Closure Workflow

Use `mmf_window_validation.jl` before launching deeper joint mode/phase work:

```bash
julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl
```

By default this reruns the threshold/aggressive GRIN-50 regimes with larger
temporal windows, emits the standard image set through `run_mmf_baseline`, and
writes `results/raman/phase36_window_validation/mmf_window_validation_summary.md`.

## Claim Boundary

Treat the MMF lane as closed/exploring unless explicitly reopened. The current
defensible statement is:

> Spectral phase shaping suppresses Raman-band generation in an idealized
> GRIN-50 MMF simulation under strict temporal-edge diagnostics.

Do not claim generic experimental Raman suppression in arbitrary multimode
fibers without launch-composition sensitivity, random/degenerate mode-coupling
sensitivity, and the `Nt=8192` grid-refinement artifact.
