# Documentation Organization Context

## Request

Organize agent documentation and human-facing documentation so future agents and
humans can find the right material quickly. Evaluate whether graph-based
agent Markdown files are worth adopting.

## Existing State

- `docs/README.md` already serves as the human-facing index.
- `agent-docs/current-agent-context/INDEX.md` exists, but `agent-docs/` did not
  have a root-level map.
- `AGENTS.md` and `CLAUDE.md` already define the human-doc versus agent-doc
  split.
- `docs/planning-history/` is the archive of the old GSD workflow and should
  not become active planning state again.
- The working tree was already heavily dirty before this pass; this task avoids
  moving existing files or rewriting unrelated docs.

## Research Finding

Use explicit Markdown links as a lightweight graph, not a graph-first docs
system.

- Diataxis supports organizing human docs by user need.
- Obsidian-style graph views are useful for visualizing relationships, but they
  depend on links that still need good indexes and careful naming.
- `llms.txt` is an emerging but practical convention for exposing a compact
  agent-readable map of important docs.

## Decision

Implement:

- a root `agent-docs/README.md`
- a root `llms.txt` manifest
- targeted index updates only

Do not:

- convert repo docs to wikilinks
- require Obsidian or any graph viewer
- move existing docs in this pass
- add front matter to every Markdown file without a consuming tool
- add a human-facing documentation policy page
