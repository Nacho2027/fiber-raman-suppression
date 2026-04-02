# Mathematical Formulation: Raman Suppression via Spectral Phase Optimization

**Version 3** — Updated 2026-04-02. All line numbers re-verified against current codebase. Added Sections 5.6-5.8 (log-scale cost, Raman overflow fix, auto-sizing). Section 5.5 SPM formula corrected. Adjoint solver updated to Tsit5/1e-8. Pedagogical explanations added throughout.

**Changes from v2 (2026-03-26):**
- Fixed 13 stale line number references
- Corrected SPM broadening formula in Section 5.5 (was missing 0.86/T0 factor)
- Updated adjoint solver from Vern9/1e-10 to Tsit5/1e-8 (Section 3.3)
- Added Section 5.6: Log-scale cost function (dB-domain optimization)
- Added Section 5.7: Raman response overflow fix
- Added Section 5.8: Auto-sizing of time window and grid
- Updated Section 7.4 to describe the current log-cost implementation
- Added Section 7.5: Boundary verification results
- Added pedagogical "In plain English" explanations throughout

---

## How to Read This Document

This document maps every equation in our optimization to a specific line of code. If you're an undergrad reading this:

- **Sections 1-2**: The physics — what equation governs light in a fiber, and what we're trying to minimize
- **Sections 3-4**: The adjoint method — how we efficiently compute gradients (the "which direction to adjust" information)
- **Section 5**: Numerical details — how the math becomes code
- **Sections 6-7**: Validation — how we know it's correct

You don't need to understand every equation to work with the code. The key ideas are:
1. Light in a fiber follows a wave equation (Section 1)
2. We want to minimize Raman energy at the output (Section 2)
3. The adjoint method gives us the gradient in one backward simulation (Sections 3-4)
4. L-BFGS uses the gradient to update the spectral phase (Section 4)

---

## 1. Forward Problem: Generalized Nonlinear Schrödinger Equation (GNLSE)

### 1.1 Physical Model

**In plain English:** A laser pulse is a packet of light with many different frequencies (colors). As it travels through a fiber, three things happen: (1) different colors travel at different speeds (dispersion), (2) the light intensity changes the fiber's refractive index (Kerr effect), and (3) the light excites vibrations in the glass that steal energy and shift it to redder colors (Raman scattering). The GNLSE captures all three effects.

We propagate a pulse $u(z, t)$ through a single-mode fiber of length $L$. The GNLSE in the frequency domain, written in the **interaction picture** (which separates out the fast oscillations from dispersion), is:

$$
\frac{\partial \tilde{u}_\omega}{\partial z} = i \, e^{-i D(\omega) z} \left[ (1 - f_R) \hat{N}_{\text{Kerr}} + \hat{N}_{\text{Raman}} \right] e^{i D(\omega) z} \, \tilde{u}_\omega
$$

The interaction picture field is related to the lab-frame field by $\tilde{u}_\omega = e^{-i D(\omega) z} \, u_\omega$. This transformation removes the fast dispersive oscillations, letting the ODE solver take larger steps.

**Code reference**: `src/simulation/simulate_disp_mmf.jl`, function `disp_mmf!` (lines 25-61)

### 1.2 Dispersion Operator

**In plain English:** Dispersion means different colors travel at different speeds. We describe this with a Taylor series of the propagation constant around the carrier frequency. $\beta_2$ (group velocity dispersion) is the dominant term — it causes the pulse to spread in time.

$$
D(\omega) = \sum_{n=0}^{N_\beta} \frac{\beta_n}{n!} \omega^n
$$

where $\omega = 2\pi \Delta f$ is angular frequency offset from the carrier, and $\beta_n$ are the Taylor expansion coefficients.

**Code reference** (`src/helpers/helpers.jl` line 187, in `get_disp_fiber_params_user_defined`):
```julia
Dω = hcat([(2π * fftfreq(Nt, 1/Δt) * 1e12) .^ n / factorial(n) for n in 0:β_order]...) * βn_ω
```

**Units**: $\beta_2$ in s²/m, $\beta_3$ in s³/m. The frequency grid is in THz (multiplied by $10^{12}$ to convert to Hz for consistency with SI units of $\beta_n$).

