# Feature Research: v2.0 Verification & Discovery

**Domain:** Correctness verification, cross-run comparison, parameter sweeps, and pattern detection for nonlinear fiber optics simulation and Raman suppression optimization
**Researched:** 2026-03-25
**Confidence:** HIGH for verification methods (established practice), MEDIUM for pattern detection (domain-specific, fewer references), LOW for automated pattern detection (novel/custom territory)

---

## Context: What Already Exists

Before mapping the feature landscape, the following capabilities are already built and should not be rebuilt:

| Already Built | Location |
|---------------|----------|
| Gradient FD check (5 random indices, 1% tolerance) | `test_optimization.jl` (lines 335–357) |
| Gradient FD check for amplitude (3 trials, 5% tolerance) | `test_optimization.jl` (lines 359–384) |
| Energy conservation check (5% tolerance, single forward pass) | `test_optimization.jl` (line 404–412) |
| Boundary energy detection (5% edge threshold) | `benchmark_optimization.jl`, `common.jl` |
| Time window sensitivity analysis (6 window sizes) | `benchmark_optimization.jl` `analyze_time_windows` |
| Chirp sensitivity (GDD and TOD sweeps, 2D sensitivity plot) | `raman_optimization.jl` `chirp_sensitivity` |
| Grid size benchmarking (Nt scaling table) | `benchmark_optimization.jl` `benchmark_grid_sizes` |
| Contract violation tests for all setup functions | `test_optimization.jl` |
| Single-run convergence plot (J vs iteration) | `visualization.jl` |
| Design-by-contract assertions throughout cost pipeline | `raman_optimization.jl`, `common.jl` |

Features below are what is **missing** for v2.0.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features the research group expects a "verified and correct" simulation to demonstrate. Missing these means the pipeline is not trustworthy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Fundamental soliton propagation test (N=1 sech pulse) | Standard NLSE correctness benchmark — N=1 sech pulse propagates without shape change over soliton period; any deviation is numerical error | MEDIUM | Requires choosing β₂ < 0 (anomalous dispersion), γ, and T₀ such that N=1; propagate one z_sol and compare input to output shape; currently no such test |
| Photon number conservation check | Energy is technically not conserved in GNLSE with self-steepening and Raman; photon number is; tracking it flags unphysical results (known issue from IEEE 2021) | MEDIUM | Compute ∫|U(ω)|²/ω dω at input and output; expect <1% drift for typical SMF-28 runs; currently only energy (which drifts more) is checked |
| Adjoint gradient full-grid FD check with Taylor remainder test | Current FD check uses 5 random indices; Taylor remainder (confirm O(ε²) convergence) is stronger — proves the adjoint is correct not just close | MEDIUM | Plot ‖J(φ+εd) - J(φ) - ε⟨∇J,d⟩‖ vs ε; expect slope 2 on log-log; currently not done |
| Cost J verified to match spectral energy ratio by direct integration | J = E_Raman/E_total; should verify the mask computation is correct by computing J both via spectral_band_cost and via direct sum and checking they agree | LOW | Simple direct-computation cross-check; catches mask index bugs |
| Cross-run J summary table (all 5 configs) | After running all 5 optimization configs, need a summary showing J_before, J_after, ΔdB, convergence iterations, wall time in one table | LOW | Currently this information is printed per-run but never aggregated; a researcher reviewing results needs the full table to understand relative performance |
| Overlay convergence plot (all runs on one axes) | Convergence curves from all 5 runs overlaid; shows whether SMF-28 converges faster than HNLF, whether longer fibers need more iterations | MEDIUM | Currently one convergence plot per run; need multi-run overlay in a single figure |
| Overlay spectral comparison (all runs, before vs after) | One panel per fiber type showing all optimized spectra together; reveals which fiber/power combos suppress most | MEDIUM | Currently separate figures per run; no cross-run spectral overlay exists |
| Per-run metadata saved to structured file (not just logs) | JSON/CSV record of {fiber_type, L, P, J_before, J_after, iterations, wall_time, phase_norm} per run | LOW | Enables downstream analysis and plotting; currently only printed to stdout/log |

### Differentiators (Competitive Advantage)

