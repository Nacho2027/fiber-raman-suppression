# Fiber Raman Suppression

Raman-suppression simulation, optimization, and result-generation workflows for
nonlinear fiber propagation.

## What lives here

- Adjoint-based spectral-phase optimization for suppressing stimulated Raman
  scattering in optical fibers.
- Canonical single-run and sweep workflows for the maintained SMF-28 and HNLF
  studies.
- Approved config files for the narrow supported lab-facing surface.
- Shared result I/O, plotting, and report-generation utilities used by the lab
  workflow.
- Research scripts, status notes, and synthesis documents that capture what the
  recent phases actually established.

## Current research status

The active exploratory science phase is closed for now. The project is moving
to codebase hardening, findings packaging, and lab/presentation readiness.

| Lane | Status | Where to read |
|------|--------|---------------|
| Single-mode phase optimization | Supported core workflow | [supported workflows](docs/guides/supported-workflows.md) |
| Staged multivariable `amp_on_phase` | Positive experimental result; optional workflow, not default lab path | [closure report](docs/reports/research-closure-2026-04-28/REPORT.md) |
| Direct joint multivariable optimization | Negative / low-priority result | [closure report](docs/reports/research-closure-2026-04-28/REPORT.md) |
| Long-fiber 200 m | Completed image-backed milestone, not optimizer-converged | [200 m status](docs/status/longfiber-200m-closure-2026-04-28.md) |
| Multimode / MMF | Qualified simulation candidate; high-grid refinement remains open | [MMF readiness report](docs/reports/mmf-raman-readiness-2026-04-28/REPORT.md) |
| Newton / preconditioning | Deferred research note, not production optimizer path | [research notes](docs/research-notes/README.md) |

The concise end-of-exploration summary is
[docs/reports/research-closure-2026-04-28/REPORT.md](docs/reports/research-closure-2026-04-28/REPORT.md).

## Usual starting point

For a fresh clone:

```bash
make install
make doctor
make optimize
```

That sequence instantiates the pinned Julia environment, installs the thin
Python/Jupyter wrapper into a local `.venv`, runs the lightweight install
checks, and produces the canonical SMF-28 optimization run.

If you want the same headless Linux environment regardless of host machine:

```bash
make docker-build
make docker-test
```

If you need the supporting docs, start with:

- [docs/guides/installation.md](docs/guides/installation.md)
- [docs/guides/container.md](docs/guides/container.md)
- [docs/guides/configurable-experiments.md](docs/guides/configurable-experiments.md)
- [docs/guides/quickstart-optimization.md](docs/guides/quickstart-optimization.md)
- [docs/README.md](docs/README.md)

## Common tasks

| Task | Read |
|------|------|
| Install dependencies and verify the environment | [docs/guides/installation.md](docs/guides/installation.md) |
| Run in a reproducible Linux container | [docs/guides/container.md](docs/guides/container.md) |
| Run or modify a configurable experiment | [docs/guides/configurable-experiments.md](docs/guides/configurable-experiments.md) |
| Run the canonical optimization | [docs/guides/quickstart-optimization.md](docs/guides/quickstart-optimization.md) |
| Run a parameter sweep on the burst VM | [docs/guides/quickstart-sweep.md](docs/guides/quickstart-sweep.md) |
| See what is actually supported vs still experimental | [docs/guides/supported-workflows.md](docs/guides/supported-workflows.md) |
| See the current findings and lane closure state | [docs/reports/research-closure-2026-04-28/REPORT.md](docs/reports/research-closure-2026-04-28/REPORT.md) |
| Understand repo boundaries before editing code | [docs/architecture/repo-navigation.md](docs/architecture/repo-navigation.md) |
| Understand saved result files | [docs/architecture/output-format.md](docs/architecture/output-format.md) |
| Interpret standard plots and sweep heatmaps | [docs/guides/interpreting-plots.md](docs/guides/interpreting-plots.md) |
| Review the physics and cost-function rationale | [docs/architecture/cost-function-physics.md](docs/architecture/cost-function-physics.md) |
| Add a fiber preset or optimization variable | [docs/guides/adding-a-fiber-preset.md](docs/guides/adding-a-fiber-preset.md), [docs/guides/adding-an-optimization-variable.md](docs/guides/adding-an-optimization-variable.md) |
| Give an agent or LLM tool a compact docs map | [llms.txt](llms.txt) |
| Re-enter recent project conclusions | [docs/synthesis/](docs/synthesis/) and [docs/status/](docs/status/) |

## Research-Engine CLI

For configurable lab workflows, use the checkout-local `fiberlab` front door.
It is a thin wrapper over the maintained Julia entry points, so notebooks, CLI
users, and future automation all hit the same validation and artifact contracts:

```bash
./fiberlab explore list
./fiberlab explore plan research_engine_gain_tilt_smoke
./fiberlab check config research_engine_gain_tilt_smoke
./fiberlab explore run research_engine_gain_tilt_smoke --local-smoke
./fiberlab explore run research_engine_gain_tilt_scalar_search_smoke --local-smoke
./fiberlab explore compare results/raman --top 10
```

Use `explore` first when asking new research questions. It is the playground
lane: inspect a config, run explicit local smokes, dry-run heavy/dedicated
paths, and compare outputs without presenting the workflow as lab-promoted. Use
`check config` before compute when you want a plain-language answer to: can this
be inspected, how should it run, will artifacts/metadata be enough to compare,
and what is still missing?

New front-layer runs also write `run_manifest.json` beside the result artifact.
That file is the run's lab-notebook entry: command, config hash, regime,
variables, objective, run context, artifact status, key metrics, and git
provenance. `explore compare` reads this file when present and shows the run
context, compare-ready flag, and missing handoff items directly in the
comparison table.

Executable exploratory configs also write a generic fallback bundle:
`{tag}_explore_summary.json` and `{tag}_explore_overview.png`. These are not a
replacement for physics-specific plots. They give every novel objective or
variable a first-pass spectrum, temporal-pulse, objective-trace, and control
summary so a researcher can inspect the run without writing plotting code first.

The first low-dimensional derivative-free playground backend is
`solver.kind = "bounded_scalar"` for a gain-tilt-only control. It is meant for
small scalar search spaces, not full-grid phase or amplitude design.

Use the conservative `run`/`ready` lane when you need the currently supported
reference workflow:

```bash
./fiberlab configs
./fiberlab plan research_engine_poc
./fiberlab run research_engine_poc
./fiberlab latest research_engine_poc
./fiberlab ready latest research_engine_poc
./fiberlab sweep plan smf28_power_micro_sweep
./fiberlab objectives --validate
./fiberlab variables --validate
```

Use `./fiberlab scaffold objective ...` or `./fiberlab scaffold variable ...`
to start planning a new research objective or optimized control without editing
deep internals. Scaffolds are visible and validated, but they are not executable
until the physics, gradients, outputs, and tests are promoted.

## Repository layout

```text
src/         Julia package code and reusable infrastructure
configs/     Approved run and sweep specs for the supported workflow surface
scripts/     Canonical entry points, maintained workflows, shared script libs,
             research drivers, and operational helpers
docs/        Human-facing documentation, architecture notes, status, and synthesis
agent-docs/  Agent-facing continuity notes, handoffs, and current context
llms.txt     Compact machine-readable map of the highest-value docs
test/        Tiered regression suite
results/     Run artifacts and generated figures; not normal source code
notebooks/   Scratch analysis, not the canonical workflow surface
```

The maintained command-line entry points are under
[`scripts/canonical/`](scripts/canonical/README.md). If you are deciding where
new code should live, read
[docs/architecture/repo-navigation.md](docs/architecture/repo-navigation.md)
before editing.

The supported-vs-experimental boundary is documented in
[docs/guides/supported-workflows.md](docs/guides/supported-workflows.md).

## Environment and Compute Expectations

- Julia `1.12.6` is the pinned development/runtime version for this repo.
- Python `3.10+` is required for the optional notebook wrapper; `.python-version`
  records the current local target, `3.11`.
- Docker is optional but recommended when you want a clean Linux/headless
  reference environment.
- The Rivera Lab `claude-code-host` / `fiber-raman-burst` workflow is the
  project compute setup for heavy sweeps, not a requirement for running the
  supported single-run workflow on another machine.
- Heavy sweeps and substantial simulation runs should run on a multicore
  machine rather than the small always-on editing VM.
- Any workflow that produces `phi_opt` is expected to leave the standard image
  set on disk before the run is considered complete.

These workflow rules are documented in
[docs/guides/quickstart-sweep.md](docs/guides/quickstart-sweep.md) and in the
project operating docs.

## Results and outputs

Canonical runs write JLD2 payloads, JSON sidecars, and the standard image set
under `results/`. Sweep reports and presentation figures are generated from
those saved artifacts rather than by rerunning optimization.

For field definitions and loading conventions, see
[docs/architecture/output-format.md](docs/architecture/output-format.md).

## Attribution and license

The repo builds on Michael Horodynski's
[MultiModeNoise.jl](https://github.com/michaelhorodynski/MultiModeNoise.jl),
extended here with adjoint optimization, workflow tooling, result
serialization, and visualization specific to the Raman-suppression project.

MIT license. See [LICENSE](LICENSE).
