# Blind Equation-Derivation Prompt

Use this prompt for an outside verifier who has not seen the codebase. The
goal is to get an independent mathematical derivation before comparing against
any implementation.

```text
You are performing a blind equation-verification pass for a nonlinear fiber
optics Raman-suppression research project.

Important rule:
Do not inspect any implementation, repository files, prior project notes, or
existing verification documents before deriving the equations. First derive
the expected equations from the mathematical problem statement and standard
references. Only after the independent derivation is written should the
project team compare it against code.

Goal:
Independently derive the equations that should govern a spectral phase-shaping
optimization problem for suppressing Raman-band output energy in a nonlinear
optical fiber. Keep the explanation undergraduate-readable but technically
serious. Show the main steps, not just final answers.

External references to use:
- Govind P. Agrawal, Nonlinear Fiber Optics, 6th edition, for the generalized
  nonlinear Schrodinger equation, Kerr nonlinearity, delayed Raman response,
  dispersion, and self-steepening.
- Johan Hult, fourth-order Runge-Kutta interaction-picture method, for the
  interaction-picture propagation convention.
- A standard numerical optimization reference such as Nocedal and Wright for
  gradients, Hessian-vector products, trust-region interpretation, and
  finite-difference checks.
- A standard Fourier-analysis or FFT reference for transform conventions, if
  needed.

Problem setting:
The project controls the input spectral phase of an optical pulse. The shaped
input spectral field is

    u_k(0; phi) = u_{k,0} exp(i phi_k),

where k indexes frequency samples and phi_k is a real phase mask. The pulse is
propagated through a nonlinear fiber. The main objective is to reduce the
fraction of output spectral energy that lies inside a chosen Raman band.

Derive and verify the expected equations below.

1. Forward fiber model

Derive the lab-frame generalized nonlinear Schrodinger equation for a spectral
field with:
- dispersion operator D(omega),
- Kerr nonlinearity,
- delayed Raman convolution,
- self-steepening factor,
- Fourier transforms between spectral and time domains.

Then derive the interaction-picture form using a transform of the form

    utilde(z, omega) = exp(-i D(omega) z) uhat(z, omega).

Be explicit about signs and where the nonlinear term is evaluated.

Deliverable:
- Lab-frame evolution equation.
- Interaction-picture evolution equation.
- Short explanation of why the interaction picture is used.
- Any sign or Fourier-convention caveats.

2. Raman-band objective

Let the physical objective be the output energy fraction in a Raman band:

    J = E_Raman / E_total,

where

    E_Raman = sum_{k in Raman band} |u_k(L)|^2,
    E_total = sum_k |u_k(L)|^2.

Let chi_k = 1 inside the Raman band and chi_k = 0 outside.

Derive the terminal derivative with respect to the complex output field,
including the quotient rule. In particular, derive the expected expression for

    partial J / partial u_k^*(L).

Deliverable:
- Step-by-step quotient-rule derivation.
- Final terminal sensitivity.
- Note any factor-of-2 convention that depends on the chosen complex inner
  product convention.

3. Adjoint phase gradient

Given the input phase map

    u_k(0; phi) = u_{k,0} exp(i phi_k),

and an adjoint input sensitivity lambda_0, derive the gradient with respect to
the real phase variable phi_k.

Expected type of result:

    dJ/dphi_k = real-valued expression involving lambda_0,k and i u_k(0; phi).

Deliverable:
- Derive du_k / dphi_k.
- Derive the real-valued chain rule.
- State the final phase-gradient formula.
- Explain the sign convention and what would change if the adjoint inner
  product convention were different.

4. Regularized objective and dB chain rule

Suppose the optimizer may use a regularized linear objective

    J_lin(phi) = J_phys(phi)
               + lambda_gdd R_gdd(phi)
               + lambda_edge R_edge(phi),

and an optional decibel-scaled objective

    J_surf(phi) = 10 log10(J_lin(phi)).

Derive:
- grad J_surf in terms of grad J_lin,
- Hessian of J_surf in terms of grad J_lin and Hessian J_lin.

Deliverable:
- Gradient chain rule.
- Hessian chain rule.
- Explanation of why adding regularizers before or after the log transform
  gives different optimizer surfaces.

5. GDD / phase-smoothness regularizer

Consider a discrete second-difference regularizer

    R_gdd(phi) = sum_{i=2}^{N-1}
        (phi_{i+1} - 2 phi_i + phi_{i-1})^2 / Delta_omega^3.

Derive the gradient with respect to phi_j.

Deliverable:
- Interior gradient stencil.
- Boundary handling assumptions.
- Matrix form if useful, e.g. R = ||D2 phi||^2 scaled by Delta_omega.
- Explain the linear-algebra meaning of the regularizer.

6. Temporal edge-energy regularizer

The shaped input pulse can be transformed to the time domain. A temporal
edge-energy fraction is defined by

    R_edge(phi) =
        sum_{j in edge} |u(t_j, 0; phi)|^2
        /
        sum_j |u(t_j, 0; phi)|^2.

Derive the derivative of this quantity with respect to the spectral phase
variables phi_k.

Deliverable:
- Quotient-rule derivative in time-domain variables.
- Chain rule through the inverse Fourier transform.
- Chain rule through u_k(0; phi) = u_{k,0} exp(i phi_k).
- State any dependence on FFT normalization convention.

7. Reduced-basis phase map

Suppose the full phase vector is restricted to a lower-dimensional linear
subspace:

    phi = B c,

where B is a basis matrix and c is the optimizer coordinate vector.

Derive:

    grad_c J = B^T grad_phi J.

Deliverable:
- Linear-algebra derivation using differentials.
- Geometric explanation of what the basis restriction does.
- Explain how the formula changes, if at all, if the columns of B are not
  orthonormal.
- Explain what happens if gauge/constant-phase removal or centering is applied.

8. Multivariable phase, amplitude, and energy controls

Suppose the optimizer may control:
- phase variables,
- spectral amplitude variables,
- scalar pulse energy,
- transformed optimizer coordinates such as tanh, log, sigmoid, or normalized
  coordinates.

Derive the generic chain-rule structure for each control type.

Also derive the derivative of a temporal edge-energy fraction with respect to
amplitude variables. The important point is that changing amplitude changes
both the edge-energy numerator and the total-energy denominator.

Deliverable:
- Generic chain rule from optimizer coordinates to physical controls.
- Amplitude derivative of an energy fraction using the quotient rule.
- Scalar-energy derivative structure.
- Warning signs for common mistakes.

9. Multimode shared-phase gradient

Suppose the field has modes indexed by m, and the same spectral phase phi_k is
applied to all modes. The objective depends on all propagated modal fields.

Derive the shared-phase gradient with respect to phi_k.

Deliverable:
- Modewise phase derivative.
- Sum over modal adjoint sensitivities.
- State whether launch coefficients or modal normalization could alter the
  formula.

10. Mode-coordinate derivatives

Suppose a multimode launch is parameterized by a small set of complex mode
coefficients or real mode-coordinate variables. Determine what an analytic
gradient would require.

Deliverable:
- Derive the cleanest expected chain rule if mode coordinates are simple real
  variables.
- Explain why complex coordinates require careful real/imaginary treatment.
- State when finite differences are scientifically acceptable for this block.

11. Hessian-vector products and trust-region diagnostics

Derive how a finite-difference Hessian-vector product should be defined for a
named scalar objective F(phi):

    H(phi) v approx [grad F(phi + epsilon v) - grad F(phi)] / epsilon.

Also derive the basic trust-region predicted-vs-actual reduction ratio.

Deliverable:
- HVP finite-difference formula.
- Symmetry/Taylor checks that should hold if the HVP is reliable.
- Trust-region ratio formula.
- Clear distinction between finite-difference HVPs and analytic second-adjoint
  Hessian products.

Required final output:

1. Independent derivation notes for all sections above.
2. A table with:
   - equation/path,
   - independent expected formula,
   - assumptions,
   - possible convention caveats,
   - suggested numerical check.
3. A list of equations that are especially vulnerable to sign, factor-of-2,
   Fourier-normalization, or objective-surface mistakes.
4. A suggested finite-difference or Taylor test plan for verifying each
   derivative after the project team compares these derivations to code.
5. A short explanation of what evidence would be needed before calling each
   equation publication-grade.

Do not claim that an equation matches the project implementation. You have not
seen the implementation. Your job is to produce the independent expected math
that another person can compare against the code later.
```
