# Phase 4: Correctness Verification - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the forward NLSE solver and adjoint gradient are physically correct against analytical solutions and theoretical invariants. Produce a human-readable verification report with PASS/FAIL evidence. Does NOT add new optimization capabilities, cross-run comparison, or parameter sweep features.

</domain>

<decisions>
## Implementation Decisions

### Verification Location
- **D-01:** Create a new standalone `scripts/verification.jl` for research-grade physics verification. Do NOT extend `test_optimization.jl`. The existing tests in `test_optimization.jl` remain as-is (fast CI-style at looser tolerances). `verification.jl` is a separate, dedicated script for thorough validation.

### Tolerance Strategy
- **D-02:** Two-tier approach. Existing `test_optimization.jl` keeps its 10% soliton tolerance at Nt=2^9 (fast, ~seconds). New `verification.jl` runs at **Nt=2^14 (production fidelity)** with 2% threshold for VERIF-01. Production grid size is mandatory because smaller grids change boundary effects (superGaussian attenuator shape, Raman hRω wrapping, band_mask physical bandwidth) and can mask real physics bugs.
- **D-03:** Photon number conservation (VERIF-02) tested on all 5 production configs (SMF-28 and HNLF presets from `FIBER_PRESETS`). Phase 7 sweeps will bake photon number check into sweep infrastructure for broader coverage automatically.
- **D-04:** No additional test configs needed for Phase 4 beyond the existing 5 production presets. Phase 7 will cover broader parameter space.

### Claude's Discretion
- Report output mechanism: Claude decides whether `verification.jl` writes a markdown report file to `results/raman/validation/` or uses console @info logging (or both). User doesn't have a strong preference.
- VERIF-04 (direct J cross-check) implementation details — straightforward, no user input needed.
- Grid sizes for Taylor remainder and FD checks in `verification.jl` — use Nt=2^14 to match production and avoid boundary artifacts.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Test Infrastructure
- `scripts/test_optimization.jl` (lines 517-680) — Forward Solver Correctness section with existing soliton, dispersion, energy, and linear regime tests. DO NOT modify these; `verification.jl` is additive.
- `scripts/test_optimization.jl` (lines 686-750) — Adjoint & Gradient Correctness with existing Taylor remainder and full FD checks.
- `scripts/test_optimization.jl` (lines 96-112) — `make_test_problem` and `make_amplitude_test_problem` factory functions.

### Setup and Cost Functions
- `scripts/common.jl` — `setup_raman_problem`, `spectral_band_cost`, `FIBER_PRESETS` dictionary, `recommended_time_window`, `check_boundary_conditions`

### Physics Reference
- `results/raman/MATHEMATICAL_FORMULATION.md` — Analytical reference cases and mathematical derivations for the NLSE, adjoint method, and cost functional

### Research (Verification Methods)
- `.planning/research/FEATURES.md` — Detailed verification protocols: soliton test, photon number conservation, Taylor remainder, cross-run metadata schema
- `.planning/research/PITFALLS.md` — Critical pitfall: normalized cost J=E_band/E_total absorbs energy errors; photon number is the correct invariant; grid mismatch invalidates cross-run J comparison

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `make_test_problem()` factory in `test_optimization.jl` — creates minimal Nt=2^8 problems. `verification.jl` can use the same pattern at larger Nt.
- `measure_fwhm()` and `significant_spectral_indices()` utilities in `test_optimization.jl`
- `FIBER_PRESETS` in `common.jl` — named tuples with (gamma, betas) for SMF28, HNLF variants
- `setup_raman_problem()` — the standard entry point for creating (uω0, fiber, sim, band_mask) from physical parameters
- `MultiModeNoise.solve_disp_mmf()` — the forward solver used by existing soliton test
- `cost_and_gradient()` in `raman_optimization.jl` — computes J and adjoint gradient simultaneously

### Established Patterns
- Tests use `@testset` with descriptive names and `@info @sprintf` for diagnostic output
- Small grid tests (Nt=2^7-2^9) for speed; verification can use larger grids since it runs less frequently
- `deepcopy(fiber)` before modifying `zsave` — prevents dict mutation (documented bug from TDD cycle)
- Include guards: `_COMMON_JL_LOADED`, `_VISUALIZATION_JL_LOADED` — `verification.jl` should follow the same `include("common.jl")` pattern

### Integration Points
- `verification.jl` includes `common.jl` and `raman_optimization.jl` (for `cost_and_gradient`)
- Output to `results/raman/validation/` directory (new, needs mkdir)
- Uses the same `using MultiModeNoise` + `using Test` pattern as `test_optimization.jl`

</code_context>

<specifics>
## Specific Ideas

- The photon number integral ∫|U(ω)|²/ω dω needs care near ω=0 (singularity). Research suggests using ω+ω₀ (carrier frequency offset) to avoid division by zero.
- VERIF-01 soliton test must disable Raman (fR≈0) — existing test already does this with `fR=1e-15`.
- Taylor remainder test in existing code uses epsilons [1e-1, 1e-2, 1e-3, 1e-4] and checks slope in range 1.4-2.6. Verification.jl can use same range or extend.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-correctness-verification*
*Context gathered: 2026-03-25*
