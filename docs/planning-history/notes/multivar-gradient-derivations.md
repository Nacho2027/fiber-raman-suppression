# Multi-Variable Gradient Derivations

**Session A** — owned by `sessions/A-multivar`.
Purpose: derive adjoint-method gradients for a unified multi-variable pulse-shaping
cost function where a *single* forward-adjoint solve provides gradients w.r.t. any
subset of {phase φ(ω), amplitude A(ω), energy E, mode coefficients c_m}.

Notation follows `src/simulation/sensitivity_disp_mmf.jl` and
`scripts/raman_optimization.jl`. All operations are on the discrete spectral grid
of size `(Nt, M)`. Sums over ω mean Σ_{ν=1..Nt}; sums over m mean Σ_{m=1..M}.

---

## 1. Problem setup

Given an input field `uω0(ω, m)` (the "reference launch" from `setup_raman_problem`),
apply shaping:

```
u_shaped(ω, m) = α · A(ω) · cis(φ(ω)) · c_m · uω0(ω, m)    (✱)
```

where
- `α = √(E / E_ref)` is the energy-scaling factor (E_ref = Σ |uω0|²)
- `A(ω) ≥ 0` is a real positive spectral amplitude modulation (gauge: sign in φ)
- `φ(ω) ∈ ℝ` is the spectral phase
- `c_m ∈ ℂ` is a per-mode launch coefficient (normalization: Σ|c_m|² = 1)

For the single-mode milestone (M=1, c_1 = 1), (✱) collapses to
`u_shaped(ω) = α · A(ω) · cis(φ(ω)) · uω0(ω)`.

Propagate `u_shaped` forward through the fiber to get `uωf = u_shaped(L)` (after
interaction-picture lab-frame lift). Cost:

```
J = J(uωf)                         e.g. fractional energy in Raman band
```

The terminal adjoint is `λ(L) = ∂J/∂conj(uωf)` (already computed by
`spectral_band_cost`). Propagate `λ` backward through the adjoint ODE (no changes
to `src/simulation/`) to obtain `λ₀ = λ(0)` — the cotangent at the fiber input.

---

## 2. Master chain rule

For any infinitesimal variation `δu_shaped(ω, m)` of the input, the induced
variation in J is

```
δJ = 2 · Σ_{ω,m} Re[ conj(λ₀(ω, m)) · δu_shaped(ω, m) ]          (▲)
```

This is the definition of the adjoint state — the ONLY place the fiber physics
enters the gradient. Every shaping-parameter gradient below is obtained by
differentiating (✱) w.r.t. that parameter, plugging `δu_shaped` into (▲), and
reading off the coefficient.

---

## 3. Phase gradient ∂J/∂φ(ω)

From (✱): `∂u_shaped/∂φ(ω) = i · u_shaped(ω, m)`  (for the single ω-index; zero
for other ω indices. For each mode m the same φ(ω) applies — phase is a 1D
function of ω shared across modes unless we extend later).

Plug into (▲):

```
∂J/∂φ(ω) = 2 · Σ_m Re[ conj(λ₀(ω, m)) · i · u_shaped(ω, m) ]          (P)
```

**Matches** `scripts/raman_optimization.jl :: cost_and_gradient` exactly (with
u_shaped = uω0·cis(φ) when α=1, A=1, c_m = δ_{m1}).

---

## 4. Amplitude gradient ∂J/∂A(ω)

From (✱): `∂u_shaped/∂A(ω) = α · cis(φ(ω)) · c_m · uω0(ω, m) = u_shaped / A(ω)`
(when A > 0).

```
∂J/∂A(ω) = 2 · Σ_m Re[ conj(λ₀(ω, m)) · cis(φ(ω)) · c_m · α · uω0(ω, m) ]   (A)
         = 2 · Σ_m Re[ conj(λ₀(ω, m)) · u_shaped(ω, m) / A(ω) ]   (equiv. form)
```

**Consistency check:** When α=1, φ=0, c_1=1 (amplitude-only optimization), (A)
reduces to `2·Re[conj(λ₀) · uω0]`, matching
`scripts/amplitude_optimization.jl :: cost_and_gradient_amplitude`. ✓

---

## 5. Energy gradient ∂J/∂E

From (✱): `u_shaped ∝ α = √(E/E_ref)`, so `∂u_shaped/∂E = u_shaped / (2E)`.

Plug into (▲):

```
∂J/∂E = 2 · Σ_{ω,m} Re[ conj(λ₀(ω, m)) · u_shaped(ω, m) / (2E) ]
      = (1/E) · Σ_{ω,m} Re[ conj(λ₀(ω, m)) · u_shaped(ω, m) ]               (E)
```

This is a scalar (∂J/∂E is one number, not a vector). Computationally, it's a
single reduction over all (ω, m) indices.

---

## 6. Mode-coefficient gradient ∂J/∂c_m   *(stubbed / deferred — see Decision D4)*

