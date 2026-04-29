# Golden Smoke Run

The golden smoke run checks that install, run, inspect, and export still work
together.

Clean-clone rehearsal on 2026-04-28 validated the smoke path with run
`smf28_phase_export_smoke_20260428_1611741`.

Finalizer rehearsal on 2026-04-28 also validated the smoke path with run
`smf28_phase_export_smoke_20260429_0156419`.

```bash
make golden-smoke
```

It runs:

```bash
julia -t auto --project=. scripts/canonical/lab_ready.jl --config research_engine_export_smoke
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_export_smoke
julia -t auto --project=. scripts/canonical/lab_ready.jl --latest research_engine_export_smoke --require-export
```

After it finishes, inspect the generated standard images and export bundle under
`results/raman/smoke/`.

Use this before handing the repo to another lab user. Use heavier tests before
making broad numerical claims.
