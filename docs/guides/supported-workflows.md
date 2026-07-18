# Supported Workflows

The supported surface is Julia-only. The preferred mental model is the
FiberLab adjoint inverse-design API: explicit controls, objectives, and
models connected by an explicit adjoint contract.

## Notebook API

```julia
using FiberLab

fiber = Fiber(preset = :SMF28, length_m = 2.0, power_w = 0.2)
grid = Grid(nt = 4096, time_window_ps = 12.0)
resolved_grid = resolve_grid(fiber, Pulse(), grid)
problem = fiber_problem(fiber; grid = grid, raman_threshold_thz = -5.0)

control = FullGridPhase(problem)
objective = raman_band_objective(problem; log_cost = false)
model = fiber_model(problem)
x0 = zeros(dimension(control))

check_adjoint_gradient(
    model,
    control,
    objective,
    x0;
    coordinate_indices = [1, dimension(control) ÷ 2],
)
```

`resolve_grid` is a setup-only preflight. It reports the exact grid that the
auto-sizing policy will construct. Auto grids preserve a 10% carrier-frequency
margin; exact grids are rejected if their FFT bandwidth reaches nonpositive
absolute optical frequencies. `resolve_sampling_grid` applies the same
hardware-independent sampling checks without a fiber model.

See [Notebook API Quickstart](notebook-api.md) for native adjoint execution and
the compatibility bridge to config-backed runs.

## Experiment Configs

Configs are the maintained compatibility path for reproducible runs:

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
```

Equivalent direct Julia commands:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --list
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_poc
julia -t auto --project=. scripts/canonical/run_experiment.jl research_engine_poc
```

The retired `smf28_L2m_P0p2W` config maps to `research_engine_poc`. For a new
HNLF point, copy `configs/experiments/templates/single_mode_phase_template.toml`
and set the fiber parameters. Compare completed runs with
`./fiberlab explore compare RESULTS_ROOT`. Comparison fails closed unless every
ranked run has the same objective, optimization-cost scale, and copied
`[problem]`/`[objective]` configuration signature. This guards requested-config
heterogeneity; it is not a resolved-physics or source-code identity. Use the ordinary index or narrow it with
`--config-id`, `--objective`, `--fiber`, or `--contains` when a results root
contains heterogeneous experiments.

## Lab Handoff Smoke

```bash
make docs-check
make lab-ready
make golden-smoke
```

Use these as permanent gates:

- `make docs-check`: verifies the short agent/human documentation maps and
  catches broken documentation structure.
- `make lab-ready`: validates all maintained configs, front-layer behavior, and
  fast regression tests without producing a long-lived science result.
- `make golden-smoke`: runs one real supported smoke experiment and verifies
  the artifact bundle, standard images, and export handoff.

`make golden-smoke` writes generated output under `results/raman/smoke/`. That
output is ignored by git and should be pruned after verification unless a run is
intentionally promoted into human-facing docs:

```bash
SMOKE_KEEP=0 make prune-smoke
```

## Experimental Work

Do not add new research drivers under `scripts/`. Promote reusable logic into
`src/fiberlab/` or an extension contract, then record lane status in
[Research Verdicts](../research-verdicts.md).
