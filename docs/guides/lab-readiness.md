# Lab Readiness

[<- docs index](../README.md) | [first lab user](./first-lab-user-walkthrough.md) | [configurable experiments](./configurable-experiments.md)

This is the operational definition of lab readiness for the configurable
research engine. It is stricter than demo readiness.

Lab readiness means a new lab user can install the repo, inspect the supported
research surface, run the supported workflow, verify the artifacts, and know
which experimental surfaces are intentionally blocked until promoted.

For the shortest onboarding path, start with
[first-lab-user-walkthrough.md](./first-lab-user-walkthrough.md).

## Readiness Levels

Use these levels when discussing the repo.

- Demo-ready: the public UX is coherent and the simulation-free acceptance
  harness passes.
- Locally lab-ready: supported configs, validation gates, Python wrappers,
  artifact contracts, indexing, and lab-ready gates pass on a normal workstation.
- Smoke lab-ready: the smallest supported real run executes, writes artifacts,
  exports a neutral handoff bundle, and passes `lab_ready --latest`.
- Milestone lab-ready: slow/full numerical tests and any heavy physics runs pass
  on appropriate compute, with representative plots visually inspected.
- Research-promoted: an experimental surface, objective, or variable has
  implementation, validation, artifacts, docs, and acceptance tests strong
  enough to move out of planning/experimental status.

## Promotion Stages

The configurable front layer reports a promotion stage for each experiment plan:

- `planning`: the config is inspectable and compute-plannable, but local
  front-layer execution is intentionally blocked or incomplete.
- `smoke`: the config can execute a small run and validate artifacts, but should
  not be presented as fully promoted science.
- `validated`: the research surface has passed representative real-size
  validation on appropriate compute, but may still need final handoff/docs polish.
- `lab_ready`: another lab user can run the workflow, validate outputs, inspect
  artifacts, and understand the remaining scientific scope without code surgery.

MMF and long-fiber are currently `planning`. Direct single-mode multivariable
smokes such as gain tilt are currently `smoke`. The supported single-mode
phase-only export path is `lab_ready`.

## Finite Exit Criteria

Avoid turning lab readiness into an endless sequence of smaller checks. For the
current front-layer phase, the finite exit criteria are:

- `make lab-ready` passes
- `make golden-smoke` passes
- the generated standard image set is visually inspected
- the neutral export bundle validates
- adversarial config and sweep tests are in the fast tier
- docs state which surfaces are supported, experimental, or planning-only

Once those are true, stop hardening the same supported smoke path and move to
promotion work for the next research surface: multivariable, long-fiber, MMF,
or a non-Raman objective.

## Local Lab-Ready Gate

Run this before giving the repo to another lab user or using it as a supported
workflow checkpoint:

```bash
make lab-ready
```

This runs:

- tool availability checks
- the research-engine acceptance harness
- Python wrapper tests
- all approved experiment config validation
- all approved experiment-sweep config validation
- `lab_ready --config research_engine_export_smoke`
- the full fast Julia tier

This is simulation-free except for small setup/contract checks already in the
fast tier. It is intended to catch broken UX, broken config contracts, missing
artifact gates, broken result indexing, and broken Python wrappers quickly.

## Adversarial Config Coverage

The fast tier includes generated adversarial config tests. These tests mutate
the approved TOML configs in temporary directories and then run the normal
front-layer loader and validator. This is meant to catch mistakes a lab user is
likely to make while editing configs:

- unsafe numeric knobs such as nonpositive `Nt`, `L_fiber`, `P_cont`,
  `time_window`, pulse settings, solver iteration counts, and solver
  tolerances
- objective typos and objective/variable mismatches
- unsupported variable tuples, solvers, parameterizations, and grid policies
- invalid regularizer names and negative or nonfinite regularizer weights
- artifact-policy mistakes such as disabling required standard images
- export requests for modes that do not yet support export
- long-fiber and multimode configs that try to bypass `burst_required`
  planning gates

This does not prove every possible future config is correct. It does make the
current supported boundary fail closed: when a researcher changes TOML into an
unsupported or unsafe state, the system should reject it before launching a
simulation.

The fast tier also includes generated adversarial sweep tests. These mutate
approved sweep TOML files and validate the expanded case set:

- empty sweeps are rejected
- labels must be the same length as values, nonempty, and unique
- approved sweep files must default to `execution.mode = "dry_run"`
- approved sweep files must keep `execution.require_validate_all = true`
- unsupported sweep axes are rejected before case generation
- generated cases with invalid values or unsupported objective choices are
  rejected through the normal experiment validator
- planning-only bases such as long-fiber remain inspectable, but sweep
  execution records skipped cases instead of launching hidden heavy compute

## Real Smoke Gate

Run this when you need proof that a checkout can execute the smallest supported
workflow and produce real artifacts:

```bash
make golden-smoke
```

This runs:

- `lab_ready --config research_engine_export_smoke`
- `run_experiment.jl research_engine_export_smoke`
- `lab_ready --latest research_engine_export_smoke --require-export`

