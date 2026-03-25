# Research Report: Amplitude Optimization Failure Diagnosis & Remediation

**Date:** 2026-03-12
**Author:** Research Agent (Prompt 16a)
**Status:** All four catastrophic failures diagnosed; remediation strategies proposed

---

## Executive Summary

The spectral amplitude optimization for Raman suppression in single-mode fiber exhibits four catastrophic failures: (1) box constraints not enforced, producing A = -26035; (2) trivial attenuation solutions; (3) gradient breakdown at L = 5m; and (4) historical near-zero optimizer movement. After code analysis and literature review, the root causes are identified below. The primary recommendation is to **retain amplitude optimization but with fundamental architectural changes**: proper `Fminbox` constraints, a hard energy constraint via projection, a low-dimensional parameterization, and a reduced-step adjoint gradient with fallback finite-difference validation.

---

## 1. Root Cause Analysis

### Failure 1: Box Constraint Violation (A = -26035)

**Location:** `amplitude_optimization.jl`, lines 256–277 (`optimize_spectral_amplitude`)

**Root cause:** The `clamp!()` call on line 259 is placed *inside* the `Optim.only_fg!()` closure. This means:

1. LBFGS computes an unconstrained step based on its internal Hessian approximation (inverse-Hessian via rank-2 updates).
2. The next evaluation of the objective clamps A back to `[1-δ, 1+δ]`.
3. However, LBFGS's line search has already accepted the step at the unclamped point. The quasi-Newton Hessian approximation is built from the secant condition `s = x_{k+1} - x_k` and `y = g_{k+1} - g_k`. When x actually jumped to -26035 but the gradient was evaluated at the clamped value ~0.70, the secant pair `(s, y)` is corrupted.
4. This corrupted Hessian generates increasingly wild steps, causing divergence.

The `clamp!` approach is a *projection onto the feasible set*, but it is applied at the wrong point in the algorithm. For projected-gradient methods to work, the projection must happen **after** the step (not inside the objective), and the gradient must be evaluated **at the projected point**. The current code evaluates the gradient at the projected point but reports the **unprojected** position to LBFGS's internal state.

**Comparison with phase optimizer:** The phase optimizer (`raman_optimization.jl`, lines 208–226) uses unconstrained LBFGS with no bounds at all. Phase is naturally unbounded (any real value), so no projection is needed, and the optimizer works correctly.

### Failure 2: Trivial Attenuation Solution

**Location:** `amplitude_optimization.jl`, lines 73–82 (energy penalty) and `common.jl` line 69 (`spectral_band_cost`)

**Root cause (multi-factor):**

1. **Soft energy constraint:** The energy penalty `λ_E · (E_shaped/E_original - 1)²` is quadratic — it becomes cheaper to violate than to satisfy as the Raman reduction from attenuation exceeds the penalty. At δ = 0.30, the optimizer can reduce peak power by ~30%, yielding large Raman reduction at modest energy penalty cost.

2. **Free-form parameterization:** With Nt = 8192 independent amplitude values, the optimizer has enough degrees of freedom to create narrow spectral notches at the exact frequencies where Raman gain is strongest. A single-bin notch at the lower bound (A = 0.70) has minimal energy penalty but maximum Raman reduction per unit energy cost.

3. **Cost function structure:** `spectral_band_cost` (line 69 of `common.jl`) computes the *fractional* energy in the Raman band: `J = E_band / E_total`. Reducing the total energy actually *increases* J (denominator shrinks), which should discourage pure attenuation. However, when A attenuates only frequencies that feed Raman (near the spectral center), the numerator drops faster than the denominator, making the notch strategy favorable.

4. **Tikhonov + TV insufficient:** The Tikhonov penalty `λ_T · ‖A - 1‖²/N` penalizes average deviation but not localized notches (a single deep notch among 8192 bins has negligible average penalty). The TV penalty discourages sharp edges but at `λ_TV = 0.0001`, it is too weak to prevent the notch.

### Failure 3: Gradient Breakdown at L = 5m

