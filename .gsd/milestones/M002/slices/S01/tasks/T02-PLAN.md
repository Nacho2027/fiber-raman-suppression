# T02: 04-correctness-verification 02

**Slice:** S01 — **Milestone:** M002

## Description

Add VERIF-02 (photon number conservation across all 5 production configs) and VERIF-03 (Taylor remainder at production grid) to the existing `scripts/verification.jl`. Remove placeholder testsets and finalize the complete verification suite.

Purpose: VERIF-02 is the most novel check -- photon number (not energy) is the correct conserved invariant for GNLSE with self-steepening. This has never been tested in the codebase. VERIF-03 upgrades the existing Taylor remainder from Nt=2^8 to Nt=2^14 for production-fidelity adjoint validation. Together with Plan 01's VERIF-01 and VERIF-04, this completes the Phase 4 verification gate.

Output: A complete `scripts/verification.jl` that runs all 4 VERIF checks at production fidelity, writes a final PASS/FAIL report.

## Must-Haves

- [ ] "Photon number integral is conserved to <1% across forward propagation for all 5 production configs"
- [ ] "Taylor remainder test on log-log shows slope ~2 at Nt=2^14, confirming adjoint gradient is O(eps^2) correct"
- [ ] "A complete verification report with PASS/FAIL for all 4 checks is written to results/raman/validation/"

## Files

- `scripts/verification.jl`
