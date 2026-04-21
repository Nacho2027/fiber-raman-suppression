# Phase 5: Result Serialization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 05-result-serialization
**Areas discussed:** Serialization format, Data scope per run, Manifest structure, Convergence history

---

## Serialization Format

User asked for recommendation. Claude recommended JLD2 over NPZ (already in project) because JLD2 round-trips Julia types natively. User accepted.

**User's choice:** JLD2.jl (new dependency)

---

## Data Scope Per Run

Claude recommended: scalars + phi_opt + convergence_history + uω0 (input field). Skip full evolution solution (too large, recomputable). User accepted.

**User's choice:** Scalars + phi_opt + convergence history + uω0

---

## Manifest Structure

Claude recommended: single manifest.json in results/raman/ with scalar summaries, plus per-run _result.jld2 files next to existing PNGs. User accepted.

**User's choice:** Single manifest.json + per-run JLD2 files

---

## Convergence History

Claude recommended: Optim.jl built-in store_trace=true + Optim.f_trace(result). No custom callback needed. User accepted.

**User's choice:** Built-in Optim.jl trace

---

## Claude's Discretion

- Whether to save band_mask and sim Dict fields in JLD2
- JSON schema field names and formatting
- Error handling for JLD2 write failures

## Deferred Ideas

None.
