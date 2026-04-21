# Phase 4: Correctness Verification - Research

**Researched:** 2026-03-25
**Domain:** Julia physics verification — NLSE soliton propagation, photon number conservation, adjoint gradient Taylor remainder, spectral band cost cross-check
**Confidence:** HIGH (all findings verified against direct codebase audit and existing test run output)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Create a new standalone `scripts/verification.jl` for research-grade physics verification. Do NOT extend `test_optimization.jl`. The existing tests in `test_optimization.jl` remain as-is (fast CI-style at looser tolerances). `verification.jl` is a separate, dedicated script for thorough validation.
- **D-02:** Two-tier approach. Existing `test_optimization.jl` keeps its 10% soliton tolerance at Nt=2^9 (fast, ~seconds). New `verification.jl` runs at **Nt=2^14 (production fidelity)** with 2% threshold for VERIF-01. Production grid size is mandatory because smaller grids change boundary effects (superGaussian attenuator shape, Raman hRω wrapping, band_mask physical bandwidth) and can mask real physics bugs.
- **D-03:** Photon number conservation (VERIF-02) tested on all 5 production configs (SMF-28 and HNLF presets from `FIBER_PRESETS`). Phase 7 sweeps will bake photon number check into sweep infrastructure for broader coverage automatically.
- **D-04:** No additional test configs needed for Phase 4 beyond the existing 5 production presets. Phase 7 will cover broader parameter space.

### Claude's Discretion

- Report output mechanism: Claude decides whether `verification.jl` writes a markdown report file to `results/raman/validation/` or uses console `@info` logging (or both). User doesn't have a strong preference.
- VERIF-04 (direct J cross-check) implementation details — straightforward, no user input needed.
- Grid sizes for Taylor remainder and FD checks in `verification.jl` — use Nt=2^14 to match production and avoid boundary artifacts.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VERIF-01 | Fundamental soliton (N=1 sech) propagates one soliton period with <2% shape error, confirming NLSE solver correctness | Soliton propagation protocol fully documented in MATHEMATICAL_FORMULATION.md §6; existing Nt=2^9 test at 10% already passes at shape_error=1.3%; upgrade to Nt=2^14 and 2% threshold |
| VERIF-02 | Photon number integral |U(ω)|²/ω conserved to <1% across forward propagation for all standard configs | Physics: GNLSE with self-steepening conserves photon number not energy; formula from FEATURES.md §Photon Number Conservation; singularity avoidance at ω=0 requires ω+ω₀ denominator; 5 FIBER_PRESETS to test |
| VERIF-03 | Taylor remainder test produces log-log residual vs eps plot with slope ~2, confirming adjoint is O(eps^2) correct | Existing test at Nt=2^8 already produces slope 2.00 and 2.04; upgrade to Nt=2^14; existing epsilon range [1e-1…1e-4] verified adequate; extend to 6 points for cleaner plot |
| VERIF-04 | Cost J from spectral_band_cost matches direct spectral integration to machine precision, confirming mask correctness | Low complexity: compute `E_band_direct = sum(abs2.(uωf[band_mask,:]))` and `E_total_direct = sum(abs2.(uωf))`, compare J_direct = E_band_direct/E_total_direct against spectral_band_cost output |
</phase_requirements>

---

## Summary

Phase 4 creates `scripts/verification.jl` — a standalone research-grade verification script that runs four physics correctness checks at production grid size (Nt=2^14) and writes a PASS/FAIL report to `results/raman/validation/`. The phase does NOT modify `test_optimization.jl`.

All four required verifications have strong existing foundations: the soliton test already passes at 1.3% error on Nt=2^9 (tolerance was 10%); the Taylor remainder test already produces slope 2.00 on Nt=2^8; the cost J cross-check is a five-line calculation. The primary implementation work is (1) a new script file with the standard include structure, (2) upgrading existing tests to Nt=2^14 with production-fidelity tolerances, (3) adding the new photon number conservation check across all 5 FIBER_PRESETS, and (4) writing a structured markdown report.

The critical new physics check is VERIF-02 (photon number conservation), which has not previously been implemented anywhere in the codebase. The existing energy conservation check (`E_out/E_in`) already passes at <0.003% (2.32e-5 deviation), but photon number `∫|U(ω)|²/ω dω` is the physically correct conserved invariant for GNLSE with self-steepening, and must be verified separately. The singularity near ω=0 requires using `ωs + ω0` (carrier-offset frequency) as the denominator.

