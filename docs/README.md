# Documentation

This index covers the human-facing docs in `docs/`. It is written for Rivera
Lab users running the maintained workflows, interpreting results, or modifying
the codebase.

See also: [../README.md](../README.md) for the project-level overview.

## Start here

If you are new to the repo but already know the research context, read in this
order:

1. [guides/installation.md](./guides/installation.md)
2. [guides/configurable-experiments.md](./guides/configurable-experiments.md)
3. [guides/quickstart-optimization.md](./guides/quickstart-optimization.md)
4. [guides/interpreting-plots.md](./guides/interpreting-plots.md)
5. [architecture/repo-navigation.md](./architecture/repo-navigation.md)
6. [architecture/output-format.md](./architecture/output-format.md)

If you are resuming work after time away, the synthesis and status sections are
usually more useful than the onboarding sequence.

## Guides

| Doc | Use it for |
|-----|------------|
| [guides/installation.md](./guides/installation.md) | Environment setup and troubleshooting on laptops and project VMs. |
| [guides/configurable-experiments.md](./guides/configurable-experiments.md) | Running and modifying the configurable experiment front layer without editing optimizer internals. |
| [guides/quickstart-optimization.md](./guides/quickstart-optimization.md) | Running the maintained single-optimization workflow and checking the output. |
| [guides/quickstart-sweep.md](./guides/quickstart-sweep.md) | Running a sweep on `fiber-raman-burst` and pulling results back correctly. |
| [guides/supported-workflows.md](./guides/supported-workflows.md) | The explicit boundary between the supported lab-facing surface and still-experimental research workflows. |
| [guides/interpreting-plots.md](./guides/interpreting-plots.md) | Reading standard plots, convergence curves, and sweep heatmaps. |
| [guides/adding-a-fiber-preset.md](./guides/adding-a-fiber-preset.md) | Adding or auditing a fiber preset in the shared setup layer. |
| [guides/adding-an-optimization-variable.md](./guides/adding-an-optimization-variable.md) | Extending the optimization variable beyond spectral phase. |

## Architecture and reference

| Doc | Use it for |
|-----|------------|
| [architecture/repo-navigation.md](./architecture/repo-navigation.md) | Deciding where code should live and which layer is authoritative. |
| [architecture/codebase-visual-map.md](./architecture/codebase-visual-map.md) | Visual companion to the repo navigation guide. |
| [architecture/configurable-front-layer.md](./architecture/configurable-front-layer.md) | Proposal for a thin configurable research-engine front layer above the current workflows. |
| [architecture/output-format.md](./architecture/output-format.md) | Understanding saved JLD2 and JSON run artifacts. |
| [architecture/cost-convention.md](./architecture/cost-convention.md) | Cost-sign and dB-reporting conventions. |
| [architecture/cost-function-physics.md](./architecture/cost-function-physics.md) | Physics rationale and the adjoint/cost-function framing used here. |

## Status and synthesis

These files are for re-entry and decision support, not first-time onboarding.

| Doc | Use it for |
|-----|------------|
| [synthesis/recent-phase-synthesis-29-34.md](./synthesis/recent-phase-synthesis-29-34.md) | Recovering the main conclusions from recent phases without rereading the full planning history. |
| [synthesis/why-phase-31-changed-the-roadmap.md](./synthesis/why-phase-31-changed-the-roadmap.md) | Understanding why Phase 31 changed the project direction. |
| [synthesis/why-phase-34-still-points-back-to-phase-31.md](./synthesis/why-phase-34-still-points-back-to-phase-31.md) | Understanding why the later trust-region work still points back to the Phase 31 conclusion. |
| [status/lab-readiness-proposal-2026-04-23.md](./status/lab-readiness-proposal-2026-04-23.md) | Maintainer proposal for what the first honest lab-ready surface should be and what should wait. |
| [status/multimode-baseline-status-2026-04-22.md](./status/multimode-baseline-status-2026-04-22.md) | Current state of the multimode baseline work. |
| [status/phase-30-status.md](./status/phase-30-status.md) | What Phase 30 actually established. |
| [status/phase-32-status.md](./status/phase-32-status.md) | What Phase 32 acceleration work did and did not establish. |
| [status/phase-34-preconditioning-caveat.md](./status/phase-34-preconditioning-caveat.md) | Caveat for interpreting the current preconditioning comparisons. |
| [status/phase-34-bounded-rerun-status.md](./status/phase-34-bounded-rerun-status.md) | Summary of the bounded reruns after the Phase 34 fix. |
| [status/phase-34-dispersion-closure.md](./status/phase-34-dispersion-closure.md) | Formal decision record closing dispersion preconditioning as an active Raman-suppression branch. |

## Reference PDFs and artifacts

| Doc | Use it for |
|-----|------------|
| [reference/companion_explainer.pdf](./reference/companion_explainer.pdf) | Longer mathematical walkthrough of the forward and adjoint setup. |
| [reference/verification_document.pdf](./reference/verification_document.pdf) | Formal verification notes keyed to implementation details. |
| [reference/physics_verification.pdf](./reference/physics_verification.pdf) | Physics-verification notes and supporting derivations. |
| [artifacts/README.md](./artifacts/README.md) | Durable figures and report artifacts intentionally kept under `docs/`. |
| [reports/README.md](./reports/README.md) | Human-facing report outputs kept alongside the docs tree. |

## Planning history

The `planning-history/` subtree is retained as project history. It is useful
when you need provenance on why a phase was opened, what was claimed at the
time, or how an implementation decision evolved.

The current operational interpretation of that history usually lives in the
status and synthesis docs above.
