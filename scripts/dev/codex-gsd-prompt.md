# Codex × GSD — paste this at the top of any Codex session in this repo

You are working in the **fiber-raman-suppression** repo (Rivera Lab, Cornell).
The project uses the GSD planning system (`.planning/`) and runs across
multiple machines (Mac + claude-code-host VM + fiber-raman-burst VM). Follow
the rules below or you WILL break things.

## Always do these first, in order

1. **Read `CLAUDE.md`** — full project instructions (multi-machine workflow,
   burst-VM rules P1–P7, simulation discipline). Do not skip.
2. **Read `.planning/STATE.md`** and `.planning/ROADMAP.md` — current phase,
   recent commits, open work.
3. **Read `results/PHYSICS_AUDIT_2026-04-19.md`** if anything physics-related
   is in scope — that file is the canonical verdict on what's defensible.

## Editing rules

- **GSD strict mode is normally ON** but the wrapper script
  (`scripts/codex-gsd-bootstrap.sh`) flipped it OFF for your session. Do not
  re-enable it manually; the wrapper restores it on exit.
- **Never edit `results/raman/*.md`** — input-only, the markdown there is
  historical session output.
- **Never edit `results/PHYSICS_AUDIT_2026-04-19.md`** unless the user
  explicitly asks for an audit revision (Phase 19 owns that file).
- **Canonical docs are the .tex files under `docs/`**, not the markdown:
  - `docs/companion_explainer.tex` — undergrad pedagogical voice
  - `docs/physics_verification.tex` — derivations reference
  - `docs/verification_document.tex` — full verification artifact
- After ANY .tex edit, rebuild PDFs with two pdflatex passes per file:
  ```bash
  cd docs && for f in companion_explainer physics_verification verification_document; do
    pdflatex -interaction=nonstopmode "$f.tex" >/dev/null 2>&1
    pdflatex -interaction=nonstopmode "$f.tex" >/dev/null 2>&1
  done
  ```
  Commit `.tex` and `.pdf` together.
- **Doc figures live in `docs/figures/`** (tracked). Do NOT reference
  `results/images/` from .tex — that path is gitignored and breaks rebuilds
  on remote machines.

## Source-of-truth rule

Every new physics claim added to a `.tex` file must be sourced inline to one
of: a `file:line` reference, a phase summary in `.planning/phases/<N>-*/`, a
validation markdown in `results/validation/`, or a JLD2 artifact with the path
quoted. No unsourced numbers.

## Simulation rules (only relevant if you launch Julia)

- **Never run heavy Julia on `claude-code-host` (the always-on VM)** — only on
  `fiber-raman-burst`, and only via `~/bin/burst-run-heavy <session-tag>
  '<command>'` (Rule P5). The wrapper enforces a singleton lock; bypassing it
  has caused a hard kernel lockup before.
- Always launch Julia with `-t auto` so the threading parallelism actually
  runs (single-thread default is dormant).
- Always `burst-stop` when done — VM bills $0.90/hr while running.
- Light tests / unit tests / dependency checks: fine on this host.

## GSD CLI

The `gsd-sdk` CLI is the canonical way to interact with `.planning/`:

```bash
gsd-sdk query state.load                    # current state JSON
gsd-sdk query roadmap.analyze               # phase list + status
gsd-sdk query roadmap.get-phase <N>         # one phase's metadata
gsd-sdk query init.phase-op <N>             # phase paths + flags
gsd-sdk query state.completed-phase --phase <N> --name "<name>"
gsd-sdk query commit "<msg>" <files...>     # commit helper (tracks docs)
```

Codex does not have access to Claude Code skills (`/gsd-fast`, `/gsd-quick`,
etc.). Instead, do the equivalent work directly: edit files, run tests, make
atomic conventional commits, push.

## Commit / push discipline (multi-machine)

- Conventional commit format: `type(scope): description`
- Commit messages should explain WHY, not just WHAT.
- Co-author footer: `Co-Authored-By: Codex <noreply@openai.com>`.
- After non-trivial work, **push immediately** so other machines get it on
  their next `git fetch`. Long-lived uncommitted state on one machine is the
  #1 cause of merge conflicts later.
- **`.planning/` is gitignored.** Changes there propagate via the Mac's
  `sync-planning-{to,from}-vm` helpers, NOT git. If you edit `.planning/`
  here, tell the user so they can sync.

## When in doubt

- Ask for confirmation before destructive ops (rm, force-push, dropping
  state).
- If a tool/skill returns an error you don't understand, surface it; don't
  silently work around it.
- For physics decisions (interpretation, claim acceptance) — STOP and ask.
  For mechanical work (rebuild, commit, push, syntax fix) — proceed.

## Reference docs you may need

- `CLAUDE.md` — project rules (always)
- `docs/README.md` — what the docs are
- `docs/output-format.md` — JLD2 + JSON sidecar spec
- `.planning/phases/<N>-*/CONTEXT.md` and `<N>-*-SUMMARY.md` — per-phase scope
  and outcome
- `scripts/burst/README.md` — burst-VM wrapper details
