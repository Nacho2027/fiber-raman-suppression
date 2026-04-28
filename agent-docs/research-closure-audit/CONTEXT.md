## Context

- Goal: eliminate dangling research threads by classifying what is complete,
  what is incomplete, and what should be explicitly archived or parked.
- Primary closure lanes requested by the user:
  - multimode
  - multivariable / multiparameter optimization
  - long-fiber
- Inputs checked in this pass:
  - `AGENTS.md`, `CLAUDE.md`, `README.md`, `scripts/README.md`
  - current-agent-context notes
  - recent synthesis/status docs
  - lane-specific scripts, tests, and saved artifacts under `results/`
- Working rule for this audit:
  - code-complete does not mean science-complete
  - existing artifacts without interpretation do not count as closure
  - a lane is only "complete" if the repo supports an honest supported-range
    statement and the required outputs are present
