# Research Engine UX Architecture

[<- docs index](../README.md) | [configurable experiments](../guides/configurable-experiments.md)

This document records the intended user experience for the configurable research
engine. The goal is broader than Raman suppression: the system should become a
general fiber-optic optimization research interface, with Raman suppression as
the first implemented objective family.

## Core Principle

Do not build separate science logic for every interface.

CLI commands, notebooks, sweeps, future GUI tools, and lab scripts should all
call the same validated backend contracts:

- experiment specification
- objective/variable contracts
- solver dispatch
- validation and trust checks
- artifact generation
- provenance and summaries

Each interface is a front door. None of them should become a separate source of
truth.

## User Front Doors

### 1. Config Templates

Best for lab users who want to change common parameters without coding.

UX target:

- copy a template
- edit fiber, length, power, grid, objective, variables, solver, artifacts
- run `--dry-run`
- run `--validate-all`
- execute only when the plan is clear

Pain points addressed:

- users do not know which knobs are safe
- users accidentally edit deep code
- results are not reproducible because settings are scattered

### 2. CLI

Best for reproducible runs, remote compute, CI, batch scripts, and shared lab
workflows.

UX target:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run my_config
julia -t auto --project=. scripts/canonical/run_experiment.jl my_config
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --dry-run my_sweep
```

Pain points addressed:

- notebooks are too stateful for production runs
- long jobs need clear validation before launch
- remote execution needs a scriptable interface
- different users need to run the same experiment the same way

### 3. Jupyter / Notebook Surface

Best for exploration, teaching, visualization, and comparing outputs.

UX target:

```python
from fiber_research_engine import capabilities, dry_run_experiment

print(capabilities().stdout)
print(dry_run_experiment("my_config").stdout)
```

Notebook code should call the same engine as the CLI. It should not duplicate
objective logic, validation, solver dispatch, or artifact conventions.

Current surface:

- `python/fiber_research_engine/` provides a thin standard-library wrapper
  around the maintained Julia CLI.
- `notebooks/templates/experiment_explorer.ipynb` provides a starting notebook
  for discovery, validation, dry-run planning, and sweep planning.
- optional amp-on-phase refinement is exposed only as a dry-run/planning helper
  by default; substantial runs should still go through the canonical CLI or
  burst wrapper.

Pain points addressed:

- users need interactive exploration and plots
- professors and students need readable analysis notebooks
- notebook state can become unreproducible if it bypasses the backend

Design rule:

- notebooks may orchestrate and visualize
- notebooks may not become the canonical implementation of a workflow

### 4. Sweep / Campaign Surface

Best for novel parameter-space questions.

UX target:

```toml
id = "my_power_sweep"
base_experiment = "my_base_config"

[sweep]
parameter = "problem.P_cont"
values = [0.05, 0.10, 0.20, 0.30]
```

Expected workflow:

- expand cases
- validate every case
- execute supported local-safe cases deliberately with `--execute`
- write a campaign summary table
- rank results by metrics and trust status
- make plots and artifacts easy to find

Pain points addressed:

- manually cloning many TOML files is error-prone
- sweeps produce too many folders with no high-level answer
- a professor wants comparison and interpretation, not file spelunking

### 5. Research Extension Surface

Best for new science: new objectives, variables, diagnostics, artifacts, or
mode/fiber regimes.

UX target:

```toml
kind = "my_new_objective"
regime = "single_mode"
backend = "lab_extension"
maturity = "research"
execution = "planning_only"
source = "lab_extensions/objectives/my_new_objective.jl"
function = "my_new_objective_cost"
gradient = "my_new_objective_gradient"
supported_variables = [["phase"]]
```

or, for a new optimized control:

```toml
kind = "my_new_variable"
regime = "single_mode"
backend = "lab_extension"
maturity = "research"
execution = "planning_only"
source = "lab_extensions/variables/my_new_variable.jl"
build_function = "build_my_new_variable_control"
projection_function = "project_my_new_variable_control"
units = "physical units or normalization"
bounds = "bounds or projection behavior"
parameterizations = ["full_grid"]
compatible_objectives = ["raman_band"]
```

Pain points addressed:

- a closed menu limits future research
- arbitrary config formulas can silently produce bad science
- new objectives currently require deep code surgery

Design rule:

- built-ins are safe defaults, not the research boundary
- extensions are visible contracts first
- execution promotion requires implementation, tests, validation, and output
  semantics
- objective and variable scaffolds should create planning-only contracts, not
  hidden executable behavior

### 6. Results / Campaign Index

Best for professors and group-level decision making.

UX target:

- scan by fiber, objective, variable set, date, user, regime, sweep id
- compare objective before/after and improvement
- inspect trust status and warnings
- open standard images and artifacts
- export compact tables for meetings or papers

Current surface:

```bash
julia -t auto --project=. scripts/canonical/index_results.jl
julia -t auto --project=. scripts/canonical/index_results.jl results/raman/sweeps/front_layer
julia -t auto --project=. scripts/canonical/index_results.jl --kind run --regime single_mode --objective raman_band --fiber SMF-28 --complete-images results/raman
julia -t auto --project=. scripts/canonical/index_results.jl --csv --kind run --config-id smf28_phase_smoke --contains power results/raman/sweeps/front_layer
julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 5 --lab-ready results/raman
julia -t auto --project=. scripts/canonical/index_results.jl --compare-sweeps --top 5 results/raman/sweeps/front_layer
```

Notebook users should call the same command through:

```python
from fiber_research_engine import index_results, index_results_csv

