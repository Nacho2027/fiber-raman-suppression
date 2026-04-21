# Phase 4: Correctness Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 04-correctness-verification
**Areas discussed:** Verification location, Tolerance strategy

---

## Verification Location

| Option | Description | Selected |
|--------|-------------|----------|
| New scripts/verification.jl | Standalone script dedicated to physics verification. Separates research-grade validation from the existing fast unit/property tests in test_optimization.jl. Runs independently for lab presentations. | ✓ |
| Extend test_optimization.jl | Add VERIF-01 through VERIF-04 as new @testset sections (D, E) alongside existing A/B/C. Keeps all testing in one place. | |
| Both — fast + thorough | Keep existing tests in test_optimization.jl as-is (fast CI-style), AND create verification.jl for high-fidelity research-grade runs at larger grids. Two tiers. | |

**User's choice:** New scripts/verification.jl
**Notes:** None

### Follow-up: Report output

| Option | Description | Selected |
|--------|-------------|----------|
| Script writes report file | verification.jl writes results/raman/validation/verification_report.md with PASS/FAIL, numeric evidence, and timestamp. | |
| Console output only | Use @info logging like existing tests. | |
| You decide | Claude's discretion on report output mechanism | ✓ |

**User's choice:** You decide
**Notes:** None

---

## Tolerance Strategy

### Grid and tolerance tiers

| Option | Description | Selected |
|--------|-------------|----------|
| Higher-fidelity in verification.jl | Leave test_optimization.jl at 10% (fast, Nt=2^9). New verification.jl runs at Nt=2^12 with 2% threshold. Two tiers. | ✓ |
| Tighten existing + add new | Tighten test_optimization.jl soliton test to 5% (moderate), AND create verification.jl at 2%. Middle ground. | |
| Replace with 2% everywhere | Bump existing test to Nt=2^12 and 2% tolerance. One source of truth but tests become slower (~10x). | |

**User's choice:** Higher-fidelity in verification.jl
**Notes:** None

### Photon number config scope

| Option | Description | Selected |
|--------|-------------|----------|
| All 5 production configs | Run photon number check on SMF-28 and HNLF at all preset lengths/powers. Thorough but slower (~minutes). | ✓ |
| One representative config | Test on one canonical SMF-28 config. | |
| You decide | Claude's discretion | |

**User's choice:** All 5 production configs
**Notes:** User asked whether more configs are added by other phases. Clarified that Phase 7 sweeps add many more configs and photon number check will be baked into sweep infrastructure.

### Additional test configs

| Option | Description | Selected |
|--------|-------------|----------|
| 5 existing is fine for Phase 4 | Phase 7 sweeps will cover broader parameter space later. | ✓ |
| Add a few edge cases | Add 2-3 extreme configs to Phase 4 for stress-testing. | |

**User's choice:** 5 existing is fine for Phase 4
**Notes:** None

---

## Claude's Discretion

- Report format (write file vs console output)
- VERIF-04 direct J cross-check implementation details
- Grid sizes for Taylor remainder and FD checks in verification.jl

## Deferred Ideas

None — discussion stayed within phase scope.
