# Compute Telemetry

[<- docs index](../README.md) | [supported workflows](./supported-workflows.md)

Lab users need realistic estimates before launching heavy jobs. New substantial
runs should record lightweight compute telemetry alongside scientific artifacts.

Use the generic wrapper for any command:

```bash
scripts/ops/run_with_telemetry.sh \
  --label smoke-budget-check \
  --out-dir results/telemetry/smoke-budget-check_$(date -u +%Y%m%dT%H%M%SZ) \
  -- \
  julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_export_smoke
```

The wrapper writes:

- `telemetry.json`: command, host, CPU model, online CPU count, memory total,
  elapsed time, return code, sampled peak CPU, sampled peak RSS, and
  `/usr/bin/time -v` fields when available.
- `resource_samples.csv`: timestamped process-group CPU and memory samples.
- `time_verbose.txt`: raw `/usr/bin/time -v` output.
- `command.txt`: shell-escaped command line.

Future jobs launched through `scripts/ops/parallel_research_lane.sh` are wrapped
automatically. Their telemetry lands under:

```text
results/telemetry/<TAG>_<UTC_TIMESTAMP>/
```

## How To Use The Data

Use telemetry for planning, not scientific acceptance:

- Estimate wall time for similar configs.
- Compare machine types and thread counts.
- Identify memory pressure before choosing `Nt`, mode count, or time window.
- Decide whether a run belongs locally, on burst, or on a larger machine.

Do not treat telemetry as proof that a run is trustworthy. A run still needs the
normal artifact validation, trust checks, and visual image inspection.

## Fields To Watch

- `elapsed_s`: end-to-end command duration.
- `return_code`: `0` means the command exited successfully.
- `sampled_peak_cpu_percent_sum`: approximate summed process-group CPU use.
  Values can exceed `100` when multiple cores are active.
- `sampled_peak_rss_kb_sum`: approximate sampled peak resident memory for the
  command process group.
- `time_max_rss_kb`: maximum resident set size reported by `/usr/bin/time -v`
  when available.
- `cpu_threads_online` and `cpu_model`: enough context to compare machines.

For long jobs, keep the default sample interval. For short smoke tests, use
`--sample-interval 1` or lower if you need a denser sample trace.
