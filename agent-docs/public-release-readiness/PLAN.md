# Public Release Readiness Plan

## Completed In This Audit

- Checked required repo state and Syncthing health.
- Read active agent context before assessing methodology or infrastructure.
- Reviewed README, docs map, supported workflow docs, installation docs,
  research-engine UX docs, lab-readiness docs, and physics-validity report.
- Reviewed canonical config/CLI/test layout.
- Researched external research-software release expectations.
- Ran local validation and fast test gates.
- Added `docs/guides/public-release-readiness.md`.

## Recommended Next Work

1. Reconcile branch state.

   Fetch/rebase or otherwise decide how the current synced workspace should
   become a clean public-release branch. Do this before adding more public
   metadata so the release files land on top of a stable tree.

2. Add public metadata files.

   Minimum:

   - `CITATION.cff`
   - `CONTRIBUTING.md`
   - `CODE_OF_CONDUCT.md`
   - `SECURITY.md`
   - `codemeta.json` or `.zenodo.json`
   - GitHub issue templates

3. Add CI.

   Minimum GitHub Actions matrix:

   - Julia target version from `.julia-version`
   - `make test`
   - `make acceptance`
   - `make test-python`

4. Resolve package identity.

   Decide whether the public Julia package remains `MultiModeNoise` or whether
   the release is an application/research repo built on top of the upstream
   package. Align `Project.toml`, README, citation, and release notes.

5. Curate artifacts.

   Move durable example outputs into docs or release assets. Keep routine
   generated `results/` out of source commits.

6. Add the public researcher tour.

   Recommended docs:

   - five-minute no-compute tour
   - first real smoke run
   - notebook reader example
   - glossary
   - how to compare simulations to a real lab

7. Cut a preview release.

   Tag as `v0.1.0` or similar, archive through Zenodo, and update citation docs.
