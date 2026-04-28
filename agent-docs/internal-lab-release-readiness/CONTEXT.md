# Internal Lab Release Readiness Context

Date: 2026-04-28

This task re-scoped the prior public-release audit to Rivera Lab internal use.
The user explicitly does not care about public open-source metadata files such
as `CITATION.cff`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`,
`codemeta.json`, or `.zenodo.json`.

Internal release definition used here:

- another Rivera Lab member can install and run the supported workflow;
- supported and experimental surfaces are obvious;
- generated artifacts are inspectable and comparable;
- heavy compute boundaries are hard to violate accidentally;
- results are reproducible enough for lab continuity;
- hardware handoff caveats are clear.

Repo state:

- `main` behind `origin/main` by 28 commits.
- Working tree heavily dirty.
- Syncthing connected.

External sources checked for the re-scope:

- The Turing Way research-team checklist:
  https://book.the-turing-way.org/reproducible-research/rdm/rdm-checklist
- The Turing Way collaborative project documentation:
  https://book.the-turing-way.org/project-design/pd-overview/pd-overview-repro/
- The Turing Way team manuals:
  https://book.the-turing-way.org/collaboration/team-manual/
- Ten simple rules for usable scientific software:
  https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1005265
- Ten simple rules for workflow-ready software:
  https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009823
- FAIR4RS, interpreted only as internal reusability guidance:
  https://www.nature.com/articles/s41597-022-01710-x

Local materials reviewed:

- `docs/guides/lab-readiness.md`
- `docs/guides/first-lab-user-walkthrough.md`
- `docs/guides/configurable-experiments.md`
- existing release-readiness note from the prior public-scope audit

Human-facing output:

- `docs/guides/internal-lab-release-readiness.md`
