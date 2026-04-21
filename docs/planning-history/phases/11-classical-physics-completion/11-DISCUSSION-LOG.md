# Phase 11: Classical Physics Completion - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 11-classical-physics-completion
**Areas discussed:** Multi-start z-dynamics, Spectral divergence, H1-H4 testing, Long-fiber degradation, Synthesis document
**Mode:** Auto (--auto flag, all recommended defaults selected)

---

## Multi-Start Z-Dynamics

| Option | Description | Selected |
|--------|-------------|----------|
| All 10 multi-start | Complete coverage of solution landscape | ✓ |
| 3 representative | Faster but may miss outliers | |

**User's choice:** [auto] All 10 (recommended)
**Notes:** 10 propagations at ~10s each = ~2 min total. No reason to subsample.

---

## Spectral Divergence Analysis

| Option | Description | Selected |
|--------|-------------|----------|
| 3 dB threshold | Standard engineering threshold | ✓ |
| 1 dB threshold | More sensitive, noisier | |
| Relative to peak | Normalized divergence | |

**User's choice:** [auto] 3 dB threshold (recommended)

---

## Long-Fiber Investigation

| Option | Description | Selected |
|--------|-------------|----------|
| Higher Nt + re-optimize | Full investigation | ✓ |
| Higher Nt only | Tests resolution | |
| Accept as fundamental | Skip investigation | |

**User's choice:** [auto] Higher Nt + re-optimize (recommended)
**Notes:** Both Nt=2^14 re-propagation and max_iter=100 re-optimization test different hypotheses about the breakdown.

---

## Synthesis Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Phases 9+10+11 | Clean story from central question through resolution | ✓ |
| Phases 6.1+9+10+11 | Includes earlier exploratory work | |
| Full v2.0 | Everything from verification onward | |

**User's choice:** [auto] Phases 9+10+11 (recommended)
**Notes:** Phase 6.1 was exploratory and superseded by Phase 9's systematic analysis.

## Claude's Discretion

- Figure layouts, statistical tests, CPA comparison depth
- Whether to start synthesis from Phase 9 or include 6.1

## Deferred Ideas

- Multimode M>1 extension
- Quantum noise computation
- Z-resolved optimization cost functions