**Primary recommendation:** Create `scripts/verification.jl` following the same include/guard structure as `test_optimization.jl`, with four `@testset` blocks, Nt=2^14 throughout, console `@info` logging for all numeric evidence, and a markdown report written to `results/raman/validation/`.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `MultiModeNoise` (local) | 1.0.0-DEV | Forward solver `solve_disp_mmf`, adjoint `solve_adjoint_disp_mmf` | The physics engine under test; must be the same entry points used in production |
| `Test` (stdlib) | bundled | `@testset`, `@test` macros for PASS/FAIL tracking | Same pattern as `test_optimization.jl`; structured test output |
| `LinearAlgebra` (stdlib) | bundled | `norm()`, `dot()` for Taylor remainder computation | Already used in existing Taylor test |
| `FFTW` | in Project.toml | FFT for photon number frequency grid | Same FFTW plans used in production |
| `Printf` (stdlib) | bundled | `@sprintf` for numeric evidence formatting in `@info` log | Project convention; all scripts use `@sprintf` inside `@info` |
| `Logging` (stdlib) | bundled | `@info`, `@warn` macros | Project convention; scripts layer uses `Logging` not `println` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Statistics` (stdlib) | bundled | `mean()` if needed for spectral centroid shifts | If VERIF-02 wants to report spectral centroid alongside photon number |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-written Taylor remainder | Zygote/Enzyme AD | AD struggles with DifferentialEquations.jl in-place mutations; out of scope per REQUIREMENTS.md |
| Direct Julia `Test` | Custom PASS/FAIL booleans | `@testset` gives structured output and proper exit codes; simpler to interpret |

**Installation:** No new dependencies needed. All libraries are already in `Project.toml`.

---

## Architecture Patterns

### Recommended Project Structure

```
scripts/
├── verification.jl          # NEW — Phase 4 deliverable
├── common.jl                # EXISTING — include'd by verification.jl
├── raman_optimization.jl    # EXISTING — include'd for cost_and_gradient
├── test_optimization.jl     # EXISTING — do NOT modify
└── ...
results/raman/validation/
├── test_output_20260324.log # EXISTING
└── verification_YYYYMMDD.md # NEW — written by verification.jl
```

### Pattern 1: Script Structure for verification.jl

**What:** Same header, include, and include-guard pattern as `test_optimization.jl`.

**When to use:** Every verification script in this codebase.

**Example:**
```julia
"""
Physics Correctness Verification Script

Runs four production-fidelity checks (Nt=2^14) to confirm solver and adjoint
correctness. Results written to results/raman/validation/verification_DATE.md.

Checks:
  VERIF-01: Fundamental soliton (N=1 sech) shape preserved to <2%
  VERIF-02: Photon number conserved to <1% across all 5 FIBER_PRESETS
  VERIF-03: Taylor remainder slope ~2 on log-log (adjoint O(eps^2) correct)
  VERIF-04: spectral_band_cost J matches direct integration to machine precision

Run: julia scripts/verification.jl
"""
using Test
using LinearAlgebra
using FFTW
using Logging
using Printf
using MultiModeNoise

