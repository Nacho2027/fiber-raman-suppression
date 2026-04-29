# Project Operating Manual

This file is the long-form operating reference. `AGENTS.md` is the short
contract. If the two ever disagree, use `AGENTS.md` first and fix this file.

## Work Rules

- Keep agent notes in `agent-docs/<topic>/`.
- Keep polished user docs, reports, and runbooks in `docs/`.
- Do not add new active work notes to `docs/planning-history/`; it is an
  archive.
- Read `agent-docs/current-agent-context/` before substantial numerics,
  methodology, or infrastructure work.
- Research before editing: grep the repo, read called code, and check external
  docs when behavior depends on a tool or library.
- Add or update tests for non-trivial changes. Run the relevant tests before
  calling the work done.
- Document public behavior changes in the right user-facing doc. Comments and
  docstrings should explain assumptions, units, invariants, and failure modes.

## Supported Workflow

The maintained lab path is single-mode Raman suppression by spectral phase
optimization. The supported entry points live in `scripts/canonical/` and are
also exposed through `./fiberlab`.

Useful commands:

```bash
make install
make doctor
make lab-ready
make golden-smoke
make optimize
```

The supported-vs-experimental boundary is in
`docs/guides/supported-workflows.md`.

## Mandatory Output Contract

Every optimization driver that produces `phi_opt` must call
`save_standard_set(...)` from `scripts/standard_images.jl` before exiting.

Expected files:

- `{tag}_phase_profile.png`
- `{tag}_evolution.png`
- `{tag}_phase_diagnostic.png`
- `{tag}_evolution_unshaped.png`

Do not treat file existence as enough. For a single run, inspect all four
images. For sweeps or batches, inspect representative best, typical, worst, and
outlier cases, then record what was checked in `agent-docs/<topic>/SUMMARY.md`.

## Code Style

- Julia uses 4-space indentation.
- Functions are `snake_case`; mutating functions end in `!`.
- Physics variables may use Greek letters where the surrounding code already
  does.
- Prefer `cis(x)` for phase rotations.
- Use `@tullio` for tensor contractions when that is the local pattern.
- Use `@assert` for internal pre/postconditions and `ArgumentError` for
  user-facing validation.
- Use SI units internally unless a file clearly states otherwise.

Common units:

| Quantity | Unit |
|---|---|
| wavelength | meters |
| time | seconds in physics parameters, ps for grids where documented |
| frequency | THz for spectral grids, Hz for repetition rates |
| power | W |
| dispersion | `s^2/m`, `s^3/m` |
| nonlinearity | `W^-1 m^-1` |

## Architecture

- `src/` holds reusable Julia package code.
- `scripts/lib/` holds shared script implementation.
- `scripts/canonical/` holds maintained command-line wrappers.
- `scripts/research/` holds active research drivers outside the supported
  surface.
- `configs/` holds approved run, sweep, experiment, and SLM profile specs.
- `docs/` holds human-facing documentation.
- `agent-docs/` holds continuity notes for agents.

Core flow:

1. build `sim` and `fiber` dictionaries;
2. propagate the spectral field in the interaction picture;
3. compute Raman-band cost;
4. run the adjoint gradient;
5. optimize spectral phase or an explicitly configured control;
6. save the result payload, manifest, trust artifacts, and standard images.

## Compute Discipline

The Mac and `claude-code-host` are synchronized by Syncthing. `.git` is not
synced. Git is the source of history; Syncthing only moves live files.

Start sessions with:

```bash
git status
syncthing cli show connections
```

Before committing or pushing:

```bash
git fetch origin
git status
```

Heavy simulation work belongs on `fiber-raman-burst`, launched through the
heavy-job wrapper. Always run simulation Julia commands with threads enabled:

```bash
julia -t auto --project=. ...
```

Stage code to burst with `rsync`, run through `~/bin/burst-run-heavy`, pull
`results/` back explicitly, and stop the burst VM when done.

## Results Policy

`results/` is generated output, not normal source code. Commit only selected
fixtures, summaries, or figures that were intentionally promoted into docs or
tests. Do not commit routine PNGs, burst logs, or large JLD2 outputs.

## Parallel Work

Avoid simultaneous edits to the same files. Syncthing can create conflict
copies; it cannot merge intent. If a shared coordination doc must change, append
a dated entry or write a local `agent-docs/<topic>/SUMMARY.md` and let the user
integrate it later.
