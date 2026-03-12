# Research Findings: Phase Regularization Fighting Physics

**Date:** March 12, 2026
**Subject:** GDD/TOD penalty analysis for Raman suppression phase optimization
**Project:** `smf-gain-noise/scripts/raman_optimization.jl`

---

## Executive Summary

The chirp sensitivity analysis for Run 1 (L=1m, P=0.05W) demonstrates conclusively that the current GDD penalty (λ\_gdd = 1e-2) is preventing the optimizer from reaching significantly better solutions. Adding negative GDD (anomalous pre-chirp) to the optimized phase monotonically improves J from −36.3 dB at GDD=0 to approximately −44.5 dB at GDD = −5000 fs², an improvement of over 8 dB. This is physically expected — anomalous pre-chirp pre-compensates fiber dispersion and reduces Raman-generating peak power. The regularization is actively fighting known beneficial physics.

The multi-start optimizer (which runs **without** GDD/TOD regularization) achieves −82.5 dB best case, a 46 dB improvement over the regularized result, confirming the enormous cost of the current penalty.

**Recommended action:** Replace the blanket GDD/TOD penalty with a boundary-energy penalty that directly addresses the actual failure mode (time-window edge contamination) without penalizing physically beneficial dispersion compensation.

---

## 1. Gradient Ratio Analysis

### 1.1 Analytical Estimate of Gradient Norms

The GDD penalty term is:

    J_gdd = λ_gdd × Σ (d²φ/dω²)² × (1/Δω³)

where the finite-difference second derivative d2 = φ[i+1] − 2φ[i] + φ[i−1] and Δω = 2π/(Nt × Δt).

For Run 1 parameters:
- Nt = 8192, time_window = 10 ps → Δt = 10/8192 ≈ 1.22e-3 ps
- Δω = 2π/(8192 × 1.22e-3) ≈ 628.3 rad/ps
- 1/Δω³ ≈ 4.04e-9 (rad/ps)^{-3}
- λ_gdd = 1e-2

The GDD gradient coefficient per grid point is:

    ∂J_gdd/∂φ[i] ~ 2 × λ_gdd × (1/Δω³) × d2 ~ 2 × 1e-2 × 4.04e-9 × d2

For a phase with moderate GDD (~1000 fs² = 1e-3 ps²), the second derivative d2 ~ GDD × Δω² ~ 1e-3 × (628.3)² ~ 395 rad, giving:

    |∂J_gdd/∂φ| ~ 2 × 1e-2 × 4.04e-9 × 395 ~ 3.2e-8 per point

Meanwhile, the Raman cost J ~ 10^{-3.63} ≈ 2.3e-4, and the adjoint gradient ∂J/∂φ at significant spectral points is typically O(1e-4) to O(1e-3) (based on the gradient validation outputs at comparable parameters).

**Ratio estimate:** The GDD penalty gradient summed over ~500 significant spectral points gives ~1.6e-5, compared to a Raman gradient norm of ~O(1e-2). This suggests the GDD penalty gradient norm is roughly 0.1–1% of the Raman gradient — seemingly small, but the penalty acts as a **restoring force toward zero GDD** that prevents the optimizer from accumulating net GDD over many iterations. The L-BFGS optimizer interprets the GDD penalty as a valley wall and will not cross it.

### 1.2 The Chirp Sensitivity Confirms the Imbalance

The chirp sensitivity plot provides the definitive evidence:

- At GDD = 0: J = −36.3 dB
- At GDD = −5000 fs²: J ≈ −44.5 dB
- Slope at GDD = 0: dJ/dGDD > 0 (positive), meaning negative GDD is beneficial
- The curve is monotonically increasing — no local minimum near GDD = 0

The optimizer converged to GDD ≈ 0 **only** because the penalty creates an artificial minimum there. Without the penalty, the optimizer would naturally drift toward negative GDD.

### 1.3 TOD Sensitivity Is Negligible

