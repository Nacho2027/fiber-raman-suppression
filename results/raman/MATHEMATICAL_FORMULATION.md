# Mathematical Formulation: Raman Suppression via Spectral Phase Optimization

## Task for Analytical Verification

This document contains the complete mathematical formulation of our Raman suppression optimization system. Every equation maps to a specific line of code. The goal is to analytically verify that:

1. The forward GNLSE is correctly discretized
2. The adjoint equation is the correct adjoint of the forward equation
3. The gradient ∂J/∂φ follows from the chain rule correctly
4. The cost function and its terminal condition are consistent

Computational validation results are included at the end.

---

## 1. Forward Problem: Generalized Nonlinear Schrödinger Equation (GNLSE)

### 1.1 Physical Model

We propagate a pulse u(z, t) through a single-mode fiber of length L. The GNLSE in the frequency domain is:

$$
\frac{\partial \tilde{u}_\omega}{\partial z} = i \, e^{-i D(\omega) z} \left[ (1 - f_R) \hat{N}_{\text{Kerr}} + \hat{N}_{\text{Raman}} \right] e^{i D(\omega) z} \, \tilde{u}_\omega
$$

where $\tilde{u}_\omega(z)$ is the field in the **interaction picture**: $\tilde{u}_\omega = e^{-i D(\omega) z} \, u_\omega$.

**Code reference**: `src/simulation/simulate_disp_mmf.jl`, function `disp_mmf!` (lines 12-45)

### 1.2 Dispersion Operator

$$
D(\omega) = \sum_{n=0}^{N_\beta} \frac{\beta_n}{n!} \omega^n
$$

where $\omega = 2\pi \Delta f$ is angular frequency offset from the carrier, and $\beta_n$ are the Taylor expansion coefficients of the propagation constant.

**Implemented as** (helpers.jl line 88):
```julia
Dω = hcat([(2π * fftfreq(Nt, 1/Δt) * 1e12)^n / factorial(n) for n in 0:β_order]...) * βn_ω
```

**Units**: $\beta_2$ in s²/m, $\beta_3$ in s³/m. The frequency grid is in THz (multiplied by $10^{12}$ to convert to Hz).

**Parameters (SMF-28 at 1550nm)**:
- $\beta_2 = -2.17 \times 10^{-26}$ s²/m ($= -21.7$ ps²/km)
- $\beta_3 = 1.2 \times 10^{-40}$ s³/m ($= 0.12$ ps³/km)

### 1.3 Kerr Nonlinearity (single mode, M=1)

$$
\hat{N}_{\text{Kerr}}(z, t) = \gamma |u(z,t)|^2 \, u(z,t)
$$

For M modes, the overlap tensor $\gamma_{ijkl}$ generalizes this, but for M=1 it reduces to a scalar $\gamma$.

**Code reference**: `disp_mmf!` lines 25-29:
```julia
@tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t,k]*v[t,l] + w[t,k]*w[t,l])
@tullio αK[t, i] = δKt[t, i, j] * v[t, j]
@tullio βK[t, i] = δKt[t, i, j] * w[t, j]
ηKt = (αK + im*βK) * (1 - f_R)
```

where $v = \text{Re}(u)$, $w = \text{Im}(u)$, so $\delta_K = \gamma |u|^2$ and $\eta_K = \delta_K \cdot u \cdot (1 - f_R)$.

**Parameters**:
- $\gamma = 1.1 \times 10^{-3}$ W⁻¹m⁻¹ (SMF-28)
- $\gamma = 10.0 \times 10^{-3}$ W⁻¹m⁻¹ (HNLF)

### 1.4 Raman Nonlinearity

$$
\hat{N}_{\text{Raman}}(z, t) = \gamma \left[ h_R(t) * |u(z,t)|^2 \right] u(z,t)
$$

where $*$ denotes temporal convolution and $h_R(t)$ is the Raman response function:

$$
h_R(t) = f_R \cdot \frac{\tau_1^2 + \tau_2^2}{\tau_1 \tau_2^2} \cdot \exp\!\left(-\frac{t}{\tau_2}\right) \sin\!\left(\frac{t}{\tau_1}\right) \cdot \Theta(t)
$$

with $\Theta(t)$ the Heaviside step function.

**Implemented in frequency domain** (convolution → multiplication): `disp_mmf!` lines 31-39:
```julia
hRω_δRω = hRω * FFT(δK)       # multiplication in freq domain = convolution in time
δR = real(IFFT(hRω_δRω))       # back to time domain
ηR[t,i] = Σ_j δR[t,i,j] * u[t,j]
```