Features that elevate this from "the code works" to "the physics is understood."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Phase shape clustering: is the optimal phase quadratic, soliton-like, or irregular? | Researchers need to know if the optimizer finds a physically interpretable solution (e.g., pre-chirp to counteract SPM) or just numerical noise | HIGH | Project each optimized phase profile onto GDD/TOD basis; compute unexplained residual; if residual << total phase, phase is essentially a polynomial chirp and has physical meaning |
| Parameter sweep: J_final vs (L, P) heatmap grid | Shows the landscape of Raman suppression achievability — is HNLF at 1m x 100W very suppressible? Is SMF-28 at 5m x 200W suppression-limited? | HIGH | Run optimization over a grid of (L, P) pairs for each fiber; plot J_final as a 2D heatmap; computationally expensive but scientifically essential |
| Soliton number N vs suppression quality correlation | N = L_D/L_NL; higher N means more complex nonlinear dynamics; expect correlation between N and J_before (hard problem) and between N and ΔdB (optimization potential) | MEDIUM | Compute N for each run config; plot N vs J_before and N vs ΔdB; a correlation here validates that the optimizer is exploiting known physics |
| Phase shape universality test: do SMF-28 and HNLF at matched N produce similar phase profiles? | If optimal phase shape depends only on N (not fiber parameters), it suggests a universal strategy independent of fiber type | HIGH | Requires designing matched-N runs, then comparing normalized phase profiles; computationally expensive |
| Optimization sensitivity to initial phase (multi-start test) | Show that L-BFGS converges to the same basin from multiple random starts, establishing that the optimization landscape has a well-defined minimum | MEDIUM | Run 5–10 random initial phases; plot all convergence curves and final J values; if variance < 0.5 dB across starts, the minimum is robust. `benchmark_optimization.jl` has `multi_start_optimization` but it's not integrated into the standard run pipeline |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automatic differentiation (AD) to verify adjoint | Seems like a clean replacement for hand-derived adjoint | Julia AD (Zygote/Enzyme) struggles with DifferentialEquations.jl callbacks, pre-allocated buffers, and in-place mutations; would require major refactor with no physics insight gain | Keep the hand-derived adjoint verified by finite differences + Taylor remainder; this is exact and explainable |
| Full parameter grid with dense sampling (e.g., 20×20 L×P) | "More points = better coverage" | Each (L,P) point requires a full optimization run (~50 L-BFGS iterations × forward + adjoint solve); at 50s/run, a 20×20 grid = 55 CPU-hours; wall time on a workstation would be days | Use a coarse 4×4 or 5×4 grid first to find regions of interest, then refine selectively |
| Comparing against other simulators (PyNLO, Luna.jl) | Validates that the simulation is correct | Cross-simulator comparison requires matching all physical parameters, ODE solver tolerances, and interaction-picture conventions exactly; differences often reflect solver configuration, not physics errors; creates maintenance burden | Use analytical solutions (fundamental soliton, photon number) and internal consistency checks instead |
| Automated ML-based pattern detection | Pattern detection over many runs sounds like a differentiator | The current 5 runs are not enough data for clustering or ML methods; PCA on 5 vectors is meaningless; would need 50+ runs | Manual physical projection (GDD, TOD basis decomposition) gives more insight with less data and is directly interpretable |
| Interactive dashboard (web-based or notebook) | Useful for exploratory analysis | PROJECT.md explicitly rules out interactive plots; static PNG/PDF output is the constraint; Jupyter notebooks exist but are not the primary workflow | Well-structured static summary figure that shows all runs together |

---

## Feature Dependencies

```
[Metadata file per run]
    └──required by──> [Cross-run J summary table]
    └──required by──> [Overlay convergence plot]
    └──required by──> [Overlay spectral comparison]
    └──required by──> [Parameter sweep heatmap]
    └──required by──> [Soliton number correlation plot]

[Fundamental soliton test]
    └──validates──> [Photon number conservation check]
    (must pass before trusting photon-number as a metric)

[Taylor remainder gradient test]
    └──supersedes──> existing 5-index FD check
    (does not remove it; adds a stronger assertion on top)

[Parameter sweep L×P grid]
    └──requires──> [Metadata file per run]
    └──enhances──> [Soliton number correlation]
    (sweep generates the data; correlation uses it)

[Phase shape clustering]
    └──requires──> [Metadata file per run]
    (need per-run phase vectors saved, not just J values)
```

### Dependency Notes

- **Metadata file is the prerequisite for everything cross-run:** Every aggregation feature (summary table, convergence overlay, spectral overlay, scatter plots) requires that per-run outputs are written to a structured file, not just printed. This is the single most important infrastructure feature.
- **Fundamental soliton test validates the forward solver before any gradient work:** Run this first in the verification sequence. If the forward solver is wrong, all gradient and optimization tests are suspect.
- **Taylor remainder test is independent** of the soliton test and can run in parallel. It tests the adjoint pipeline, not the ODE propagator.
- **Parameter sweep is computationally expensive** and should only run after the verification tests pass, to avoid running a long sweep with a buggy solver.

---

## MVP Definition

This milestone is a research milestone, not a software product milestone. The MVP is: "I can trust the results and see patterns across runs."

### Launch With (v2.0 core)