**Parameters (SMF-28 at 1550 nm)**:
- $\beta_2 = -2.6 \times 10^{-26}$ s²/m (anomalous dispersion — longer wavelengths travel faster)
- $\beta_3 = 1.2 \times 10^{-40}$ s³/m (third-order dispersion)

### 1.3 Kerr Nonlinearity (single mode, M=1)

**In plain English:** When light is intense, it changes the refractive index of the glass. This causes the pulse to modify its own phase as it propagates (self-phase modulation). The effect is proportional to the intensity $|u|^2$.

$$
\hat{N}_{\text{Kerr}}(z, t) = \gamma |u(z,t)|^2 \, u(z,t)
$$

For $M$ spatial modes, the overlap tensor $\gamma_{ijkl}$ generalizes this, but for $M=1$ it reduces to a scalar $\gamma$.

**Code reference**: `disp_mmf!` lines 39-43:
```julia
@tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t,k]*v[t,l] + w[t,k]*w[t,l])
@tullio αK[t, i] = δKt[t, i, j] * v[t, j]
@tullio βK[t, i] = δKt[t, i, j] * w[t, j]
@. ηKt = αK + 1im * βK
@. ηKt *= one_m_fR
```

where $v = \text{Re}(u)$, $w = \text{Im}(u)$, so $\delta_K = \gamma |u|^2$ and $\eta_K = \delta_K \cdot u \cdot (1 - f_R)$.

**Parameters**:
- $\gamma = 1.1 \times 10^{-3}$ W⁻¹m⁻¹ (SMF-28)
- $\gamma = 10.0 \times 10^{-3}$ W⁻¹m⁻¹ (HNLF)

### 1.4 Raman Nonlinearity

**In plain English:** Raman scattering is a delayed nonlinear response — the glass atoms don't respond instantly. The Raman response function $h_R(t)$ describes how quickly the glass "rings" after being excited. It's a damped oscillation with a decay time of ~32 fs and an oscillation period of ~12 fs. Mathematically, this appears as a convolution (blurring) of the intensity $|u|^2$ with $h_R(t)$.

$$
\hat{N}_{\text{Raman}}(z, t) = \gamma \left[ h_R(t) * |u(z,t)|^2 \right] u(z,t)
$$

where $*$ denotes temporal convolution and $h_R(t)$ is the Raman response function:

$$
h_R(t) = f_R \cdot \frac{\tau_1^2 + \tau_2^2}{\tau_1 \tau_2^2} \cdot \exp\!\left(-\frac{t}{\tau_2}\right) \sin\!\left(\frac{t}{\tau_1}\right) \cdot \Theta(t)
$$

with $\Theta(t)$ the Heaviside step function (= 1 for $t \geq 0$, = 0 for $t < 0$). The Raman response is **causal** — the glass can only respond after being excited, not before.

**Implemented in frequency domain** (convolution becomes multiplication): `disp_mmf!` lines 46-54:
```julia
hRω_δRω = hRω * FFT(δK)       # multiplication in freq domain = convolution in time
δR = real(IFFT(hRω_δRω))       # back to time domain
ηR[t,i] = Σ_j δR[t,i,j] * u[t,j]
```

**Parameters**:
- $f_R = 0.18$ (fractional Raman contribution — 18% of the nonlinear response is Raman, 82% is instantaneous Kerr)
- $\tau_1 = 12.2$ fs (oscillation period)
- $\tau_2 = 32$ fs (decay time)

**Code reference** (`src/helpers/helpers.jl` lines 107-108 in `get_disp_fiber_params`, or lines 182-183 in `get_disp_fiber_params_user_defined`):
```julia
ts_pos = max.(ts, 0.0)   # clamp negative t to 0 to prevent overflow (see Section 5.7)
hRt = fR * Δt * 1e3 * (τ1^2 + τ2^2) / (τ1 * τ2^2) .* exp.(-ts_pos * 1e15 / τ2) .* sin.(ts_pos * 1e15 / τ1) .* (sign.(ts) .+ 1) / 2
hRω = fft(hRt)
```

### 1.5 Self-Steepening

**In plain English:** Higher frequencies experience slightly stronger nonlinear effects than lower frequencies. This is captured by multiplying the nonlinear terms by $\omega / \omega_0$.

$$
\hat{S}(\omega) = \frac{\omega}{\omega_0}
$$

where $\omega_0 = 2\pi f_0$ is the carrier angular frequency.

