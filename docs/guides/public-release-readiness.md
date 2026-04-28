# Public Release Readiness

[<- docs index](../README.md) | [lab readiness](./lab-readiness.md) | [supported workflows](./supported-workflows.md)

This note separates the repo's current lab-facing readiness from what still
needs to be true before a broad public research-software release.

For Rivera Lab internal handoff, use
[internal-lab-release-readiness.md](./internal-lab-release-readiness.md)
instead. Public metadata files and DOI/archive machinery are not blockers for
that narrower internal scope.

## Verdict

The repo is close to an honest lab handoff for the narrow supported workflow,
but it is not yet ready for a polished public lab release.

The supported surface is credible:

- single-mode, phase-only Raman suppression
- config-driven runs through `fiberlab` and `scripts/canonical/`
- dry-run planning before compute
- standard images, trust reports, manifests, and neutral CSV handoff
- explicit promotion gates for experimental multivariable, long-fiber, and MMF
  work

The public-release blockers are mostly packaging, metadata, automation, and
claim-boundary issues rather than the absence of a usable core workflow.

## Current Evidence

The following local checks passed on 2026-04-28 in the current synced workspace:

```bash
make test
make acceptance
./fiberlab validate
julia --project=. scripts/canonical/run_experiment.jl --validate-all
julia --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
julia --project=. scripts/canonical/lab_ready.jl --config research_engine_export_smoke
make test-python
```

The strongest smoke evidence is the supported `research_engine_export_smoke`
config. Existing smoke results under `results/raman/smoke` include multiple
lab-ready export runs with complete standard images, trust reports, and neutral
CSV handoff bundles.

Important caveat: the audit was run on a dirty working tree where `main` was
behind `origin/main` by 28 commits. Treat this as a readiness audit of the
current synced workspace, not of a clean release tag.

## External Release Bar

Public research software should satisfy the expectations captured by current
community standards:

- FAIR4RS: software should be findable, citable, richly described, accessible,
  interoperable where practical, and reusable under clear conditions.
  Source: https://www.nature.com/articles/s41597-022-01710-x
- JOSS review criteria: installation, functionality, tests, documentation,
  statement of need, community support paths, and reuse potential must be clear.
  Source: https://joss.readthedocs.io/en/latest/review_criteria.html
- The Turing Way: research materials should be findable and usable by all team
  members, with documentation, version control, testing, workflows, archiving,
  and data-management planning.
  Source: https://book.the-turing-way.org/project-design/pd-overview/pd-checklist
- CodeMeta and citation metadata: software metadata should support discovery,
  citation, and interoperability across platforms.
  Source: https://codemeta.github.io/
- GitHub/Zenodo release practice: public software releases should be archived
  and citable; Zenodo can archive GitHub releases and mint versioned DOIs.
  Sources: https://help.zenodo.org/docs/github/ and
  https://docs.github.com/articles/referencing-and-citing-content
- Julia package practice: `Project.toml` and `Manifest.toml` are the
  environment authority, and package compatibility bounds should be explicit.
  Sources: https://pkgdocs.julialang.org/v1/toml-files/ and
  https://pkgdocs.julialang.org/v1/compatibility/

## Release Blockers

Fix these before making the repository public as a polished lab release.

1. Clean git history and release state.

   The current workspace is heavily dirty, includes large file moves/deletions,
   and is behind `origin/main`. Public release should start from a clean branch
   or tag with intentional commits, no Syncthing conflict files, and no stale
   generated cache artifacts.

2. Add CI.

   There is no `.github/workflows/` CI configuration in the current checkout.
   A public user should see automated checks for at least:

   - Julia fast tier: `make test`
   - Python wrapper tests: `make test-python`
   - acceptance harness: `make acceptance`
   - docs/link sanity where practical

3. Add public project metadata.

   Missing top-level files for release:

   - `CITATION.cff`
   - `CONTRIBUTING.md`
   - `CODE_OF_CONDUCT.md`
   - `SECURITY.md` or a short support/security policy
   - `codemeta.json` or `.zenodo.json`
   - GitHub issue templates for bug reports, result-reproduction failures, and
     feature/research-surface requests