include("common.jl")
include("raman_optimization.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────
const VERIF_NT = 2^14
const VERIF_OUTPUT_DIR = joinpath(@__DIR__, "..", "results", "raman", "validation")
```

### Pattern 2: VERIF-01 Soliton Test (Production Grid)

**What:** Propagate N=1 sech pulse one full soliton period at Nt=2^14. Compare normalized intensity profiles using max-deviation metric (not norm ratio), to match the <2% success criterion directly.

**When to use:** VERIF-01 only. Raman must be disabled (fR=1e-15).

**Key parameters (from existing test):**
- `beta2 = -2.6e-26` s²/m (anomalous, matches existing soliton test)
- `gamma = 0.0013` W⁻¹m⁻¹ (SMF-28 gamma)
- `pulse_fwhm = 185e-15` s, `pulse_rep_rate = 80.5e6` Hz
- `T0 = pulse_fwhm / (2 * acosh(sqrt(2)))` → soliton half-width
- `P_peak_soliton = abs(beta2) / (gamma * T0^2)` → N=1 condition
- `L_D = T0^2 / abs(beta2)`, `z_soliton = (pi / 2) * L_D` → one full period

**Difference from existing test:** Success criterion changes from `shape_error < 0.10` (norm-based) to `max_deviation < 0.02` (max-deviation-based), at `Nt=2^14` and `time_window=10.0`.

**Example:**
```julia
# Source: scripts/test_optimization.jl lines 617-679 (adapted for Nt=2^14, 2% threshold)
@testset "VERIF-01: Fundamental soliton N=1 shape preserved (<2% max deviation)" begin
    beta2 = -2.6e-26; gamma = 0.0013
    pulse_fwhm = 185e-15; pulse_rep_rate = 80.5e6
    T0 = pulse_fwhm / (2 * acosh(sqrt(2)))
    P_peak = abs(beta2) / (gamma * T0^2)
    P_cont = P_peak * pulse_fwhm * pulse_rep_rate / 0.881374
    L_D = T0^2 / abs(beta2)
    z_soliton = (pi / 2) * L_D

    uω0, fiber, sim, _, _, _ = setup_raman_problem(
        Nt=VERIF_NT, L_fiber=z_soliton, P_cont=P_cont, time_window=10.0,
        β_order=2, gamma_user=gamma, betas_user=[beta2], fR=1e-15
    )
    fiber_prop = deepcopy(fiber)
    fiber_prop["zsave"] = [0.0, z_soliton]
    sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)

    I_in  = abs2.(sol["ut_z"][1,   :, 1])
    I_out = abs2.(sol["ut_z"][end, :, 1])
    I_in_norm  = I_in  ./ maximum(I_in)
    I_out_norm = I_out ./ maximum(I_out)
    center_mask = I_in_norm .> 0.05
    max_dev = maximum(abs.(I_out_norm[center_mask] .- I_in_norm[center_mask]))

    @info @sprintf("VERIF-01: max_deviation=%.4f (threshold 0.02), P_peak=%.1f W, z_sol=%.4f m",
        max_dev, P_peak, z_soliton)
    @test max_dev < 0.02
end
```

### Pattern 3: VERIF-02 Photon Number Conservation

**What:** Compute `N_ph = sum(abs2.(uω) ./ abs.(ωs .+ ω0)) * Δt` at input and output of forward propagation. Assert <1% drift for each of the 5 FIBER_PRESETS.

**Critical detail:** Use `ωs + ω0` (absolute angular frequency, not offset) as denominator to avoid singularity at ω=0. `ωs` is the offset frequency grid from `sim["ωs"]`; `ω0 = sim["ω0"]` is the carrier angular frequency (THz-scale).

**Source:** FEATURES.md §Photon Number Conservation; CONTEXT.md §Specifics.

**Example:**
```julia
# Source: .planning/research/FEATURES.md — Photon Number Conservation section
function compute_photon_number(uω, sim)
    ωs = sim["ωs"]         # offset angular frequency grid (THz)
    ω0 = sim["ω0"]         # carrier angular frequency (THz)
    Δt = sim["Δt"]         # time step (ps)
    abs_ω = abs.(ωs .+ ω0) # avoid singularity at ω=0
    return sum(abs2.(uω) ./ abs_ω) * Δt
end

for (preset_name, L_fiber, P_cont, time_window) in PRODUCTION_CONFIGS
    uω0, fiber, sim, _, _, _ = setup_raman_problem(
        Nt=VERIF_NT, L_fiber=L_fiber, P_cont=P_cont, time_window=time_window,
        fiber_preset=preset_name
    )
    fiber_prop = deepcopy(fiber); fiber_prop["zsave"] = [fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)
    uωf = sol["uω_z"][end, :, :]

    N_ph_in  = compute_photon_number(uω0, sim)
    N_ph_out = compute_photon_number(uωf, sim)
    drift = abs(N_ph_out / N_ph_in - 1.0)

    @info @sprintf("VERIF-02 [%s]: N_ph_in=%.4e, N_ph_out=%.4e, drift=%.4f%%",
        preset_name, N_ph_in, N_ph_out, drift * 100)
    @test drift < 0.01  # <1%