**Code reference**: `disp_mmf!` line 59:
```julia
ηt .*= selfsteep   # where selfsteep = fftshift(ωs / ω0)
```

### 1.6 Complete Forward ODE

Combining everything, in the interaction picture:

$$
\frac{d\tilde{u}_\omega}{dz} = i \, e^{-iD(\omega)z} \cdot \hat{S}(\omega) \cdot \left[ (1 - f_R) \eta_K(z,t) + \eta_R(z,t) \right]_\omega \cdot e^{iD(\omega)z}
$$

where subscript $\omega$ denotes the FFT, and:
- $\eta_K = \gamma |u|^2 u$ (Kerr term)
- $\eta_R = \gamma (h_R * |u|^2) u$ (Raman term)
- $u_\omega = e^{iD(\omega)z} \tilde{u}_\omega$ (lab frame recovery)

**Solver**: `DifferentialEquations.jl` with `Tsit5()` (explicit Runge-Kutta 5(4)), `reltol=1e-8`.

**Code reference**: `src/simulation/simulate_disp_mmf.jl` line 182:
```julia
solve(prob_disp_mmf, Tsit5(), reltol=1e-8)
```

---

## 2. Optimization Problem

### 2.1 Decision Variable

**In plain English:** We have a pulse shaper that can delay each color by a different amount. The "spectral phase" $\varphi(\omega)$ is the delay pattern we choose. We're searching for the $\varphi$ that minimizes Raman scattering at the fiber output.

$$
u_0(\omega) = u_{00}(\omega) \cdot e^{i\varphi(\omega)}
$$

where $u_{00}(\omega)$ is the unmodified input pulse spectrum.

**Code reference** (`scripts/raman_optimization.jl` line 63):
```julia
uω0_shaped = @. uω0 * cis(φ)    # cis(x) = exp(ix), avoids computing sin+cos separately
```

### 2.2 Cost Function

**In plain English:** After the pulse propagates through the fiber, we measure how much energy ended up in the "Raman band" — the frequency range where Raman scattering deposits energy (more than 5 THz red-shifted from the pump). We divide by total energy to get a fraction between 0 and 1.

$$
J[\varphi] = \frac{E_{\text{band}}}{E_{\text{total}}} = \frac{\sum_{\omega \in \mathcal{B}} |u_L(\omega)|^2}{\sum_\omega |u_L(\omega)|^2}
$$

where $u_L(\omega)$ is the output field at $z = L$, and $\mathcal{B}$ is the Raman-shifted frequency band (all $\Delta f < -5$ THz from pump center).

**Properties**:
- $J \in [0, 1]$
- $J = 0$ means perfect suppression (no energy in Raman band)
- $J = 1$ means all energy transferred to Raman band
- In decibels: $J_{\text{dB}} = 10 \log_{10}(J)$. Our best result is $J = -78$ dB $= 1.6 \times 10^{-8}$.

**Code reference** (`scripts/common.jl` lines 266-268, in `spectral_band_cost`):
```julia
E_band = sum(abs2.(uωf[band_mask, :]))
E_total = sum(abs2.(uωf))
J = E_band / E_total
```

### 2.3 Adjoint Terminal Condition

**In plain English:** To run the adjoint backward, we need a "starting condition" at the fiber output. This is the derivative of our cost function with respect to the output field — it tells the adjoint "how much each output frequency contributes to the Raman cost."

$$
\lambda_L(\omega) = \frac{\partial J}{\partial u_L^*(\omega)} = \frac{u_L(\omega) \left[ \mathbb{1}_{\mathcal{B}}(\omega) - J \right]}{E_{\text{total}}}
$$

**Derivation**: Using the quotient rule on $J = E_{\text{band}} / E_{\text{total}}$:

For $\omega$ in the Raman band ($\omega \in \mathcal{B}$): the derivative has a positive contribution from the numerator and a negative contribution from the denominator, giving $u_L(\omega) (1 - J) / E_{\text{total}}$.

For $\omega$ outside the band: only the denominator contributes, giving $u_L(\omega) (0 - J) / E_{\text{total}}$.

Combining with the indicator function $\mathbb{1}_{\mathcal{B}}$: $\lambda_L(\omega) = u_L(\omega) (\mathbb{1}_\mathcal{B}(\omega) - J) / E_{\text{total}}$.

