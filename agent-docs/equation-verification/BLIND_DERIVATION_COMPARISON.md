# Blind Derivation Comparison

Date: 2026-04-27

## Scope

This note compares the independent blind derivation supplied by the user
against the current public verification document and the relevant source paths.
The independent derivation was intentionally not code-aware. This comparison is
the second step: derive first, then compare.

## Bottom Line

No core equation mismatch was found in the active verification document or the
checked implementation paths. The blind derivation did expose several
convention details that needed to be made explicit in the public note:

- self-steepening is an absolute-frequency ratio in code, equivalent to
  \(1+\Omega/\omega_0\) when written with offset frequency;
- Fourier sign and FFT normalization must be treated as a convention bundle
  with the dispersion sign, interaction-picture transform, and adjoint FFT;
- the GDD regularizer uses a nonperiodic truncated second-difference stencil,
  not a periodic wraparound;
- the temporal edge denominator is constant for phase-only updates but not for
  amplitude updates;
- finite-difference HVPs must remain tied to the named scalar objective.

These clarifications were added to
`docs/reference/current-equation-verification.tex`.

## Equation-By-Equation Comparison

| Topic | Blind derivation result | Code/public-doc comparison | Status |
|---|---|---|---|
| Forward GNLSE | Lab-frame linear term \(+iD\hat u\), nonlinear Kerr/Raman term, self-steepening \(1+\Omega/\omega_0\) for offset frequency. | `disp_mmf!` uses `cis(Dω*z)`, `cis(-Dω*z)`, and `selfsteep = fftshift(ωs / ω0)`. Here `ωs` is the absolute angular-frequency grid, so this is the same as \(1+\Omega/\omega_0\). | Matches with convention caveat. |
| Interaction picture | \(\tilde u=e^{-iDz}\hat u\), RHS \(e^{-iDz}\mathcal N[e^{iDz}\tilde u]\). | `disp_mmf!` reconstructs `uω = exp_D_p * ũω` and returns `1im * exp_D_m * ηt`. | Matches. |
| Raman-band cost | \(\partial J/\partial U_k^*=(\chi_k-J)U_k/E\). | `spectral_band_cost` returns `uωf .* (band_mask .- J) ./ E_total`. | Matches. |
| Phase gradient | \(dJ/d\phi_k=2\operatorname{Re}[\lambda_k^* i u_k]\), unless the stored adjoint is doubled. | `cost_and_gradient` uses `2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))`. | Matches current adjoint convention. |
| dB objective | \(\nabla J_{\rm surf}=(10/\ln 10)\nabla J_{\rm lin}/J_{\rm lin}\). | `apply_log_surface!` scales the already-regularized gradient by `10/(J*log(10))`. | Matches. |
| dB Hessian | \(H_{\rm surf}=a(H_{\rm lin}/J_{\rm lin}-gg^T/J_{\rm lin}^2)\). | Public doc already states this; HVP docs must name the scalar surface. | Matches with documentation caveat. |
| GDD regularizer | \(R=\|D_2\phi\|^2/\Delta\omega^3\), \(\nabla R=2D_2^TD_2\phi/\Delta\omega^3\), nonperiodic boundary rows. | `add_gdd_penalty!` loops `i=2:(Nt-1)` and adds the three-point row contribution. This is exactly \(D_2^TD_2\). | Matches; public doc strengthened. |
| Boundary phase regularizer | Full quotient derivative in time domain; FFT adjoint normalization matters. | `add_boundary_phase_penalty!` uses only the edge numerator derivative for phase. That is valid because total input energy is invariant under phase-only FFT updates. | Matches with phase-only caveat. |
| Boundary amplitude derivative | Amplitude changes numerator and denominator. | `multivar_optimization.jl` includes the denominator term `- edge_frac * abs2(u_shaped) / A`. | Matches repaired path; burst rerun still pending. |
| Reduced basis | \(\nabla_cJ=B^T\nabla_\phi J\), independent of basis orthonormality for coordinate gradients. | Public doc states this. Basis projection/prolongation conventions still need result-provenance detail in the reduced-basis note. | Matches; provenance gap remains. |
| MMF shared phase | Sum modewise phase sensitivities. | Public doc and MMF code path use shared-phase summed gradients. | Matches; fresh MMF regression rerun pending. |
| Mode coordinates | Analytic real-coordinate chain possible, but finite differences acceptable for a small deterministic block. | Current project policy intentionally finite-differences the small mode-coordinate block after analytic chain preflight failed. | Matches policy. |
| HVP / trust region | Finite-difference HVP must be tied to named \(F\); trust ratio is actual over predicted reduction. | Public doc already warns HVPs are finite-difference diagnostics, not analytic second-adjoint Hessians. | Matches. |

## Changes Made After Comparison

- Updated the public verification document to distinguish absolute frequency
  \(\omega\) from offset frequency \(\Omega\) in self-steepening.
- Added a convention note tying Fourier sign, dispersion sign, and
  interaction-picture sign together.
- Added the matrix-form GDD gradient and nonperiodic boundary-stencil caveat.
- Added the phase-only versus amplitude-enabled edge-fraction distinction.

## Remaining Verification Gaps

- Fresh burst rerun of the production verification script.
- Fresh burst rerun of the multivariable gradient smoke suite, especially the
  repaired boundary-amplitude quotient derivative.
- Fresh MMF regression rerun for shared-phase gradient health.
- Result-provenance table for reduced-basis note claims.
