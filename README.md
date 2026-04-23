# Fiber Raman Suppression

Raman-suppression simulation, optimization, and result-generation workflows for
nonlinear fiber propagation.

## What lives here

- Adjoint-based spectral-phase optimization for suppressing stimulated Raman
  scattering in optical fibers.
- Canonical single-run and sweep workflows for the maintained SMF-28 and HNLF
  studies.
- Shared result I/O, plotting, and report-generation utilities used by the lab
  workflow.
- Research scripts, status notes, and synthesis documents that capture what the
  recent phases actually established.

## Usual starting point

For a fresh clone:

```bash
make install
make test
make optimize
```

That sequence instantiates the Julia environment, runs the fast regression
tests, and produces the canonical SMF-28 optimization run.

If you need the supporting docs, start with:

- [docs/guides/installation.md](docs/guides/installation.md)
- [docs/guides/quickstart-optimization.md](docs/guides/quickstart-optimization.md)
- [docs/README.md](docs/README.md)

## Common tasks

| Task | Read |
|------|------|
| Install dependencies and verify the environment | [docs/guides/installation.md](docs/guides/installation.md) |
| Run the canonical optimization | [docs/guides/quickstart-optimization.md](docs/guides/quickstart-optimization.md) |
| Run a parameter sweep on the burst VM | [docs/guides/quickstart-sweep.md](docs/guides/quickstart-sweep.md) |
| Understand repo boundaries before editing code | [docs/architecture/repo-navigation.md](docs/architecture/repo-navigation.md) |
| Understand saved result files | [docs/architecture/output-format.md](docs/architecture/output-format.md) |
| Interpret standard plots and sweep heatmaps | [docs/guides/interpreting-plots.md](docs/guides/interpreting-plots.md) |
| Review the physics and cost-function rationale | [docs/architecture/cost-function-physics.md](docs/architecture/cost-function-physics.md) |
| Add a fiber preset or optimization variable | [docs/guides/adding-a-fiber-preset.md](docs/guides/adding-a-fiber-preset.md), [docs/guides/adding-an-optimization-variable.md](docs/guides/adding-an-optimization-variable.md) |
| Re-enter recent project conclusions | [docs/synthesis/](docs/synthesis/) and [docs/status/](docs/status/) |

## Repository layout

```text
src/         Julia package code and reusable infrastructure
scripts/     Canonical entry points, maintained workflows, shared script libs,
             research drivers, and operational helpers
docs/        Human-facing documentation, architecture notes, status, and synthesis
test/        Tiered regression suite
results/     Run artifacts and generated figures; not normal source code
notebooks/   Scratch analysis, not the canonical workflow surface
```

The maintained command-line entry points are under
[`scripts/canonical/`](scripts/canonical/README.md). If you are deciding where
new code should live, read
[docs/architecture/repo-navigation.md](docs/architecture/repo-navigation.md)
before editing.

## Environment and compute expectations

- Julia `1.9.3+` is required; the repo currently targets Julia `1.12.x`.
- `claude-code-host` is for editing, orchestration, and light verification.
- Heavy sweeps and substantial simulation runs belong on `fiber-raman-burst`.
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