**Code reference** (`scripts/common.jl` line 269):
```julia
dJ = uωf .* (band_mask .- J) ./ E_total
```

---

## 3. Adjoint Equation

### 3.1 Why the Adjoint?

**In plain English:** We need the gradient $\partial J / \partial \varphi(\omega)$ — how does changing the phase at each frequency affect the Raman cost? There are thousands of frequencies, so testing each one individually would require thousands of forward simulations.

The adjoint method gives us ALL the gradients in just ONE backward simulation. It works by propagating a "sensitivity field" $\lambda(z)$ backward through the fiber, accumulating information about how each part of the fiber contributed to the final cost.

Think of it like this: the forward simulation asks "what happens to the pulse?" The adjoint asks "where did the Raman energy come from?" Running one forward + one backward gives us the complete gradient.

### 3.2 Adjoint in the Interaction Picture

For an ODE $du/dz = f(u, z)$, the adjoint satisfies:

$$
\frac{d\lambda}{dz} = -\left(\frac{\partial f}{\partial u}\right)^\dagger \lambda - \left(\frac{\partial f}{\partial u^*}\right)^T \lambda^*
$$

In the interaction picture, with $\tilde{\lambda}_\omega = e^{-iD(\omega)z} \lambda_\omega$:

$$
\frac{d\tilde{\lambda}_\omega}{dz} = \underbrace{\lambda \cdot \frac{\partial f_{KR1}^*}{\partial u^*}}_{\text{Term 1}} + \underbrace{(1-f_R) \lambda^* \cdot \frac{\partial f_K}{\partial u^*}}_{\text{Term 2}} + \underbrace{\lambda \cdot \frac{\partial f_{R2}^*}{\partial u^*}}_{\text{Term 3}} + \underbrace{\lambda^* \cdot \frac{\partial f_R}{\partial u^*}}_{\text{Term 4}}
$$

The four terms come from differentiating the Kerr and Raman nonlinearities with respect to the field and its conjugate. Each corresponds to a different way the field interacts with itself through the nonlinearity.

**Code reference** (`src/simulation/sensitivity_disp_mmf.jl` line 78):
```julia
dλ̃ω = λ_∂fKR1c∂uc + one_m_fR * λc_∂fK∂uc + λ_∂fR2c∂uc + λc_∂fR∂uc
```

### 3.3 Term-by-Term Breakdown

**Term 1** (`calc_λ_∂fKR1c∂uc!`, line 130): Combined Kerr-Raman response:
$$
\text{Term 1}_j = i \, e^{-iD_j z} \, \text{IFFT}\!\left[\sum_i \lambda_i(t) \cdot \delta_{KR1}(t, i, j)\right]
$$

**Term 2** (`calc_λc_∂fK∂uc!`, line 142): Kerr conjugate coupling:
$$
\text{Term 2}_j = -i N_t \, e^{-iD_j z} \, \text{IFFT}\!\left[\sum_i \lambda_i^*(t) \cdot \delta_{K2}(t, i, j)\right]
$$

**Term 3** (`calc_λ_∂fR2c∂uc!`, line 93): Raman conjugate response:
$$
\text{Term 3}_j = \frac{i}{N_t} e^{-iD_j z} \, \text{FFT}\!\left[\sum_i \left(\gamma_{lkij} \lambda_i u_k^*\right) \circledast h_R^* \cdot u_j\right]
$$

**Term 4** (`calc_λc_∂fR∂uc!`, line 112): Raman direct response:
$$
\text{Term 4}_j = -i N_t \, e^{-iD_j z} \, \text{IFFT}\!\left[\sum_i \left(\gamma_{lkij} \lambda_i^* u_k\right) \circledast h_R \cdot u_j\right]
$$

where $\circledast$ denotes convolution (implemented via FFT multiplication).

**Solver**: `Tsit5()` (explicit Runge-Kutta 5(4)), `reltol=1e-8`, integrated backward from $z = L$ to $z = 0$. (Changed from Vern9/1e-10 in v2 — the adjoint accuracy is bounded by Tsit5's 4th-order interpolant regardless of adjoint solver order, and matching the forward solver's method/tolerance gave identical gradient accuracy with faster execution.)

**Code reference** (`src/simulation/sensitivity_disp_mmf.jl` line 301):
```julia
solve(prob_adjoint_disp_mmf, Tsit5(), reltol=1e-8, saveat=(0, fiber["L"]))
```

