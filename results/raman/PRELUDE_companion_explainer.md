# The Companion Explainer: Understanding the Math Behind Raman Suppression

**For:** Ignacio — an undergrad physics major who wants to actually understand what's going on
**Prerequisite:** You know what a Fourier transform is, what a wave equation looks like, and basic complex numbers. That's it.

---

## Part 1: The Big Picture (No Math Yet)

Imagine you have a flashlight beam going through a long piece of glass. The glass has atoms that vibrate. When your light hits those atoms, some of it bounces off at a lower energy — like a ball bouncing off a trampoline and coming back slower. That's Raman scattering. The light loses energy and shifts to redder colors.

Now imagine your flashlight is actually a femtosecond laser — a pulse of light so short it lasts 0.000000000000185 seconds (185 fs). This pulse contains many colors mixed together, like a tiny rainbow. As it travels through the fiber, three things happen simultaneously:

1. **Dispersion:** Different colors travel at different speeds. The pulse spreads out in time.
2. **Kerr effect:** The light is so intense it literally changes the refractive index of the glass. The pulse modifies its own phase as it propagates.
3. **Raman scattering:** The glass steals energy and red-shifts it.

Our job: find a way to pre-shape the pulse so that, as it propagates, the Raman scattering is minimized.

The twist: we can only control the **spectral phase** at the input — that is, how much we delay each color before it enters the fiber. We can't change which colors are present or how bright they are (that would be amplitude shaping). It's like we're allowed to adjust the timing of each runner in a relay race, but not which runners participate.

---

## Part 2: The Wave Equation (The GNLSE)

### From Maxwell's equations to one equation

You've seen the wave equation in physics class:

$$\frac{\partial^2 E}{\partial z^2} = \frac{1}{c^2}\frac{\partial^2 E}{\partial t^2}$$

For light in a fiber, we need to add three modifications:
1. The speed of light depends on frequency (dispersion)
2. The refractive index depends on intensity (Kerr effect)
3. Energy transfers between frequencies (Raman scattering)

