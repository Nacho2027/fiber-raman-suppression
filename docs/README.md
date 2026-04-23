# Documentation — Fiber Raman Suppression

One-page index of every doc in this folder. All docs are plain markdown — no
static-site build step. The LaTeX PDFs beside them (see "Math pedagogy" below)
stay for math-heavy readers.

See also: [`../README.md`](../README.md) for the project-level overview.

## Operational docs (the ones you run commands from)

| Doc | Read when you want to... |
|-----|--------------------------|
| [installation.md](./installation.md) | Install Julia, Python/Matplotlib, and dependencies; troubleshoot Mac / Linux / GCP VM setups. |
| [quickstart-optimization.md](./quickstart-optimization.md) | Run your first optimization (<15 min). **Start here if you just cloned.** |
| [quickstart-sweep.md](./quickstart-sweep.md) | Launch a parameter sweep and interpret `results/raman/sweeps/`. |
| [output-format.md](./output-format.md) | Understand the JLD2 + JSON sidecar format produced by every run. |
| [interpreting-plots.md](./interpreting-plots.md) | Read the 4-panel report card and know what "good Raman suppression" looks like. |
| [adding-a-fiber-preset.md](./adding-a-fiber-preset.md) | Extend `FIBER_PRESETS` with a new fiber type. |
| [adding-an-optimization-variable.md](./adding-an-optimization-variable.md) | Extend the framework with a new optimization variable (stub — Session A in progress). |

## Recent synthesis

| Doc | Read when you want to... |
|-----|--------------------------|
| [recent-phase-synthesis-29-34.md](./recent-phase-synthesis-29-34.md) | Recover the main lessons from Phases 29-34 without rereading the full planning history. |
| [why-phase-31-changed-the-roadmap.md](./why-phase-31-changed-the-roadmap.md) | Understand why Phase 31 shifted attention from penalty tuning toward continuation, curvature, and basin access. |

## Phase Status Notes

| Doc | Read when you want to... |
|-----|--------------------------|
| [phase-30-status.md](./phase-30-status.md) | See what Phase 30 actually completed versus what its flagship continuation demo failed to prove. |
| [phase-32-status.md](./phase-32-status.md) | See which Phase 32 acceleration experiments really ran and which conclusions are still provisional. |
| [phase-34-preconditioning-caveat.md](./phase-34-preconditioning-caveat.md) | Understand why current Phase 34 preconditioning comparisons need a wiring caveat before interpretation. |

## Physics / math pedagogy

| Doc | What it is |
|-----|------------|
| [cost-function-physics.md](./cost-function-physics.md) | Prose walkthrough of GNLSE, adjoint, log-scale cost, Raman band. |
| [companion_explainer.pdf](./companion_explainer.pdf) | First-principles math walkthrough (undergrad-friendly). |
| [verification_document.pdf](./verification_document.pdf) | Formal equation-by-equation code verification. |
| [physics_verification.pdf](./physics_verification.pdf) | Physics verification notes. |

## Canonical reading order

If you are new to the project:

1. [`../README.md`](../README.md) — 90-second overview.
2. [installation.md](./installation.md) — get dependencies working.
3. [quickstart-optimization.md](./quickstart-optimization.md) — your first result.
4. [interpreting-plots.md](./interpreting-plots.md) — make sense of it.
5. [cost-function-physics.md](./cost-function-physics.md) — understand why it works.
6. [output-format.md](./output-format.md) — needed before writing analysis scripts.

Everything else is reference material for the first time you need it.

## Related project artifacts

- [`../results/RESULTS_SUMMARY.md`](../results/RESULTS_SUMMARY.md) — plain-language summary of
  what the optimizer achieves across fiber presets.
- [`../.planning/STATE.md`](../.planning/STATE.md) — running log of decisions, bugs fixed, open
  concerns. Useful context for maintainers.