### 3.4 Interaction Picture Transform for the Adjoint

$$
\tilde{\lambda}_L = e^{-iD(\omega)L} \cdot \lambda_L
$$

**Code reference** (`src/simulation/sensitivity_disp_mmf.jl` line 296):
```julia
λ̃ωL = exp.(-1im * fiber["Dω"] * fiber["L"]) .* λωL
```

---

## 4. Gradient Computation (Chain Rule)

### 4.1 Sensitivity of J to Input Field

The adjoint provides:

$$
\delta J = 2 \, \text{Re}\!\left\langle \lambda(0), \delta u_0 \right\rangle = 2 \, \text{Re} \sum_\omega \lambda_0^*(\omega) \, \delta u_0(\omega)
$$

### 4.2 Chain Rule Through the Phase Mask

**In plain English:** We know how $J$ responds to changes in the input field $u_0$ (from the adjoint). Now we need to connect that to changes in the phase $\varphi$. Since $u_0 = u_{00} e^{i\varphi}$, a small change $\delta\varphi$ gives $\delta u_0 = i u_0 \delta\varphi$.

$$
\delta u_0(\omega) = i \, u_0(\omega) \, \delta\varphi(\omega)
$$

Substituting:

$$
\boxed{\frac{\partial J}{\partial \varphi(\omega)} = 2 \, \text{Re}\!\left[ \lambda_0^*(\omega) \cdot i \, u_0(\omega) \right]}
$$

This is the gradient we feed to L-BFGS. It's computed exactly (no finite differences) using one forward + one backward simulation.

**Code reference** (`scripts/raman_optimization.jl` line 91):
```julia
∂J_∂φ = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))
```

### 4.3 Equivalent Form

$$
\frac{\partial J}{\partial \varphi(\omega)} = -2 \, \text{Im}\!\left[ \lambda_0^*(\omega) \cdot u_0(\omega) \right]
$$

since $\text{Re}(i \cdot z) = -\text{Im}(z)$.

---

## 5. Numerical Discretization Details

### 5.1 FFT Conventions