4. Resolve identity and versioning.

   `Project.toml` still names the Julia package `MultiModeNoise`, version
   `1.0.0-DEV`, and lists the inherited upstream author. The README describes a
   Rivera Lab Raman-suppression project with a Python package named
   `fiber-research-engine`. Before release, decide whether this is:

   - a forked/extended `MultiModeNoise` research application, or
   - a new package/application with attribution to upstream `MultiModeNoise.jl`.

   Then align package names, authors, version, citation, and README language.

5. Reconcile Julia version metadata.

   The docs and `.julia-version` target Julia `1.12.6`, while `Project.toml`
   has `julia = "1.9.3"` in `[compat]`. Decide the supported public range and
   test it. If the release is pinned to Julia 1.12, say so consistently.

6. Separate source from generated artifacts.

   `results/` is documented as generated output, but many `results/` text and
   JLD2 paths are tracked historically. Keep only deliberate fixtures,
   validation reports, and durable summaries in git. Move paper-ready figures
   into `docs/artifacts/` or release assets. Do not publish a repo where routine
   generated outputs look like source.

7. Remove sync/cache debris.

   The workspace currently contains a Syncthing conflict doc and Python
   `__pycache__` directories. They are ignored, but the release branch should be
   checked explicitly for conflict files, generated bytecode, local venvs, and
   machine-local state.

8. Make claim boundaries impossible to miss.

   The repo already documents that MMF, long-fiber, and broad multivariable work
   are not first-line lab surfaces. A public release should repeat that boundary
   in the README, release notes, and any paper/software abstract so users do not
   treat exploratory results as turnkey predictions.

## Researcher UX Upgrades

These are the highest-value improvements for external researchers.

- Provide a "5 minute no-compute tour":
  `./fiberlab capabilities`, `./fiberlab configs`, `./fiberlab plan
  research_engine_export_smoke`, and screenshots or linked example outputs.
- Provide a "first real run" recipe:
  `make install`, `make doctor`, `make golden-smoke`, then inspect the four
  images and `export_handoff/`.
- Add one notebook that is a reader, not a second implementation:
  load `opt_result.json`, display standard images, read the neutral CSV phase
  handoff, and compare smoke runs with `fiberlab index`.
- Add public example data:
  one tiny smoke artifact bundle, one supported baseline summary, and one
  intentionally caveated experimental example. Keep heavyweight artifacts as
  release assets or Zenodo deposits.
- Add a glossary:
  Raman band, phase mask, GDD, boundary penalty, trust report, standard image
  set, lab-ready, smoke, planning, validated.
- Add "what to cite":
  software DOI, upstream `MultiModeNoise.jl`, GNLSE/RK4IP sources, pulse-shaper
  sources, and the project paper or report.
- Add "how to compare to your lab":
  measured input pulse, shaper calibration, pixel replay, power calibration,
  output spectrometer dynamic range, and expected mismatch between simulated and
  measured dB.
- Add a decision tree:
  "I want to change power/length", "I want to change a fiber", "I want a new
  objective", "I want MMF", "I want to export to hardware".

## Suggested Release Sequence

1. Freeze the supported scope to single-mode phase-only plus smoke/export.
2. Reconcile branch state and remove sync/cache/generated debris.
3. Add metadata, citation, contribution, and support files.
4. Add CI for `make test`, `make acceptance`, and Python wrapper tests.
5. Run `make doctor`, `make golden-smoke`, and inspect the generated standard
   images.
6. Create a small release fixture or release asset set.
7. Tag `v0.1.0` as a public research preview, not `v1.0`.
8. Archive the tag through Zenodo and update the README citation section.

## Release Classification

Recommended public label today:

```text
Research preview: single-mode phase-only Raman suppression workflow is supported;
MMF, long-fiber, broad multivariable optimization, and hardware predictiveness
are experimental or planning-stage.
```

Do not label the current repo as a general Raman-suppression lab platform until
hardware replay/calibration, clean release metadata, CI, and artifact curation
are complete.
