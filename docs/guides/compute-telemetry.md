# Compute Telemetry

Telemetry is for answering simple operational questions: what ran, how long it
took, and what failed.

## Index telemetry

```bash
julia -t auto --project=. scripts/canonical/index_telemetry.jl
julia -t auto --project=. scripts/canonical/index_telemetry.jl --sort elapsed --desc --top 10
julia -t auto --project=. scripts/canonical/index_telemetry.jl --failed
```

## Use it for

- estimating sweep wall time;
- finding failed or interrupted runs;
- comparing smoke runs after code changes;
- spotting unexpectedly slow configs.

Telemetry is not physics validation. Use result metrics and inspected plots for
that.