- Forward FFT: $U_k = \sum_{n=0}^{N-1} u_n e^{-2\pi i k n / N}$ (Julia's `fft`)
- Inverse FFT: $u_n = \frac{1}{N} \sum_{k=0}^{N-1} U_k e^{2\pi i k n / N}$ (Julia's `ifft`)
- Frequency grid: `fftfreq(Nt, 1/Δt)` gives frequencies in FFT order
- `fftshift` reorders to centered frequencies (negative freqs on the left)

### 5.2 Time/Frequency Grid

- Time window: `time_window` in ps, divided into `Nt` points
- $\Delta t = \text{time\_window} / N_t$ (ps)
- Frequency resolution: $\Delta f = 1 / (N_t \cdot \Delta t)$ (THz, since $\Delta t$ is in ps)
- Angular frequency: $\Delta\omega = 2\pi \Delta f$ (rad/ps)

**Important unit note for JLD2 data files:**
- `sim_Dt` is stored in **picoseconds**
- `sim_omega0` is stored in **rad/ps** (not rad/s). Convert to THz: $f_0 = \omega_0 / (2\pi)$

### 5.3 Raman Response Discretization

$$
h_R[n] = f_R \cdot \Delta t \cdot 10^3 \cdot \frac{\tau_1^2 + \tau_2^2}{\tau_1 \tau_2^2} \cdot e^{-\max(t_n, 0) / \tau_2} \cdot \sin(\max(t_n, 0) / \tau_1) \cdot \Theta(t_n)
$$

The $\Delta t \cdot 10^3$ prefactor converts the integral from seconds to the ps-based time grid. The $\max(t_n, 0)$ clamp prevents numerical overflow for large negative $t_n$ (see Section 5.7).

### 5.4 Initial Pulse

For a sech² pulse:
$$
u(t) = \sqrt{P_{\text{peak}}} \cdot \text{sech}\!\left(\frac{t}{T_0}\right)
$$

where:
- $T_0 = \text{FWHM} / 1.763$ (sech² pulse width parameter; $1.763 = 2 \cdot \text{acosh}(\sqrt{2})$)
- $P_{\text{peak}} = 0.881374 \cdot P_{\text{cont}} / (\text{FWHM} \times f_{\text{rep}})$ (peak power from average power)

**Default parameters**: FWHM = 185 fs, $f_{\text{rep}} = 80.5$ MHz, $\lambda_0 = 1550$ nm.

### 5.5 Time Window and Grid Sizing

**In plain English:** The simulation uses a finite time window. If it's too small, the pulse spreads beyond the edges and an attenuator absorbs the overflow, corrupting the results. Two utility functions compute safe window sizes.

**`recommended_time_window(L_fiber; safety_factor, beta2, gamma, P_peak, pulse_fwhm)`** (`scripts/common.jl` line 191):

Computes a safe time window [ps] from dispersive walk-off plus SPM-induced broadening:

$$
T_{\text{walk-off}} = |\beta_2| \cdot L \cdot \Delta\omega_{\text{Raman}} \cdot 10^{12} \quad \text{[ps]}
$$

where $\Delta\omega_{\text{Raman}} = 2\pi \times 13 \text{ THz}$. When $\gamma > 0$ and $P_{\text{peak}} > 0$:

$$
\varphi_{NL} = \gamma \cdot P_{\text{peak}} \cdot L \quad \text{[rad] (nonlinear phase accumulation)}
$$

$$
\delta\omega_{\text{SPM}} = \frac{0.86 \cdot \varphi_{NL}}{T_0} \quad \text{[rad/s] (SPM spectral broadening for sech²)}
$$

$$
T_{\text{SPM}} = |\beta_2| \cdot L \cdot \delta\omega_{\text{SPM}} \cdot 10^{12} \quad \text{[ps]}
$$

The 0.86 factor and the division by $T_0 = \text{FWHM}/1.763$ come from Agrawal, *Nonlinear Fiber Optics*, Chapter 4 — the maximum SPM-induced frequency shift for a sech² pulse is $\delta\omega_{\max} \approx 0.86 \cdot \varphi_{NL} / T_0$.

The total safe window is:

$$
T_{\text{window}} = \max\!\left(5, \lceil \text{safety\_factor} \times (T_{\text{walk-off}} + T_{\text{SPM}} + 0.5) \rceil\right) \quad \text{[ps]}
$$

**`nt_for_window(time_window_ps; dt_min_ps=0.0105)`** (`scripts/common.jl` line 233):

$$
N_t = 2^{\lceil \log_2(T_{\text{window}} / \Delta t_{\text{min}}) \rceil}
$$

Default $\Delta t_{\text{min}} = 0.0105$ ps $\approx 10.5$ fs.

### 5.6 Log-Scale Cost Function (NEW in v3)

**In plain English:** When we minimize $J$ directly (a number between 0 and 1), the gradient shrinks as $J$ gets small. At $J = 10^{-4}$, the gradient is $10^{-4}$ times as strong as at $J = 1$. The optimizer thinks it's converged when really there's still 40 dB of room to improve. Switching to $\log_{10}(J)$ fixes this: going from -40 dB to -50 dB produces the same gradient magnitude as going from -10 dB to -20 dB.

When `log_cost=true` (the default), the cost function becomes:

$$
J_{\text{dB}} = 10 \log_{10}\!\left(\max(J, 10^{-15})\right)
$$

The gradient is scaled by the chain rule:

$$
\frac{\partial J_{\text{dB}}}{\partial \varphi} = \frac{10}{J \cdot \ln 10} \cdot \frac{\partial J}{\partial \varphi}
$$

The factor $10 / (J \cdot \ln 10)$ amplifies the gradient as $J$ decreases, exactly compensating the vanishing linear gradient. The floor $\max(J, 10^{-15})$ prevents division by zero.

**Impact:** This single change improved suppression by 20-28 dB across all sweep configurations.

**Code reference** (`scripts/raman_optimization.jl` lines 97-107):
```julia
if log_cost
    J_clamped = max(J, 1e-15)
    J_phys = 10.0 * log10(J_clamped)
    log_scale = 10.0 / (J_clamped * log(10.0))
    ∂J_∂φ_scaled = ∂J_∂φ .* log_scale
end
```

**Optimizer settings:** `f_abstol = 0.01` dB (stops when improvement per iteration < 0.01 dB).

### 5.7 Raman Response Overflow Fix (NEW in v3)

**In plain English:** The Raman response $h_R(t) = 0$ for $t < 0$ (causality). But in the code, we first compute $\exp(-t/\tau_2)$ for ALL time points, then multiply by the Heaviside to zero out $t < 0$. For large negative $t$ (when the time window exceeds ~45 ps), $\exp(-t/\tau_2) = \exp(|t|/\tau_2)$ overflows to infinity. Then $\infty \times 0 = \text{NaN}$ in IEEE floating point, which propagates through the entire simulation.

**Fix:** Clamp $t$ to $\max(t, 0)$ before the exponential:

```julia
ts_pos = max.(ts, 0.0)
exp.(-ts_pos * 1e15 / τ2)   # always finite: exp(0) = 1 for t < 0, decaying for t > 0
```

This doesn't change the mathematical result ($h_R(t < 0) = 0$ regardless), but prevents NaN.

**Impact:** Unblocked all L=5 m sweep points, which previously crashed with NaN.

**Code reference** (`src/helpers/helpers.jl` lines 106-107 and 181-182).

### 5.8 Auto-Sizing Time Window (NEW in v3)

**In plain English:** If you call `setup_raman_problem()` with a time window that's too small for the fiber length and power, the code now automatically increases it instead of just printing a warning.

When $T_{\text{window}} < T_{\text{recommended}}$:
1. Override $T_{\text{window}} \leftarrow T_{\text{recommended}}$
2. Override $N_t \leftarrow \max(N_t, N_{t,\text{recommended}})$
3. Log the change

**Code reference** (`scripts/common.jl` lines 348-359 and 427-438):
```julia
if time_window < tw_rec
    Nt_rec = nt_for_window(tw_rec)
    time_window = tw_rec
    Nt = max(Nt, Nt_rec)
end
```

---

## 6. Characteristic Length Scales

These help you understand when different effects dominate:

$$
L_D = \frac{T_0^2}{|\beta_2|} \quad \text{(dispersion length — how far until the pulse doubles in width)}
$$

$$
L_{NL} = \frac{1}{\gamma P_{\text{peak}}} \quad \text{(nonlinear length — how far until nonlinear phase = 1 radian)}
$$

$$
N = \sqrt{\frac{L_D}{L_{NL}}} = \sqrt{\frac{\gamma P_{\text{peak}} T_0^2}{|\beta_2|}} \quad \text{(soliton number)}
$$

**What N means:**
- $N = 1$: dispersion and nonlinearity exactly balance → the pulse propagates without changing shape (a soliton)
- $N < 1$: dispersion dominates → the pulse just spreads out
- $N > 1$: nonlinearity dominates → the pulse compresses, then breaks apart (soliton fission), and Raman scattering shifts the fragments to longer wavelengths

---

## 7. Validation Results (Computational)

### 7.1 Forward Solver Tests

| Test | Expected | Measured | Tolerance | Status |
|------|----------|----------|-----------|--------|
| Dispersion broadening: $T_{\text{out}}/T_{\text{in}} = \sqrt{1 + (L/L_D)^2}$ | 1.547 | 1.500 | 10% | PASS |
| Energy conservation over 20 z-points | 0 | max dev 2.3e-5 | 1% | PASS |
| Linear regime ($P \to 0$): output matches pure dispersion | identical | rel diff < 1e-3 | 0.1% | PASS |
| Soliton (N=1): shape preserved after 1 period ($f_R \approx 0$) | 0 | shape error 1.3% | 10% | PASS |
| Soliton peak power preservation | 1.0 | 0.9998 | 10% | PASS |

### 7.2 Adjoint Gradient Tests

| Test | Expected | Measured | Status |
|------|----------|----------|--------|
| Taylor remainder: $O(\varepsilon^2)$ slope | 2.0 | **2.00, 2.04** | PASS |
| Finite-difference check (29 components, Nt=128) | rel err < 5% | max **0.026%** | PASS |
| Amplitude gradient with regularizers (29 components) | rel err < 5% | max **0.41%** | PASS |

**How the Taylor test works:** We perturb the phase by $\varepsilon \cdot \delta\varphi$ and measure the remainder $r_2(\varepsilon) = |J(\varphi + \varepsilon\delta\varphi) - J(\varphi) - \varepsilon \nabla J \cdot \delta\varphi|$. If the gradient is correct, $r_2$ should shrink as $\varepsilon^2$ (i.e., making $\varepsilon$ 10× smaller makes $r_2$ 100× smaller). We measured slopes of 2.00 and 2.04, confirming the adjoint gradient is mathematically exact.

### 7.3 Optimization Formulation Tests

| Test | Expected | Measured | Status |
|------|----------|----------|--------|
| Armijo: step in $-\nabla J$ decreases $J$ | $J_1 < J_0$ | $\Delta J = -5.96 \times 10^{-8}$ | PASS |
| $\|\nabla J\|$ reduced after 20 iterations | < 10% of initial | **0.15%** of initial | PASS |
| GDD alone doesn't suppress Raman | $J_{\text{GDD}} / J_0 > 0.7$ | 0.97 | PASS |
| Multi-start convergence (3 starts, 10 iter) | spread < 3 dB | **1.52 dB** | PASS |
| Determinism: identical inputs → identical outputs | bitwise identical | yes | PASS |

### 7.4 Log-Scale Cost Validation (NEW in v3)

The log-scale cost (`log_cost=true`) returns $J_{\text{dB}} = 10 \log_{10}(J)$ with gradient scaled by $10/(J \ln 10)$.

**Consistency check:** The scaling factor is the exact chain rule derivative of $10 \log_{10}(x)$:

$$
\frac{d}{dx}\left(10 \log_{10}(x)\right) = \frac{10}{x \ln 10}
$$

This is applied to the full gradient $\partial J / \partial \varphi$ (which comes from the adjoint and is always computed in linear scale), making cost and gradient consistent.

**Empirical validation:**
- SMF-28 L=2m P=0.20W: improved from -35.1 dB (linear cost) to -60.5 dB (log cost) in same number of iterations
- Multi-start spread collapsed from 28.6 dB to 10.9 dB
- 10/10 starts converged (was 0/10)

### 7.5 Boundary Verification (NEW in v3)

Some optimized points showed high boundary energy (pulse energy near the simulation window edges). We tested whether the optimizer was "cheating" by pushing energy into the attenuator rather than genuinely suppressing Raman:

| Point | Boundary energy | Original J | 2x wider window J | Change |
|-------|----------------|-----------|-------------------|--------|
| SMF28 L=0.5m P=0.20W | 14.4% | -71.4 dB | -65.8 dB | +5.5 dB |
| SMF28 L=1m P=0.10W | 2.4% | -57.0 dB | -68.9 dB | -12.0 dB |
| HNLF L=0.5m P=0.005W | 6.2% | -69.6 dB | -73.8 dB | -4.2 dB |
| HNLF L=0.5m P=0.03W | 25.4% | -51.0 dB | -52.7 dB | -1.7 dB |

**Conclusion:** 3/4 points improve with wider windows (the optimizer uses the extra room productively). One point lost 5.5 dB — its "honest" suppression is -66 dB rather than -71 dB. Points with low boundary energy (<5%) are fully trustworthy.

---

## 8. Questions for Analytical Verification

1. **Is the adjoint ODE (Section 3.2) the correct adjoint of the forward ODE (Section 1.6)?** Specifically, do the four terms correspond to differentiating the Kerr and Raman nonlinearities w.r.t. $u$ and $u^*$?

2. **Is the terminal condition (Section 2.3) correct?** Verify $\partial J / \partial u_L^*$ for the quotient $J = E_{\text{band}} / E_{\text{total}}$.

3. **Is the chain rule through the phase mask (Section 4.2) correct?** Verify that $\delta u_0 = i u_0 \delta\varphi$ when $u_0 = u_{00} e^{i\varphi}$.

4. **Are the FFT scaling factors consistent?** The factors of $N_t$ and $1/N_t$ from FFT/IFFT must be tracked through the adjoint.

5. **Is the self-steepening correctly adjointed?** The forward multiplies by $\omega/\omega_0$ after IFFT. The adjoint should apply the same factor.

6. **Does the interaction picture preserve adjoint structure?** Verify $\tilde{\lambda} = e^{-iDz} \lambda$ is the correct transform for the adjoint variable.

7. **Is the log-cost gradient correct?** Verify that $\partial J_{\text{dB}} / \partial \varphi = (10 / J \ln 10) \cdot \partial J / \partial \varphi$ follows from the chain rule and that L-BFGS with this cost/gradient pair is mathematically well-posed.