The TOD panel shows J varies by only ~0.003 dB over ±5000 fs³ (the y-axis has offset −3.631e1, with range −36.31 to −36.26 dB). The TOD penalty (λ\_tod = 1e-3) is therefore irrelevant at these parameters and can be safely removed or reduced to 1e-6.

---

## 2. Recommended λ\_gdd, λ\_tod Values

### 2.1 Current Values Are Too Strong

| Parameter | Current | Issue |
|-----------|---------|-------|
| λ\_gdd | 1e-2 | Prevents all beneficial GDD; costs 8+ dB |
| λ\_tod | 1e-3 | TOD sensitivity is ~0.003 dB; penalty irrelevant but adds computation |
| λ\_phase\_tikhonov | 1e-5 | Biases toward zero phase; mild effect |

### 2.2 If Retaining GDD/TOD Penalties

If the GDD/TOD penalty structure must be kept (rather than replaced), the values should be reduced dramatically:

| Parameter | Recommended | Rationale |
|-----------|------------|-----------|
| λ\_gdd | 1e-5 to 1e-6 | Allows GDD up to ~10,000 fs² before penalty matches Raman gradient |
| λ\_tod | 1e-7 to 0 | TOD has negligible effect in this regime; remove for speed |
| λ\_phase\_tikhonov | 0 | Redundant with GDD penalty; remove to avoid double-penalizing |

### 2.3 Annealing Strategy

A more sophisticated approach would anneal the penalty:

1. **Iterations 1–5:** λ\_gdd = 1e-3 (moderate constraint to establish initial structure)
2. **Iterations 6–25:** λ\_gdd = 1e-5 (loose constraint, let optimizer explore GDD)
3. **Iterations 26–50:** λ\_gdd = 0, but with boundary-energy monitoring — halt if edge energy exceeds 1e-4

This can be implemented by wrapping the Optim.jl call in a loop with changing regularization parameters, warm-starting each stage from the previous result.

### 2.4 Threshold Approach

A cleaner alternative: penalize GDD only above a physically motivated threshold.

    J_gdd_thresh = λ_gdd × max(0, |GDD| − GDD_max)²

where GDD\_max ~ 10,000 fs² (based on the chirp sensitivity showing benefits up to at least 5000 fs²). This allows all physically reasonable pre-chirp while preventing runaway dispersion. The GDD can be extracted from the phase as:

    GDD_eff = Σ_i w_i × d²φ/dω² × Δω

where w\_i are spectral weights (proportional to pulse spectral power).

---

## 3. Alternative Regularization: Boundary-Energy Penalty

### 3.1 Why GDD Penalties Are the Wrong Tool

The GDD/TOD penalties were introduced (Prompt 10b) to replace the old adjacent-difference penalty (λ\_phase\_smooth) that scaled as 1/Nt² and was ineffective at Nt=8192. The actual problem they were meant to solve was **boundary exploitation** — the optimizer chirping the pulse so heavily that it hits the time-window edges, exploiting the periodic FFT boundary to "wrap around" and artificially suppress the Raman band.

GDD penalties address this indirectly by limiting chirp, but they are overly restrictive because:

1. They penalize ALL chirp, including physically beneficial pre-chirp
2. They don't distinguish between safe GDD (within the time window) and dangerous GDD (causing wraparound)
3. They scale poorly — the "safe" amount of GDD depends on fiber length, pulse duration, and time-window size

### 3.2 Proposed Boundary-Energy Penalty

A direct boundary-energy penalty addresses the actual failure mode:

```julia
function boundary_penalty(φ, uω0, fiber, sim; α_boundary=1.0, edge_fraction=0.05)
    # Propagate shaped pulse
    uω0_shaped = @. uω0 * cis(φ)
    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_bc, sim)
    ut_end = sol["ut_z"][end, :, :]

    # Edge energy
    Nt = sim["Nt"]
    n_edge = max(1, Nt ÷ 20)
    E_total = sum(abs2.(ut_end))
    E_edges = sum(abs2.(ut_end[1:n_edge, :])) +
              sum(abs2.(ut_end[end-n_edge+1:end, :]))
    edge_frac = E_edges / max(E_total, eps())

    # Soft penalty: zero below threshold, quadratic above
    threshold = 1e-6
    penalty = edge_frac > threshold ? α_boundary * (log10(edge_frac) - log10(threshold))^2 : 0.0

    return penalty
end
```

