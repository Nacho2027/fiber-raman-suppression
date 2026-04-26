# MMF Research Scripts

This directory contains the multimode Raman optimization workflow, its setup
helpers, baseline runners, and associated analysis scripts.

This is active research tooling. It is valuable and maintained, but it is not
part of the small supported public entry surface for first-time users.

## Current Closure Workflow

The active MMF blocker is output-window trust, not code scaffolding. Use
`mmf_window_validation.jl` before launching deeper joint mode/phase work:

```bash
julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl
```

This reruns the threshold/aggressive GRIN-50 regimes with larger temporal
windows, emits the standard image set through `run_mmf_baseline`, and writes
`results/raman/phase36_window_validation/mmf_window_validation_summary.md`.
