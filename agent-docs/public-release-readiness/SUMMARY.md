# Public Release Readiness Summary

## Bottom Line

The repo is close to an honest internal lab handoff for the supported
single-mode phase-only workflow. It is not yet polished enough for a broad
public lab release.

Recommended public classification:

```text
Research preview: single-mode phase-only Raman suppression workflow is
supported; MMF, long-fiber, broad multivariable optimization, and hardware
predictiveness remain experimental or planning-stage.
```

## Verification Run

Commands run successfully:

- `syncthing cli show connections`
- `julia --project=. scripts/canonical/run_experiment.jl --validate-all`
- `julia --project=. scripts/canonical/run_experiment_sweep.jl --validate-all`
- `make test`
- `make install-python`
- `make test-python`
- `make acceptance`
- `./fiberlab validate`
- `./fiberlab capabilities`
- `julia --project=. scripts/canonical/lab_ready.jl --config research_engine_export_smoke`
- `julia --project=. scripts/canonical/index_results.jl --compare --top 10 results/raman/smoke`

Important result:

- Fast Julia tier passed.
- Acceptance harness passed.
- Python wrapper tests passed after creating `.venv`.
- Config validation passed for 10 experiment configs.
- Sweep validation passed for 1 sweep config.
- Supported export smoke config reported `PASS`.

## Major Strengths

- Clear supported-vs-experimental boundary.
- `fiberlab` front door hides Julia command complexity while preserving one
  backend.
- Config contracts, dry runs, capabilities, control layout, artifact planning,
  and promotion blockers are visible before compute.
- Standard image set, trust reports, result manifests, neutral CSV handoff, and
  result indexing are strong for researcher workflows.
- Tests are unusually broad for a research repo, including adversarial config
  mutation and SLM replay.

## Release Blockers

- Dirty working tree and branch behind `origin/main`.
- No `.github/workflows/` CI in this checkout.
- No top-level `CITATION.cff`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, `codemeta.json`, or `.zenodo.json`.
- Package identity is inconsistent: Julia project is `MultiModeNoise`
  `1.0.0-DEV`, Python package is `fiber-research-engine`, public README is
  Rivera Lab Raman suppression.
- Julia version metadata is inconsistent: docs say 1.12.6 while `Project.toml`
  compat says 1.9.3.
- `results/` still contains tracked historical artifacts and generated files;
  public release needs curation.
- A Syncthing conflict file and Python cache artifacts are present in the
  workspace, though ignored.

## File Added

- `docs/guides/public-release-readiness.md`
