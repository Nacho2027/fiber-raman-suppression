# Configurable Front-Layer Proposal

This note proposes a thin, explicit front layer that can turn the repo into a
configurable research engine without hiding the physics behind a large
framework.

The design goal is not "make every idea configurable." It is:

- let a lab user choose a supported problem regime
- swap among approved optimization variables, objectives, and solver modes
- get the same canonical result/artifact behavior every time
- keep the interesting science visible in code, not buried in meta-machinery

## Short answer

The repo needs one stable layer above the existing physics and optimization
primitives:

```text
config file
    -> normalized experiment spec
    -> regime-specific problem builder
    -> control/objective/solver selection
    -> canonical artifact bundle writer
```

Today, the physics kernels mostly exist. What is missing is a stable contract
for how a run is described and assembled.

## Why this is the right layer

The current repo already has most of the hard low-level pieces:

- single-mode problem setup in `scripts/lib/common.jl`
- long-fiber setup in `scripts/research/longfiber/longfiber_setup.jl`
- multimode setup in `scripts/research/mmf/mmf_setup.jl`
- phase-only, amplitude, multivar, and MMF optimization paths
- canonical result payload + sidecar in `src/io/results.jl`
- mandatory standard image generation in `scripts/lib/standard_images.jl`
- TOML-backed canonical run configs in `configs/runs/` and `configs/sweeps/`

The repo does not yet have one coherent "instrument interface" that says:

- what problem am I solving?
- what variables are active?
- what scalar objective is authoritative?
- what solver family should be used?
- what artifacts are mandatory?

That is the abstraction gap to close.

## Minimum abstractions

The repo does not need a plugin framework. It needs five explicit contracts.

### 1. `ExperimentSpec`

This is the normalized run description loaded from TOML.

It should answer:

- which regime is requested
- which preset and physical parameters are requested
- which control variables are active
- which objective is authoritative
- which solver mode is requested
- which artifacts must be written

This should live in a thin script-layer parser first, not as a deep package
API.

### 2. `ProblemBundle`

This is the regime-independent object returned by a setup builder.

Minimum required fields:

- `regime`
- `uω0`
- `fiber`
- `sim`
- `band_mask`
- `Δf`
- `metadata`
- `capabilities`

`metadata` is for reproducibility and artifact writing.
`capabilities` is the key science-friendly part. It says what is valid for this
problem, for example:

- allowed variables: `[:phase]` or `[:phase, :amplitude, :energy]`
- allowed objectives: `[:raman_band]` or `[:mmf_sum, :mmf_fundamental, :mmf_worst_mode]`
- allowed solvers: `[:lbfgs, :multistart_lbfgs]`

This avoids mysterious runtime behavior. A config either matches the problem
capabilities or it fails validation clearly.

### 3. `ControlLayout`

This is the minimum abstraction needed for optimization variables.

It should define:

- which named variables are active
- how to pack/unpack them into one optimizer vector
- how those variables map to the shaped launch field
- how gradients pull back from field space into variable space

This is the natural unifying layer between:

- phase-only single-mode
- amplitude-only
- phase + amplitude + energy multivar
- shared-phase multimode
- later mode-weight optimization

The key design rule is:

- variable *selection* is config-driven
- variable *mathematics* is code-defined

Do not let config files define arbitrary symbolic transformations.

### 4. `ObjectiveSurface`

This is the authoritative scalar objective plus its regularization convention.

It should define:

- base physics objective kind
- active regularizers
- whether the optimized scalar is linear or log/dB
- machine-readable surface metadata for trust reports and saved artifacts

The repo already has a good precedent here in the existing
`*_cost_surface_spec(...)` helpers. The front layer should promote that pattern
instead of inventing another one.

### 5. `ArtifactPlan`

This is the run-output contract.

Minimum required outputs for a maintained optimization run:

- JLD2 payload
- JSON sidecar
- manifest update
- trust report
- standard image set whenever `phi_opt` exists

Optional outputs can be selected by config, but the default maintained bundle
should stay small and fixed.

## How the regimes fit into one front layer

Single-mode, multimode, long-fiber, and multiparameter cases should share the
same top-level config shape and diverge only at the problem-builder layer.

### Shared top-level shape

Every run should answer the same top-level questions:

1. `problem`
2. `controls`
3. `objective`
4. `solver`
5. `artifacts`

### Regime-specific builders

Each regime gets one explicit builder:

- `single_mode` -> wraps `setup_raman_problem(...)` or `setup_raman_problem_exact(...)`
- `long_fiber` -> wraps `setup_longfiber_problem(...)`
- `multimode` -> wraps `setup_mmf_raman_problem(...)`

These builders should all return the same `ProblemBundle` shape.

That gives one coherent front surface without pretending the regimes are the
same physics problem.

### Why this is better than one giant generic builder

- long-fiber has different grid policy and warm-start realities
- multimode has different cost variants and control constraints
- single-mode multivar is not the same as multimode shared-phase

Trying to erase those distinctions in one generic setup function would make the
 repo harder to trust. A common front schema with explicit regime builders is
 the correct middle ground.

## What should be config-driven vs code-defined

The practical answer to your question is: yes, a researcher should be able to
control the common choices without editing code.

That is the whole point of the front layer.

If the repo requires script surgery every time someone wants to change:

- the optimized variables
- the cost variant
- the regularizer weights
- the solver settings
- the output bundle

then it is not yet a usable research engine.

### Config-driven now

These are appropriate user-facing knobs:

- regime selection
- named fiber or MMF preset
- physical scalars like `L_fiber`, `P_cont`, `Nt`, `time_window`
- grid policy choices such as `auto_if_undersized` vs `exact`
- active optimization variables from an approved list
- objective family from an approved list
- regularizer weights
- solver family from an approved list
- run metadata and output location
- artifact bundle toggles

This includes exactly the kinds of changes a researcher should make routinely:

- switch from phase-only to phase + amplitude + energy in single-mode
- switch from Raman-band objective to an approved MMF cost variant
- choose exact-grid versus auto-sized setup
- request standard artifacts only versus standard + export bundle
- toggle gradient validation for a short verification run
- change warm-start policy, multistart count, or iteration budget

### Code-defined now

These should remain explicit code:

- the actual adjoint and forward physics
- control parameterization math
- objective formulas and pullbacks
- solver implementations
- standard artifact writers
- validation logic and capability checks
- continuation logic and warm-start interpolation details

### Not config-driven yet

These would be overengineering right now:

- arbitrary symbolic objective composition
- arbitrary user-defined variables loaded from config
- arbitrary multi-stage solver graphs
- unrestricted callback injection
- notebook-defined workflows treated as authoritative configs

## Stable contracts by concern

| Concern | Stable contract | Config selects | Code owns |
|-----|-----|-----|-----|
| Problem specification | `ExperimentSpec.problem -> ProblemBundle` | regime, preset, physical scalars, grid policy | actual builder and validation |
| Optimization variables | `ControlLayout` | active variables, approved parameterization profile, initialization policy | pack/unpack, field mapping, gradient pullback |
| Objective / cost | `ObjectiveSurface` | objective kind, regularizer weights, log/linear mode | physics cost, adjoint terminal condition, surface metadata |
| Solver selection | `SolverPlan` | `lbfgs`, `multistart_lbfgs`, later `continuation_lbfgs` | iteration logic, convergence behavior, typed result payload |
| Output generation | `ArtifactPlan` | bundle profile, export toggles, output root | JLD2/JSON manifest writing, trust report, standard images |

## Recommended API shape

The front-layer user API should stay extremely small.

### CLI

Supported surface:

```bash
julia --project=. -t auto scripts/canonical/run_experiment.jl configs/experiments/my_run.toml
```

Helpful flags later:

- `--dry-run` prints the normalized experiment plan and capability checks
- `--list-presets` prints approved regime/preset/objective/variable names

### Internal orchestration

The implementation can stay thin and explicit:

```julia
spec = load_experiment_spec(path)
problem = build_problem(spec.problem)
controls = build_control_layout(spec.controls, problem)
surface = build_objective_surface(spec.objective, problem, controls)
result = run_solver(spec.solver, problem, controls, surface)
write_artifacts(spec.artifacts, problem, surface, result)
```

That is enough abstraction. Anything more generic should wait until repeated
use proves it necessary.

## Recommended config shape

Use TOML, because the repo already does.

Recommended top-level sections:

- `id`
- `description`
- `maturity`
- `[problem]`
- `[controls]`
- `[objective]`
- `[solver]`
- `[artifacts]`

Recommended regime field:

- `problem.regime = "single_mode" | "long_fiber" | "multimode"`

Recommended control field:

- `controls.variables = ["phase"]`, `["phase", "amplitude"]`, or similar

Recommended maturity field:

- `supported`
- `experimental`

This is important. It lets the front layer expose research lanes honestly
without pretending they are equally trustworthy.

See `configs/experiments/research_engine_poc.toml` for a concrete sketch.

## Feasible now

These changes are realistic in the current repo without a giant rewrite.

### Phase 1: normalize the front layer for single-mode

- add a richer TOML schema on top of the existing `configs/runs/`
- build one `ExperimentSpec` loader
- introduce one `ProblemBundle` contract
- route canonical single-mode phase-only runs through it
- keep `run_optimization(...)` as the implementation backend

This is mostly refactoring of orchestration, not physics.

### Phase 2: fold single-mode multivar into the same front layer

- reuse the same single-mode `ProblemBundle`
- expose `controls.variables = ["phase", "amplitude", "energy"]`
- expose solver choice only where the capability matrix allows it
- keep the multivar path marked `experimental`

This gives immediate value without promising that multivar is already the
recommended workflow.

### Phase 3: add long-fiber as another builder

- `problem.regime = "long_fiber"`
- long-fiber-specific grid policy and warm-start fields
- same artifact bundle and result contract

This is a good fit because the long-fiber path is already a real workflow, just
not yet promoted.

### Phase 4: add multimode with explicit constraints

- `problem.regime = "multimode"`
- objective kinds limited to approved MMF variants
- controls initially limited to shared `phase`
- `mode_weights` optimization stays disabled until the science closes

This keeps the front layer coherent without claiming more than the current MMF
lane can support.

## Later, not now

These are good ideas, but they should wait.

- multi-stage continuation chains as a first-class config graph
- arbitrary weighted objective composition
- automatic promotion of research scripts into the front layer
- package-grade public API for all front-layer contracts
- generalized plugin discovery

If the repo reaches the point where many groups author many configs, then more
infrastructure may be justified. It is not justified yet.

## Researcher-facing control surface

This is the concrete set of controls that should move behind parameters/config
instead of code edits.

### Problem definition controls

- `regime`
- `preset`
- `L_fiber`
- `P_cont`
- `Nt`
- `time_window`
- `grid_policy`
- `pulse_fwhm`
- `pulse_rep_rate`
- `raman_threshold`
- regime-specific extras like `mode_weights` or `warm_start`

### Optimization controls

- `variables`
- `parameterization`
- `initialization`
- `objective.kind`
- regularizer weights
- `solver.kind`
- `max_iter`
- `multistart.n_starts`
- checkpoint/resume policy

### Output controls

- whether to write the canonical result bundle
- whether to write standard images
- whether to write a handoff/export bundle
- whether to write extra diagnostics
- output directory/profile name

### Verification controls

- whether to run gradient validation
- whether to run a Taylor check
- whether to run exact-grid replay
- whether to run export verification
- whether failure in those checks is blocking

The rule should be:

- common scientific choices are parameterized
- new scientific definitions are added in code once and then exposed as new
  named options

That keeps the system both configurable and inspectable.

## Support matrix for variable / objective selection

This is the practical near-term capability matrix the front layer should aim
for.

| Regime | Variables exposed by config | Objective choices exposed by config | Status |
|-----|-----|-----|-----|
| `single_mode` | `phase` | `raman_band` | supported now |
| `single_mode` | `phase`, `amplitude`, `energy` | `raman_band` | experimental but feasible now |
| `long_fiber` | `phase` | `raman_band` | experimental but feasible now |
| `multimode` | `phase` with `shared_across_modes` | `mmf_sum`, `mmf_fundamental`, `mmf_worst_mode` | experimental after MMF baseline stabilization |
| `multimode` | `phase`, `mode_weights` | MMF objectives | later, after science closure |

This is what "configurable" should mean here: a researcher chooses from this
matrix in a config, and the front layer validates the choice.

## Sequencing plan after the current refactor / research-closure work

1. Fix interface truthfulness first.
   The canonical wrappers, docs, and config loaders must agree on what one run
   does.

2. Introduce the front-layer contracts only for supported single-mode.
   Do not start by normalizing MMF or long-fiber.

3. Promote the config schema and a `--dry-run` validator.
   Validation is part of lab usability.

4. Move artifact writing behind one explicit bundle writer.
   The result contract is more important than abstract solver elegance.