print(index_results("results/raman/sweeps/front_layer").stdout)
print(index_results_csv(
    "results/raman",
    kind="run",
    regime="single_mode",
    objective="raman_band",
    fiber="SMF-28",
).stdout)
print(index_results("results/raman", compare=True, lab_ready=True, top=5).stdout)
print(index_results("results/raman/sweeps/front_layer", compare_sweeps=True, top=5).stdout)
```

This is deliberately read-only. It scans existing run artifacts and sweep
summaries, then renders a compact Markdown or CSV table with config id, regime,
objective, variables, solver, timestamp, trust report, run config, artifact
path, headline metrics, and standard-image status where available. It does not
decide whether a result is scientifically accepted; it makes the evidence
easier to find. The comparison view ranks runs by mechanical readiness and then
objective value, so professors can quickly find candidates for deeper review.
The sweep comparison view ranks completed campaign summaries by best achieved
case while keeping case counts and failures visible. New sweeps write
`SWEEP_SUMMARY.json` and `SWEEP_SUMMARY.csv` sidecars so campaign comparison
does not depend on Markdown parsing; older Markdown-only sweeps remain
readable as a fallback.

Pain points addressed:

- results are scattered across folders
- nobody knows which run is the latest valid one
- artifacts exist but trust status is unclear
- repeated experiments are hard to compare

## Interface Boundaries

### Backend Owns

- parsing configs
- validation
- objective and variable contracts
- control layout planning: units, bounds, shapes, and optimizer-vector blocks
- solver dispatch
- artifact planning from regime/objective/variable hooks
- output schema
- trust checks
- artifact paths and provenance

## Control And Artifact Planning

The exploratory-physics surface should be explicit about two things before a
run launches:

- `ControlLayout`: what each optimized variable means physically, its units,
  bounds, shape, and optimizer-vector representation.
- `ArtifactPlan`: which plots, metrics, tables, and reports are required by the
  regime, objective, and variables.

Dry-runs should make both visible:

```bash
julia -t auto --project=. scripts/canonical/run_experiment.jl --control-layout my_config
julia -t auto --project=. scripts/canonical/run_experiment.jl --artifact-plan my_config
```

This is the bridge between configurability and lab usability. The engine should
not guess graphs. Instead, contracts request named artifact hooks, each with a
default view rule and a future config override key.

### CLI Owns

- command-line entry points
- local/remote/batch-friendly execution
- concise human-readable plans and summaries

### Notebooks Own

- interactive inspection
- plots and comparison views
- small exploratory runs when safe
- narrative analysis

### Config Owns

- scientific choices among implemented contracts
- parameter values
- sweep values
- artifact and verification policy

### Extensions Own

- new scientific definitions
- declared assumptions
- validation requirements
- promotion path to executable workflows

## Pain Point Checklist

Design every new feature against this checklist:

- Can a new user discover what exists?
- Can a researcher tell which knobs are safe?
- Does validation fail before compute?
- Can the same experiment run from CLI and notebook without changing logic?
- Are outputs standardized and findable?
- Does a sweep produce a high-level summary?
- Is remote compute provider-neutral by default?
- Are Rivera Lab burst helpers optional, not required?
- Can a new objective be added without editing deep internals?
- Is unvalidated research code clearly labeled as research/planning-only?
- Can Prof. Rivera compare results without opening every folder manually?

## Near-Term Priorities

The next priority is a playground pivot, not another round of status-only
gating. The repo should have two honest lanes:

- `lab-ready`: safe default workflows another researcher can run without hidden
  context.
- `explore`: experimental workflows for novel fiber inverse-design ideas, with
  warnings, provenance, artifact checks, and clear promotion blockers.

Implemented first CLI shape:

```bash
./fiberlab run research_engine_export_smoke
./fiberlab explore list
./fiberlab explore plan smf28_phase_amplitude_energy_poc
./fiberlab explore run smf28_phase_amplitude_energy_poc --local-smoke
./fiberlab explore run grin50_mmf_phase_sum_poc --heavy-ok --dry-run
./fiberlab explore compare results/raman --top 10
```

In this model, `run` remains conservative. `explore` is where researchers can
run semi-promoted MMF, long-fiber, multivariable, and custom-objective work
without pretending it is lab-ready. The output must be loudly labeled
experimental and must include config, provenance, warnings, metrics, artifacts,
and validation status.

The first implementation supports `explore list`, `explore plan`, guarded
`explore run`, and `explore compare`. Executable experimental front-layer
configs require `--local-smoke`. Dedicated/heavy MMF, long-fiber, and staged
multivar workflows require `--heavy-ok`; the initial slice prints the compute
plan under `--dry-run` instead of auto-launching heavy jobs.

### Playground Design References

The external tools worth learning from are patterns, not dependencies:

- Tidy3D inverse design frames workflows around a base simulation, design
  region/variables, metrics, and optimizer hyperparameters. That maps well to
  `problem`, `controls`, `objective`, `solver`, and `artifacts`.
- Meep's adjoint workflow is the right mental model for "objective over
  simulation outputs plus gradients when available." It is not currently the
  right dependency for this GNLSE fiber codebase.
- Hydra-style config composition and multirun UX is a good target for future
  config overlays and sweeps.
- MLflow-style tracking is a good model for params, metrics, artifacts, and
  provenance. The repo can implement a lightweight local version without adding
  MLflow immediately.
- Optuna's define-by-run idea is useful for exploratory low-dimensional search
  spaces. For high-dimensional phase/amplitude controls, the repo still needs
  explicit gradients or carefully limited derivative-free runs.

### Meep Decision

Do not use Meep as a dependency for the current playground.

Reasoning:

- Meep is an FDTD electromagnetic simulator. This repo's core physics is
  nonlinear fiber propagation/GNLSE-style modeling.
- Replacing the propagation backend with Meep would be a major scientific and
  software project, not a UX improvement.
- The useful Meep lesson is architectural: expose objectives as functions of
  simulation outputs, verify gradients with Taylor/finite-difference checks, and
  keep adjoint behavior explicit.

When Meep could make sense later:

- if the group wants chip/free-space photonic inverse design alongside fiber
  propagation;
- if a future module needs FDTD geometry/design-region optimization;
- if the repo becomes a multi-backend photonics playground with a shared
  experiment/provenance layer.

For the near-term fiber playground, keep the existing Julia fiber solver and
borrow the objective/adjoint UX ideas.

### Concrete Playground Slices

1. Add `promote check` to report missing tests/artifacts/docs for an exploratory
   workflow.
2. Make staged multivar callable through `explore run` instead of only printing
   a command.
3. Make MMF and long-fiber exploratory dispatch explicit: if direct front-layer
   execution is not implemented, generate and optionally launch the dedicated
   workflow only under `--heavy-ok`.
4. Add a generic exploratory run manifest with status, warnings, promotion
   blockers, config hash, git state, params, metrics, artifacts, and command.
5. Add a low-dimensional derivative-free exploratory backend for variables like
   gain tilt, energy scale, mode weights, launch parameters, and fiber/pulse
   scalars. Do not apply it blindly to full-grid phase controls.
6. Add generic fallback plots for exploratory runs: input/output spectra,
   time-domain pulse, objective trace, variable values, and regime-specific
   summaries when available.
7. Keep notebooks as orchestration/analysis front doors over the same backend,
    not separate science implementations.

## Decision

The best UX is one shared validated engine with multiple front doors:

- safe config templates for routine users
- CLI for reproducibility and compute
- notebooks for exploration and visualization
- sweeps/campaigns for parameter-space research
- extension contracts for new science
- results index for group-level comparison

This preserves research freedom without making the system mysterious or unsafe.