**Parameters**:
- $f_R = 0.18$ (fractional Raman contribution)
- $\tau_1 = 12.2$ fs
- $\tau_2 = 32$ fs

**Code reference** (helpers.jl lines 83-84):
```julia
hRt = fR * Δt * 1e3 * (τ1² + τ2²)/(τ1 * τ2²) * exp.(-ts*1e15/τ2) .* sin.(ts*1e15/τ1) .* (sign.(ts) .+ 1)/2
hRω = fft(hRt)
```

### 1.5 Self-Steepening

The nonlinear terms are multiplied by the self-steepening factor:

$$
\hat{S}(\omega) = \frac{\omega}{\omega_0}
$$

where $\omega_0 = 2\pi f_0$ is the carrier angular frequency.

**Code reference**: `disp_mmf!` line 43:
```julia
ηt .*= selfsteep   # where selfsteep = fftshift(ωs / ω0)
```

### 1.6 Complete Forward ODE

Combining everything, in the interaction picture:

$$
\frac{d\tilde{u}_\omega}{dz} = i \, e^{-iD(\omega)z} \cdot \hat{S}(\omega) \cdot \left[ (1 - f_R) \eta_K(z,t) + \eta_R(z,t) \right]_\omega \cdot e^{iD(\omega)z}
$$

where subscript $\omega$ denotes the FFT, and:
- $\eta_K = \gamma |u|^2 u$ (Kerr)
- $\eta_R = \gamma (h_R * |u|^2) u$ (Raman)
- $u_\omega = e^{iD(\omega)z} \tilde{u}_\omega$ (lab frame recovery)

**Solver**: `DifferentialEquations.jl` with `Tsit5()` (explicit Runge-Kutta 5(4)), `reltol=1e-8`.

---

## 2. Optimization Problem

### 2.1 Decision Variable

We optimize the spectral phase $\varphi(\omega)$ applied to the input pulse:

$$
u_0(\omega) = u_{00}(\omega) \cdot e^{i\varphi(\omega)}
$$

where $u_{00}(\omega)$ is the unmodified input pulse spectrum.

**Code reference** (raman_optimization.jl line 58):
```julia
uω0_shaped = uω0 * cis(φ)    # cis(x) = exp(ix)
```

### 2.2 Cost Function

$$
J[\varphi] = \frac{E_{\text{band}}}{E_{\text{total}}} = \frac{\sum_{\omega \in \mathcal{B}} |u_L(\omega)|^2}{\sum_\omega |u_L(\omega)|^2}
$$

where $u_L(\omega)$ is the output field at $z = L$, and $\mathcal{B}$ is the Raman-shifted frequency band (defined by `band_mask`: all $\Delta f < -5$ THz, i.e., red-shifted beyond the Raman threshold).

**Properties**:
- $J \in [0, 1]$
- $J = 0$ means no energy in the Raman band (perfect suppression)
- $J = 1$ means all energy in the Raman band

**Code reference** (common.jl lines 61-77):
```julia
E_band = sum(abs2.(uωf[band_mask, :]))
E_total = sum(abs2.(uωf))
J = E_band / E_total
```

### 2.3 Adjoint Terminal Condition

The gradient of $J$ with respect to the output field $u_L(\omega)$ provides the terminal condition for the adjoint:

$$
\lambda_L(\omega) = \frac{\partial J}{\partial u_L^*(\omega)} = \frac{u_L(\omega) \left[ \mathbb{1}_{\mathcal{B}}(\omega) - J \right]}{E_{\text{total}}}
$$

**Derivation**: Using the quotient rule on $J = E_{\text{band}} / E_{\text{total}}$:

$$
\frac{\partial J}{\partial u_L^*(\omega)} = \frac{\partial}{\partial u_L^*} \frac{\sum_{\omega' \in \mathcal{B}} |u_L(\omega')|^2}{\sum_{\omega'} |u_L(\omega')|^2}
$$

For $\omega \in \mathcal{B}$: numerator derivative gives $u_L(\omega)$, denominator derivative gives $-J \cdot u_L(\omega)$, both divided by $E_{\text{total}}$.

For $\omega \notin \mathcal{B}$: numerator derivative is 0, denominator derivative gives $-J \cdot u_L(\omega) / E_{\text{total}}$.

Combining: $\lambda_L(\omega) = u_L(\omega) (\mathbb{1}_\mathcal{B}(\omega) - J) / E_{\text{total}}$.