5. Add single-mode multivar as experimental on the same front layer.
   This proves the design can swap variables without deep surgery.

6. Add long-fiber as experimental but coherent.
   This proves the design can support a second regime with different setup
   rules.

7. Add multimode only after the baseline decision remains stable.
   The front layer should not stabilize a moving target prematurely.

## Outputs should look like this

The outputs should be explicit enough for three different readers:

- the researcher running the simulation
- the PI reviewing the result
- the experimentalist loading the phase into hardware

### 1. Canonical research run bundle

This already mostly exists and should remain the default:

- `_result.jld2`
- `_result.json`
- copied `run_config.toml`
- trust report
- standard image set
- manifest row

This is the bundle for reproducibility and later analysis.

### 2. Inspection summary

The repo already has the right idea in `scripts/canonical/inspect_run.jl`.

The front layer should treat this as part of the normal workflow, not as an
extra utility. A user should be able to see quickly:

- which config ran
- whether it converged
- what the key dB numbers were
- whether trust checks passed
- whether the standard image set is complete

### 3. Experimental handoff bundle

The repo already has a first pass in `scripts/canonical/export_run.jl`, which
currently writes:

- `phase_profile.csv`
- `metadata.json`
- `README.md`
- copied `source_run_config.toml` when present

That is a good start, but for a real SLM-facing front layer the export contract
should be made more explicit.

Recommended handoff contents:

- simulation-axis wrapped phase
- simulation-axis unwrapped phase
- group delay
- axis metadata in wavelength and frequency
- provenance
- source config id
- source run id
- export profile id
- optional device-resampled phase map

## How this fits an SLM workflow

There are two distinct export levels.

### Level A: analysis-grade export

This is what the repo already supports reasonably well.

It gives the lab:

- the optimized phase on the simulation axis
- unwrapped phase for interpretation
- group delay for physics discussion
- metadata and provenance

That is enough for inspection, comparison, and preliminary handoff.

Current boundary: this export path is phase-only/canonical-run oriented. The
front layer should reject experimental multivariable SLM/export handoff until
the exporter can represent amplitude and energy controls explicitly.

### Level B: device-grade export

This should be the next explicit layer, and it should be profile-driven.

A device-grade export needs:

- target device profile
- target pixel count / canvas shape
- phase range convention
- wavelength of calibration
- LUT or wavefront-compensation attachment
- interpolation/resampling rule
- clipping/wrapping rule

The workflow should be:

```text
saved run
    -> choose export profile
    -> choose axis/cropping rule
    -> resample to device grid
    -> wrap to device phase convention
    -> apply LUT / correction map if available
    -> save device bundle + preview
```

The important point is that the device-grade export should be a separate,
explicit step. Do not blur "optimized continuous phase" and "what is actually
loaded into hardware."

### Why this is realistic

This matches what common vendor software expects.

From vendor documentation:

- HOLOEYE’s SDK can load float/int phase arrays directly and also accepts
  common image files.
- HOLOEYE’s software stack also supports wavefront-compensation overlays.
- Santec’s GUI software explicitly supports BMP and CSV pattern data, alongside
  an SDK.

So the repo should not commit to one vendor-specific binary format first.
Instead it should support:

- a neutral handoff bundle
- then vendor/device-specific export profiles layered on top

## Verification should be staged, not monolithic

The repo already has meaningful pieces of this:

- gradient validation in optimization code
- trust reports
- result-validation workflows
- inspect/export smoke tests

The front layer should make verification visible and configurable.

### Stage 1: config validation

Before running:

- does the regime exist?
- are the requested variables allowed for that regime?
- is the objective allowed for that regime?
- is the solver allowed for that variable/objective combination?
- are required fields present?

### Stage 2: numerical run validation

After running:

- convergence status
- energy drift
- boundary fraction
- optional gradient / Taylor check
- optional exact-grid replay or doubling check

### Stage 3: artifact validation

- result payload readable
- sidecar readable
- standard image set complete
- trust report present
- manifest updated

### Stage 4: export validation

For handoff/export:

- exported axis length matches expectation
- wrapped phase range is correct
- required metadata fields exist
- copied source config exists
- device profile constraints are satisfied

### Stage 5: experiment-facing validation

Before loading onto an SLM:

- simulation export was generated from the intended run
- export profile matches the actual device
- calibration / correction assets are attached
- preview image and phase histogram look sane
- the resampled export can be replayed in simulation if needed

