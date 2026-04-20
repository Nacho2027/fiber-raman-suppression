# Phase 21 Summary — Numerical Recovery of Phase 18 SUSPECT Results

**Session:** `I-recovery`  
**Date:** 2026-04-20  
**Branch:** `sessions/I-recovery`

## Surprises First

1. **Sweep-1 got worse, not better, on the honest grid.**  
   The original `N_phi` knee story does **not** survive recovery as stated. Even
   after escalating from `108 ps` to `216 ps` and `Nt=65536`, every recovered
   Sweep-1 point still had output edge fraction `> 5e-2`, with the worst at
   `1.688e-01`. The best recovered point is the full-resolution run at
   `-66.03 dB`, weaker than the original `-68 dB` claim and still not pulse-contained.

2. **The Session F 100 m number survives exactly, but only as a lower bound.**  
   The honest revalidation gives `-54.77 dB` again with edge fraction
   `8.468e-06` and energy drift `4.908e-04`. The schema issue was real:
   `100m_validate_fixed.jld2` is only a scalar summary; the actual `phi_opt`
   lives in `100m_opt_full_result.jld2`. The stored run remains `converged=false`,
   so the right statement is “best achieved value on an honest grid,” not
   “certified optimum.”

3. **Phase 13 SMF-28 re-anchors far deeper than the audit recomputation, while
   HNLF becomes even deeper once the grid is truly honest.**  
   SMF-28 recovers to `-66.61 dB` on `Nt=16384, T=54 ps` with edge
   `8.097e-04`. HNLF needed a much larger final grid than its seed-based audit
   would suggest: `Nt=65536, T=320 ps`, after which it reaches `-86.68 dB` with
   edge `2.236e-04`. So the old HNLF `-74.45 dB` anchor was not only polluted,
   it was also materially under-windowed.

4. **The opportunistic MMF run is incomplete, but the blocker is practical, not
   conceptual.**  
   The aggressive MMF job launched and allocated ~23 GB RSS on burst, but did
   not reach a result artifact inside the short optional window. I stopped it to
   avoid burning more burst time after the mandatory priorities were already done.

## Verdicts

| Priority | Verdict | Honest result | Notes |
|---|---|---:|---|
| Sweep-1 at `L=2 m, P=0.2 W` | **RETIRED** | best recovered `-66.03 dB` at `N_phi=65536`, but edge fractions `5.18e-02 … 1.69e-01` | Knee story does not qualify as numerically honest; recovered states still hug boundaries even on `216 ps` |
| Session F 100 m schema + validation | **RECOVERED** | `-54.77 dB` | Honest lower bound, not optimum; summary file lacked `phi_opt`, full state found in `100m_opt_full_result.jld2` |
| Phase 13 Hessian re-anchor — SMF-28 | **RECOVERED** | `-66.61 dB` | Honest at `Nt=16384, T=54 ps`, edge `8.097e-04`, converged |
| Phase 13 Hessian re-anchor — HNLF | **RECOVERED** | `-86.68 dB` | Honest only after forcing `Nt=65536, T=320 ps`, edge `2.236e-04`; run remained unconverged at 50 iters |
| MMF aggressive `M=6, L=2 m, P=0.5 W` | **PARTIAL** | — | Job started, consumed ~23 GB RSS, no final artifact before stop; see `results/burst-logs/I-recovery_20260420T055047Z.log` |

## Evidence

- Sweep-1 markdown: `.planning/phases/21-numerical-recovery/sweep1_recovery.md`
- Sweep-1 JLD2 set: `results/raman/phase21/sweep1/`
- Session F 100 m normalized report: `results/raman/phase21/longfiber100m/sessionf_100m_validation.md`
- Phase 13 reports:
  - `results/raman/phase21/phase13/smf28_reanchor.md`
  - `results/raman/phase21/phase13/hnlf_reanchor.md`
- Standard images: `.planning/phases/21-numerical-recovery/images/`
- MMF partial log: `results/burst-logs/I-recovery_20260420T055047Z.log`

## Decisions Made During Recovery

- The prompt-referenced handoff file `.planning/notes/HANDOFF-2026-04-20.md`
  was not present in this clone. I reconstructed context from tracked audit,
  validation, and session status files instead.
- Sweep-1 grid sizing based on the raw old seeds was rejected after it inflated
  for group-delay gauge rather than physics. The final methodology sized from a
  conservative first-principles floor and then judged the **recovered** states.
- Both Sweep-1 and Phase 13 needed serial image generation after threaded
  compute. PyPlot/PyCall segfaulted when standard images were emitted inside
  threaded workers on burst.
- The burst VM was stopped after compute, briefly restarted only to copy Phase 21
  artifacts back to the local worktree, then stopped again. Final state:
  **TERMINATED**.

## What I Would Do Next

1. Treat the Sweep-1 simplicity narrative as numerically unsupported until a
   boundary-aware objective or a substantially larger-window continuation test
   shows contained optima.
2. Update the canonical docs to describe the 100 m result as a validated lower
   bound with paired-summary/full-state schema.
3. Use the new Phase 13 anchors, not the old audit recomputations, when
   discussing the Hessian-study dB values.
4. If MMF matters for the next draft, rerun it in its own session with a longer
   wall-clock allowance and an explicit checkpoint/output cadence.
