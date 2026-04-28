# Internal Lab Release Readiness Summary

## Bottom Line

For Rivera Lab internal use, the repo is close to releasable for a scoped
handoff. The supported scope should remain:

```text
single-mode phase-only Raman suppression with standard artifacts and neutral
phase export
```

The remaining blockers are practical handoff issues, not public open-source
metadata.

## What Changed

Added:

- `docs/guides/internal-lab-release-readiness.md`
- `agent-docs/internal-lab-release-readiness/CONTEXT.md`
- `agent-docs/internal-lab-release-readiness/SUMMARY.md`

Updated:

- `docs/README.md`
- `llms.txt`
- `agent-docs/README.md`
- `docs/guides/public-release-readiness.md`

## Internal Blockers That Matter

- Clean handoff commit: do not release from the current dirty, behind-remote
  tree.
- Keep `make lab-ready` and `make golden-smoke` green on the target user
  machine.
- Make visual inspection of the four standard images part of handoff.
- Have a new lab member follow `first-lab-user-walkthrough.md` without help.
- Keep local-vs-burst compute rules simple and explicit.
- Curate a small set of blessed examples instead of making users inspect the
  whole `results/` tree.
- Add/complete a concrete SLM calibration/replay path before implying hardware
  predictiveness.

## What No Longer Counts As A Blocker For This Scope

The following are not required for an internal Rivera Lab handoff:

- `CITATION.cff`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `codemeta.json`
- `.zenodo.json`
- public DOI/archive flow

They may still be useful later for a public release, but they should not drive
the internal handoff plan.
