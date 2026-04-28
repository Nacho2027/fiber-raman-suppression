# Documentation Organization Summary

## Outcome

Added a lightweight documentation discovery system:

- `agent-docs/README.md` now maps agent-facing context and topic directories.
- `llms.txt` gives agents and LLM tooling a compact map of the highest-value
  docs.
- Existing indexes can point to `agent-docs/README.md` and `llms.txt` without
  adding a human-facing documentation policy page.

## Graph Decision

Use hierarchy and curated indexes as primary navigation. Use plain Markdown
links as the durable graph. Do not adopt Obsidian-only wikilinks or require a
graph viewer.

## Sources Checked

- Diataxis: https://diataxis.fr/
- Obsidian internal links: https://obsidian.md/help/links
- Obsidian graph view: https://obsidian.md/help/plugins/graph
- llms.txt proposal: https://llmstxt.org/
- HelpGuides llms.txt note: https://docs.helpguides.io/article/using-llmstxt

## Verification

- Read `agent-docs/README.md`, `llms.txt`, and this summary after edits.
- Confirmed no remaining references to the removed human-facing policy page.
- Checked for Obsidian-style wikilinks; the only matches were existing
  Julia/Python-looking string literals for `supported_variables`.
- Ran a local Markdown-link scan across 514 Markdown/manifest files.
  Straightforward stale links in current docs/agent docs were fixed:
  absolute `/home/...` agent links in `agent-docs/parallel-research-campaign/`
  and stale `.planning` / `results` paths in
  `docs/architecture/cost-function-physics.md`.
- After a follow-up check, two real archived-history links were also fixed:
  the Phase 22 Pareto image and the Phase 33 synthesis link.
- Re-ran the link scan on the touched files; missing link count is `0`.
- The naive full-repo regex scan still reports 8 hits, all from code snippets
  such as `sol["ode_sol"](L)` being parsed as Markdown. A smarter scan that
  strips fenced and inline code reports `checked=514 missing=0`.
- Reviewed targeted `git status --short`; changed files are limited to the
  agent/tooling docs added in this pass, `AGENTS.md`, the existing dirty
  `README.md`, and the stale-link corrections noted above.
