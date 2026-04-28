# Configurable Research Engine Plan

## Goal

Make the repository usable as a configurable scientific instrument for
fiber-optic optimization research, not just a collection of author-operated
scripts.

Raman suppression is the first implemented research family and the current
default objective surface. The architecture should not be framed as Raman-only:
future families may include dispersion management, pulse compression,
mode-shaping, stability/robustness optimization, coupling optimization, or
other fiber-optic objectives.

The target user should be able to change the scientific question in config,
validate the question, run or stage compute, and inspect standardized outputs
without editing optimizer internals. When a question requires new physics, new
objectives, or new optimized variables, the code-defined contract should make
that extension explicit instead of hiding it behind config theater.

UX architecture decision: maintain one validated backend with multiple front
doors: config templates, CLI, Jupyter/notebooks, sweeps/campaigns, research
extensions, and a results index. See
`docs/architecture/research-engine-ux.md`.

## Current Position

The front layer now supports:

- single-run experiment configs
- objective/cost registration
- capability discovery
- config validation
- dry-run planning
- provider-neutral compute plans
- control-layout inspection
- artifact-plan inspection
- supported single-mode phase-only execution
- experimental single-mode multivariable execution
- long-fiber planning-only configs
- multimode planning-only configs
- neutral phase handoff
- front-layer experiment sweep expansion and validation
- metadata-only lab objective extensions under `lab_extensions/objectives/`
- metadata-only lab variable extensions under `lab_extensions/variables/`

This is enough for reproducible parameter exploration inside known physics and
optimization contracts, currently centered on Raman suppression. It is not yet
enough for arbitrary new fiber-optic objectives, variables, solvers, or mode
models without code work.

## Roadmap To Novel Research Use

### 1. Sweep Layer

Status: started.

Purpose: let a researcher ask parameter-space questions without cloning many
TOML files by hand.

Minimum scope:

- expand a validated base experiment across one parameter path
- validate every generated case before compute
- render an explicit dry-run plan
- support safe parameters first: `problem.L_fiber`, `problem.P_cont`,
  `problem.Nt`, `problem.time_window`, `solver.max_iter`, `objective.kind`

Current slice:

- latest-sweep discovery is available through `run_experiment_sweep.jl --latest`
- completed sweeps write `SWEEP_SUMMARY.md`, `SWEEP_SUMMARY.json`, and
  `SWEEP_SUMMARY.csv`
- the shared results index can scan sweep summaries without manually finding
  timestamped folders

### 2. Notebook Surface

Status: started.

Purpose: support interactive exploration without forking the science logic away
from the CLI/backend.

Minimum scope:

- small wrapper API for loading configs, dry-running, running small safe cases,
  inspecting outputs, and plotting standard images
- notebook template for experiment exploration and comparison
- clear rule that notebooks orchestrate and visualize, but do not own objective
  logic or artifact contracts

Current slice:

- `python/fiber_research_engine/` wraps the maintained Julia CLI for notebooks
- `notebooks/templates/experiment_explorer.ipynb` demonstrates discovery,
  validation, experiment dry-run, and sweep dry-run from Jupyter

### 3. Campaign Summaries

Status: started.

Purpose: make sweeps scientifically useful after they run.

Minimum scope:

- table of config id, parameter value, objective before/after, improvement dB,
  convergence, artifact path, trust report path, and standard image status
- sort by best suppression and flag failed/window-limited cases
- produce a Markdown summary under the sweep output directory

Current slice:

- `run_experiment_sweep.jl --execute` writes `SWEEP_SUMMARY.md`,
  `SWEEP_SUMMARY.json`, and `SWEEP_SUMMARY.csv` with status, objective
  metrics, convergence, iterations, and artifact/error path per case
- summaries include artifact validation, trust-report, and standard-image status
  columns
- `run_experiment_sweep.jl --latest` prints the latest completed sweep summary
  without requiring users to find timestamped folders manually

Next promotion:

- add cross-sweep comparison views and sortable campaign indexes

### 4. Results Index

Status: started.

Purpose: make outputs searchable and comparable across users, configs, sweeps,
and research campaigns.

Minimum scope:

- index run id, config id, objective, variables, fiber, regime, date, user,
  artifact paths, trust status, and headline metrics
- let CLI and notebook surfaces query the same index
- avoid forcing professors to inspect folders manually

Current slice:

- `scripts/canonical/index_results.jl` scans run artifacts and sweep summaries
  from one or more roots and renders Markdown or CSV
- `fiber_research_engine.index_results(...)` exposes the same index to
  notebooks without duplicating scan logic
- ledger metadata is populated from `run_config.toml`, `opt_result.json`, and
  local trust-report files where available
