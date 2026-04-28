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

## Build An Index

Use the canonical indexer to turn raw telemetry directories into a planning
report:

```bash
julia -t auto --project=. scripts/canonical/index_telemetry.jl
```

By default it scans `results/telemetry` and prints a Markdown table with run
labels, return codes, elapsed time, host, Julia thread count, sampled peak CPU,
sampled peak RSS, and command text.

Common planning queries:

```bash
# Slowest runs first.
julia -t auto --project=. scripts/canonical/index_telemetry.jl \
  --sort elapsed --desc --top 20

# Memory-heaviest runs first.
julia -t auto --project=. scripts/canonical/index_telemetry.jl \
  --sort rss --desc --top 20

# Failed or interrupted commands only.
julia -t auto --project=. scripts/canonical/index_telemetry.jl --failed

# CSV for spreadsheet analysis or a lab notebook appendix.
julia -t auto --project=. scripts/canonical/index_telemetry.jl --csv \
  > results/telemetry/telemetry_index.csv

# Search one label, command fragment, host, id, or path.
julia -t auto --project=. scripts/canonical/index_telemetry.jl \
  --contains mmf --sort elapsed --desc
```

You can also pass explicit roots or individual `telemetry.json` files:

```bash
julia -t auto --project=. scripts/canonical/index_telemetry.jl \
  results/telemetry results/burst-telemetry
```

## How To Use The Data

Use telemetry for planning, not scientific acceptance:

- Estimate wall time for similar configs.
- Compare machine types and thread counts.
- Identify memory pressure before choosing `Nt`, mode count, or time window.
- Decide whether a run belongs locally, on burst, or on a larger machine.

Do not treat telemetry as proof that a run is trustworthy. A run still needs the
normal artifact validation, trust checks, and visual image inspection.

The index is a compute-budgeting aid. It does not decide whether a scientific
result should be accepted.

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

## Lab Usage Pattern

Before launching a new expensive run, search for the closest previous run:

```bash
julia -t auto --project=. scripts/canonical/index_telemetry.jl \
  --contains longfiber --sort elapsed --desc --top 10
```

Record the closest match in the experiment note with:

- the prior run label and command,
- the prior elapsed time,
- the prior peak sampled RSS,
- the machine hostname and thread count,
- the planned differences in `Nt`, fiber length, mode count, sweep count, or
  optimization iteration count.

This is intentionally simple. It gives a researcher enough information to avoid
surprise multi-day jobs or memory pressure without pretending the code can
predict runtime from physics parameters yet.
