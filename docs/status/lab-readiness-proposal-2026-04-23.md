# Lab-Readiness Proposal (2026-04-23)

This note defines what "lab-ready" should mean for this repository, assuming
the highest-value science lanes should still be finished before the lab depends
on the repo as shared instrument software.

The short version is:

- the repo should become a **trusted narrow instrument** before it becomes a
  **broad scientific platform**
- the first supported lab surface should be **single-mode, phase-only Raman
  suppression** with reproducible run/save/inspect/export workflows
- multimode, long-fiber, trust-region continuation work, and multivariable
  optimization should remain explicitly experimental until their science and
  operations both settle

## Current verdict

The repo is **lab-ready for a narrow single-mode phase-only baseline workflow**,
not yet for the broader research platform.

It already has several strong pieces:

- a real docs tree
- canonical script wrappers
- a documented JLD2 + JSON output schema
- result manifests
- regression tiers
- strong conventions around standard image generation and heavy compute
- approved TOML run configs
- maintained inspect and export commands
- a trust-clean SMF-28 baseline run

The narrow baseline that can be treated as lab-facing is:

- `configs/runs/smf28_L2m_P0p2W.toml`
- `scripts/canonical/optimize_raman.jl smf28_L2m_P0p2W`
- `scripts/canonical/inspect_run.jl <run_dir>`
- `scripts/canonical/export_run.jl <run_dir>`

The current acceptance bar for that baseline is:

- optimizer `converged=true`
- trust report overall `PASS`
- determinism, boundary, photon-number conservation, gradient validation, and
  cost-surface checks all `PASS`
- complete and visually inspected standard image set
- generated export handoff bundle

The HNLF config is also an approved comparison/reference run, but it should be
read as a trust-clean reference rather than as the primary baseline until its
optimizer convergence behavior is settled.

The repo still has broader rollout-critical gaps:

- some high-value research lanes are still open
- the public programmatic API is still thin
- most run definitions are still hard-coded in scripts rather than expressed as
  stable config
- notebooks are exploratory only

That means the next move is not a giant productization pass. The right move is
to keep the supported surface narrow, harden the sweep/multi-param path next,
and keep moving research lanes clearly outside the supported lab contract until
they close.

## 1. Actual lab-facing use cases

The repo does not need to serve every research idea on day one. It needs to
serve the use cases a lab will actually trust and repeat.

The first real lab-facing use cases should be:

1. Run one approved canonical single-mode optimization from a known starting
   config and get a reproducible result bundle.
2. Re-run a small catalog of approved single-mode configs for comparison to old
   baselines or recent runs.
3. Run an approved sweep on burst, recover the results cleanly, and regenerate
   summary reports without recomputing.
4. Inspect a saved run after the fact without touching the optimizer.
5. Export one approved optimized phase profile and the associated metadata in a
   form that an experimentalist can hand off to pulse-shaping or analysis code.
6. Use a notebook to explore or present saved results, not to define the
   authoritative compute path.

Secondary use cases that should exist later, but not define the first rollout:

- adding a new approved fiber preset
- comparing multiple saved runs programmatically
- regenerating plots and export bundles from archived runs
- limited perturbation or robustness checks around an approved baseline

Research use cases that should stay outside the initial lab contract:

- multimode baseline discovery
- long-fiber platform claims beyond the currently supported exploratory envelope
- multivariable optimization as a standard control surface
- trust-region / Newton / preconditioner experimentation
- arbitrary notebook-authored optimization workflows

## 2. Infrastructure that should exist before lab rollout

Before the lab depends on this repo, the repo should have a small but honest
product layer around the canonical workflow.

### A. One truthful supported entry surface

The lab should have one obvious supported surface:

- one canonical single-run command
- one canonical sweep command
- one canonical inspect/validate path
- one canonical export/handoff path

Those commands must match the docs exactly. If `README.md` says "single
canonical optimization," the command cannot secretly run a heavy suite.

### B. Approved run catalog, not free-form script editing

The first lab users should not edit constants inside large scripts to run a new
approved case. The repo should grow a small approved-run catalog, likely via
TOML configs or typed specs, with examples like:

- `configs/runs/smf28_L2m_P0p2W.toml`
- `configs/runs/hnlf_L0p5m_P0p01W.toml`
- `configs/sweeps/smf28_default.toml`

