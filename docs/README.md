# Documentation

Docs for installing the repo, running the Raman examples, checking the plots,
and understanding what each saved result means. Old planning records are kept
separately so they do not read like current instructions.

## Read first

1. [Installation](guides/installation.md)
2. [Supported workflows](guides/supported-workflows.md)
3. [Researcher playbook](guides/researcher-playbook.md)
4. [Configurable experiments](guides/configurable-experiments.md)
5. [Internal lab release readiness](guides/internal-lab-release-readiness.md)
6. [Quickstart optimization](guides/quickstart-optimization.md)
7. [Interpreting plots](guides/interpreting-plots.md)
8. [Output format](architecture/output-format.md)

If you are returning to the project after a break, start with the
[research closure report](reports/research-closure-2026-04-28/REPORT.md).

## Guides

| Doc | Use it for |
|---|---|
| [installation](guides/installation.md) | local setup and health checks |
| [container](guides/container.md) | Docker setup |
| [supported workflows](guides/supported-workflows.md) | which commands to run first |
| [researcher playbook](guides/researcher-playbook.md) | turning a research idea into a checked config |
| [configurable experiments](guides/configurable-experiments.md) | running TOML-driven experiments through `./fiberlab` |
| [quickstart optimization](guides/quickstart-optimization.md) | single SMF-28 optimization |
| [quickstart sweep](guides/quickstart-sweep.md) | burst-machine sweep recipe |
| [golden smoke run](guides/golden-smoke-run.md) | end-to-end handoff smoke |
| [lab readiness](guides/lab-readiness.md) | checks before another lab user runs it |
| [internal lab release readiness](guides/internal-lab-release-readiness.md) | final internal handoff checklist and supported-scope reminder |
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
| [config runner design](architecture/configurable-front-layer.md) | how TOML experiment configs reach Julia code |
| [research engine UX](architecture/research-engine-ux.md) | CLI/notebook UX notes |

## Reports and status

| Doc | Use it for |
|---|---|
| [research closure](reports/research-closure-2026-04-28/REPORT.md) | current project-state summary |
| [MMF readiness](reports/mmf-raman-readiness-2026-04-28/REPORT.md) | what the current MMF result does and does not show |
| [lab physics validity](reports/lab-physics-validity-2026-04-28/REPORT.md) | what the checked lab run does and does not prove |
| [status notes](status/) | short records for individual lanes |
| [research notes](research-notes/README.md) | paper/presentation note series |

## Archive

`planning-history/` is retained for provenance. Do not use it as onboarding.
Current decisions should be summarized in `status/`, `reports/`, or
`architecture/`.