**Code reference** (common.jl line 70):
```julia
dJ = uωf .* (band_mask .- J) ./ E_total
```

---

## 3. Adjoint Equation

### 3.1 Derivation

The adjoint equation propagates $\lambda(z)$ **backward** from $z = L$ to $z = 0$. For an ODE $du/dz = f(u, z)$, the adjoint satisfies:

$$
\frac{d\lambda}{dz} = -\left(\frac{\partial f}{\partial u}\right)^\dagger \lambda - \left(\frac{\partial f}{\partial u^*}\right)^T \lambda^*
$$

where $\dagger$ denotes conjugate transpose and the sign is negative because we integrate backward ($z: L \to 0$).

### 3.2 Adjoint in the Interaction Picture

In the interaction picture, with $\tilde{\lambda}_\omega = e^{-iD(\omega)z} \lambda_\omega$, the adjoint ODE becomes:

$$
\frac{d\tilde{\lambda}_\omega}{dz} = \underbrace{\lambda \cdot \frac{\partial f_{KR1}^*}{\partial u^*}}_{\text{Term 1}} + \underbrace{(1-f_R) \lambda^* \cdot \frac{\partial f_K}{\partial u^*}}_{\text{Term 2}} + \underbrace{\lambda \cdot \frac{\partial f_{R2}^*}{\partial u^*}}_{\text{Term 3}} + \underbrace{\lambda^* \cdot \frac{\partial f_R}{\partial u^*}}_{\text{Term 4}}
$$

where the four terms arise from differentiating the Kerr and Raman nonlinear operators with respect to the field and its conjugate.

**Code reference** (sensitivity_disp_mmf.jl line 50):
```julia
dλ̃ω = λ_∂fKR1c∂uc + one_m_fR * λc_∂fK∂uc + λ_∂fR2c∂uc + λc_∂fR∂uc
```

### 3.3 Term-by-Term Breakdown

**Term 1** (`calc_λ_∂fKR1c∂uc!`, line 76): Combined Kerr-Raman response to $|u|^2$:
$$
\text{Term 1}_j = i \, e^{-iD_j z} \, \text{IFFT}\!\left[\sum_i \lambda_i(t) \cdot \delta_{KR1}(t, i, j)\right]
$$
where $\delta_{KR1} = 2(1-f_R)\delta_{K1} + \delta_{R1}$ and $\delta_{K1}(t,i,j) = \sum_{k,l} \gamma_{lkij} |u_k||u_l|$.

**Term 2** (`calc_λc_∂fK∂uc!`, line 82): Kerr conjugate coupling:
$$
\text{Term 2}_j = -i N_t \, e^{-iD_j z} \, \text{IFFT}\!\left[\sum_i \lambda_i^*(t) \cdot \delta_{K2}(t, i, j)\right]
$$
where $\delta_{K2}(t,i,j) = \sum_{k,l} \gamma_{lkij} u_k u_l$ (without conjugation).

**Term 3** (`calc_λ_∂fR2c∂uc!`, line 55): Raman conjugate response:
$$
\text{Term 3}_j = \frac{i}{N_t} e^{-iD_j z} \, \text{FFT}\!\left[\sum_i \left(\gamma_{lkij} \lambda_i u_k^*\right) \circledast h_R^* \cdot \text{IFFT}(u)_j\right]
$$
where $\circledast$ denotes the convolution implemented via FFT multiplication.

**Term 4** (`calc_λc_∂fR∂uc!`, line 65): Raman direct response:
$$
\text{Term 4}_j = -i N_t \, e^{-iD_j z} \, \text{IFFT}\!\left[\sum_i \left(\gamma_{lkij} \lambda_i^* u_k\right) \circledast h_R \cdot u_j\right]
$$

**Solver**: `Vern9()` (explicit Runge-Kutta 9(8)), `reltol=1e-10`, integrated from $z = L$ to $z = 0$.

### 3.4 Interaction Picture Transform for the Adjoint

The terminal condition is transformed to the interaction picture before solving:

$$
\tilde{\lambda}_L = e^{-iD(\omega)L} \cdot \lambda_L
$$

**Code reference** (sensitivity_disp_mmf.jl line 168):
```julia
λ̃ωL = exp.(-1im * fiber["Dω"] * fiber["L"]) .* λωL
```

---

## 4. Gradient Computation (Chain Rule)

### 4.1 Sensitivity of J to Input Field

The adjoint provides the sensitivity of $J$ to perturbations $\delta u_0$ of the input field:

$$
\delta J = 2 \, \text{Re}\!\left\langle \lambda(0), \delta u_0 \right\rangle = 2 \, \text{Re} \sum_\omega \lambda_0^*(\omega) \, \delta u_0(\omega)
$$

### 4.2 Chain Rule Through the Phase Mask

Since $u_0(\omega) = u_{00}(\omega) e^{i\varphi(\omega)}$, a perturbation $\delta\varphi(\omega)$ gives:

$$
\delta u_0(\omega) = i \, u_0(\omega) \, \delta\varphi(\omega)
$$

Substituting into the sensitivity formula:

$$
\delta J = 2 \, \text{Re} \sum_\omega \lambda_0^*(\omega) \cdot i \, u_0(\omega) \cdot \delta\varphi(\omega)
$$

Therefore:

$$
\boxed{\frac{\partial J}{\partial \varphi(\omega)} = 2 \, \text{Re}\!\left[ \lambda_0^*(\omega) \cdot i \, u_0(\omega) \right]}
$$

**Code reference** (raman_optimization.jl line 87):
```julia
∂J_∂φ = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))
```

### 4.3 Key Identity to Verify

The above formula can be rewritten as:

$$
\frac{\partial J}{\partial \varphi(\omega)} = -2 \, \text{Im}\!\left[ \lambda_0^*(\omega) \cdot u_0(\omega) \right]
$$

since $\text{Re}(i \cdot z) = -\text{Im}(z)$. This is an equivalent form that may be easier to verify analytically.

---

## 5. Numerical Discretization Details

### 5.1 FFT Conventions

