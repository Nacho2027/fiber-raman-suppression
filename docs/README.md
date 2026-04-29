# Documentation

This is the map for human-facing docs. It keeps current runbooks separate from
old planning records.

## Read first

1. [Installation](guides/installation.md)
2. [Supported workflows](guides/supported-workflows.md)
3. [Researcher playbook](guides/researcher-playbook.md)
4. [Configurable experiments](guides/configurable-experiments.md)
5. [Quickstart optimization](guides/quickstart-optimization.md)
6. [Interpreting plots](guides/interpreting-plots.md)
7. [Output format](architecture/output-format.md)

If you are returning to the project after a break, start with the
[research closure report](reports/research-closure-2026-04-28/REPORT.md).

## Guides

| Doc | Use it for |
|---|---|
| [installation](guides/installation.md) | local setup and health checks |
| [container](guides/container.md) | Docker setup |
| [supported workflows](guides/supported-workflows.md) | what is maintained and what is experimental |
| [researcher playbook](guides/researcher-playbook.md) | what to do when starting a new research idea |
| [configurable experiments](guides/configurable-experiments.md) | running TOML-driven experiments through `./fiberlab` |
| [quickstart optimization](guides/quickstart-optimization.md) | single SMF-28 optimization |
| [quickstart sweep](guides/quickstart-sweep.md) | burst-machine sweep recipe |
| [golden smoke run](guides/golden-smoke-run.md) | end-to-end handoff smoke |
| [lab readiness](guides/lab-readiness.md) | promotion gates for lab use |
| [SLM replay](guides/slm-replay.md) | export and replay of phase masks |
| [adding a fiber preset](guides/adding-a-fiber-preset.md) | adding a new preset safely |
| [adding an optimization variable](guides/adding-an-optimization-variable.md) | extending the control vector |
| [research extensions](guides/research-extensions.md) | planning new objectives or variables |
| [compute telemetry](guides/compute-telemetry.md) | reading run timing and failure records |

## Architecture

| Doc | Use it for |
|---|---|
| [repo navigation](architecture/repo-navigation.md) | deciding where code belongs |
| [codebase visual map](architecture/codebase-visual-map.md) | quick directory/data-flow map |
| [output format](architecture/output-format.md) | saved JLD2, JSON, manifest, and image files |
| [cost convention](architecture/cost-convention.md) | sign and dB conventions |
| [cost-function physics](architecture/cost-function-physics.md) | objective and adjoint framing |
| [configurable front layer](architecture/configurable-front-layer.md) | front-layer design notes |
| [research engine UX](architecture/research-engine-ux.md) | CLI/notebook UX notes |

## Reports and status

| Doc | Use it for |
|---|---|
| [research closure](reports/research-closure-2026-04-28/REPORT.md) | current project-state summary |
| [MMF readiness](reports/mmf-raman-readiness-2026-04-28/REPORT.md) | multimode claim boundary |
| [lab physics validity](reports/lab-physics-validity-2026-04-28/REPORT.md) | what the lab surface can and cannot prove |
| [status notes](status/) | short records for individual lanes |
| [research notes](research-notes/README.md) | paper/presentation note series |

## Archive

`planning-history/` is retained for provenance. Do not use it as onboarding.
Current decisions should be summarized in `status/`, `reports/`, or
`architecture/`.