**Location:** `amplitude_optimization.jl`, line 193; `sensitivity_disp_mmf.jl`, lines 1–51 (adjoint solver)

**Root cause:** The amplitude gradient formula (line 193):
```
grad_raman = 2.0 .* real.(conj.(λ0) .* uω0)
```
is mathematically correct for the chain rule `δu₀ = uω0 · δA`, giving `∂J/∂A = 2·Re(conj(λ₀)·uω0)`. The factor of 2 arises from `∂|u|²/∂u* = u` applied inside `spectral_band_cost` (line 70 of `common.jl`), where `dJ = uωf .* (band_mask .- J) ./ E_total` already contains the factor. So the gradient formula is **correct in principle**.

The failure at L = 5m is a **numerical conditioning issue**, not a formula bug. Here's why:

- **Phase gradient** (line 92 of `raman_optimization.jl`): `∂J/∂φ = 2·Re(conj(λ₀)·i·uω0·cis(φ))`. The perturbation `δu₀ = i·u₀·δφ` is *orthogonal* to u₀ (purely imaginary rotation in the complex plane). This means the perturbation doesn't change the field magnitude, only its phase. In nonlinear propagation, phase perturbations are relatively benign — they primarily affect the soliton's temporal position and accumulated nonlinear phase, both of which vary smoothly.

- **Amplitude gradient**: `δu₀ = uω0·δA` is *parallel* to u₀ (real scaling). This changes the field magnitude directly, which changes the peak power, which changes the soliton order N ∝ √P. At L = 5m, the propagation is in a strongly nonlinear regime where small changes in peak power cause:
  - Different soliton fission dynamics (N changes → different number of ejected solitons)
  - Different Raman self-frequency shift rates (SSFS ∝ |β₂|⁻¹·T₀⁻⁴)
  - Chaotic sensitivity to initial amplitude — a hallmark of soliton dynamics in long fibers

The adjoint ODE solver (`sensitivity_disp_mmf.jl`, line 173) uses `Vern9()` with `reltol=1e-10`, which is adequate for the forward problem but may be insufficient for the backward adjoint when the forward solution exhibits high sensitivity. The adjoint λ(z) tracks perturbation growth backward through z, and when the forward dynamics are chaotic, λ grows exponentially, causing the adjoint gradient to lose accuracy.

**Supporting evidence:** The test suite (`test_optimization.jl`, lines 344–368) validates amplitude gradients at L = 0.1m with 5% tolerance, and they pass. The gradient fails specifically at L = 5m where the soliton propagation becomes strongly nonlinear.

### Failure 4: Historical Near-Zero Movement

**Root cause:** Before Prompt 11b's rebalancing, the regularization weights were too large relative to the Raman gradient. The test on lines 618–640 of `test_optimization.jl` (`regularization_balance: Raman gradient not crushed`) was specifically written to catch this. The Raman gradient `‖∂J_raman/∂A‖` was swamped by the energy penalty gradient `‖∂J_energy/∂A‖`, so the optimizer was effectively frozen at A ≈ 1.

After rebalancing (reducing `λ_energy` and `λ_tikhonov`), the Raman gradient became dominant, but this exposed Failures 1–3.

---

## 2. Corrected Box Constraint Implementation

### Recommended: Fminbox(LBFGS())

Replace the manual-clamp LBFGS with Optim.jl's native `Fminbox`, which implements a primal barrier interior-point method with proper handling of bounds.

