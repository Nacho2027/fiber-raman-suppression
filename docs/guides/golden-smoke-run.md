# Golden Smoke Run

This is the shortest real run that proves the lab handoff path still works.

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