The point is not maximal flexibility. The point is stable, diffable,
reviewable, reproducible run definitions.

### C. Stable run bundle contract

This is already partly in place and should be treated as mandatory:

- JLD2 payload
- JSON sidecar
- standard image set
- manifest entry
- trust/validation report

For lab use, every approved run should produce the same bundle shape every
time.

### D. Result inspection path that does not require code reading

Lab users should be able to answer:

- what run was this?
- did it converge?
- what physics config produced it?
- what plots should I open first?
- is it trustworthy enough to compare?

That means one maintained inspection flow should exist, either:

- a small Julia CLI that summarizes a run directory, or
- a maintained notebook/template that loads `_result.json` / `_result.jld2`

### E. Experimental handoff format

The lab needs an explicit export boundary between simulation output and
experiment-facing assets.

The first supported export bundle should likely include:

- sampled wavelength or frequency grid
- `phi_opt`
- optional unwrapped phase / group delay
- run metadata
- provenance (`git_sha`, config id, timestamp, schema version)
- a short README-like text summary

The export format does not need to solve every instrument integration problem.
It does need to make the simulation-to-experiment handoff explicit and
repeatable.

### F. CI and regression posture for the supported surface

The repo already has test tiers. Before rollout, the supported surface should
have regression coverage for:

- config loading / normalization
- output bundle completeness
- result load round trip
- canonical wrapper behavior
- export schema

This is less about numerics depth than about preventing interface drift.

## 3. What should wait until after unfinished research lanes are closed out

Several attractive things should not be forced into the first lab-ready layer.

### Multimode

Multimode now has a more credible baseline recommendation, but it is still a
research lane. It should not become a first-user lab workflow until:

- the meaningful baseline regime is re-run and accepted as durable
- the cost choice is settled operationally
- the trust checks and result bundle are stable
- the workflow is documented as supported rather than exploratory

### Long-fiber

The repo has a real long-fiber path, but the current maintainer assessment is
still "supported single-mode exploratory path," not "group-grade platform."
Long-fiber should remain a promoted-later surface until:

- one stable API exists
- one supported-range statement exists
- 50 m / 100 m regression checks exist
- the docs say clearly what is supported versus experimental

### Multivariable optimization

Yes, it matters for the long-term roadmap, but it should remain research-only
for initial lab rollout.

Current status in the repo is:

- the joint `:phase + :amplitude + :energy` machinery exists
- smoke tests and artifact validation exist
- the canonical demo still underperforms phase-only on the reference case

So the right product decision is:

- keep multivar visible as an experimental lane
- do not make it part of the standard lab workflow
- only promote it after it wins a benchmark that matters and its convergence
  behavior is stable enough to support non-author users

### Continuation / trust-region / acceleration surfaces

These are scientifically important and should continue, but they should stay
behind the research boundary until the project closes the main questions around
path quality, bounded transfer, and whether any acceleration or second-order
surface earns its complexity.

## 4. How refactoring and lab-readiness sequencing should interact

Refactoring should support the rollout boundary, not race ahead of it.

The rule should be:

- refactor aggressively enough to make the supported surface clean
- avoid broad abstraction work on still-moving research lanes

That implies a three-part sequencing rule.

### First: boundary hardening

Do the refactors that make the supported surface honest:

- separate canonical single-run orchestration from research suites
- move approved run definitions into a stable config/spec layer
- ensure result/export/inspection paths are small and explicit

### Second: research isolation

Keep the still-moving science lanes local:

- multimode stays in `scripts/research/mmf/`
- long-fiber stays in `scripts/research/longfiber/`
- multivar stays in `scripts/research/multivar/`
- trust-region work stays in `scripts/research/trust_region/`

Promote only the parts that have become genuinely reusable and stable.

### Third: promotion after closure

Once a research lane closes scientifically, then promote:

- reusable setup and config pieces into `src/` or `scripts/lib/`
- one thin canonical wrapper
- one user guide
- one regression slice

This keeps the repo from over-abstracting unstable science.

## 5. Recommended user-facing workflow

The workflow should be product-shaped, not author-shaped.

### Notebooks

Recommended role:

- result inspection
- comparison
- presentation
- lightweight post hoc analysis

Not recommended role:

- primary optimization driver
- canonical sweep launcher
- source of truth for run configuration

The maintained notebook layer should eventually be a small set of templates:

1. `01_inspect_single_run.ipynb`
2. `02_compare_runs.ipynb`
3. `03_export_handoff_check.ipynb`

Those notebooks should load saved artifacts. They should not duplicate solver
setup logic.

### Canonical optimization runs

Recommended workflow:

1. choose an approved run config
2. run one canonical command
3. save a standard run bundle
4. inspect the standard image set and trust report
5. optionally export the phase profile for experiment

The initial user should not decide solver knobs by editing a large script.

### Sweeps

Recommended workflow:

1. choose an approved sweep config
2. stage to burst through the documented wrapper path
3. run under heavy-job control
4. pull results back
5. regenerate reports from saved artifacts
6. inspect ranked summary plus representative best / typical / worst cases

The sweep surface should be treated as an operational workflow, not as a casual
"maybe this will fit on my laptop" path.

### Result inspection

Recommended workflow:

Open artifacts in this order:

1. `_result.json`
2. trust / validation markdown
3. standard image set
4. optional notebook or CLI comparison tools

This should work without reading the implementation.

### Export / experimental handoff

Recommended workflow:

1. select one approved run directory
2. run one export command
3. produce one handoff folder with arrays, metadata, and provenance
4. archive that handoff bundle with a run id and config id

The export path should be explicit about interpolation or resampling if the lab
instrument uses a different grid than the saved simulation artifact.

## Sequencing plan

### What must happen before lab rollout

1. Declare the first supported surface narrowly: canonical single-mode,
   phase-only Raman suppression.
2. Fix the canonical-entrypoint truth gap so the documented single-run command
   actually performs one canonical run.
3. Add an approved config/spec layer for canonical runs and sweeps.
4. Add one maintained inspection flow for saved runs.
5. Add one maintained export/handoff flow.
6. Add regression tests for the user-facing surface.
7. Write one short "supported vs experimental" doc that names the boundaries
   directly.

### What can be built in parallel

These can progress without waiting for every science lane to close:

1. config-file plumbing for the canonical single-mode path
2. export bundle schema and writer
3. run-inspection notebook or CLI
4. manifest/result catalog improvements
5. wrapper cleanup that aligns docs with actual behavior
6. docs that explain the supported surface and compute discipline

### What should happen after research closure

Only after the relevant science lane closes should the repo promote:

1. multimode into a supported user workflow
2. long-fiber into a generally supported group-facing workflow
3. multivariable optimization into a standard user option
4. continuation or trust-region methods into default-facing controls
5. a broader programmatic API beyond the narrow supported run/export/load path

## Recommended front-layer API

The front layer should be small and boring.

For the first lab-ready version, the repo should expose:

- one CLI/config entry for `run`
- one CLI/config entry for `sweep`
- one CLI entry for `inspect`
- one CLI entry for `export`
- one load API for saved runs

Programmatic Julia API:

- keep `load_run` / `save_run`
- add a thin typed run-spec layer later
- do not expose the entire research orchestration stack as public API

Config system:

- prefer TOML
- keep schemas small
- validate required fields strictly
- version the config schema if needed

Examples:

- one canonical single-run example
- one approved HNLF example
- one approved sweep example
- one export/handoff example

## Minimum viable lab-ready state

This repo is minimally lab-ready when all of the following are true:

1. A new lab user can install the repo, run one approved canonical single-mode
   optimization, and get the documented run bundle without editing source.
2. The documented canonical commands match actual behavior.
3. Saved runs have a stable bundle: payload, sidecar, manifest entry, standard
   image set, and trust report.
4. There is one maintained inspection path for saved results.
5. There is one maintained export path for experimental handoff.
6. The docs clearly distinguish supported workflows from experimental ones.
7. The supported surface has regression coverage.
8. Multimode, long-fiber, multivar, and advanced optimizer research are still
   usable, but explicitly marked as outside the first lab contract unless and
   until they are promoted.

If those conditions are met, the repo is not "finished," but it is credible as
shared lab infrastructure for a narrow class of work.

## Maintainer recommendation

Treat the next transition as:

- **Phase A:** finish the highest-value science lanes
- **Phase B:** harden the single-mode canonical lab surface
- **Phase C:** only then promote additional research lanes one by one

That sequencing is slower than a broad polish pass, but it is much more likely
to produce a tool the lab will actually trust.