```julia
function optimize_spectral_amplitude(uω0_base, fiber, sim, band_mask;
    A0=nothing, max_iter=50, δ_bound=0.10,
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)

    Nt = sim["Nt"]
    M = sim["M"]

    if isnothing(A0)
        A0 = ones(Nt, M)
    end

    lower_val = 1.0 - δ_bound
    upper_val = 1.0 + δ_bound

    # Fminbox requires initial point STRICTLY inside bounds
    A0_vec = clamp.(vec(A0), lower_val + 1e-8, upper_val - 1e-8)

    lower = fill(lower_val, length(A0_vec))
    upper = fill(upper_val, length(A0_vec))

    reg_kwargs = (λ_energy=λ_energy, λ_tikhonov=λ_tikhonov, λ_tv=λ_tv, λ_flat=λ_flat)
    last_breakdown = Ref(Dict{String,Float64}())
    last_A_extrema = Ref((1.0, 1.0))

    t_start = time()
    function callback(state)
        elapsed = time() - t_start
        bd = last_breakdown[]
        J_r = get(bd, "J_raman", NaN)
        J_e = get(bd, "J_energy", NaN)
        A_min, A_max = last_A_extrema[]
        @info @sprintf("  [%3d/%d] J=%.6f  J_ram=%.4e  J_E=%.4e  A∈[%.3f,%.3f]  (%.1f s)",
                state.iteration, max_iter, state.value, J_r, J_e, A_min, A_max, elapsed)
        return false
    end

    # Objective + gradient function (no clamping needed — Fminbox handles bounds)
    function fg!(F, G, A_vec)
        A = reshape(A_vec, Nt, M)
        J, grad, breakdown = cost_and_gradient_amplitude(
            A, uω0_base, fiber, sim, band_mask; reg_kwargs...
        )
        last_breakdown[] = breakdown
        last_A_extrema[] = extrema(A)
        if G !== nothing
            G .= vec(grad)
        end
        if F !== nothing
            return J
        end
    end

    result = optimize(
        Optim.only_fg!(fg!),
        lower,
        upper,
        A0_vec,
        Fminbox(LBFGS(m=10)),
        Optim.Options(iterations=max_iter, f_abstol=1e-6, callback=callback,
                      outer_iterations=max_iter)
    )

    return result, last_breakdown[]
end
```

**Key changes:**
1. Bounds arrays `lower` and `upper` are passed to `Fminbox` instead of manual `clamp!`
2. Initial point is nudged strictly inside bounds (`± 1e-8`)
3. `outer_iterations` controls Fminbox's barrier iterations; `iterations` controls inner LBFGS

### Why not projected gradient?

A correctly implemented projected gradient (clamp *after* the step, evaluate gradient *at* the projected point, modify the LBFGS update to use the projected secant pair) would also work. However, this requires modifying Optim.jl internals or writing a custom optimizer. `Fminbox` already implements the correct algorithm.

---

## 3. Recommended Amplitude Parameterization

### Problem with Free-Form A(ω)

With Nt = 8192 free parameters, the optimizer has far too many degrees of freedom. Physical amplitude shaping devices (spatial light modulators, acousto-optic programmable dispersive filters) typically have 128–640 independent pixels, and practical Raman suppression requires only *smooth, broadband* spectral reshaping, not narrow notches.

### Proposal: Low-Dimensional Basis Expansion

Parameterize the amplitude as:

```
A(ω) = 1 + δ · Σ_{k=0}^{K-1} c_k · B_k(ω)
```

where `B_k(ω)` are orthonormal basis functions over the pulse bandwidth, and `c_k ∈ [-1, 1]` are the K optimization variables (with K = 5–20).

**Recommended basis options:**

1. **Discrete Cosine Transform (DCT) basis:** `B_k(ω) = cos(kπ(ω - ω_min)/(ω_max - ω_min))`, normalized. Naturally smooth, easy to implement, good spectral locality.

2. **Zernike-like polynomials on the spectral domain:** Orthogonal over the pulse bandwidth, provide systematic control from low-order (tilt, curvature) to high-order (fine structure).

3. **Truncated Fourier series over the pulse bandwidth:** `B_k(ω) = cos(2πkω/B)` where B is the pulse bandwidth. Equivalent to DCT but explicitly bandlimited.

**Advantages:**
- K = 10 parameters instead of 8192 → optimization is fast and well-conditioned
- Box constraint on c_k ∈ [-1, 1] guarantees A(ω) ∈ [1-δ, 1+δ]
- No narrow notches possible (smooth basis prevents them)
- Gradient ∂J/∂c_k = Σ_ω (∂J/∂A(ω)) · δ · B_k(ω) — simple chain rule from existing gradient