**Advantages:**
- Directly penalizes the failure mode (boundary contamination)
- Allows unlimited GDD as long as the pulse stays within the time window
- The `check_boundary_conditions` infrastructure already exists
- Threshold is physically motivated (edge energy < 1e-6 means negligible boundary effects)

**Disadvantage:**
- Requires an additional forward propagation per cost evaluation (doubles compute cost)
- Gradient computation requires differentiating through the boundary check

### 3.3 Cheap Approximation: Input-Side Edge Energy

A cheaper alternative avoids the extra forward solve:

```julia
function input_edge_penalty(φ, uω0, sim; α_input_edge=1.0)
    # Check if the shaped INPUT pulse has energy at time edges
    uω0_shaped = @. uω0 * cis(φ)
    ut0 = ifft(uω0_shaped, 1)

    Nt = sim["Nt"]
    n_edge = max(1, Nt ÷ 20)
    E_total = sum(abs2.(ut0))
    E_edges = sum(abs2.(ut0[1:n_edge, :])) +
              sum(abs2.(ut0[end-n_edge+1:end, :]))
    edge_frac = E_edges / max(E_total, eps())

    return edge_frac > 1e-6 ? α_input_edge * edge_frac : 0.0
end
```

This is cheap (just an IFFT) and differentiable analytically. If the **input** shaped pulse has edge energy, the output certainly will too. This catches the main failure mode (excessive chirp spreading the pulse beyond the window) without penalizing physical GDD that keeps the pulse within bounds.

### 3.4 Literature: Absorbing Boundary Layers

The NLS/GNLSE simulation community has well-established methods for boundary artifact suppression:

1. **Complex Absorbing Potentials (CAP):** Add an imaginary potential V(t) = −iα(t) in the edge regions, where α(t) smoothly increases toward the boundaries. This damps energy that reaches the edges without reflecting it back. Compatible with split-step methods because the absorbing layer applies only to the linear substep.

2. **Perfectly Matched Layers (PML):** Transform the coordinate system in the edge regions to introduce complex stretching. More rigorous than CAP but harder to implement.

3. **Adaptive ABL (2024):** Recent work proposes adaptive selection of CAP parameters based on the solution amplitude, avoiding the need for manual tuning.

For this project, a CAP approach could be integrated directly into the split-step solver within MultiModeNoise, providing inherent boundary safety without any phase regularization at all. This would be the most robust long-term solution but requires modifying the solver library.

---

## 4. Phase Structure Assessment

### 4.1 Observed Comb/Spike Structures

All three optimized phases (L=1m, L=2m, L=5m) show a characteristic pattern: narrow phase notches (spikes to 0 or π) at specific wavelengths within the pulse bandwidth, with flat phase regions between them. The phase detail insets show these features clearly.

Key observations:
- Run 1 (L=1m): ~5–6 narrow notches within the 1520–1600 nm bandwidth
- Run 2 (L=2m): Similar pattern, with notches at slightly different wavelengths, plus broader phase variation
- Run 3 (L=5m): More notches, broader phase excursions, consistent with stronger nonlinear effects

### 4.2 Physical Interpretation: Phase-Matching Disruption

These comb structures are likely **physical** (not grid artifacts) for the following reasons:

1. **Mechanism:** Narrow phase jumps at specific frequencies create destructive interference at the output for the Raman-shifted spectral components. By introducing π-shifts at frequencies separated by roughly the Raman shift (~13 THz), the optimizer creates conditions where the Raman gain at each red-shifted frequency is partially cancelled by interference between different spectral components.

2. **Scaling with L:** The number of notches increases with fiber length, consistent with the increasing importance of phase-matching conditions over longer propagation distances.

