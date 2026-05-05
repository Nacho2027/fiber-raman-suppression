# Scripts

Scripts are compatibility and operations tooling. The user-facing FiberLab
API lives in `src/fiberlab/`.

Run maintained commands from `scripts/canonical/`. Shared implementation lives
in `scripts/lib/` for now and should move behind the FiberLab API as it
stabilizes.

| Path | Purpose |
|---|---|
| `canonical/` | maintained compatibility wrappers |
| `lib/` | transitional implementation used by scripts |
| `workflows/` | compatibility implementation called by wrappers |
| `burst/` | burst-machine helpers |
| `ops/` | local operations helpers |

Old phase, analysis, validation, report-generation, and dedicated research
drivers were moved out of the active repo on 2026-05-04.

Do not add a new top-level script for one experiment. Add or update a checked
TOML config, FiberLab API object, and a thin canonical wrapper only when there
is a maintained command surface.
