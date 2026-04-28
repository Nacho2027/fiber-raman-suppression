# Internal Lab Release Readiness

[<- docs index](../README.md) | [lab readiness](./lab-readiness.md) | [first lab user](./first-lab-user-walkthrough.md)

This is the release-readiness view for Rivera Lab internal use. It deliberately
does not require public open-source ceremony such as `CITATION.cff`,
`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `codemeta.json`, or
Zenodo metadata.

The bar here is practical:

- a new lab member can install and run the supported workflow;
- the workflow fails closed when they pick unsupported physics or unsafe config
  values;
- results are easy to inspect, compare, and hand off;
- heavy compute does not accidentally run on the wrong machine;
- the repo makes it hard to overclaim exploratory results.

## Verdict

The repo is close to internally releasable for Rivera Lab if the release is
scoped to the supported single-mode phase-only workflow.

It should not be presented internally as a general Raman-suppression platform
where every lane is equally usable. The right internal framing is:

```text
Supported lab workflow: single-mode phase-only Raman suppression with standard
artifacts and neutral phase export.

Research/planning workflows: MMF, long-fiber, broad multivariable optimization,
new objectives, and new optimized controls.
```

For internal use, the remaining high-value work is not public metadata. It is
runbook polish, artifact curation, first-user testing, and making the supported
path boringly repeatable.

## What Was Checked

Local verification from the current synced workspace:

```bash
syncthing cli show connections
julia --project=. scripts/canonical/run_experiment.jl --validate-all
julia --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
make test
make install-python
make test-python
make acceptance
./fiberlab validate
./fiberlab capabilities
julia --project=. scripts/canonical/lab_ready.jl --config research_engine_export_smoke
julia --project=. scripts/canonical/index_results.jl --compare --top 10 results/raman/smoke
```

Results:

- Syncthing was connected.
- Experiment config validation passed for 10 configs.
- Experiment sweep validation passed for 1 sweep.
- Fast Julia test tier passed.
- Python wrapper tests passed after creating the local `.venv`.
- The research-engine acceptance harness passed.
- The supported export smoke config reported `PASS`.
- Existing smoke outputs included multiple lab-ready runs with standard images,
  trust checks, and export handoff bundles.

Audit caveat: the workspace was heavily dirty and `main` was behind
`origin/main` by 28 commits. This is an audit of the current synced workspace,
not a clean release tag.

## Internal Standards Used

The external material that matters for internal lab use is about reproducible
team workflows, not public discoverability.

- The Turing Way research-team checklist says every team member should be able
  to find and use the project's data, code, documentation, and related research
  materials. It also emphasizes documenting procedures and following group data
  management practices.
  Source: https://book.the-turing-way.org/reproducible-research/rdm/rdm-checklist
- The Turing Way collaborative-project guidance warns that practices designed
  for one person often do not work for a team, and recommends clear project
  documentation, contribution/review/support expectations, and accessible
  materials.
  Source: https://book.the-turing-way.org/project-design/pd-overview/pd-overview-repro/
- Turing Way team-manual guidance is relevant because this repo has lab-specific
  compute, sync, and handoff rules that need to be explicit for new members.
  Source: https://book.the-turing-way.org/collaboration/team-manual/
- Scientific-software usability guidance recommends exposing a small set of
  understandable default parameters, putting advanced parameters behind clearer
  expert paths, and choosing conservative defaults.
  Source: https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1005265
- Workflow-ready software guidance recommends outputs that are both human
  understandable, such as reports/plots, and machine-readable, such as JSON.
  Source: https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009823
- FAIR4RS still matters internally only in the reusable-workflow sense:
  software and metadata should make reuse possible. The DOI/discovery pieces are
  optional for this internal scope.
  Source: https://www.nature.com/articles/s41597-022-01710-x

## What The Repo Already Does Well

1. It has a real supported front door.

   `./fiberlab` and `scripts/canonical/` give lab users a stable path instead
   of forcing them into historical scripts or notebooks.

2. It fails closed for unsupported work.

   Experimental configs show promotion stages and blockers. MMF and long-fiber
   are visible but blocked from casual local execution. This is exactly what an
   internal lab release needs.

3. It has the right artifact contract.

   Standard images, trust reports, JSON/JLD2 outputs, run manifests, result
   indexing, and neutral CSV export are the right mix of human-readable and
   machine-readable outputs.

4. It has unusually strong config protection.

   The fast tier mutates configs and sweeps adversarially, then checks that
   unsafe or unsupported changes are rejected before compute.

5. It is honest about physics scope.

   The docs clearly state that MMF, long-fiber, and broad multivariable
   optimization are not first-line lab workflows.

6. It has a first-user path.

   `first-lab-user-walkthrough.md`, `lab-readiness.md`, and
   `configurable-experiments.md` already describe the normal user journey.

## Internal Release Blockers

These are the blockers that matter for Rivera Lab use.

1. Clean handoff state.

   Do not hand this to a new lab user from the current dirty tree. The active
   workspace has many moved/deleted files, new directories, generated outputs,
   and a branch behind remote. Internal release should happen from a known
   commit with a short label such as `internal-handoff-2026-04-28`.

2. One-command health check must stay green.

   `make lab-ready` and `make golden-smoke` are the right internal gates. Before
   handoff, run both on the actual machine the lab member will use. Keep the
   terminal output or a short handoff note with the date, machine, commit, and
   generated run directory.

3. Visual inspection must be part of the handoff.

   The repo already says PNG existence is not enough. For internal release, this
   should be operational: the first lab user should open the four standard
   images from `make golden-smoke` while being shown what sane axes, finite
   curves, and complete panels look like.

4. First-user walkthrough needs a real trial by someone other than the author.

   A lab member should follow `first-lab-user-walkthrough.md` from a fresh clone
   or clean checkout. Any place they ask "what does this mean?" is a doc bug.

5. Compute boundaries need one laminated path.

   The repo has good burst rules, but internal users need a single "local vs
   burst" decision path:

   - local: install, validate, smoke, inspect, supported short run;
   - burst or other workstation: heavy sweeps, MMF, long-fiber, slow/full tests;
   - never: hidden heavy compute from casual local commands.

6. Results curation needs tightening.

   For internal use, it is fine to keep more results than a public repo would,
   but the lab still needs a small set of blessed examples:

   - latest valid golden smoke;
   - supported `research_engine_poc` baseline;
   - one positive staged `amp_on_phase` example labeled experimental;
   - one MMF example labeled simulation candidate, not lab-ready;
   - one long-fiber milestone labeled non-turnkey.

7. Hardware handoff still needs a calibration path.

   Neutral CSV export is useful, but internal users need to understand that it
   is not an SLM-ready guarantee. The next lab-facing step is a concrete replay
   and calibration checklist for the actual Rivera Lab shaper.

8. The docs are still dense.

   The repo has enough documentation, maybe too much. Internal release should
   make the first path obvious:

   ```text
   README -> first-lab-user-walkthrough -> lab-readiness -> configurable-experiments
   ```

   Research reports and planning history should not be the first thing a new
   lab user reads.

## What Researchers Will Want To Do

A Rivera Lab researcher will most likely arrive with one of these intentions.

| Intent | Current UX | Readiness |
|---|---|---|
| "Can I run the baseline?" | `make install`, `make lab-ready`, `make golden-smoke`, `./fiberlab run research_engine_poc` | Strong |
| "Can I change power or length?" | copy/edit config, `./fiberlab plan`, `./fiberlab validate` | Strong if they stay in supported regime |
| "Can I compare runs?" | `./fiberlab explore compare` / `index_results.jl` | Good |
| "Can I send a phase mask to hardware?" | neutral CSV export plus generic SLM replay | Useful but not enough without device calibration |
| "Can I run MMF?" | visible planning config and compute plan | Not lab-ready; correctly gated |
| "Can I run long fiber?" | visible planning config and compute plan | Not lab-ready; correctly gated |
| "Can I invent a new objective?" | scaffold planning-only extension | Good architecture; not turnkey |
| "Can I use notebooks?" | Python wrapper and template notebook | Good if notebooks remain readers/orchestrators |

## Internal Release Sequence

1. Pick a clean handoff commit.
2. Run `make lab-ready`.
3. Run `make golden-smoke`.
4. Visually inspect the generated four standard images.
5. Run:

   ```bash
   ./fiberlab capabilities
   ./fiberlab configs
   ./fiberlab plan research_engine_export_smoke
   ./fiberlab check config research_engine_poc
   ./fiberlab explore compare results/raman/smoke --top 10
   ```

6. Write a short internal handoff note with:

   - commit SHA;
   - machine;
   - Julia/Python versions;
   - commands run;
   - smoke run directory;
   - visual inspection result;
   - known unsupported lanes.

7. Have one lab member repeat the walkthrough without help.
8. Fix every ambiguity they hit before calling the internal release done.

## Bottom Line

For internal Rivera Lab use, this repo is already in good shape for a scoped
handoff. The critical next step is not public metadata. It is a clean handoff
commit plus a first-user dry run that proves the supported path works for
someone who did not build the system.

Recommended internal status:

```text
Internally releasable after clean handoff commit, green lab-ready/golden-smoke
run, visual image inspection, and one independent first-user walkthrough.
```
