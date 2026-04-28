# Public Release Readiness Context

Date: 2026-04-28

This audit reviewed the current synced workspace for readiness to release the
fiber Raman suppression repository publicly to researchers outside the lab.

Repo state at audit start:

- Branch: `main`
- Upstream status: behind `origin/main` by 28 commits
- Working tree: heavily dirty, with large source/docs reorganization already in
  progress
- Syncthing: connected

External standards checked:

- FAIR4RS research software principles:
  https://www.nature.com/articles/s41597-022-01710-x
- JOSS review criteria:
  https://joss.readthedocs.io/en/latest/review_criteria.html
- The Turing Way reproducible research/project design guidance:
  https://book.the-turing-way.org/project-design/pd-overview/pd-checklist
- CodeMeta metadata vocabulary:
  https://codemeta.github.io/
- GitHub/Zenodo citation and release archiving:
  https://help.zenodo.org/docs/github/
  https://docs.github.com/articles/referencing-and-citing-content
- Julia Pkg `Project.toml`/`Manifest.toml` and compatibility docs:
  https://pkgdocs.julialang.org/v1/toml-files/
  https://pkgdocs.julialang.org/v1/compatibility/

Local docs and code reviewed:

- `README.md`
- `llms.txt`
- `Project.toml`
- `pyproject.toml`
- `Makefile`
- `docs/README.md`
- `docs/guides/supported-workflows.md`
- `docs/guides/installation.md`
- `docs/guides/configurable-experiments.md`
- `docs/guides/lab-readiness.md`
- `docs/guides/first-lab-user-walkthrough.md`
- `docs/architecture/repo-navigation.md`
- `docs/architecture/research-engine-ux.md`
- `docs/reports/lab-physics-validity-2026-04-28/REPORT.md`
- `scripts/canonical/`, `scripts/lib/`, `python/fiber_research_engine/`,
  `configs/`, and `test/`

Key interpretation:

- The narrow supported workflow is much stronger than a normal academic code
  dump.
- The public-release blockers are mostly around clean release state, metadata,
  CI, identity/versioning, and curation.
- The correct public label is research preview, not mature lab platform.
