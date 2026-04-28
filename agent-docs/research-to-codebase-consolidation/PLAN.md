# Research-To-Codebase Consolidation Plan

Created: 2026-04-28

## Goal

Stop opening new science lanes and convert the current project into a coherent
research-engine/codebase package with durable findings.

## Non-Goals

- No new physics directions.
- No broad refactor.
- No additional long-running simulations unless a packaging gate explicitly
  requires verification.
- No bulk committing generated `results/`.

## Workstreams

### 1. Findings Package

- Use `docs/reports/research-closure-2026-04-28/REPORT.md` as the primary
  short-form summary.
- Add one status note for the completed 200 m long-fiber run after visual
  inspection.
- Keep the existing MMF readiness report as the detailed MMF caveat document.
- Keep multivar staged `amp_on_phase` findings as the accepted multivar result.

### 2. Codebase Surface

- Keep front-layer configs as the public entry point.
- Treat `research_engine_poc`, `research_engine_smoke`, and
  `research_engine_export_smoke` as the supported baseline surfaces.
- Treat `smf28_amp_on_phase_refinement_poc`,
  `smf28_phase_amplitude_energy_poc`, `smf28_longfiber_phase_poc`, and
  `grin50_mmf_phase_sum_poc` as experimental/planning surfaces.
- Make README and docs point to supported workflows first, then experimental
  reports.

### 3. Result Hygiene

- Do not commit raw result directories by default.
- Promote selected result artifacts only by copying them into
  `docs/reports/<report>/figures/` or another explicit docs location.
- Keep burst logs and checkpoints untracked unless a tiny fixture is needed for
  a test.

### 4. Validation

Before calling the codebase package ready:

- `julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-all`
- `make acceptance`
- `make lab-ready`
- Visual inspection of any report figures copied into `docs/reports/`

## Lane Status For Future Agents

| Lane | Status | Next action |
|---|---|---|
| Single-mode phase | Supported | Polish docs and README |
| Multivar | Staged `amp_on_phase` accepted; direct joint negative | Package result, no new campaign |
| Long-fiber | 200 m completed at `-55.16 dB`, not converged | Inspect images, write status note |
| MMF | 4096-grid candidate accepted with caveats; 8192 incomplete | Preserve caveat, no more brute-force |
| Newton/preconditioning | Deferred | Keep as research note only |

## First Pass Checklist

- [x] Create closure report.
- [x] Inspect long-fiber 200 m images.
- [x] Add long-fiber 200 m status note.
- [ ] Update top-level README navigation.
- [ ] Run acceptance/lab-ready checks after docs edits.