end
```

### Pattern 4: VERIF-03 Taylor Remainder at Production Grid

**What:** Identical logic to existing test (lines 688-723 of `test_optimization.jl`) but at `Nt=2^14`. Use 6 epsilon points to produce a cleaner log-log plot. Assert slope in range 1.4–2.6 for at least 3 consecutive pairs.

**Known result at Nt=2^8:** slopes 2.00 and 2.04 — physics is already correct; the upgrade to Nt=2^14 primarily confirms that the production-grid adjoint has the same order.

**Note on epsilon range:** At Nt=2^14, machine precision effects appear at smaller epsilon. The existing range `[1e-1, 1e-2, 1e-3, 1e-4]` is appropriate. The 4th point (1e-4) may enter the noise floor at large Nt; the slope check should use only the first 3 pairs (1e-1→1e-2, 1e-2→1e-3) to match the existing test strategy.

### Pattern 5: VERIF-04 Cost Cross-Check

**What:** After any forward propagation, compute J both via `spectral_band_cost` and via direct computation. Assert they match to machine precision (atol=1e-12).

**Example:**
```julia
# Source: scripts/common.jl lines 61-77 (spectral_band_cost implementation)
@testset "VERIF-04: spectral_band_cost matches direct integration" begin
    uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(
        Nt=VERIF_NT, L_fiber=1.0, P_cont=0.05, time_window=10.0,
        fiber_preset=:SMF28
    )
    fiber_prop = deepcopy(fiber); fiber_prop["zsave"] = [fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)
    uωf = sol["uω_z"][end, :, :]

    J_func, _ = spectral_band_cost(uωf, band_mask)
    E_band   = sum(abs2.(uωf[band_mask, :]))
    E_total  = sum(abs2.(uωf))
    J_direct = E_band / E_total

    @info @sprintf("VERIF-04: J_func=%.6e, J_direct=%.6e, diff=%.2e",
        J_func, J_direct, abs(J_func - J_direct))
    @test J_func ≈ J_direct atol=1e-12
