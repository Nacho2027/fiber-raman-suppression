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

Pain points addressed:

- a closed menu limits future research
- arbitrary config formulas can silently produce bad science
- new objectives currently require deep code surgery

Design rule:

- built-ins are safe defaults, not the research boundary
- extensions are visible contracts first
- execution promotion requires implementation, tests, validation, and output
  semantics

### 6. Results / Campaign Index

Best for professors and group-level decision making.

UX target:

- search by fiber, objective, variable set, date, user, regime, sweep id
- compare objective before/after and improvement
- inspect trust status and warnings
- open standard images and artifacts
- export compact tables for meetings or papers

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
- solver dispatch
- output schema
- trust checks
- artifact paths and provenance

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

1. Add supported sweep execution for local-safe cases only.
2. Add Markdown/CSV campaign summaries for sweeps.
3. Add optional refinement planning to the notebook wrapper without making it
   a default lab workflow.
4. Add a searchable run/campaign index.
5. Add promotion guides for objective and variable extensions.

## Decision

The best UX is one shared validated engine with multiple front doors:

- safe config templates for routine users
- CLI for reproducibility and compute
- notebooks for exploration and visualization
- sweeps/campaigns for parameter-space research
- extension contracts for new science
- results index for group-level comparison

This preserves research freedom without making the system mysterious or unsafe.