These are needed to close the milestone and present results at a lab meeting.

- [ ] **Fundamental soliton propagation test** — without this, the NLSE solver has no known-ground-truth validation
- [ ] **Photon number conservation check** — energy conservation already passes at 5%; photon number is the physically correct invariant for GNLSE with self-steepening + Raman
- [ ] **Taylor remainder gradient test** — stronger than existing FD check; proves adjoint is correct to O(ε²)
- [ ] **Per-run metadata JSON output** — infrastructure prerequisite for all cross-run features
- [ ] **Cross-run J summary table** — human-readable table showing all 5 configs' J_before, J_after, ΔdB, wall time
- [ ] **Overlay convergence plot (all 5 runs)** — single figure showing convergence curves; immediately reveals relative optimization difficulty

### Add After Core Passes (v2.0 extended)

Add once verification passes and core infrastructure is in place.

- [ ] **Overlay spectral comparison** — after core J summary is working, add spectral overlays per fiber type
- [ ] **Phase projection onto GDD/TOD basis** — compute how much of the optimal phase is explainable as a polynomial chirp; report residual
- [ ] **Soliton number N annotation in metadata and summary** — annotate each run with N = sqrt(L_D/L_NL); enables correlation plots without re-running

### Future Consideration (v2.0+, separate planning)

Deferred because computationally expensive or require more runs to be meaningful.

- [ ] **Parameter sweep L×P heatmap** — expensive; requires dedicated compute session; plan separately
- [ ] **Phase universality test at matched N** — requires custom run configs beyond current 5; needs dedicated design
- [ ] **Multi-start robustness analysis** — `multi_start_optimization` exists in `benchmark_optimization.jl` but is not wired to the standard pipeline; activate separately

---

## Feature Prioritization Matrix

| Feature | Research Value | Implementation Cost | Priority |
|---------|----------------|---------------------|----------|
| Fundamental soliton N=1 propagation test | HIGH — ground truth for solver | MEDIUM | P1 |
| Photon number conservation | HIGH — physically correct invariant | MEDIUM | P1 |
| Taylor remainder gradient test | HIGH — proves adjoint correctness | MEDIUM | P1 |
| Per-run metadata JSON | HIGH — enables all cross-run analysis | LOW | P1 |
| Cross-run J summary table | HIGH — lab meeting deliverable | LOW (depends on metadata) | P1 |
| Overlay convergence plot | HIGH — shows optimization landscape | MEDIUM | P1 |
| Overlay spectral comparison | MEDIUM — visual; summary table covers the numbers | MEDIUM | P2 |
| Phase GDD/TOD projection | MEDIUM — physical insight | MEDIUM | P2 |
| Soliton number N annotation | MEDIUM — links physics to optimization | LOW | P2 |
| Parameter sweep L×P heatmap | HIGH eventually — but expensive | HIGH | P3 |
| Phase universality test | HIGH scientifically — but needs design | HIGH | P3 |
| Multi-start robustness | MEDIUM — confidence in optimizer | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v2.0 lab meeting presentation
- P2: Should have, add when P1 is complete
- P3: Future milestone or dedicated compute session

---

## Verification Method Details

### Fundamental Soliton Test

**Physical basis:** For the NLSE without Raman or self-steepening, a hyperbolic secant pulse with
```
N = sqrt(γ P₀ T₀² / |β₂|) = 1
```
is an exact soliton solution. It propagates without shape change over distance z_sol = π/2 · L_D where L_D = T₀²/|β₂|.

**Test protocol:**
1. Use SMF28_beta2_only preset (β₂ only, no β₃, no Raman: fR=0 for this test)
2. Choose T₀ such that N=1 at P_peak (e.g., T₀ = sqrt(γ P₀ / |β₂|))
3. Propagate exactly one soliton period z_sol
4. Compare temporal intensity profile |u(t,z_sol)|² to input |u(t,0)|²
5. Expect: max relative error < 2% for Nt=2^12, time_window > 10×T₀

**Why this catches real bugs:** This test fails if the interaction-picture phase factors (exp_D_p, exp_D_m) are wrong, if the step size is too large, or if FFT normalization is wrong. It cannot fail due to Raman or self-steepening complications.

**Confidence:** HIGH — fundamental soliton is a textbook result (Agrawal, Nonlinear Fiber Optics, Ch.5; gnlse-python validates against this exact test)

### Photon Number Conservation

**Physical basis:** The GNLSE with frequency-dependent nonlinearity (self-steepening) conserves photon number N_ph = ∫|U(ω)|²/ω dω, not energy. Using energy as the conservation test underestimates numerical errors for pulses where self-steepening is significant.

