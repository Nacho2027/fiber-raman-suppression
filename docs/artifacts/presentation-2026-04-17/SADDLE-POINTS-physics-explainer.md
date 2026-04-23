# Saddle points in the Raman-suppression landscape — what they are, whether they're physically interesting, and what creates them

This is the physics story for your meeting. I'm going to build it from first principles because I think several things are actually interesting (and some claims in the briefing were under-explained).

---

## 1. What "saddle point" means in this context

The optimization problem is: pick a spectral phase `phi(omega)` at the fiber input that minimizes

```
    J(phi) = energy in the Raman band / total energy   (at the fiber output)
```

`phi` lives in a huge space (16384 real numbers, one per frequency bin). Any critical point — a point where the gradient `dJ/dphi` is zero — is either a minimum, a maximum, or a saddle. The way you distinguish them is by looking at the **Hessian** H, the matrix of second derivatives `d^2 J / dphi_i dphi_j`:

- Minimum: all eigenvalues positive (you're at the bottom of a bowl in every direction).
- Maximum: all eigenvalues negative (top of a hill).
- Saddle: some positive, some negative (bowl in some directions, hill in others).

Phase 13 measured the Hessian eigenvalues at our best L-BFGS optima and found **both signs**. Specifically:

| Config                          | `lambda_max`       | `lambda_min`        | ratio    |
|---------------------------------|-------------------:|--------------------:|---------:|
| SMF-28 canonical (L=2 m, P=0.2 W) | `+1.07 × 10^-5` | `-2.79 × 10^-7`    | 2.6%     |
| HNLF canonical (L=0.5 m, P=0.01 W)| `+5.08 × 10^-5` | `-2.09 × 10^-7`    | 0.41%    |

All 20 reported top eigenvalues are positive; all 20 bottom eigenvalues are negative. That's unambiguous — these are saddles.

---

## 2. Is the *location* interesting? Two features that are genuinely surprising.

### Surprise A — the negative-curvature directions are IN-BAND, not out-of-band

Intuition says: at frequencies where the pulse has no spectral amplitude (|U(omega)| = 0), changing `phi(omega)` at that frequency does nothing (you can't modulate the phase of a thing that isn't there). So those bins should trivially be flat directions. That's a boring reason to have zero curvature.

**But the measured soft eigenvectors are NOT at out-of-band frequencies.** Look at the bottom-5 eigenvector plot — they concentrate on the pulse bandwidth, with high-frequency oscillations *inside* the band. That's much more interesting. It means there are genuine reshaping perturbations of the phase — perturbations that actually change what comes out of the fiber — that almost don't change the Raman energy ratio.

### Surprise B — the curvature ratio `|λ_min|/λ_max` varies with fiber type

SMF-28 has a ratio of 2.6%. HNLF has 0.41%, six times smaller. That's not numerical noise — it's a physical trend. HNLF has much larger `gamma` (nonlinear coefficient) and smaller |beta_2|. The saddle in HNLF is "sharper" (stronger positive curvature in the dominant direction, but the soft directions are similarly soft). Something about the balance between dispersion and nonlinearity determines how isotropic the landscape is.

### Not-a-surprise — the two gauge null-modes

Any cost of the form `E_band / E_total` is invariant under

```
    phi(omega)  →  phi(omega) + c + alpha·omega       (constant + linear-in-omega)
```

The reason: adding a constant `c` rotates the complex envelope globally (doesn't change intensity), and adding `alpha·omega` is a time translation (shifts the pulse rigidly; since the cost is computed from the output spectrum, rigid time shift is invisible). These are **exact** symmetries, and by Noether's theorem they produce **exactly zero** Hessian eigenvalues in the corresponding direction. Two modes must be at λ = 0 exactly: `e_1 = const` and `e_2 ∝ omega` (centered on the band).

Our Arpack computation couldn't resolve these because matrix-free Lanczos can't reach eigenvalues too close to zero without shift-invert. They're there by theorem, just not measured as numbers. This is a known limitation, not a mystery.

---

## 3. What physics actually creates the saddle structure? My best guess.

This is the most interesting question. I don't have a fully-worked-out answer — nobody does — but here are the pieces.

### Piece 1 — the optimization landscape inherits the nonlinearity of the NLSE

The forward propagation is solving the generalized nonlinear Schrödinger equation (NLSE):

```
    dU/dz = i·beta_2/2 · d^2 U/dt^2      (dispersion)
           + i·gamma · |U|^2 · U         (Kerr)
           + gamma · f_R · (delayed Raman response convolution)
```

The cost is evaluated at `z = L`. Changing `phi(omega)` at the input changes `U(t, 0)`, which evolves through the NLSE's full nonlinear chain, and the output `U(omega, L)` is not a simple function of the input. It's *polynomial* in the input field to all orders (SPM is cubic in amplitude, cross-band coupling mixes frequencies iteratively as you propagate).

The cost is a *polynomial-like* functional of `phi` of arbitrarily high order. Such functionals generically have many stationary points, most of them saddles, in high dimensions. This is a well-known feature of high-dimensional nonconvex optimization (e.g., in neural networks): the strict-minimum fraction of critical points shrinks as dimension grows.

### Piece 2 — interference between different nonlinear mechanisms

Kerr (instantaneous) and Raman (delayed) act on the pulse simultaneously. They can interfere constructively or destructively with respect to generating Raman-band energy. The phase `phi` controls which way they interfere. At a saddle, some small perturbation increases one mechanism and decreases the other by approximately the same amount, net change ≈ 0. These "compensating" directions are the soft eigenvectors.

### Piece 3 — the "approximate conservation laws" angle

The NLSE (without Raman) is integrable in 1D. Integrability means infinitely many conserved quantities exist, and the dynamics preserve all of them exactly. Two well-known ones: total energy (trivial) and total momentum (linear in `omega`, related to the group-velocity gauge).

Raman breaks strict integrability, but the breaking is weak (`f_R ≈ 0.18`, so the Raman nonlinearity is a small correction to Kerr). Some "approximately conserved" structure survives. Perturbations along those approximate symmetries shouldn't change the output much — hence small curvature. The bottom-5 eigenvectors being in-band with high-frequency oscillation is consistent with the *near-symmetries* of integrable NLS dynamics (cnoidal-wave modes, breather modes, etc.).

This is a research hypothesis, not a proof. It would be a nice project to compute overlap of the soft eigenvectors with known NLS near-modes.

---

## 4. Why L-BFGS halts there (and what to do about it)

L-BFGS only uses the gradient. At a saddle, gradient = 0 — so L-BFGS sees "done, gradient is tiny" and stops. Its internal inverse-Hessian approximation is built incrementally from past steps and systematically under-weights negative curvature directions that it hasn't explored (negative curvature produces a line search that can't reduce J along the Wolfe conditions — L-BFGS would treat such a direction as "noise" and discard it from its approximation).

Methods that would see through this:
1. **Explicit second-order (Newton-type).** You compute or estimate the smallest Hessian eigenvalue and check its sign. If negative, you take a step along the corresponding eigenvector (negative-curvature step). Our Phase 13 seed `newton-method-implementation.md` lays out the plan.
2. **Sharpness penalties.** You add `λ·S(phi)` to the cost where `S` punishes regions of high curvature. The optimizer avoids settling into saddle-like regions. Phase 14 ships a straight Hutchinson trace estimator, but note: a straight trace can *fail* at saddles because positive and negative eigenvalues cancel (trace ≈ 0 when the spectrum is symmetric). The fix is a penalty on `sum |lambda_i|` (signed absolute).
3. **Sub-space reduction.** Use a low-resolution basis (N_phi = 57) and factor a small dense Hessian explicitly. At N_phi = 57 the Hessian is 57×57, easy to invert. This is the Session E / Newton-on-reduced-subspace plan.

---

## 5. Why it matters for Rivera Lab

This is quantum-noise / squeezing work, not telecom. The Raman suppression is a tool for preserving quantum correlations in multimode fiber. Classical Raman energy is a proxy: the *real* objective is quantum-noise figure. The optimizer is operating on a classical surrogate.

- If the classical landscape has many saddles, it's a hint that the *quantum* landscape also has many saddles. That matters because the gradient of the quantum objective may look different near a saddle of the classical one — warm-starting from a classical optimum and polishing with a quantum-aware cost is a good strategy.
- The soft-eigenvector structure could correspond to perturbations that preserve classical Raman suppression *but* damage squeezing. Worth checking before committing to a candidate.

---

## 6. One-paragraph meeting answer

> "The Hessian at our best L-BFGS optima has eigenvalues of both signs — all 20 reported top eigenvalues are positive, all 20 bottom eigenvalues are negative — which makes them saddle points rather than minima. Two of the zero-eigenvalue modes are the exact gauge symmetries of the cost (constant phase and linear group-delay, both physically invisible). The interesting part is the *other* soft directions: they concentrate in the pulse bandwidth with high-frequency structure, and their existence probably reflects the near-integrability of NLS dynamics being only weakly broken by Raman. The negative curvatures are small but genuinely non-zero (0.4-2.6% of the stiff direction), so Newton-type methods on a reduced subspace should do strictly better than L-BFGS. This is the motivation for the Phase 14 sharpness-aware and Session E reduced-subspace Newton plans."