After it passes, inspect the generated standard images:

- `opt_phase_profile.png`
- `opt_evolution.png`
- `opt_phase_diagnostic.png`
- `opt_evolution_unshaped.png`

Do not call a real generated run lab-ready until the standard images have been
visually inspected. File existence alone is not enough.

Golden-smoke outputs are retained so they can be inspected. After the demo or
verification pass, prune older routine smoke runs with:

```bash
make prune-smoke
```

## Demo-Week Checklist

For a short live demo, do not start from the whole research history. Use this
fixed sequence:

```bash
make lab-ready
make golden-smoke
make demo-run
julia -t auto --project=. scripts/canonical/index_telemetry.jl --sort elapsed --desc --top 10
```

Then show:

- `scripts/canonical/run_experiment.jl --dry-run research_engine_live_demo`
  to prove the run is inspectable before execution.
- `scripts/canonical/demo_run_check.jl --latest research_engine_live_demo`
  to prove the latest generated demo bundle has standard artifacts, export, a
  trust report, and meaningful suppression.
- The four standard images from the latest demo directory.
- The `export_handoff/` bundle, especially the neutral phase CSV and
  `roundtrip_validation.json`.

`make demo-run` is intentionally separate from `make golden-smoke`. Golden
smoke is the smallest strict handoff proof and must pass `lab_ready --latest`.
The live demo is a slightly larger SMF-28 phase-only run designed to show a
visible before/after result in a research-group meeting. Its check requires
complete artifacts/export and a minimum objective improvement, but reports
optimizer convergence as advisory. Use `lab_ready --latest ...` when the claim
is canonical convergence certification.

This demo proves the lab-facing instrument can run a real short optimization
and produce a handoff bundle. It does not prove every experimental research lane
is promoted.

## Milestone Gate

For milestone claims, paper figures, or broad lab handoff, local checks are not
enough. Run the heavier tiers on appropriate compute:

```bash
make test-slow
make test-full
```

Use burst, a cluster, or another sufficiently provisioned machine for heavy
simulation work. Do not treat failure to run heavy tests locally as success.
Record where the heavy tests ran and which result artifacts were visually
inspected.

## Current Supported Surface

The currently supported lab-facing path is:

- single-mode
- phase-only
- Raman-band objective
- `lbfgs`
- standard image set
- trust report
- optional neutral CSV phase handoff

The best smoke and live-demo configs for this surface are:

```text
research_engine_export_smoke
research_engine_live_demo
```

The best configurable baseline starting point is:

```text
research_engine_poc
```

## Experimental Or Black-Boxed Surfaces

These are intentionally not yet full lab-ready surfaces:

- phase/amplitude/energy multivariable optimization
- multimode optimization
- long-fiber optimization
- planning-only objective extensions
- planning-only variable extensions

For now, the front layer must make these surfaces visible, dry-runnable,
compute-plannable, and explicitly gated. They should not silently appear as
fully supported lab workflows until their execution, artifacts, validation, and
tests are promoted.

## Current Research Closure State

As of the
[2026-04-28 closure report](../reports/research-closure-2026-04-28/REPORT.md):

- Multivariable work is closed for packaging: direct joint optimization is a
  negative result, while staged `amp_on_phase` remains optional and
  experimental.
- Long-fiber has a completed 200 m image-backed milestone, but it is not
  optimizer-converged or a turnkey lab platform.
- MMF has a qualified corrected 4096-grid simulation candidate, but high-grid
  refinement, launch sensitivity, and model-scope checks remain unpromoted.
- Newton/preconditioning stays deferred and should not appear in the production
  optimizer path.

Lab rollout should not wait on more runs from those lanes. It should keep the
supported workflow narrow and use the research lanes only as documented
examples or optional experimental paths.

## Promotion Requirements

Before an experimental surface becomes lab-ready, it needs:

- one approved config with clear maturity/status
- one small smoke config or synthetic acceptance fixture
- objective and variable contracts
- artifact plan with implemented outputs
- artifact validation
- results-index support
- lab-ready gate support
- tests for complete and missing-artifact cases
- documented interpretation of outputs
- visual-inspection expectations
- slow/full or burst verification when physics requires it

For new objectives or variables, metadata validation is not enough. A research
extension becomes runnable only after its physics, gradients, outputs, and
acceptance tests are implemented.

## What To Say Honestly

If `make lab-ready` passes, it means:

- the supported front-layer interface is mechanically healthy
- configs and gates are coherent
- artifact contracts are enforced
- indexing and lab-ready reporting work
- experimental surfaces are discoverable and blocked or gated appropriately

It does not mean:

- every experimental research lane is scientifically validated
- multimode and long-fiber execution are promoted
- every generated plot has been visually inspected
- a new objective or variable is safe just because it appears in TOML

For full lab use, pair `make lab-ready` with `make golden-smoke`, visual
inspection, and the appropriate heavy-tier verification for the specific
scientific claim.