- filters are available for kind, config id, regime, objective, fiber,
  complete standard images, and a simple substring match
- `--compare` ranks run artifacts by mechanical lab readiness and then
  suppression objective, with `--top` for meeting-sized shortlists
- `--compare-sweeps` summarizes completed sweep summaries by case counts,
  failures, best case, best achieved objective, and median achieved objective

Next promotion:

- add date-range and trust-status filters once those fields are consistently
  normalized
- add richer sweep visual comparison plots after campaign sidecars stabilize

### 5. Heavy Regime Promotion

Status: planned.

Purpose: move one planning-only regime into the front-layer execution contract.

Candidate order:

- long-fiber first if the group needs SMF-28/long-reach results
- multimode first if the group needs GRIN-50 mode physics and MMF cost studies

Promotion criteria:

- front-layer config maps to the dedicated workflow
- standard artifact set is produced
- trust checks are explicit
- local execution remains blocked when `burst_required`
- provider-neutral compute path remains documented

### 6. Objective Authoring Guide

Status: started.

Purpose: let a new researcher add a new cost function safely, including
non-Raman fiber-optic objectives.

Minimum scope:

- declare metadata in `lab_extensions/objectives/*.toml`
- make the contract discoverable through `--objectives`
- validate metadata and promotion blockers through `--validate-objectives`
- scaffold a new planning-only objective through
  `scripts/canonical/scaffold_objective.jl`
- document where to implement the formula
- document where to implement/check gradients
- document how to promote from `planning_only` to executable
- document which tests must be added
- document how to expose a config example

Current slice:

- scaffold helper creates a TOML contract plus Julia cost/gradient stubs
- scaffold defaults remain `planning_only`, `research`, and `lab_extension`
  so new science starts visible but non-executable

Next promotion:

- add a real non-Raman smoke objective or a no-op analytic toy objective for
  extension-runner validation
- add execution gating so only promoted extension objectives can run
- add objective-specific artifact metric hooks

### 7. Variable Authoring Guide

Status: started.

Purpose: let a new researcher add a new optimized control safely, including
controls beyond spectral phase/amplitude when the physics and output semantics
are defined.

Minimum scope:

- define variable semantics and units
- define bounds/parameterization
- define objective compatibility
- define artifact/export meaning
- add tests and one config example

Current slice:

- built-in variable contracts are discoverable through
  `run_experiment.jl --variables`
- planning-only variable extensions are discoverable under
  `lab_extensions/variables/`
- `run_experiment.jl --validate-variables` reports metadata validity and
  promotion blockers
- `scripts/canonical/scaffold_variable.jl` creates a TOML contract plus Julia
  build/projection stubs with overwrite protection
- `mode_weights_demo` demonstrates a multimode, non-executable variable
  planning contract for future modal-weight research

Next promotion:

- add a real variable promotion guide that maps a variable contract into
  `ControlLayout`, bounds/projection behavior, objective compatibility, and
  artifact/export semantics
- add one tiny executable variable smoke surface only after the control math and
  output meaning are unambiguous

### 8. Scientific Acceptance Gate

Status: planned.

Purpose: prevent mechanically complete runs from being mistaken for
scientifically acceptable results.

Minimum scope:

- objective improvement threshold
- boundary leakage threshold
- energy/photon conservation threshold
- standard image inspection checklist
- trust-report checklist
- explicit notes for parameter regimes that are exploratory only

### 9. Control And Artifact Planning

Status: started.

Purpose: make exploratory physics understandable before compute launches.

Minimum scope:

- report each optimized variable as a physical control block
- show units, bounds, shape, and optimizer-vector length
- combine regime/objective/variable artifact hooks into one output plan
- show which requested plots/metrics are implemented now versus planned
- document how automatic plot defaults and user overrides should work

Current slice:

- `scripts/lib/control_layout.jl` renders inspectable optimizer-vector blocks
  for current variables
- `scripts/lib/artifact_plan.jl` combines regime, objective, and variable
  artifact hooks
- `run_experiment.jl --control-layout <config>` prints the control layout
- `run_experiment.jl --artifact-plan <config>` prints required plots/metrics,
  default view rules, override keys, and implementation status
- dry-runs now summarize control layout and artifact hooks
- `docs/guides/exploratory-physics-workflow.md` explains the lab workflow in
  plain language

Next promotion:

- wire remaining artifact hooks directly into post-run generation for future
  controls/objectives such as mode weights and pulse compression
- add plot override parsing under `[plots.*]`
- require artifact-plan completeness before marking a non-smoke workflow
  `supported`

## Operating Principle

Use config for selecting among implemented scientific contracts. Use code for
new physics, new objectives, new variables, and new solver behavior. This keeps
the interface flexible without hiding the science.
