# T01: 04-correctness-verification 01

**Slice:** S01 — **Milestone:** M002

## Description

Create the `scripts/verification.jl` skeleton with the two simpler verification checks: VERIF-01 (soliton shape preservation) and VERIF-04 (cost cross-check). Establish the report generation infrastructure that Plan 02 will extend.

Purpose: Build the verification script foundation with the two highest-confidence tests. VERIF-01 already passes at 1.3% error on Nt=2^9 -- upgrading to Nt=2^14 and 2% max-deviation threshold is straightforward. VERIF-04 is a five-line calculation. This plan also creates the report writer and result collection infrastructure used by Plan 02.

Output: A runnable `scripts/verification.jl` that passes VERIF-01 and VERIF-04, writes a partial verification report.

## Must-Haves

- [ ] "An N=1 sech soliton propagated one soliton period at Nt=2^14 matches its input shape to within 2% max deviation"
- [ ] "The cost J returned by spectral_band_cost matches direct E_band/E_total integration to machine precision (atol=1e-12)"
- [ ] "verification.jl runs to completion and produces a human-readable report in results/raman/validation/"

## Files

- `scripts/verification.jl`
- `results/raman/validation/`