After a lot of algebra (starting from Maxwell's equations, applying the slowly-varying envelope approximation, and keeping terms to first order in the nonlinearity), you get the **Generalized Nonlinear Schrodinger Equation (GNLSE)**:

$$\frac{\partial u}{\partial z} = \underbrace{iD(\omega) \cdot u}_{\text{dispersion}} + \underbrace{i\gamma(1-f_R)|u|^2 u}_{\text{Kerr}} + \underbrace{i\gamma f_R (h_R * |u|^2) u}_{\text{Raman}}$$

Let's unpack each piece:

**The field $u(z, t)$:** This is the complex envelope of the electric field. Its magnitude squared $|u|^2$ gives the instantaneous power in Watts. It depends on position along the fiber ($z$) and time ($t$).

**Dispersion $iD(\omega) u$:** In the frequency domain, each color $\omega$ picks up a phase $D(\omega) \cdot z$ as it propagates. $D(\omega)$ is a polynomial:

$$D(\omega) = \frac{\beta_2}{2}\omega^2 + \frac{\beta_3}{6}\omega^3 + \cdots$$

- $\beta_2$ = group velocity dispersion. Negative means longer wavelengths travel faster (anomalous dispersion).
- $\beta_3$ = third-order dispersion. Usually a small correction.

Think of it like this: $D(\omega)$ is a recipe for how much each color gets delayed per meter of fiber.

**Kerr effect $i\gamma|u|^2 u$:** The refractive index changes proportionally to the light intensity: $n = n_0 + n_2 |E|^2$. This means the phase of the light shifts by an amount proportional to its own intensity. The constant $\gamma$ (gamma) captures how strongly the fiber responds. Units: W$^{-1}$m$^{-1}$.

For SMF-28 fiber: $\gamma = 0.0011$ W$^{-1}$m$^{-1}$ (weakly nonlinear)
For HNLF: $\gamma = 0.010$ W$^{-1}$m$^{-1}$ (highly nonlinear — 10x stronger)

**Raman effect $i\gamma f_R (h_R * |u|^2) u$:** The glass doesn't respond instantly — the atoms take ~30 fs to ring up and then decay. The response function $h_R(t)$ is a damped oscillation:

$$h_R(t) = \frac{\tau_1^2 + \tau_2^2}{\tau_1 \tau_2^2} e^{-t/\tau_2} \sin(t/\tau_1) \cdot \Theta(t)$$

where $\tau_1 = 12.2$ fs (oscillation period), $\tau_2 = 32$ fs (decay time), and $\Theta(t)$ is the Heaviside step function (= 0 for t < 0, because the glass can't respond before being hit).

The $*$ means convolution — the Raman response at time $t$ depends on the intensity history over the previous ~100 fs. The fraction $f_R = 0.18$ means 18% of the nonlinear response is Raman (delayed) and 82% is Kerr (instantaneous).

### The interaction picture trick

The dispersion term $iD(\omega)u$ causes rapid oscillations that make the ODE solver take tiny steps. It's like trying to simulate a vibrating guitar string by tracking every oscillation — wasteful if you only care about the slowly-changing envelope.

The fix: define a new variable $\tilde{u}$ that "rotates with" the dispersion:

$$\tilde{u}_\omega(z) = e^{-iD(\omega)z} \cdot u_\omega(z)$$

This is exactly like going to a rotating reference frame in classical mechanics. In the rotating frame, the dispersion vanishes and only the nonlinear terms remain:

$$\frac{d\tilde{u}_\omega}{dz} = i \cdot e^{-iDz} \cdot \text{[nonlinear stuff in the lab frame]} \cdot e^{+iDz}$$

The ODE solver can now take large steps because the fast oscillations are gone. When we need the physical field, we just undo the transformation: $u_\omega = e^{+iDz}\tilde{u}_\omega$.

---

## Part 3: The Optimization Problem

### What we control

A pulse shaper applies a spectral phase $\varphi(\omega)$ to each frequency:

$$u_0(\omega) = u_{00}(\omega) \cdot e^{i\varphi(\omega)}$$

where $u_{00}$ is the original (unshaped) pulse. In code: `cis(phi)` which computes $e^{i\varphi}$ efficiently.

This doesn't change the power spectrum $|u_0(\omega)|^2 = |u_{00}(\omega)|^2$ — it only changes the timing of different colors. But that timing determines the temporal shape $u_0(t)$, which determines how the pulse evolves in the fiber.

### What we minimize

After propagation through length $L$, the output field is $u_L(\omega)$. We define the cost:

$$J = \frac{\sum_{\omega \in \text{Raman band}} |u_L(\omega)|^2}{\sum_{\text{all } \omega} |u_L(\omega)|^2} = \frac{\text{energy in Raman band}}{\text{total energy}}$$

The "Raman band" is defined as all frequencies shifted more than 5 THz to the red of the pump center. $J = 0$ means no energy was transferred to Raman. $J = 1$ means everything was Raman-shifted.

In decibels: $J_{\text{dB}} = 10 \log_{10}(J)$. Our best result is $J = -78$ dB = 0.000000016 = 16 billionths.

### The landscape

$J$ is a function of $\varphi(\omega)$ — a vector with $N_t = 8192$ components. We need to find the $\varphi$ that minimizes $J$. The landscape is like a mountain range in 8192 dimensions.

We can't try all possibilities (there are infinitely many). We need the **gradient** — a vector that points in the direction of steepest descent. If we have the gradient, we can iteratively walk downhill.

---

## Part 4: The Adjoint Method (The Key Insight)

### The problem with brute force

To compute $\partial J / \partial \varphi_k$ (how $J$ changes when we tweak the phase at frequency $k$), we could use finite differences:

$$\frac{\partial J}{\partial \varphi_k} \approx \frac{J(\varphi + \epsilon \cdot e_k) - J(\varphi - \epsilon \cdot e_k)}{2\epsilon}$$

But this requires **two full simulations per frequency component**. With $N_t = 8192$ components, that's 16,384 simulations. Each takes ~1 second. Total: **4.5 hours per gradient evaluation.** And we need 30-60 gradients per optimization. That's weeks of compute.

### The adjoint trick: run the movie backwards

Instead of asking "how does tweaking frequency $k$ affect the output?" for each $k$ separately, the adjoint method asks the reverse question: "given that we know what went wrong at the output, how did each input frequency contribute?"

**Forward simulation** (takes ~1 second): Propagate $u_0 \to u_L$ through the fiber. This tells us the cost $J$.

**Adjoint simulation** (takes ~1 second): Start from the output and propagate a "sensitivity field" $\lambda$ backwards from $z = L$ to $z = 0$. The starting condition is:

$$\lambda_L(\omega) = \frac{u_L(\omega) \cdot [\mathbb{1}_{\text{band}}(\omega) - J]}{E_{\text{total}}}$$

This is the derivative of $J$ with respect to the output field — it encodes "how much each output frequency contributed to the Raman cost." Large $\lambda_L$ at a frequency means that frequency is strongly contributing to the Raman energy.

The adjoint field $\lambda(z)$ then propagates backward through the same fiber, feeling the same nonlinearity (but transposed and conjugated). When it reaches $z = 0$, it contains the sensitivity to every input frequency simultaneously:

$$\frac{\partial J}{\partial \varphi(\omega)} = 2 \cdot \text{Re}\left[\lambda_0^*(\omega) \cdot i \cdot u_0(\omega)\right]$$

**That's the entire gradient, from one forward + one backward simulation.** Total: ~2 seconds instead of 4.5 hours.

### Why does this work? (Intuition)

Think about blame in a relay race. If the team lost, you could:
- **Forward approach:** Replace each runner one at a time and re-run the race. Takes $N$ races.
- **Adjoint approach:** Start from the finish line and trace backward: "we lost 2 seconds in the last leg, which was caused by a bad handoff in the third leg, which was caused by runner 2 starting too late." One backward analysis tells you every runner's contribution.

The math is more involved (it uses the adjoint of the linearized GNLSE), but the principle is the same.

### The adjoint equation

The adjoint field satisfies:

$$\frac{d\lambda}{dz} = -\left(\frac{\partial f}{\partial u}\right)^\dagger \lambda - \left(\frac{\partial f}{\partial u^*}\right)^T \lambda^*$$

where $f$ is the right-hand side of the GNLSE. The $\dagger$ means conjugate transpose. The negative sign is because we integrate backwards.

For our GNLSE, this splits into four terms (corresponding to differentiating the Kerr and Raman nonlinearities with respect to $u$ and $u^*$):

$$\frac{d\tilde{\lambda}}{dz} = \text{Term 1} + \text{Term 2} + \text{Term 3} + \text{Term 4}$$

You don't need to memorize these terms. Just know that they exist, they're derived by differentiating the forward equation, and they've been verified to 0.026% accuracy against finite differences.

### The chain rule: from field sensitivity to phase sensitivity

The adjoint gives us $\lambda_0$ — the sensitivity to the input **field**. But we control the **phase**, not the field directly. The connection:

$$u_0(\omega) = u_{00}(\omega) \cdot e^{i\varphi(\omega)}$$

A small change $\delta\varphi$ gives:

$$\delta u_0 = i \cdot u_0 \cdot \delta\varphi$$

(This is just the derivative of $e^{ix}$, which is $ie^{ix}$.)

Plugging into the sensitivity formula:

$$\boxed{\frac{\partial J}{\partial \varphi(\omega)} = 2 \cdot \text{Re}\left[\lambda_0^*(\omega) \cdot i \cdot u_0(\omega)\right]}$$

This is the gradient. Feed it to L-BFGS, update $\varphi$, repeat.

---

## Part 5: The Log-Scale Trick (Why -78 dB Was Impossible Before)

### The vanishing gradient problem

When we minimize $J$ directly (a number between 0 and 1), something bad happens as $J$ gets small. The gradient:

$$\frac{\partial J}{\partial \varphi} \propto \frac{u_L \cdot (\text{band\_mask} - J)}{E_{\text{total}}}$$

As $J \to 0$, the terminal condition $\lambda_L \to u_L \cdot \text{band\_mask} / E_{\text{total}}$, which depends only on how much field is in the Raman band. When suppression is good, there's almost no field in the band, so $\lambda_L$ is tiny, $\lambda_0$ is tiny, and the gradient is tiny.

The optimizer thinks: "the gradient is basically zero, I must be at the minimum." But it's not — there's still 40 dB of room to improve. It's like walking downhill in fog: the ground flattens out and you stop, but you're on a plateau, not in the valley.

### The fix: optimize in decibels

Instead of minimizing $J$, minimize $J_{\text{dB}} = 10 \log_{10}(J)$. The gradient becomes:

$$\frac{\partial J_{\text{dB}}}{\partial \varphi} = \underbrace{\frac{10}{J \cdot \ln(10)}}_{\text{amplification factor}} \cdot \frac{\partial J}{\partial \varphi}$$

As $J$ gets smaller, the amplification factor $1/J$ gets larger, exactly compensating the shrinking gradient. Going from -40 dB to -50 dB produces the same gradient magnitude as going from 0 dB to -10 dB.

**Result:** 20-28 dB improvement on every configuration. Points stuck at -35 dB now reach -60 dB. The optimizer's "fog" has been lifted.

This is the same principle behind why we measure sound in decibels — the ear responds logarithmically, so a logarithmic scale captures the perceptually relevant information. Similarly, the optimization problem has a logarithmic structure that the linear cost function was hiding.

---

## Part 6: What the Soliton Number Tells You

### The key ratio: nonlinearity vs. dispersion

Two length scales characterize pulse propagation:

**Dispersion length** $L_D = T_0^2 / |\beta_2|$: how far the pulse travels before dispersion doubles its width. Short pulses have small $L_D$ (they spread fast).

**Nonlinear length** $L_{NL} = 1/(\gamma P_{\text{peak}})$: how far the pulse travels before nonlinearity shifts its phase by 1 radian. High power gives small $L_{NL}$ (nonlinearity acts fast).

The soliton number is their ratio:

$$N = \sqrt{\frac{L_D}{L_{NL}}} = \sqrt{\frac{\gamma P_{\text{peak}} T_0^2}{|\beta_2|}}$$

**$N = 1$:** Dispersion and nonlinearity exactly balance. The pulse propagates forever without changing shape — this is a soliton. The Kerr effect perfectly compensates dispersion at every point. Beautiful physics, discovered in fiber in 1980.

**$N < 1$:** Dispersion wins. The pulse just spreads out. Boring but safe — Raman is weak because the peak power drops quickly.

**$N > 1$:** Nonlinearity wins. The pulse compresses (Kerr effect focuses it in time), reaches a very high peak power, then breaks apart (soliton fission). At the moment of peak compression, the Raman scattering rate is maximized because it scales as $T_0^{-4}$ — shorter, more intense pulses scatter much more.

### What N means for our optimization

| N range | What happens | Suppression difficulty |
|---------|-------------|----------------------|
| 1.0-1.5 | Gentle soliton propagation | Easy: -60 to -78 dB |
| 1.5-2.5 | Pulse breathing, some compression | Moderate: -50 to -70 dB |
| 2.5-4.0 | Soliton fission onset | Hard: -45 to -65 dB |
| 4.0-7.0 | Full fission, Raman shifting | Harder: -40 to -55 dB |

The optimizer fights Raman by pre-chirping the pulse — spreading it in time to lower the peak power. At low N, a little pre-chirp goes a long way. At high N, the nonlinear dynamics are so strong that they overcome the pre-chirp within the first nonlinear length.

---

## Part 7: What the Wirtinger Derivative Actually Is

This is the part that looks scariest in the verification document, but it's actually simple.

### The problem with complex derivatives

In real calculus, the derivative $df/dx$ is straightforward. But for a function of a complex variable $u = x + iy$, there are two independent directions you can vary: the real part $x$ and the imaginary part $y$.

The standard complex derivative $df/du$ only exists if $f$ satisfies the Cauchy-Riemann equations (i.e., $f$ is analytic). But $|u|^2 = u \cdot u^*$ is NOT analytic — it depends on both $u$ and $u^*$ independently.

### Wirtinger's solution: treat $u$ and $u^*$ as independent

Define two new derivatives:

$$\frac{\partial f}{\partial u} = \frac{1}{2}\left(\frac{\partial f}{\partial x} - i\frac{\partial f}{\partial y}\right) \qquad \frac{\partial f}{\partial u^*} = \frac{1}{2}\left(\frac{\partial f}{\partial x} + i\frac{\partial f}{\partial y}\right)$$

Now you can differentiate anything. For example:

$$\frac{\partial |u|^2}{\partial u^*} = \frac{\partial (u \cdot u^*)}{\partial u^*} = u$$

This is the key identity used in the terminal condition derivation. The $\partial/\partial u^*$ derivative "sees" $u^*$ but treats $u$ as a constant.

### Why the factor of 2 appears everywhere

For a real-valued function $J$ (like our cost):

$$\delta J = \sum_k \frac{\partial J}{\partial u_k} \delta u_k + \frac{\partial J}{\partial u_k^*} \delta u_k^* = 2 \cdot \text{Re} \sum_k \frac{\partial J}{\partial u_k^*} \delta u_k$$

The factor of 2 comes from combining the $u$ and $u^*$ terms. It's purely a bookkeeping convention of Wirtinger calculus — no physics is hiding in it.

---

## Part 8: Why FFT Factors of $N_t$ Appear

Julia's FFT convention:
- Forward: $U_k = \sum_{n=0}^{N-1} u_n e^{-2\pi i kn/N}$ (unnormalized — sum without $1/N$)
- Inverse: $u_n = \frac{1}{N} \sum_{k=0}^{N-1} U_k e^{+2\pi ikn/N}$ (normalized by $1/N$)

This asymmetry means:
- `fft` amplifies by a factor of $N_t$
- `ifft` doesn't amplify (it includes $1/N_t$)

In the adjoint, we need the transpose-conjugate of the FFT operation. The adjoint of `fft` (which is $N_t \times \text{ifft}$) and the adjoint of `ifft` (which is $(1/N_t) \times \text{fft}$) produce the $N_t$ factors you see scattered through the adjoint code.

If this seems arbitrary — it is. Different FFT libraries use different normalization conventions. The physics doesn't care about the convention, but the code has to be self-consistent.

---

## Part 9: How to Verify All of This

The strongest evidence that everything is correct comes from two tests:

### Taylor remainder test

Pick a random direction $\delta\varphi$ in the 8192-dimensional phase space. Compute:

$$r(\epsilon) = |J(\varphi + \epsilon \cdot \delta\varphi) - J(\varphi) - \epsilon \cdot \nabla J \cdot \delta\varphi|$$

If the gradient $\nabla J$ is correct, $r(\epsilon)$ should shrink as $\epsilon^2$ (because the Taylor expansion error is $O(\epsilon^2)$). On a log-log plot, the slope should be exactly 2.

**Our result: slopes of 2.00 and 2.04.** This is as good as it gets. It means the adjoint gradient matches the true gradient to machine precision.

### Finite difference check

For each frequency $k$, compute the gradient by:
1. Adjoint: $(\partial J / \partial \varphi_k)_{\text{adjoint}}$ — one forward + one backward solve
2. Finite differences: $(\partial J / \partial \varphi_k)_{\text{FD}} = \frac{J(\varphi + \epsilon e_k) - J(\varphi - \epsilon e_k)}{2\epsilon}$ — two forward solves

Compare. **Max relative error: 0.026%.** The adjoint gradient is extremely accurate.

---

## Part 10: What's Left to Understand

If you've followed this far, you understand the big picture. The remaining details in the full verification document are:

1. **Term-by-term adjoint derivation** (Section 3.3 of the LaTeX): The four terms of the adjoint equation. These come from differentiating the Kerr ($\gamma|u|^2 u$) and Raman ($\gamma(h_R * |u|^2)u$) terms with respect to $u$ and $u^*$. Each differentiation produces a slightly different structure (with/without conjugation, with/without convolution). The algebra is tedious but mechanical.

2. **GDD penalty derivation** (Section 7 of the LaTeX): Penalizing the curvature of the phase. Uses a standard finite-difference approximation of the second derivative. The gradient involves the fourth finite difference (the "biharmonic operator"). Straightforward calculus.

3. **Boundary penalty derivation**: Penalizing energy at the time window edges. Uses the chain rule through IFFT. The factor of $1/N_t$ comes from the IFFT normalization.

None of these contain surprising physics. They're just careful bookkeeping of derivatives through the computational pipeline.

---

## Part 11: The ML Connection (Why This Is Just Neural Network Training)

### The deep analogy

If you know anything about machine learning, the optimization we're doing is structurally identical to training a neural network. This isn't a loose analogy — it's mathematically the same procedure.

| Concept | Neural Network | Our Problem |
|---------|---------------|-------------|
| **Parameters** | Weight matrices $W_1, W_2, \ldots$ | Spectral phase $\varphi(\omega)$ |
| **Input** | Training data $x$ | Unshaped pulse $u_{00}(\omega)$ |
| **Forward pass** | $x \to h_1 \to h_2 \to \cdots \to \hat{y}$ | $u_0 \to u(z_1) \to u(z_2) \to \cdots \to u_L$ |
| **Loss function** | Cross-entropy, MSE, etc. | $J = E_{\text{Raman}} / E_{\text{total}}$ |
| **Backpropagation** | Chain rule through layers | Adjoint solve through fiber |
| **Optimizer** | Adam, SGD, L-BFGS | L-BFGS |
| **One training step** | Forward + backward + update | Forward solve + adjoint solve + L-BFGS step |

### The forward pass: layers vs. fiber positions

In a neural network, the forward pass pushes data through layers:
$$h_{k+1} = \sigma(W_k h_k + b_k)$$

In our problem, the forward pass propagates the pulse through the fiber. The ODE solver takes discrete steps in $z$:
$$u(z + \Delta z) = u(z) + \Delta z \cdot f(u(z), z)$$

Each $\Delta z$ step is like one "layer" of a neural network, except:
- There are ~1000 steps (much deeper than most networks)
- The "weights" (fiber parameters) are fixed — we're not learning them
- The "activation function" is the GNLSE nonlinearity ($|u|^2 u$ + Raman convolution)

### Backpropagation: it's the SAME chain rule

In a neural network, backprop computes $\partial L / \partial W_k$ by propagating the loss gradient backward through layers:

$$\delta_k = \frac{\partial L}{\partial h_k} = W_{k+1}^T \delta_{k+1} \cdot \sigma'(z_k)$$

In our problem, the adjoint propagates the cost gradient backward through the fiber:

$$\frac{d\lambda}{dz} = -\left(\frac{\partial f}{\partial u}\right)^\dagger \lambda - \left(\frac{\partial f}{\partial u^*}\right)^T \lambda^*$$

The structure is identical: you start with the loss gradient at the output, and propagate it backward through the same operations (transposed/conjugated) to get the gradient at the input.

The key difference: in a neural network, each layer is a simple matrix multiply + nonlinearity, so the backward pass is straightforward. In our problem, each "layer" is a step of a nonlinear PDE, so the backward pass requires solving a separate ODE (the adjoint equation). But the principle is exactly the same.

### Why L-BFGS instead of Adam?

In ML, Adam is popular because:
- It works well with noisy gradients (mini-batches)
- It adapts learning rates per-parameter
- It's simple to implement

In our problem:
- Gradients are exact (no stochasticity — we use the full "batch")
- The problem is smooth (PDE, not piecewise-linear ReLU)
- L-BFGS builds a quadratic approximation of the loss surface, which is much more efficient for smooth problems

L-BFGS converges in 20-60 iterations where Adam might take thousands. For our problem, each iteration costs ~2 seconds (one forward + one backward solve), so L-BFGS finishes in 1-2 minutes.

### The log-cost insight in ML terms

The log-cost trick (Section 5) is equivalent to a well-known ML technique: using **log-scale loss functions** for imbalanced problems. If you're classifying rare events (1 in a million), cross-entropy loss naturally handles the scale through the log. Our $J_{\text{dB}} = 10\log_{10}(J)$ does the same thing — it maps the exponentially shrinking cost to a linear scale where the optimizer can make steady progress.

In ML, this is sometimes called "focal loss" (Lin et al., 2017) — downweighting easy examples and amplifying hard ones. Our $1/J$ gradient amplification is the same idea: as Raman gets suppressed (the "easy" part is done), the gradient gets amplified to focus on the remaining hard-to-suppress components.

---

## Part 12: First Principles — Where the GNLSE Comes From

### Starting from Maxwell's equations

You asked for first principles. Here they are.

Maxwell's equations in a dielectric (no free charges, non-magnetic):

$$\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t} \qquad \nabla \times \mathbf{B} = \mu_0 \frac{\partial \mathbf{D}}{\partial t}$$

In a fiber, the displacement field has a nonlinear part:

$$\mathbf{D} = \epsilon_0 \mathbf{E} + \mathbf{P}_L + \mathbf{P}_{NL}$$

where $\mathbf{P}_L = \epsilon_0 \chi^{(1)} \mathbf{E}$ is the linear polarization and $\mathbf{P}_{NL}$ contains $\chi^{(3)}$ (third-order susceptibility — the lowest nonlinear order in a centrosymmetric medium like glass).

### The slowly-varying envelope approximation

Write the field as a carrier wave times a slowly-varying envelope:

$$E(z, t) = \frac{1}{2}\left[u(z, t) e^{i(\beta_0 z - \omega_0 t)} + \text{c.c.}\right]$$

"Slowly varying" means $u$ changes much more slowly than the carrier oscillation $e^{-i\omega_0 t}$. Formally: $|\partial u / \partial t| \ll \omega_0 |u|$ and $|\partial u / \partial z| \ll \beta_0 |u|$.

Substituting into Maxwell's equations and keeping only terms where the derivatives of $u$ appear (dropping $\partial^2 u / \partial z^2$ because $u$ varies slowly):

$$\frac{\partial u}{\partial z} + \beta_1 \frac{\partial u}{\partial t} = -\frac{\alpha}{2}u + i\sum_{n \geq 2} \frac{\beta_n}{n!}\left(i\frac{\partial}{\partial t}\right)^n u + i\gamma |u|^2 u$$

This is the standard NLSE. The left side has propagation ($\partial/\partial z$) and group velocity ($\beta_1 \partial/\partial t$). Moving to the co-moving frame ($T = t - \beta_1 z$) eliminates the $\beta_1$ term.

### Adding the Raman response

The Kerr effect ($\chi^{(3)} |E|^2 E$) actually has a time delay — the electrons respond instantly but the nuclei (which are ~2000x heavier) respond on a ~30 fs timescale. Including this delay:

$$P_{NL}(t) = \epsilon_0 \chi^{(3)} \left[(1 - f_R)|u(t)|^2 + f_R \int_0^\infty h_R(\tau)|u(t-\tau)|^2 d\tau\right] u(t)$$

The first term is the instantaneous electronic response (Kerr). The second is the delayed nuclear response (Raman). The fraction $f_R = 0.18$ comes from measuring the relative strengths of the electronic and nuclear contributions in silica.

This gives us the full GNLSE:

$$\frac{\partial u}{\partial z} = i\sum_{n \geq 2} \frac{\beta_n}{n!}\left(i\frac{\partial}{\partial t}\right)^n u + i\gamma\left[(1 - f_R)|u|^2 u + f_R (h_R * |u|^2) u\right]$$

That's exactly what our code solves. Every term traces back to Maxwell's equations plus the material response of silica glass.

### Where $\gamma$ comes from

The nonlinear coefficient:

$$\gamma = \frac{n_2 \omega_0}{c \cdot A_{\text{eff}}}$$

where $n_2 \approx 2.6 \times 10^{-20}$ m$^2$/W is the nonlinear refractive index of silica (a material property), and $A_{\text{eff}}$ is the effective mode area of the fiber (a geometry property — smaller core = more intense light = stronger nonlinearity). For SMF-28, $A_{\text{eff}} \approx 80$ $\mu$m$^2$. For HNLF, $A_{\text{eff}} \approx 10$ $\mu$m$^2$ (8x smaller = 8x more nonlinear).

### Where $h_R(t)$ comes from

The Raman response function models the vibrational spectrum of SiO$_2$. The dominant mode is the symmetric stretch of the Si-O-Si bridge at ~440 cm$^{-1}$ (~13.2 THz). The Blow-Wood model approximates this as a damped harmonic oscillator:

$$h_R(t) = \frac{\tau_1^2 + \tau_2^2}{\tau_1 \tau_2^2} e^{-t/\tau_2} \sin(t/\tau_1) \Theta(t)$$

This is the impulse response of a damped oscillator with:
- Resonance frequency: $1/\tau_1 = 1/(12.2 \text{ fs})$ = 82 THz
- Damping rate: $1/\tau_2 = 1/(32 \text{ fs})$ = 31 THz
- Quality factor: $Q = \pi \tau_2 / \tau_1 \approx 8.2$ (moderately underdamped)

The real Raman spectrum of silica is more complex (multiple overlapping peaks), but the Blow-Wood model captures the dominant features and is the standard approximation used throughout the field.

---

## Part 13: The Adjoint from First Principles

### The constrained optimization viewpoint

We want to minimize $J[u_L]$ subject to the constraint $du/dz = f(u, z)$. This is a standard problem in the calculus of variations.

**Step 1: Form the Lagrangian.** Introduce a Lagrange multiplier $\lambda(z)$ (a function, not a number — this is like Lagrange multipliers in mechanics but infinite-dimensional):

$$\mathcal{L} = J[u_L] + \int_0^L \left\langle \lambda(z), \frac{du}{dz} - f(u, z) \right\rangle dz$$

The inner product $\langle \cdot, \cdot \rangle$ sums over all frequencies: $\langle a, b \rangle = \sum_\omega a^*(\omega) b(\omega)$.

If $u$ satisfies the constraint ($du/dz = f$), the integral vanishes and $\mathcal{L} = J$. So finding the minimum of $\mathcal{L}$ with respect to both $u$ and $\lambda$ simultaneously gives us the minimum of $J$ subject to the constraint.

**Step 2: Variation with respect to $\lambda$.** Setting $\delta \mathcal{L} / \delta \lambda = 0$ recovers the forward equation $du/dz = f$. No surprise.

**Step 3: Variation with respect to $u$.** This is where the adjoint appears. We want $\delta \mathcal{L} / \delta u = 0$:

$$\delta \mathcal{L} = \underbrace{\left\langle \frac{\partial J}{\partial u_L}, \delta u_L \right\rangle}_{\text{boundary term}} + \int_0^L \left\langle \lambda, \frac{d(\delta u)}{dz} - \frac{\partial f}{\partial u}\delta u \right\rangle dz$$

**Step 4: Integration by parts.** The $\langle \lambda, d(\delta u)/dz \rangle$ term integrates by parts:

$$\int_0^L \left\langle \lambda, \frac{d(\delta u)}{dz} \right\rangle dz = \left[\langle \lambda, \delta u \rangle\right]_0^L - \int_0^L \left\langle \frac{d\lambda}{dz}, \delta u \right\rangle dz$$

**Step 5: Choose $\lambda$ to kill the bulk term.** If $\lambda$ satisfies:

$$\frac{d\lambda}{dz} = -\left(\frac{\partial f}{\partial u}\right)^\dagger \lambda$$

then the integral vanishes and we're left with:

$$\delta \mathcal{L} = \left\langle \frac{\partial J}{\partial u_L} + \lambda_L, \delta u_L \right\rangle - \langle \lambda_0, \delta u_0 \rangle$$

**Step 6: Terminal condition.** Set $\lambda_L = -\partial J / \partial u_L^*$ to kill the boundary term at $z = L$:

$$\delta \mathcal{L} = -\langle \lambda_0, \delta u_0 \rangle$$

**Step 7: Read off the gradient.** Since $\delta u_0 = i u_0 \delta\varphi$ (from the phase mask chain rule):

$$\delta J = -\langle \lambda_0, i u_0 \delta\varphi \rangle = 2 \text{Re}[\lambda_0^* \cdot i \cdot u_0] \cdot \delta\varphi$$

And we have our gradient formula. QED.

(The factor of 2 and sign conventions depend on the Wirtinger calculus details. The verification document traces these carefully. The key point: the adjoint equation arises naturally from integrating by parts in the Lagrangian.)

---

## Quick Reference: The 5 Equations That Matter

If you remember nothing else, remember these:

**1. The forward equation (GNLSE):**
$$\frac{du}{dz} = iDu + i\gamma(1-f_R)|u|^2 u + i\gamma f_R (h_R * |u|^2) u$$

**2. The cost function:**
$$J = \frac{E_{\text{Raman band}}}{E_{\text{total}}}$$

**3. The adjoint terminal condition:**
$$\lambda_L = \frac{u_L \cdot (\mathbb{1}_{\text{band}} - J)}{E_{\text{total}}}$$

**4. The gradient:**
$$\frac{\partial J}{\partial \varphi(\omega)} = 2 \cdot \text{Re}\left[\lambda_0^* \cdot i \cdot u_0\right]$$

**5. The log-scale trick:**
$$\frac{\partial J_{\text{dB}}}{\partial \varphi} = \frac{10}{J \ln 10} \cdot \frac{\partial J}{\partial \varphi}$$

Everything else is implementation details.

---

*Written as a companion to the formal verification document. All equations verified against the codebase on 2026-04-02.*