**Implementation sketch:**
```julia
function A_from_coefficients(c, δ, basis_matrix)
    # basis_matrix: (Nt, K) matrix of basis function values
    # c: (K,) coefficient vector with |c_k| ≤ 1
    return 1.0 .+ δ .* (basis_matrix * c)
end

function cost_and_gradient_amplitude_lowdim(c, δ, basis_matrix, uω0, fiber, sim, band_mask; kwargs...)
    A = A_from_coefficients(c, δ, basis_matrix)
    J, grad_A, breakdown = cost_and_gradient_amplitude(A, uω0, fiber, sim, band_mask; kwargs...)
    # Chain rule: ∂J/∂c = δ · basis_matrixᵀ · ∂J/∂A
    grad_c = δ .* (basis_matrix' * grad_A)
    return J, grad_c, breakdown
end
```

---

## 4. Hard Energy Constraint Proposal

### Why Soft Penalty Fails

The current energy penalty `λ_E · (E_shaped/E_original - 1)²` allows 18.7% energy deviation at the optimal penalty-vs-Raman trade-off. Increasing `λ_E` suppresses the Raman gradient (back to Failure 4).

### Option A: Projection After Each Step

After each optimizer step, project A onto the energy-preserving manifold:

```
A_projected(ω) = A(ω) · √(E_original / E_shaped)
```

where `E_shaped = Σ A²(ω) · |uω0(ω)|²` and `E_original = Σ |uω0(ω)|²`.

This rescaling preserves the *shape* of A(ω) while enforcing exact energy conservation. The gradient must be projected onto the tangent space of the constraint manifold:

```
grad_projected = grad - (grad · ∂E/∂A) / ‖∂E/∂A‖² · ∂E/∂A
```

where `∂E/∂A = 2A · |uω0|² / E_original`.

### Option B: Reparameterize to Enforce Exactly

Write `A(ω) = √(|uω0(ω)|² + ε) / |uω0(ω)|` where ε is chosen to redistribute energy. This is harder to work with but eliminates the energy constraint entirely.

### Option C: Augmented Lagrangian

Add a Lagrange multiplier μ for the energy constraint:

```
L = J_raman + μ · (E_shaped/E_original - 1) + ρ/2 · (E_shaped/E_original - 1)²
```

Update μ after each outer iteration. This is the standard approach for equality constraints and converges to the exact solution as ρ → ∞.

**Recommendation:** Option A (projection) is simplest and most robust. Combined with the low-dimensional parameterization (Section 3), it adds minimal complexity.

---

## 5. Gradient Accuracy Analysis

### Why Amplitude Gradient Fails at L = 5m but Phase Gradient Doesn't

The key difference is the **condition number of the forward map** with respect to each perturbation type:

**Phase perturbation** `δu₀ = i·u₀·δφ`:
- Changes only the phase of each spectral component
- Doesn't change the soliton order N (peak power unchanged)
- Forward map φ → u(L) is smooth and well-conditioned
- Adjoint gradient tracks phase rotation — varies slowly with z

**Amplitude perturbation** `δu₀ = u₀·δA`:
- Changes the peak power of the pulse: P_peak → P_peak · A²
- Changes the soliton order: N → N · A
- At L = 5m with N ≈ several, the system is in a multi-soliton regime
- Amplitude perturbations can trigger different soliton fission scenarios
- Forward map A → u(L) has high condition number (chaos-like sensitivity)
- Adjoint λ(z) grows exponentially during backward propagation, magnifying numerical errors

### Quantitative Estimate

For a fundamental soliton, the Raman self-frequency shift rate scales as T₀⁻⁴. A 1% change in amplitude → 2% change in peak power → different soliton duration after fission → ~8% change in SSFS rate. Over L = 5m, this compounds to produce O(1) changes in the output spectrum, making the forward map effectively discontinuous at the scale of finite-difference perturbations (ε = 1e-5).

### Remediation Strategies

1. **Reduce fiber length for amplitude optimization:** Limit L to the regime where the gradient is valid (L ≤ 1–2m based on test results).

