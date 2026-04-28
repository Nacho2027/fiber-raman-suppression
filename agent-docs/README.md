# Agent Documentation

This directory is the agent-facing continuity layer. It is for working state,
handoffs, durable implementation context, and research-operation notes that
would be too noisy or too internal for `docs/`.

For human-facing guidance, reports, and polished explanations, use
[`../docs/README.md`](../docs/README.md). For the short operational contract,
use [`../AGENTS.md`](../AGENTS.md).

## Start Here

Before deep numerics, methodology, infrastructure, or compute work, read:

1. [`current-agent-context/INDEX.md`](current-agent-context/INDEX.md)
2. The lane-specific context file if it exists:
   [`LONGFIBER.md`](current-agent-context/LONGFIBER.md),
   [`MULTIMODE.md`](current-agent-context/MULTIMODE.md), or
   [`MULTIVAR.md`](current-agent-context/MULTIVAR.md)
3. Any active topic directory named in that context file

## Directory Types

| Area | Purpose |
|------|---------|
| `current-agent-context/` | Curated durable facts that future agents should read before technical work. |
| `<topic>/CONTEXT.md` | Why the task exists, constraints, relevant files, and prior state. |
| `<topic>/PLAN.md` | Execution plan, open questions, and verification strategy. |
| `<topic>/SUMMARY.md` | What changed, what was verified, what remains risky or unfinished. |
| Ad hoc lane folders | Session-local or campaign-local notes that are useful to agents but not polished human docs. |

If a topic only produced a small handoff, `SUMMARY.md` alone is acceptable.
For non-trivial active work, prefer the full `CONTEXT.md` / `PLAN.md` /
`SUMMARY.md` triplet.

## Current Topic Map

| Topic | Read when |
|-------|-----------|
| [`current-agent-context/`](current-agent-context/) | You need active project state, compute rules, or durable numerics/methodology guidance. |
| [`equation-verification/`](equation-verification/) | You are checking analytic gradients, equation-level claims, or finite-difference fallback status. |
| [`phase31-reduced-basis/`](phase31-reduced-basis/) | You are touching reduced-basis phase parameterization or Phase 31 follow-up. |
| [`research-closure-audit/`](research-closure-audit/) | You need the closure audit behind the current reports and lane status. |
| [`multimode-baseline-stabilization/`](multimode-baseline-stabilization/) | You are resuming MMF baseline stabilization or interpreting the qualified MMF lane. |
| [`parallel-research-campaign/`](parallel-research-campaign/) | You are reconstructing the parallel-session lane assignments and prompts. |
| [`repo-refactor-plan/`](repo-refactor-plan/) | You are deciding whether a code or docs move belongs to the current refactor shape. |
| [`documentation-organization/`](documentation-organization/) | You are changing how agent docs, human docs, links, or manifests are organized. |
| [`internal-lab-release-readiness/`](internal-lab-release-readiness/) | You are preparing a Rivera Lab internal handoff or checking practical lab-user blockers. |
| [`public-release-readiness/`](public-release-readiness/) | You are preparing a public preview release or checking release blockers, metadata, CI, and artifact curation. |

Older folders are preserved when they contain useful handoff detail. Do not
assume every old topic is active just because it exists.

## What Belongs Here

Put material in `agent-docs/` when it is:

- an implementation plan or handoff for an agent
- a record of commands, run tags, verification decisions, or unresolved risks
- durable context that future agents need before touching code or results
- internal coordination for multi-session or machine-specific workflows

Do not put polished user guides, lab reports, presentation-ready explanations,
or public research notes here. Those belong in `docs/`.

## Link Policy

Use normal Markdown links instead of Obsidian-only wikilinks. Plain Markdown
links work in GitHub, local editors, grep-based tooling, and future static-site
or agent indexing tools.

Use links deliberately:

- Link from a topic summary to the human-facing doc or result that supersedes it.
- Link from current context files to the active topic folders they depend on.
- Add reciprocal links only when both directions help a reader re-enter work.
- Avoid linking every repeated term; overlinked notes become harder for agents
  to skim and harder for humans to maintain.

The lightweight graph is the set of these explicit Markdown links plus the
indexes in this file, `docs/README.md`, and `llms.txt`.

## Maintenance Rule

When closing a substantial task, update exactly the lowest-level index that
helps the next reader find the work:

- Update this file for a new durable agent topic.
- Update `current-agent-context/INDEX.md` only for context future agents should
  routinely read.
- Update `docs/README.md` for human-facing docs.
- Update `llms.txt` when a new or renamed document becomes a top-level source
  of truth for humans or agents.