Treating `c_m = x_m + i·y_m` as two real parameters:

```
∂u_shaped/∂x_m = α · A(ω) · cis(φ(ω)) · uω0(ω, m)        (only column m)
∂u_shaped/∂y_m = i · α · A(ω) · cis(φ(ω)) · uω0(ω, m)    (only column m)
```

Plug into (▲):

```
∂J/∂x_m = 2 · Σ_ω Re[ conj(λ₀(ω, m)) · α · A(ω) · cis(φ(ω)) · uω0(ω, m) ]   (C_x)
∂J/∂y_m = 2 · Σ_ω Re[ conj(λ₀(ω, m)) · i · α · A(ω) · cis(φ(ω)) · uω0(ω, m) ]
        = 2 · Σ_ω Re[ i · conj(λ₀(ω, m)) · α · A(ω) · cis(φ(ω)) · uω0(ω, m) ]
        = -2 · Σ_ω Im[ conj(λ₀(ω, m)) · α · A(ω) · cis(φ(ω)) · uω0(ω, m) ]   (C_y)
```

Energy-norm constraint `Σ|c_m|² = 1` is enforced by constrained optimization (e.g.
projected gradient onto the sphere) or reparameterization (spherical angles,
Stiefel embeddings). Decision D4 defers concrete choice to Session C.

---

## 7. Unified gradient vector

Concatenate the enabled parameters into a single flat search vector `x`. A
convenient layout:

```
x = [ vec(φ);  vec(A);  E;  real(c); imag(c) ]    # disabled blocks omitted
    (Nt·M)    (Nt·M)   1   M         M
```

With block sizes `n_φ, n_A, n_E, n_c_real, n_c_imag ∈ {0, Nt·M, Nt·M, 1, M, M}`
depending on which subset of variables is enabled.

The gradient `g = ∂J/∂x` is assembled by concatenating (P), (A), (E), (C_x),
(C_y) as corresponding blocks. L-BFGS in Optim.jl consumes `(x, g)` directly; no
change to the optimizer internals.

**Key insight:** all four formulas (P, A, E, C_x, C_y) use the same `λ₀`. One
forward-adjoint solve → all gradients. The marginal cost of adding a variable is
a single FFT-domain elementwise multiply + reduction, not a second ODE solve.

---

## 8. Preconditioning (Decision D5)

Define diagonal scaling `s` per block:
- `s_φ = 1.0`
- `s_A = 1.0 / δ_bound`   (δ_bound ≈ 0.10 ⇒ s_A = 10)
- `s_E = 1.0 / E_ref`
- `s_c = 1.0` (unit normalized)

Apply via change of variables: optimize in `y = S·x` where `S = diag(s)`. Gradient
transforms as `∂J/∂y = S⁻¹ · ∂J/∂x`. This keeps the L-BFGS internal history
matrix numerically well-conditioned when mixing very different parameter scales.

Implementation: transform on entry (`x = S⁻¹·y`), un-transform gradient
(`g_y = S⁻¹·g_x`). L-BFGS only ever sees scaled `y` and `g_y`.

---

## 9. Regularization gradients (inherited)

Regularizers on φ (GDD penalty, boundary penalty) — same form as
`raman_optimization.jl :: cost_and_gradient`.
Regularizers on A (energy, Tikhonov, TV, flatness) — same form as
`amplitude_optimization.jl :: amplitude_cost`.

All regularization gradients ADD into the corresponding block of `g_x` before
scaling. No new derivations needed.

---

## 10. Finite-difference validation protocol

For each enabled variable block, at a random non-zero test point `x_test`:

1. Evaluate `(J_0, g_full) = cost_and_gradient_multivar(x_test, …)`.
2. For each block (phase/amp/energy): pick 3 random indices where the input
   pulse has significant spectral energy.
3. For each index `i`: compute `J_plus = J(x_test + ε·e_i)`,
   `J_minus = J(x_test - ε·e_i)`, `fd = (J_plus - J_minus)/(2ε)`.
4. Compare to `g_full[i]`: relative error `|fd - g|/max(|fd|,|g|,1e-15)` ≤ 1e-6.

`ε = 1e-5` works for φ; `ε = 1e-6` works for A; `ε = 1e-8 · E_ref` works for E
(scalar — need to rescale to avoid noise).

If any block fails, the derivation must be re-examined before proceeding.

---

## References

- Rivera et al., *Nature Photonics* (2025) — "Noise-immune squeezing of intense
  light" — forward-adjoint framework in MMF.
- Wright, Wise, et al., *Nature Comms* (2024), PMC10918100 — multimodal pulse
  shaping with greedy search (no gradient method); our adjoint approach is the
  differentiated-simulator alternative.
- Nocedal & Wright, *Numerical Optimization* 2nd ed. ch. 7 — scaling & L-BFGS
  for heterogeneous parameter vectors.
- Internal: `src/simulation/sensitivity_disp_mmf.jl` (adjoint ODE, unchanged).