2. **Use a larger finite-difference step for validation:** At L = 5m, ε = 1e-5 may be in the chaotic regime. Try ε = 1e-3 or 1e-2 to probe the average (smoothed) sensitivity.

3. **Ensemble-averaged gradient:** Compute the gradient at multiple nearby A values and average. This smooths over the chaotic sensitivity:
```julia
function ensemble_gradient(A, uω0, fiber, sim, band_mask; n_ensemble=5, σ=0.005)
    grads = [cost_and_gradient_amplitude(A .+ σ.*randn(size(A)), ...)[2] for _ in 1:n_ensemble]
    return mean(grads)
end
```

4. **Tighter ODE tolerance for the adjoint:** The adjoint solver uses `reltol=1e-10` (line 173 of `sensitivity_disp_mmf.jl`). For long fibers, try `reltol=1e-12` or use adaptive step-size control with error monitoring.

5. **Low-dimensional parameterization (Section 3):** With K = 10 parameters, the gradient `∂J/∂c_k` averages over thousands of spectral bins, naturally smoothing the chaotic per-bin sensitivity.

---

## 6. Recommendation: Keep or Drop Amplitude Optimization

### Assessment

| Criterion | Phase Optimization | Amplitude Optimization |
|-----------|-------------------|----------------------|
| Raman suppression | 5–14 dB | <6 dB (with artifacts) |
| Energy conservation | Exact (by construction) | Requires enforcement |
| Gradient accuracy | Excellent (err < 1e-5) | Degrades at L > 2m |
| Trivial solutions | None (phase can't attenuate) | Yes (A → lower bound) |
| Physical realization | Pulse shaper (phase-only SLM) | Pulse shaper (amplitude SLM) or spectral filter |
| Degrees of freedom | Nt (naturally unbounded) | Nt (needs constraints) |

### Physics Argument

Spectral amplitude shaping for Raman suppression is fundamentally more constrained than phase shaping because:

1. **Energy budget:** Every dB of amplitude modulation depth costs energy. Phase modulation is free (energy-neutral). The Raman process is driven by peak power, so the most effective suppression strategy is to *reshape the temporal profile* (spreading the pulse in time to reduce peak power) without losing energy. Phase shaping achieves this naturally via chirp.

2. **Limited lever arm:** With A ∈ [0.70, 1.30] (δ = 0.30), the maximum achievable spectral reshaping is modest. The Raman gain bandwidth is ~5 THz, and the pulse bandwidth is ~2 THz. Amplitude shaping can redistribute energy within the pulse bandwidth but cannot fundamentally change the peak-power × interaction-length product that drives Raman.

3. **Literature precedent:** The literature on Raman suppression (see Section 7) overwhelmingly uses **spectral filtering** (attenuation of already-shifted Raman components) or **phase-based temporal reshaping**, not input spectral amplitude optimization. The closest analog is intracavity spectral filtering in mode-locked lasers, but these operate on the Raman-shifted light itself, not on the input pulse.

### Recommendation: **Keep amplitude optimization, but restructured**

Amplitude optimization should not be abandoned entirely because:

1. **Combined amplitude + phase optimization** may outperform phase-only. The amplitude can provide coarse spectral shaping while the phase provides fine temporal reshaping. This is analogous to how pulse shapers in practice always have both amplitude and phase control.

2. **The current failures are all fixable** — they stem from implementation bugs (Failure 1), missing constraints (Failure 2), and numerical issues (Failure 3), not fundamental physics limitations.

3. **Low-dimensional amplitude optimization is fast** — with K = 10 parameters, each optimization takes seconds, so it can be used as a pre-processing step before phase optimization.

**Proposed workflow:**
1. Low-dimensional amplitude optimization (K = 10, DCT basis, projected energy constraint) — coarse spectral reshaping
2. Full phase optimization — fine temporal reshaping on the amplitude-shaped pulse
3. Validate combined result

---

## 7. Literature References

### Spectral Amplitude Shaping for Raman Suppression

No published work was found that specifically uses **input spectral amplitude optimization** (without phase) to suppress soliton Raman self-frequency shift. The closest related approaches are:

1. **Upshifted spectral filtering:** Placing a bandpass filter whose center frequency is blue-shifted relative to the soliton center, which counteracts the Raman red-shift. This acts on the propagating pulse, not the input. (Theory of Raman effect on solitons, Optics Communications 2004)

2. **Bandwidth-limited amplification:** Using gain media with limited bandwidth to suppress the Raman-shifted tail. (Same reference)

3. **Temporal/spectral reshaping via initial conditions:** In the normal dispersion regime, output pulse shape can be controlled by adjusting the initial amplitude and phase (Nonlinear spectral shaping, Optics Communications 2012). However, this applies to normal dispersion, not the anomalous regime relevant here.

4. **Intracavity spectral filtering in mode-locked fiber lasers:** Spectral amplitude filters inside laser cavities can shape the output pulse, achieving parabolic, flat-top, and triangular profiles. (Applied Sciences 5(4), 2015)

### Ultrafast Pulse Shaping Technology

5. **Phase-only filtering preserves energy:** Phase-only spectral filters are preferred for energy-efficient processing because they preserve the full energy of the temporal signal, while amplitude filtering inherently discards energy. (Nature Communications, 2019)

6. **Fourier-domain pulse shaping:** The standard approach uses a spatial light modulator in a 4-f geometry to impose both amplitude and phase masks. Amplitude control is done via polarization rotation or direct attenuation. (Weiner, "Ultrafast optical pulse shaping: A tutorial review", Optics Communications 2011)

7. **AOPDF (Dazzler):** Acousto-optic programmable dispersive filters provide both amplitude and phase control with ~10–100 independent spectral channels — supporting the K = 10–20 parameterization proposed above. (Verluise et al., Optics Letters 2000)

### Adjoint Methods in Nonlinear Fiber Optics

8. **Adjoint method for nonlinear nanophotonics:** The adjoint problem is linear even when the physical problem is nonlinear, but gradient accuracy can degrade in strongly nonlinear regimes. (ACS Photonics, 2018)

9. **Neural network approaches to NLSE optimization:** When adjoint gradients become unreliable in strongly nonlinear regimes, data-driven approaches (physics-informed neural networks) can serve as surrogate models. (arXiv:2002.08815)

### Box-Constrained Optimization in Julia

10. **Optim.jl Fminbox:** Implements a primal barrier interior-point method for box constraints, following Nocedal & Wright Section 19.6. Default inner optimizer is LBFGS. (Optim.jl documentation, GitHub)

---

## Appendix A: Summary of Proposed Code Changes

| File | Change | Priority |
|------|--------|----------|
| `amplitude_optimization.jl` L256–277 | Replace manual LBFGS + clamp with `Fminbox(LBFGS())` | **Critical** |
| `amplitude_optimization.jl` new function | Add `cost_and_gradient_amplitude_lowdim()` with DCT basis | High |
| `amplitude_optimization.jl` L73–82 | Add energy projection after each step (or use augmented Lagrangian) | High |
| `sensitivity_disp_mmf.jl` L173 | Add option for tighter `reltol` for long fibers | Medium |
| `test_optimization.jl` | Add test for gradient accuracy vs. fiber length | Medium |
| `amplitude_optimization.jl` | Add combined amplitude+phase optimization pipeline | Future |

## Appendix B: Comparison of Constraint Approaches

| Approach | Pros | Cons |
|----------|------|------|
| Manual clamp inside objective | Simple | **Broken** — corrupts LBFGS Hessian |
| Manual clamp after step (projected gradient) | Correct, fast | Requires custom LBFGS modification |
| `Fminbox(LBFGS())` | Correct, native to Optim.jl | Slightly slower (barrier iterations), initial point must be interior |
| Log-barrier penalty | Smooth, differentiable | Adds complexity, tuning parameter |
| `IPNewton` | Second-order convergence | Requires Hessian, heavier per-iteration |

**Winner:** `Fminbox(LBFGS())` — correct, requires minimal code changes, well-tested in Optim.jl.