end
```

### Pattern 6: Markdown Report Generation

**What:** After all `@testset` blocks complete, write a structured markdown report to `results/raman/validation/verification_DATE.md`. This fulfills the "human-readable report" criterion in the phase success criteria.

**Example:**
```julia
function write_verification_report(results, output_dir)
    mkpath(output_dir)
    date_str = Dates.format(now(), "yyyymmdd_HHMMSS")
    path = joinpath(output_dir, "verification_$(date_str).md")
    open(path, "w") do io
        println(io, "# Correctness Verification Report")
        println(io, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
        println(io, "**Grid:** Nt=2^14 (production fidelity)")
        println(io, "")
        println(io, "## Results")
        println(io, "")
        println(io, "| Check | Status | Evidence |")
        println(io, "|-------|--------|----------|")
        for r in results
            status = r.passed ? "PASS" : "FAIL"
            println(io, "| $(r.name) | $(status) | $(r.evidence) |")
        end
    end
    @info "Verification report written to $path"
    return path
end
```

### Anti-Patterns to Avoid

- **Using J (normalized cost) as a conservation metric:** `spectral_band_cost` returns `E_band / E_total` — it cannot detect absolute energy loss. Use `sum(abs2.(uωf))` vs `sum(abs2.(uω0))` directly (Pitfall 1 from PITFALLS.md).
- **Gradient check in dB units:** `optimize_spectral_phase` logs J in dB but the gradient is w.r.t. linear J. The FD check must use the same linear J as `cost_and_gradient` returns (Pitfall 5 from PITFALLS.md).
- **Forgetting deepcopy(fiber) before setting zsave:** Mutating fiber["zsave"] in-place corrupts subsequent uses of the same Dict. The existing TDD log (RED 11) documents this bug was fixed with `deepcopy`.
- **Running verification at Nt=2^8-2^9 only:** Decision D-02 locks Nt=2^14 for verification.jl. Smaller grids change attenuator shape, hRω wrapping, and band_mask bandwidth, potentially masking bugs.
- **Asserting `sum(band_mask)` is constant across test configs:** band_mask width depends on `time_window` / `Nt`. For VERIF-04, use the exact `band_mask` returned by `setup_raman_problem` for that config; do not assume a fixed number of masked bins.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Forward ODE integration | Custom Runge-Kutta | `MultiModeNoise.solve_disp_mmf` | The solver under test must be the production solver |
| Adjoint backward integration | Custom adjoint | `MultiModeNoise.solve_adjoint_disp_mmf` | The adjoint under test must be the production adjoint |
| FWHM measurement | Custom peak-finding | `measure_fwhm()` from `test_optimization.jl` (lines 89-96) | Already implemented and tested |
| Significant spectral indices | Custom power threshold | `significant_spectral_indices()` from `test_optimization.jl` (lines 98-102) | Already implemented |
| Fiber parameter construction | Repeat setup code | `setup_raman_problem` from `common.jl` | Single source of truth; handles attenuator, hRω, band_mask |
| Test structure | Custom PASS/FAIL flags | `@testset` / `@test` from `Test` stdlib | Gives automatic pass counts, exit codes, timing |

**Key insight:** `verification.jl` is a consumer of the existing stack, not a reimplementation. It calls the same production functions with larger grids and tighter tolerances.

---

## Common Pitfalls

### Pitfall 1: Photon Number Singularity at ω=0

**What goes wrong:** Computing `sum(abs2.(uω) ./ abs.(ωs))` where `ωs` is the offset frequency grid from `sim["ωs"]`. This grid contains ω=0 at the DC bin (or near-zero bins for odd Nt), causing division by zero or a very large spurious contribution.

**Why it happens:** The `fftfreq` grid is zero-centered after fftshift; bin 0 is literally 0 THz.

**How to avoid:** Use `abs.(ωs .+ ω0)` where `ω0 = sim["ω0"]` is the carrier frequency (~1216 THz at 1550 nm). This shifts all bins by the carrier, so the minimum value is `ω0 - max(|ωs|)`, which is always positive for physically sensible grids.

**Warning signs:** Photon number values of `Inf` or `NaN`, or photon number that is orders of magnitude larger than the energy integral.

### Pitfall 2: Tolerance Calibration for Photon Number at Nt=2^14

**What goes wrong:** Setting a 1% tolerance without empirical calibration. The existing energy conservation test reports max deviation of 2.32e-5 (0.002%), but this is energy, not photon number. Photon number drift can be different (STATE.md pending todo: "Empirically calibrate photon number conservation tolerance on one real SMF-28 L=1m run before setting hard assertion threshold").

**Why it happens:** Photon number involves 1/ω weighting which amplifies errors from low-frequency spectral components. At high Raman shift levels (Run 2: SMF-28 L=2m, J_before=0.71), significant energy moves to low frequencies, increasing the weighting of potential numerical errors.

**How to avoid:** Run VERIF-02 on the SMF-28 L=1m config first, print the drift value, then proceed. If drift exceeds 1%, investigate before hardening the threshold. The 1% tolerance from the FEATURES.md research is a starting target, not a guaranteed result.

**Warning signs:** Drift values of 0.3-0.8% suggesting the 1% threshold is barely met; investigate hRω wrapping (run `check_boundary_conditions`) before concluding the solver is deficient.

### Pitfall 3: Wrong uωf Extraction for Photon Number

**What goes wrong:** Using `sol["uω_z"][end, :, :]` which is the field stored at the last `zsave` point. But if `fiber_prop["zsave"]` includes intermediate points, the "end" index may not be the actual fiber output at z=L.

**Why it happens:** The `uω_z` array has shape `(n_z_saved, Nt, M)`. If `zsave = [0.0, L/2, L]`, then `end` is the third slice (z=L), which is correct. But if `zsave = [L]` only, `end` is also correct. The issue only arises if someone passes `zsave = LinRange(0, L, N)` and forgets the last point is at z=L.

**How to avoid:** Always verify `sol["z_saved"][end] ≈ fiber["L"]` before extracting the output field. Use `fiber_prop["zsave"] = [fiber["L"]]` for simple input/output photon number comparisons.

### Pitfall 4: Gradient Check Unit Mismatch (dB vs Linear)

**What goes wrong:** The optimization callback logs J in dB but `cost_and_gradient` returns gradient w.r.t. linear J. A FD check that perturbs phi and evaluates `lin_to_dB(J)` instead of `J` directly will show wrong slopes.

**Prevention:** The Taylor remainder test in `verification.jl` must call `cost_and_gradient` directly, not `optimize_spectral_phase`. The gradient is `∂J_linear/∂φ`. This matches exactly how the existing test at lines 688-723 is structured — do not deviate.

### Pitfall 5: time_window Mismatch Across FIBER_PRESETS for VERIF-02

**What goes wrong:** Different fiber configs in `FIBER_PRESETS` use different `time_window` values in the production runs (e.g., L=1m uses 10ps, L=2m uses 20ps from the run log). If the photon number check uses a fixed `time_window` across all configs, the Raman response `hRω` and attenuator shape change, making configs physically non-identical to their production runs.

**How to avoid:** Use the same `time_window` as the production runs for each config:
- Run 1 (SMF28, L=1m, P=0.05W): `time_window=10.0`
- Run 2 (SMF28, L=2m, P=0.30W): `time_window=20.0`
- Runs 3-5 (HNLF variants): use `recommended_time_window()` or the values logged in `raman_run_20260324_v7.log`

---

## Code Examples

Verified patterns from official sources (codebase audit):

### Production Config Table for VERIF-02

From `results/raman/raman_run_20260324_v7.log` (production run log):

```julia
# Source: results/raman/raman_run_20260324_v7.log — observed production configs
const PRODUCTION_CONFIGS = [
    # (preset_sym, L_fiber, P_cont, time_window)
    (:SMF28, 1.0, 0.05, 10.0),    # Run 1: SMF-28, L=1m, P=0.05W — Nt=8192, tw=10ps
    (:SMF28, 2.0, 0.30, 20.0),    # Run 2: SMF-28, L=2m, P=0.30W — Nt=8192, tw=20ps
    (:HNLF,  1.0, 0.05, 10.0),    # Run 3: HNLF, L=1m, P=0.05W
    # Runs 4 and 5 need to be confirmed from raman_optimization.jl source
]
```

Note: Confirm the exact time_window for runs 4-5 by reading `scripts/raman_optimization.jl` run definitions before implementing VERIF-02.

### Photon Number Conservation Formula

```julia
# Source: .planning/research/FEATURES.md §Photon Number Conservation
# Physics: Brabec & Krausz 2000; Agrawal NFF 6th ed. §2.3
function compute_photon_number(uω, sim)
    ωs = sim["ωs"]         # offset angular frequency in THz (after fftshift)
    ω0 = sim["ω0"]         # carrier angular frequency in THz
    Δt = sim["Δt"]         # time step in ps
    # Use carrier-offset frequency to avoid singularity at ω=0
    abs_ω = abs.(ωs .+ ω0)
    return sum(abs2.(uω) ./ abs_ω) * Δt
end
```

### Taylor Remainder Test (Production Grid Version)

```julia
# Source: scripts/test_optimization.jl lines 688-723 (adapted for VERIF_NT=2^14)
function run_taylor_remainder_test(Nt)
    uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(
        Nt=Nt, L_fiber=0.5, P_cont=0.05, time_window=10.0,
        fiber_preset=:SMF28
    )
    φ0 = 0.1 .* randn(Nt, 1)
    J0, grad = cost_and_gradient(φ0, uω0, fiber, sim, band_mask)
    δφ = randn(Nt, 1); δφ ./= norm(δφ)
    directional_deriv = dot(vec(grad), vec(δφ))

    epsilons = [1e-1, 1e-2, 1e-3, 1e-4]
    r2 = Float64[]
    for ε in epsilons
        Jε, _ = cost_and_gradient(φ0 .+ ε .* δφ, uω0, fiber, sim, band_mask)
        push!(r2, abs(Jε - J0 - ε * directional_deriv))
    end

    slopes = [log10(r2[i] / r2[i+1]) for i in 1:length(epsilons)-1]
    return epsilons, r2, slopes
end
```

### Include Guard Pattern for verification.jl

```julia
# Source: scripts/common.jl lines 21-22 (include guard pattern)
# verification.jl does not need an include guard (it is a script, not a library)
# but it follows the same include chain:
include("common.jl")          # provides setup_raman_problem, FIBER_PRESETS, spectral_band_cost
include("raman_optimization.jl")  # provides cost_and_gradient
# Note: raman_optimization.jl includes common.jl, but common.jl has _COMMON_JL_LOADED guard
```

### Deepcopy Pattern for Forward Solve

```julia
# Source: scripts/test_optimization.jl line 533, 654 (documented deepcopy pattern)
# CRITICAL: always deepcopy before setting fiber["zsave"] to prevent dict mutation
fiber_prop = deepcopy(fiber)
fiber_prop["zsave"] = [0.0, fiber["L"]]
sol = MultiModeNoise.solve_disp_mmf(uω0, fiber_prop, sim)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Energy conservation only (`E_out/E_in`) | Photon number conservation (`∫|U|²/ω dω`) | v2.0 Phase 4 (new) | Physically correct invariant for GNLSE with self-steepening; energy drifts more |
| 5-index FD gradient check only | Taylor remainder test + FD check | Phase 4 upgrade (stronger assertion at Nt=2^14) | Proves adjoint is O(ε²) correct, not just approximately close |
| 10% soliton shape tolerance (fast CI) | 2% soliton shape tolerance (production grid) | Phase 4 upgrade | Production-fidelity verification; smaller grids masked the real error level |

**Deprecated/outdated:**
- Norm-based shape error (`norm(I_out - I_in)/norm(I_in)`) for soliton test: existing test uses this at lines 669-670. The 2% criterion is max-deviation-based (`maximum(abs.(...))`), which is more physically interpretable. The norm ratio is still a valid secondary metric but should not be the primary threshold.

---

## Open Questions

1. **Production configs for runs 4 and 5 (HNLF variants)**
   - What we know: Run 3 is HNLF L=1m P=0.05W (from log). FIBER_PRESETS has `:HNLF` and `:HNLF_zero_disp`. The production run script has 5 configs.
   - What's unclear: The exact (L, P, time_window) for runs 4 and 5 — must be read from `scripts/raman_optimization.jl` run definitions before implementing VERIF-02.
   - Recommendation: Read `raman_optimization.jl` lines 200-300 (where run configs are defined) during implementation of VERIF-02.

2. **Empirical photon number drift at Nt=2^14 for production configs**
   - What we know: Energy conservation at Nt=8192 (Nt=2^13) is 2.32e-5 (0.002%). Photon number drift expected <1% per FEATURES.md research.
   - What's unclear: Whether self-steepening or Raman convolution at high power (Run 2: J_before=0.71 indicating heavy Raman) pushes drift above 1%.
   - Recommendation: Run VERIF-02 on SMF28 L=1m first, report the empirical drift, then proceed. The STATE.md pending todo explicitly flags this calibration step.

3. **Report format — console @info vs markdown file**
   - What we know: Decision grants Claude full discretion (D-01 rationale). The success criterion requires "human-readable report in `results/raman/validation/`". The validation directory already exists with a previous log.
   - Recommendation: Write BOTH — `@info` console output for live feedback during script execution, and a structured markdown file for archival. The markdown file should have one row per test with PASS/FAIL and the key numeric value (shape error, drift %, slope, delta J).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Julia | All tests | ✓ | 1.12.4 (Manifest.toml) | — |
| MultiModeNoise (local pkg) | All tests | ✓ | 1.0.0-DEV | — |
| Test (stdlib) | @testset | ✓ | bundled | — |
| FFTW.jl | photon number grid | ✓ | in Project.toml | — |
| `results/raman/validation/` dir | Report output | ✓ | exists | `mkpath()` will create it |
| `scripts/common.jl` | setup_raman_problem | ✓ | exists | — |
| `scripts/raman_optimization.jl` | cost_and_gradient | ✓ | exists | — |

No missing dependencies. Phase 4 is code-only; no new packages required.

---

## Project Constraints (from CLAUDE.md)

The following directives from `CLAUDE.md` apply directly to Phase 4 implementation:

- **Tech stack locked:** Must stay in Julia + PyPlot (matplotlib). No new visualization dependencies. `verification.jl` may write PNG plots (Taylor remainder log-log) using PyPlot if desired, but it is not required.
- **Function naming:** `snake_case` for all functions; `!` suffix for mutating helpers; `_` prefix for private helpers. The verification script's helper functions should follow this: `compute_photon_number`, `_extract_output_field`, `write_verification_report`.
- **No formatter:** No JuliaFormatter; 4-space indentation, no enforced line length.
- **Include guards:** `verification.jl` is a script (not a library), so no include guard needed. But it must use `include("common.jl")` and `include("raman_optimization.jl")` — common.jl is guarded and safe to include multiple times.
- **Section headers:** Use `# ═══...═══` for major sections, `# ───...───` for subsections within functions (established project style).
- **Box-drawing summaries:** Run summaries use `┌──┤`, `│`, `└──┘` characters for visual distinction in `@info` logs.
- **Design-by-contract:** Use `@assert` for preconditions, `@assert` for postconditions. Add `# PRECONDITIONS` / `# POSTCONDITIONS` comment headers in helper functions.
- **`deepcopy(fiber)` before mutating `fiber["zsave"]`:** Documented pattern from TDD cycle; failure here was a real bug (RED 11 in TDD log). Every forward solve in `verification.jl` must follow this pattern.
- **`abspath(PROGRAM_FILE) == @__FILE__` guard:** Not needed for `verification.jl` since it is a dedicated verification script (not included by others), but it should NOT be included by `test_optimization.jl` or `raman_optimization.jl`.
- **GSD workflow enforcement:** Phase 4 work must proceed through GSD execute-phase, not direct repo edits.
- **Comments explain WHY, not WHAT:** Physics comments should reference the physical invariant (e.g., `# Photon number is the correct invariant for GNLSE with self-steepening, not energy (Agrawal NFF §2.3)`).

---

## Sources

### Primary (HIGH confidence)

- Direct codebase audit: `scripts/test_optimization.jl` lines 517-754 — existing soliton test (1.3% error at Nt=2^9), Taylor remainder test (slopes 2.00/2.04), full FD check (0.026% max error)
- Direct codebase audit: `results/raman/validation/test_output_20260324.log` — confirmed all existing tests PASS with numeric evidence
- Direct codebase audit: `scripts/common.jl` lines 1-77 — `spectral_band_cost` implementation, `FIBER_PRESETS` dictionary (4 presets: `:SMF28`, `:SMF28_beta2_only`, `:HNLF`, `:HNLF_zero_disp`)
- Direct codebase audit: `results/raman/MATHEMATICAL_FORMULATION.md` — analytical derivation of cost functional, adjoint terminal condition, gradient chain rule, and characteristic length scales
- Direct codebase audit: `results/raman/raman_run_20260324_v7.log` — production run parameters (5 configs, energy conservation 7.9e-5 to 2.3e-3)
- `.planning/research/FEATURES.md` — photon number conservation formula, Taylor remainder protocol, verification method details
- `.planning/research/PITFALLS.md` — normalized cost masking conservation failure (Pitfall 1), dB vs linear gradient confusion (Pitfall 5)
- `.planning/phases/04-correctness-verification/04-CONTEXT.md` — locked decisions D-01 through D-04

### Secondary (MEDIUM confidence)

- Agrawal, "Nonlinear Fiber Optics" 6th ed. Ch. 2-5 — photon number conservation in GNLSE with self-steepening; soliton N=1 propagation conditions (cited in FEATURES.md with HIGH confidence attribution)
- Steven G. Johnson MIT 18.336 adjoint notes — Taylor remainder as standard gradient verification (cited in FEATURES.md)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already in Project.toml; no uncertainty
- Architecture: HIGH — `test_optimization.jl` existing structure verified by direct read; patterns are established project conventions
- Soliton test (VERIF-01): HIGH — existing test already passes at 1.3% error; upgrade to 2% threshold at Nt=2^14 is a straightforward parameter change
- Photon number (VERIF-02): MEDIUM — formula verified; empirical tolerance calibration at Nt=2^14 is flagged as a pending todo in STATE.md; the 1% threshold is a research-grade target not yet validated at production grid
- Taylor remainder (VERIF-03): HIGH — existing test achieves slope 2.00/2.04 at Nt=2^8; production grid upgrade is straightforward
- Cost cross-check (VERIF-04): HIGH — five-line calculation; machine precision match is expected by construction
- Report generation: HIGH — standard Julia file I/O; `mkpath` and `open(path, "w")` are standard patterns

**Research date:** 2026-03-25
**Valid until:** 2026-06-25 (stable project; no dependency churn expected)