That last point matters: the device-resampled phase should be simulatable. The
lab should be able to ask not only "what was the continuous optimum?" but also
"what happens after we quantize, crop, wrap, and resample it for the device?"

## If I were Prof. Rivera

From a PI perspective, the repo is valuable for years only if it behaves more
like a scientific instrument and less like one person's private workshop.

What I would want from it:

- a small catalog of approved recipes that students can run without guessing
- explicit labels for what is `supported` versus `experimental`
- the ability to rerun an old figure or baseline from its saved config years
  later
- enough provenance to trust that two runs are actually comparable
- outputs that are easy to inspect in a lab meeting without reading code
- a clean handoff path from simulation output to experiment-facing phase data
- guardrails that stop obviously invalid runs before they waste time or money

That pushes the design toward quality-of-life features, not just abstraction.

### Quality-of-life features worth prioritizing

These are the highest-value lab-operations features for the first front-layer
build.

1. `--dry-run` for every experiment config.
   Print the normalized problem, active variables, objective, solver, expected
   artifacts, and whether the config is supported or experimental.

2. Config copy and provenance in every run directory.
   Keep the exact TOML, git SHA, schema version, timestamp, and normalized
   surface metadata together with the results.

3. Searchable manifest fields for the things humans actually care about.
   Add or preserve fields like `regime`, `controls`, `objective`, `solver`,
   `maturity`, and `config_id`, not just `L` and `P`.

4. One fast "what happened?" summary path.
   A user should be able to point at a run directory and get:
   config, convergence, trust warnings, key dB numbers, and the first plots to
   open.

5. Resume/checkpoint as a first-class policy for expensive regimes.
   This matters most for long-fiber and future heavy MMF work.

6. Artifact bundles that are presentation-ready by default.
   The standard images already move in this direction. Keep pushing it.

7. Export bundles aimed at experiment handoff, not just internal Julia reuse.
   If the repo can write a clean phase/grid/provenance package, it becomes
   useful beyond the simulation author.

8. Honest failure states.
   Boundary corruption, bad windows, unsupported variable/regime combinations,
   and missing artifacts should fail loudly and specifically.

9. Stable recipe IDs for canonical and semi-canonical studies.
   People remember "the SMF-28 2 m 0.2 W baseline" better than a script path.

10. A small compare/report surface.
    A PI often wants "compare these three runs" more than "run a new exotic
    solver." Make that easy.

### Questions the front layer should answer explicitly

These are the questions that should be encoded in docs, config validation, and
CLI behavior rather than left implicit:

- Which variables can a researcher choose directly?
- Which cost functions can a researcher choose directly?
- Which combinations are supported versus experimental?
- What files are the authoritative outputs of a run?
- What exact export bundle should someone use for hardware handoff?
- What checks must pass before a run is considered trustworthy?
- Can the exported hardware profile be replayed in simulation?

### What makes it durable over years

If the repo is meant to stay useful beyond the original author, durability
matters more than cleverness.

The front layer should optimize for:

- versioned config and artifact schemas
- backward-readable historical runs when practical
- narrow supported surfaces with clear promotion rules
- old-result reproducibility from saved configs
- easy migration when a supported schema changes
- human-readable docs that point to authoritative entry points

In practice, that means the repo should preserve a chain like:

```text
paper figure or meeting result
    -> run directory
    -> config file
    -> normalized spec
    -> reproducible artifact bundle
```

That is the kind of infrastructure a PI can rely on across students and over
multiple project phases.

## Concrete file-shape recommendation

Keep the first implementation small:

- `scripts/lib/experiment_spec.jl`
- `scripts/lib/problem_builders.jl`
- `scripts/lib/control_layouts.jl`
- `scripts/lib/objective_registry.jl`
- `scripts/lib/artifact_bundle.jl`
- `scripts/workflows/run_experiment.jl`
- `scripts/canonical/run_experiment.jl`

Those names are intentionally boring. This should read like an instrument
control stack, not like a framework.

## Bottom line

The repo should become configurable by making the run description explicit and
the regime builders interchangeable, not by abstracting away the physics.

The minimum viable front layer is:

- one normalized experiment spec
- one common problem bundle
- one control-layout contract
- one objective-surface contract
- one artifact-bundle contract

That is enough to let researchers swap variables, objectives, presets, and
regimes without editing deep internals, while keeping the scientific behavior
inspectable in the code paths that already matter.