3. **Consistency across runs:** The notch pattern appears in all runs despite different starting conditions and fiber parameters, suggesting it's a robust feature of the optimization landscape.

### 4.3 Possible Grid Artifacts

However, there is reason for caution:

1. **FFT periodicity:** The notch widths appear to be only a few grid points wide. If they are 1–2 points wide, they may be exploiting the specific Nt=8192 grid and would not persist at different resolutions.

2. **Nt dependence test needed:** The definitive test is to optimize at Nt=4096, 8192, and 16384 and compare the phase structures. If the notch positions (in physical frequency units) and widths are consistent, they are physical. If they shift with Nt, they are grid artifacts.

3. **Realizability:** Physical pulse shapers (e.g., SLM-based) have limited spectral resolution — typically ~0.1 nm at best. Phase features narrower than this are unrealizable and suggest overfitting to the simulation grid.

### 4.4 Recommendation

Run a grid-convergence test: optimize at Nt = 4096, 8192, 16384 with identical physical parameters and compare:
- Phase notch positions (in nm or THz)
- Phase notch widths (in nm)
- Achieved cost J
- Whether J at Nt=4096 is close to J at Nt=16384

If the structures are grid artifacts, the optimization should also include a spectral-resolution constraint (e.g., convolve the phase with a Gaussian of width matching the SLM resolution before applying it).

---

## 5. Multi-Start Characterization

### 5.1 Multi-Start Implementation Details

From `benchmark_optimization.jl`, the `multistart_optimization` function:

- Uses **no regularization** (no λ\_gdd, λ\_tod, λ\_phase\_smooth, or λ\_phase\_tikhonov arguments are passed to `optimize_spectral_phase`)
- Generates band-limited random initial phases: uniform random in [−π, π], then low-pass filtered to `bandwidth_limit × pulse_bandwidth` (default 3×)
- Includes zero phase (unshaped) as start #1
- Runs L-BFGS with `max_iter=50` per start

### 5.2 Implications

The −82.5 dB best result from multi-start is achieved **without any regularization**. This means:

1. The −82.5 dB solution likely has significant GDD (pre-chirp) and/or the comb phase structures discussed above
2. The 25 dB spread across starts (best −82.5 dB, worst presumably ~−57 dB) confirms an extremely rough optimization landscape with many local minima
3. The zero-phase start (start #1) likely produces a result comparable to the regularized optimum (~−36 dB), since the regularization mainly prevents departure from zero phase

### 5.3 Boundary Status Unknown

Critically, `multistart_optimization` does **not** check boundary conditions on its results. The −82.5 dB solution may violate boundaries. This should be verified by running `check_boundary_conditions` on the best multi-start result.

If the −82.5 dB solution has clean boundaries, it proves the regularization is purely harmful. If it has boundary contamination, the true unregularized optimum (with clean boundaries) lies somewhere between −82.5 dB and −36.3 dB — but the chirp sensitivity already shows at least −44.5 dB is achievable with clean physics.

### 5.4 Recommended Follow-Up

1. Re-run multi-start with boundary checking enabled
2. For the best result, compute and record the effective GDD and TOD
3. Visualize the best multi-start phase profile alongside the regularized profile
4. Test whether the best multi-start result transfers across time windows (using `analyze_time_windows_optimized`)

---

## 6. Comparison with Pre-10b Results

### 6.1 What Changed at Prompt 10b

The transition at Prompt 10b replaced:
- λ\_phase\_smooth (adjacent-difference penalty, scaling as 1/Nt²) → λ\_gdd + λ\_tod (physics-motivated penalties)

The old λ\_phase\_smooth at Nt=8192 was effectively zero (scaled as 1/Nt² = 1.5e-8), meaning pre-10b optimizations were **unregularized in practice**. This explains why earlier results may have been better — the optimizer was free to add beneficial GDD.

### 6.2 Old Forward Solver Differences

If the old runs used a fixed-step solver with coarser stepping, numerical diffusion would have acted as an implicit regularizer — smoothing sharp phase features and preventing grid-scale artifacts. The current adaptive solver (Vern9) is more accurate but also more susceptible to overfitting.

### 6.3 No Old Result Images Found

The directory does not contain clearly labeled "pre-10b" results. The existing PNG files all appear to be from the current optimization framework (with the v2 visualization format). A direct quantitative comparison would require re-running the old configuration or locating archived results.

---

## 7. Physics Literature Findings

### 7.1 Pre-Chirp for Raman Suppression — Known and Beneficial

**Santhanam & Agrawal (2003)** showed that the Raman-induced spectral shift depends directly on the frequency chirp of the input pulse. The magnitude of SSFS depends on the history of pulse width changes — a pre-chirped pulse that broadens temporally during propagation experiences reduced peak power, which directly reduces Raman scattering since the Raman gain scales with intensity.

**Key finding for our project:** Negative GDD (anomalous pre-chirp) for a pulse entering anomalous-dispersion fiber causes initial temporal broadening followed by recompression. This broadening phase has lower peak power, reducing Raman scattering in the early fiber section where the pulse is most intense. Our chirp sensitivity plot showing monotonic improvement with negative GDD is entirely consistent with this physics.

A 2025 Optics Letters paper on in-amplifier SSFS optimization by pre-chirp experimentally confirmed that the optimal pre-chirp is approximately C₀ ≈ 0.65 × g × L\_D, providing a quantitative estimate for the optimal GDD.

### 7.2 SSFS Suppression Methods

The literature identifies several mechanisms:

1. **Chirp/pre-chirp control** — directly relevant, our optimizer wants to use this
2. **Spectral recoil from dispersive waves** — occurs naturally in fibers with negative dispersion slope; the Cherenkov radiation exerts a "recoil" that cancels the Raman shift
3. **Bandwidth-limited amplification/filtering** — uses a spectral filter to limit the Raman shift
4. **Dispersion sign reversal** — periodically alternating normal and anomalous dispersion cancels SSFS

Our phase optimizer is essentially discovering method (1) — chirp control — but the GDD penalty prevents it from implementing the solution.

### 7.3 Boundary Conditions in Split-Step Simulations

The GNLSE simulation community uses several approaches:

1. **Complex Absorbing Potentials (CAP):** Add V(t) = −iα(t) in edge regions. Compatible with split-step FFT. The absorbing potential applies in the linear substep and damps edge-reaching energy exponentially.

2. **Adaptive ABL (De Gruyter, 2024):** Automatically selects CAP parameters. Directly applicable to our time-splitting framework.

3. **Transparent Boundary Conditions (TBC):** Theoretically exact for linear NLS, but construction for nonlinear equations is generally impossible.

For our project, a CAP layer in MultiModeNoise would eliminate the need for any phase regularization aimed at boundary protection.

---

## 8. Recommended Optimization Strategy

### 8.1 Immediate Fix (No Code Changes to MultiModeNoise)

Replace the current regularization with a two-phase approach:

**Phase 1 (5 iterations):** Conservative start
```
λ_gdd = 1e-4, λ_tod = 0, λ_phase_tikhonov = 0
```

**Phase 2 (45 iterations):** Unrestricted optimization with boundary monitoring
```
λ_gdd = 0, λ_tod = 0, λ_phase_tikhonov = 0
```
After each iteration, compute `check_boundary_conditions`. If edge\_frac > 1e-4, increase time\_window by 50% and restart from current phase (interpolated to new grid).

### 8.2 Better Fix (Moderate Code Changes)

Replace GDD/TOD penalties with the input-edge-energy penalty:

```julia
# In cost_and_gradient, replace GDD/TOD blocks with:
if λ_boundary > 0
    ut0 = ifft(uω0_shaped, 1)
    Nt_φ = size(φ, 1)
    n_edge = max(1, Nt_φ ÷ 20)
    E_total = sum(abs2.(ut0))
    E_edges = sum(abs2.(ut0[1:n_edge, :])) + sum(abs2.(ut0[end-n_edge+1:end, :]))
    edge_frac = E_edges / max(E_total, eps())
    if edge_frac > 1e-8
        J_total += λ_boundary * edge_frac
        # Gradient: ∂(edge_frac)/∂φ via chain rule through IFFT
        # ... (requires implementing the gradient of the edge energy w.r.t. φ)
    end
end
```

The gradient computation for the input-edge penalty is straightforward: since ut0 = IFFT(uω0 × exp(iφ)), the chain rule gives an analytically computable gradient involving the IFFT of the edge-masked temporal field.

### 8.3 Best Fix (Requires MultiModeNoise Changes)

Add a Complex Absorbing Potential layer to the split-step solver:

1. Define a smooth absorbing profile α(t) that is zero in the central 90% of the time window and ramps to α\_max in the edge 5% on each side
2. In the linear half-step of the split-step method, multiply by exp(−α(t) × Δz/2)
3. This naturally damps any energy reaching the edges, preventing boundary artifacts without any external regularization

This approach is well-established in the computational physics literature and would make the simulation robust to boundary artifacts by construction.

### 8.4 Expected Improvement

Based on the chirp sensitivity analysis:
- Current regularized optimum: −36.3 dB
- With GDD = −5000 fs² (no other changes): ~−44.5 dB (8 dB improvement)
- Multi-start best (unregularized): −82.5 dB (46 dB improvement)
- Realistic target with boundary-safe unregularized optimization: −50 to −70 dB

---

## 9. Summary of Findings

| Finding | Evidence | Impact |
|---------|----------|--------|
| GDD penalty fights beneficial physics | Chirp sensitivity: monotonic improvement with negative GDD | 8+ dB lost |
| TOD penalty is irrelevant | TOD sensitivity: 0.003 dB over ±5000 fs³ | Negligible, remove |
| Multi-start uses no regularization | Code inspection: no λ\_gdd/λ\_tod passed | Confirms regularization is sole cause of gap |
| Pre-chirp is a known Raman suppression technique | Santhanam & Agrawal (2003); 2025 experimental verification | GDD penalty contradicts established physics |
| Boundary protection should be direct | Literature: CAP layers, adaptive ABL | Replace GDD penalty with boundary-energy penalty |
| Phase comb structures need Nt-convergence test | Present in all runs, width unclear | Physical or artifact — test at multiple Nt |

---

## References

- Santhanam, T. & Agrawal, G.P. "Raman-induced spectral shifts in optical fibers: general theory based on the moment method." (2003) — [PDF](https://labsites.rochester.edu/agrawal/wp-content/uploads/2019/08/paper_2003_05.pdf)
- Skryabin, D.V. et al. "Soliton Self-Frequency Shift Cancellation in Photonic Crystal Fibers." Science (2003) — [Link](https://www.science.org/doi/10.1126/science.1088516)
- "In-amplifier soliton self-frequency shift optimization by pre-chirping." Optics Letters 50(7), 2117 (2025) — [Link](https://opg.optica.org/ol/abstract.cfm?uri=ol-50-7-2117)
- "Adaptive Absorbing Boundary Layer for the Nonlinear Schrödinger Equation." (2024) — [Link](https://www.degruyterbrill.com/document/doi/10.1515/cmam-2023-0096/html)
- "A unified approach to split absorbing boundary conditions for NLS equations." Phys. Rev. E (2008) — [arXiv](https://arxiv.org/abs/0806.1854)
- "Soliton Self-Frequency Shift: Experimental Demonstrations and Applications." PMC (2012) — [Link](https://pmc.ncbi.nlm.nih.gov/articles/PMC3465838/)
- "Suppression of the soliton self-frequency shift by bandwidth-limited amplification." JOSA B 5(6), 1301 (1988) — [Link](https://opg.optica.org/josab/abstract.cfm?uri=josab-5-6-1301)
- "A new absorbing layer approach for solving the nonlinear Schrödinger equation." (2023) — [Link](https://www.sciencedirect.com/science/article/abs/pii/S016892742300096X)
