# Supported Workflows

The supported surface is intentionally small.

## Supported

- Single-mode phase-only Raman optimization:

```bash
julia -t auto --project=. scripts/canonical/optimize_raman.jl smf28_L2m_P0p2W
```

- Configurable single-mode experiments:

```bash
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab ready latest research_engine_poc
```

- Export smoke for lab handoff:

```bash
make golden-smoke
```

- Result inspection:

```bash
julia --project=. scripts/canonical/inspect_run.jl results/raman/<run_id>/
julia --project=. scripts/canonical/export_run.jl results/raman/<run_id>/
```

## Experimental

These are useful, but they are not default lab workflows:

- staged `amp_on_phase` refinement;
- gain-tilt scalar search;
- long-fiber planning configs;
- multimode planning configs;
- direct phase/amplitude/energy joint optimization;
- Newton and preconditioning research drivers.

Use `./fiberlab explore ...` for these paths so the command prints blockers and
compute warnings before running.

## Completion rule

A run that produces `phi_opt` is not complete until the standard image set is
present and visually checked:

- phase profile;
- optimized evolution;
- phase diagnostic;
- unshaped evolution.
