# S01: Correctness Verification

**Goal:** Create the `scripts/verification.
**Demo:** Create the `scripts/verification.

## Must-Haves


## Tasks

- [x] **T01: 04-correctness-verification 01** `est:3min`
  - Create the `scripts/verification.jl` skeleton with the two simpler verification checks: VERIF-01 (soliton shape preservation) and VERIF-04 (cost cross-check). Establish the report generation infrastructure that Plan 02 will extend.

Purpose: Build the verification script foundation with the two highest-confidence tests. VERIF-01 already passes at 1.3% error on Nt=2^9 -- upgrading to Nt=2^14 and 2% max-deviation threshold is straightforward. VERIF-04 is a five-line calculation. This plan also creates the report writer and result collection infrastructure used by Plan 02.

Output: A runnable `scripts/verification.jl` that passes VERIF-01 and VERIF-04, writes a partial verification report.
- [x] **T02: 04-correctness-verification 02** `est:35min`
  - Add VERIF-02 (photon number conservation across all 5 production configs) and VERIF-03 (Taylor remainder at production grid) to the existing `scripts/verification.jl`. Remove placeholder testsets and finalize the complete verification suite.

Purpose: VERIF-02 is the most novel check -- photon number (not energy) is the correct conserved invariant for GNLSE with self-steepening. This has never been tested in the codebase. VERIF-03 upgrades the existing Taylor remainder from Nt=2^8 to Nt=2^14 for production-fidelity adjoint validation. Together with Plan 01's VERIF-01 and VERIF-04, this completes the Phase 4 verification gate.

Output: A complete `scripts/verification.jl` that runs all 4 VERIF checks at production fidelity, writes a final PASS/FAIL report.

## Files Likely Touched

- `scripts/verification.jl`
- `results/raman/validation/`
- `scripts/verification.jl`