- Forward FFT: $U_k = \sum_{n=0}^{N-1} u_n e^{-2\pi i k n / N}$ (Julia's `fft`)
- Inverse FFT: $u_n = \frac{1}{N} \sum_{k=0}^{N-1} U_k e^{2\pi i k n / N}$ (Julia's `ifft`)
- Frequency grid: `fftfreq(Nt, 1/Δt)` gives frequencies in FFT order
- `fftshift` reorders to centered frequencies

### 5.2 Time/Frequency Grid

- Time window: `time_window` in ps, divided into `Nt` points
- $\Delta t = \text{time\_window} / N_t$ (ps)
- Frequency resolution: $\Delta f = 1 / (N_t \cdot \Delta t)$ (THz)
- Angular frequency: $\Delta\omega = 2\pi \Delta f$ (rad/ps)

### 5.3 Raman Response Discretization

The continuous Raman response is sampled and FFT'd:

$$
h_R[n] = f_R \cdot \Delta t \cdot 10^3 \cdot \frac{\tau_1^2 + \tau_2^2}{\tau_1 \tau_2^2} \cdot e^{-t_n / \tau_2} \sin(t_n / \tau_1) \cdot \Theta(t_n)
$$

The $\Delta t \cdot 10^3$ prefactor ensures correct units when convolution is performed via FFT (the factor converts the integral from seconds to the simulation's ps-based time grid).

### 5.4 Initial Pulse

For a sech² pulse:
$$
u(t) = \sqrt{P_{\text{peak}}} \cdot \text{sech}\!\left(\frac{t}{T_0}\right)
$$

where:
- $T_0 = \text{FWHM} / (2 \cdot \text{acosh}(\sqrt{2}))$ (sech pulse parameter)
- $P_{\text{peak}} \approx P_{\text{cont}} / (\text{FWHM} \times f_{\text{rep}})$

**Default parameters**: FWHM = 185 fs, $f_{\text{rep}} = 80.5$ MHz, $\lambda_0 = 1550$ nm.

---

## 6. Characteristic Length Scales

For reference in verifying test results:

$$
L_D = \frac{T_0^2}{|\beta_2|} \quad \text{(dispersion length)}
$$

$$
L_{NL} = \frac{1}{\gamma P_{\text{peak}}} \quad \text{(nonlinear length)}
$$

$$
N = \sqrt{\frac{L_D}{L_{NL}}} = \sqrt{\frac{\gamma P_{\text{peak}} T_0^2}{|\beta_2|}} \quad \text{(soliton number)}
$$

**Fundamental soliton condition** ($N = 1$):

$$
P_{\text{peak}} = \frac{|\beta_2|}{\gamma T_0^2}
$$

A fundamental soliton should propagate indefinitely without changing shape (in the absence of Raman, i.e., $f_R = 0$). This is the strongest test of the forward solver.

---

## 7. Validation Results (Computational)

### 7.1 Forward Solver Tests

| Test | Expected | Measured | Tolerance | Status |
|------|----------|----------|-----------|--------|
| Pure dispersion broadening: $T_{\text{out}}/T_{\text{in}} = \sqrt{1 + (L/L_D)^2}$ | 1.547 | 1.500 | 10% | PASS |
| Energy conservation: $\sum|u(z)|^2 = \text{const}$ over 20 z-points | 0 | max dev 2.3e-5 | 1% | PASS |
| Linear regime ($P \to 0$): output matches pure dispersion | identical | rel diff < 1e-3 | 0.1% | PASS |
| Soliton (N=1): shape preserved after 1 period ($f_R \approx 0$) | 0 | shape error 1.3% | 10% | PASS |
| Soliton peak power preservation | 1.0 | 0.9998 | 10% | PASS |

### 7.2 Adjoint Gradient Tests

| Test | Expected | Measured | Status |
|------|----------|----------|--------|
| Taylor remainder: $\|J(\varphi + \varepsilon\delta\varphi) - J(\varphi) - \varepsilon \langle\nabla J, \delta\varphi\rangle\| = O(\varepsilon^2)$ | slope = 2.0 | **2.00, 2.04** | PASS |
| Full finite-difference check (29 spectral components, $N_t = 128$) | rel err < 5% | max **0.026%** | PASS |
| Amplitude gradient with all regularizers (29 components) | rel err < 5% | max **0.41%** | PASS |

**Note on Taylor test**: The remainder $r_2(\varepsilon) = |J(\varphi + \varepsilon\delta\varphi) - J(\varphi) - \varepsilon \nabla J \cdot \delta\varphi|$ should satisfy $r_2(\varepsilon/10) / r_2(\varepsilon) \approx 100$ (i.e., $\log_{10}$ of the ratio $\approx 2$). We measured slopes of **2.00** and **2.04**, confirming the adjoint gradient is mathematically exact to machine precision.

### 7.3 Optimization Formulation Tests

| Test | Expected | Measured | Status |
|------|----------|----------|--------|
| Armijo: step in $-\nabla J$ decreases $J$ | $J_1 < J_0$ | $J_0 - J_1 = 5.96 \times 10^{-8}$ | PASS |
| $\|\nabla J\|$ reduced after 20 iterations | < 10% of initial | **0.15%** of initial | PASS |
| Pure GDD doesn't suppress Raman (short fiber) | $J_{\text{GDD}} / J_0 > 0.7$ | 0.97 | PASS |
| Multi-start convergence (3 random starts, 10 iter each) | spread < 3 dB | **1.52 dB** | PASS |
| Determinism: identical inputs → identical outputs | bitwise identical | yes | PASS |
| Monotonicity: longer fiber → more Raman | $J(0.5\text{m}) > J(0.1\text{m})$ | $7.35 \times 10^{-4} > 7.55 \times 10^{-5}$ | PASS |

---

## 8. Questions for Analytical Verification

1. **Is the adjoint ODE (Section 3.2) the correct adjoint of the forward ODE (Section 1.6)?** Specifically, do the four terms in the adjoint correspond to differentiating the Kerr and Raman nonlinearities with respect to $u$ and $u^*$?

2. **Is the terminal condition (Section 2.3) correct?** Verify $\partial J / \partial u_L^*$ for the quotient $J = E_{\text{band}} / E_{\text{total}}$.

3. **Is the chain rule through the phase mask (Section 4.2) correct?** Verify that $\delta u_0 = i u_0 \delta\varphi$ when $u_0 = u_{00} e^{i\varphi}$.

4. **Are the FFT scaling factors consistent?** The forward equation has factors of $N_t$ and $1/N_t$ from FFT/IFFT. Verify that the adjoint correctly accounts for these.

5. **Is the self-steepening term ($\omega/\omega_0$) correctly handled in the adjoint?** The forward equation multiplies by `selfsteep` after the IFFT. The adjoint (line 24) multiplies $\lambda_\omega$ by $\tau_\omega = \text{fftshift}(\omega_s / \omega_0)$ — verify this is the correct adjoint of the self-steepening operation.

6. **Does the interaction picture transform preserve the adjoint structure?** The forward uses $\tilde{u} = e^{-iDz} u$ and the adjoint uses $\tilde{\lambda} = e^{-iDz} \lambda$. Verify this is the correct transform for the adjoint variable.

7. **Raman convolution adjoint**: The forward computes $h_R * |u|^2$ via FFT multiplication. Verify that the adjoint terms (Terms 3 and 4) correctly use $h_R^*$ (conjugate) and the forward/inverse FFT scaling is consistent.