**Test protocol:**
1. Compute N_ph_in = sum(abs2.(uω0) ./ abs.(sim["ωs"] .+ sim["ω0"])) * sim["Δt"]
2. Run forward propagation
3. Compute N_ph_out = sum(abs2.(uωf) ./ abs.(ωs .+ ω0)) * Δt
4. Assert |N_ph_out / N_ph_in - 1| < 0.01 (1% tolerance)

**Confidence:** MEDIUM — photon number conservation in GNLSE is well-established theory (IEEE JLT 2021, Agrawal review 2024), but the tolerance (1% vs 5%) needs empirical calibration on current runs

### Taylor Remainder Test

**Physical basis:** If ∇J is the correct gradient, then J(φ + εd) - J(φ) - ε⟨∇J, d⟩ = O(ε²). Plotting this residual vs ε on a log-log scale should show slope 2 for the second-order term.

**Test protocol:**
1. Pick a random direction d (unit vector in φ-space)
2. Compute J(φ), ∇J at a fixed φ
3. For ε in [1e-6, 1e-2]: compute |J(φ + εd) - J(φ) - ε⟨∇J, d⟩|
4. Assert slope ≈ 2 in the log-log plot for the range ε ∈ [1e-5, 1e-3] (below machine epsilon effects, above truncation effects)
5. This is strictly stronger than the existing 5-index FD check, which only verifies approximate agreement at one ε value

**Expected gradient accuracy:** The current 1% FD tolerance passes with ε=1e-5. The Taylor test with slope 2 proves the adjoint is exact (not just close) to machine precision.

**Confidence:** HIGH — Taylor remainder test is standard PDE-constrained optimization verification practice (Stevens Johnson MIT 18.336 notes; Meep project documentation)

### Cross-Run Metadata JSON Schema

Each run should write a JSON file with this structure:

```json
{
  "run_tag": "RUN_20260325_v7_smf28_L2m",
  "fiber_type": "SMF-28",
  "fiber_preset": "SMF28",
  "L_fiber": 2.0,
  "P_cont": 30.0,
  "lambda0_nm": 1550.0,
  "pulse_fwhm_fs": 185.0,
  "Nt": 16384,
  "time_window_ps": 20.0,
  "soliton_number_N": 2.34,
  "J_before": 0.0234,
  "J_before_dB": -16.3,
  "J_after": 0.0012,
  "J_after_dB": -29.2,
  "delta_dB": -12.9,
  "n_iterations": 47,
  "wall_time_s": 83.2,
  "phase_norm_rad": 4.71,
  "phase_gdd_component_frac": 0.82,
  "convergence_history": [0.0234, 0.019, 0.012, ...]
}
```

This requires adding a metadata-write step at the end of each `run_optimization()` call. The `convergence_history` array enables the overlay convergence plot without re-running.

---

## Sources

- Agrawal, "Nonlinear Fiber Optics," 6th ed. — soliton N=1 propagation, photon number conservation, standard benchmark setups
- Dudley, Genty, Coen. Rev. Mod. Phys. 78, 1135 (2006) — canonical supercontinuum verification benchmark; soliton fission test cases
- gnlse-python (WUST-FOG): [github.com/WUST-FOG/gnlse-python](https://github.com/WUST-FOG/gnlse-python) — example_soliton.html shows soliton test structure; test_nonlinearity.py and test_raman.py show N=3 soliton fission benchmarks
- Luna.jl: [github.com/LupoLab/Luna.jl](https://github.com/LupoLab/Luna.jl) — validates against Dudley 2006 Fig. 3; reference for GNLSE benchmark parameters
- IEEE JLT 2021, "Revisiting Soliton Dynamics Under Strict Photon-Number Conservation": [ieeexplore.ieee.org/document/9309249](https://ieeexplore.ieee.org/document/9309249/) — photon number is the correct invariant for GNLSE with self-steepening; energy alone is insufficient
- Steven G. Johnson, MIT 18.336, "Notes on Adjoint Methods": [math.mit.edu/~stevenj/18.336/adjoint.pdf](https://math.mit.edu/~stevenj/18.336/adjoint.pdf) — Taylor remainder test as standard gradient verification
- cs231n Neural Network notes (Karpathy): gradient check tolerance — relative error > 1e-2 wrong; < 1e-4 ok; step size h=1e-5 typical — [cs231n.github.io](https://cs231n.github.io/neural-networks-3/) — confirmed standard practice
- Meep adjoint gradient inconsistency report: [github.com/NanoComp/meep/issues/1484](https://github.com/NanoComp/meep/issues/1484) — real-world example of adjoint FD discrepancy and how Taylor remainder test pinpoints the source

---

*Feature research for: v2.0 Verification & Discovery, SMF Gain-Noise project*
*Researched: 2026-03-25*
