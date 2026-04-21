# Phase 7: Parameter Sweeps - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-03-26
**Phase:** 07-parameter-sweeps
**Areas discussed:** Time window fix, Sweep grid design, Compute budget, Multi-start design

---

## Time Window Fix Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Generous fixed windows + validation | Don't fix function, use large safety_factor | |
| Fix recommended_time_window() | Add SPM broadening estimate | |
| Both: fix + validate | Fix function AND validate with photon number drift | ✓ |

**User's choice:** Both — belt and suspenders

---

## Sweep Grid Design

| Option | Description | Selected |
|--------|-------------|----------|
| 4x4 SMF-28 only | 16 points, ~20-30 min | |
| 4x4 both fiber types | 32 points, ~40-60 min | |
| You decide | Claude designs grid | ✓ |

---

## Compute Budget

| Option | Description | Selected |
|--------|-------------|----------|
| Up to 30 min | ~16 points max | |
| Up to 1 hour | ~30-40 points | |
| As long as needed | No limit, full grid | ✓ |

---

## Multi-Start Design

| Option | Description | Selected |
|--------|-------------|----------|
| 10 starts, SMF-28 L=2m P=0.30W | Most nonlinear SMF-28 config | |
| 5 starts, one per config | All fiber types | |
| You decide | Claude picks | ✓ |

---

## Claude's Discretion

- Grid L and P values
- max_iter for sweep points
- Heatmap visualization details
- Multi-start config and seed strategy
- Script organization
