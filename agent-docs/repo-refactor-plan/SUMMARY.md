# Repo Refactor Summary

## Completed Surface Cleanup

- Root-level presentation and report artifacts were moved under `docs/artifacts/` and `docs/reports/`.
- LaTeX build byproducts and Syncthing conflict files were removed from the public root/docs surface.
- `scripts/` now has one root file only: `scripts/README.md`.
- Canonical script entry points live in `scripts/canonical/`.
- Reusable include-driven script libraries live in `scripts/lib/`.
- Stable operational workflows live in `scripts/workflows/`.
- Active research drivers live under named subtrees in `scripts/research/`.
- Historical copies live under `scripts/archive/`.
- Active phase-family script filenames no longer use `phaseNN_` prefixes.

## Guardrails Added

- `test/test_repo_structure.jl` now enforces the intended `scripts/` surface.
- The fast tier includes the repo-structure test so loose root scripts and active `phaseNN_*.jl` filenames fail CI/local fast checks.
- Public docs now point at the reorganized canonical/lib/workflow/research paths instead of old top-level script paths.

## Preserved Functionality

- Canonical optimization, sweep, report generation, validation, and standard-image regeneration remain available through `scripts/canonical/`.
- Script-library compatibility is preserved for existing include-based tests and research drivers through `scripts/lib/`.
- Phase 13, Phase 31, trust-region, MMF, long-fiber, cost-audit, recovery, and benchmark research functionality remains available under `scripts/research/`.
- Archive copies remain available under `scripts/archive/` for historical reproducibility, but they are not part of the active public interface.

## Remaining Non-Destructive Boundary

The biggest remaining public-repo cleanliness issue is tracked artifact policy:

- `data/` contains small source datasets and plotting helpers.
- `fibers/` contains tracked generated/cache-like `.npz` fiber files.
- `notebooks/` contains exploratory notebooks.
- `results/` contains a mix of durable summaries, trust reports, JLD2 run outputs, telemetry, and generated caches.

These should not be deleted casually. The next cleanup should classify each tracked artifact as one of:

- durable source input
- lightweight reproducibility fixture
- human-facing summary/report
- generated runtime output that should move to release artifacts or be removed from git

Until that classification is explicit, the safe boundary is to document the policy and avoid adding more generated artifacts to git.
