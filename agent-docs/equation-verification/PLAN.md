# Equation Verification Rerun Plan

Date: 2026-04-26

## Current Status

- Public verification document created:
  `docs/reference/current-equation-verification.tex`
- Compiled PDF created and visually inspected:
  `docs/reference/current-equation-verification.pdf`
- The PDF has status rows for the active analytic, finite-difference, and
  caveated derivative paths.
- Fresh burst reruns are still pending because the burst machine already had an
  active heavy job when checked.

## Goal

Rebuild the verification backbone so the research-note series can rely on
current, audited equations rather than historical verification text. The final
output should support outward-facing notes, lab presentation, and paper-writing
workflows.

## Why This Is Needed

The old public verification documents under `docs/reference/` are useful but
stale relative to the active codebase. Since those documents were written, the
project has added or changed:

- dB objective-surface handling after regularizers
- numerical trust reports
- boundary regularization and pre-attenuator edge checks
- reduced-basis continuation
- sharpness/robustness objectives
- trust-region and Hessian-vector-product diagnostics
- multimode and multivariable optimization paths
- a repaired multivariable boundary-amplitude quotient gradient

The current source of truth is split between code, tests, saved validation
reports, and `agent-docs/equation-verification/SUMMARY.md`. That is not good
enough for publication-grade documentation.

## Verification Work Packages

### 1. Forward Model

- Verify the interaction-picture GNLSE implemented by `disp_mmf!`.
- Confirm the Fourier convention used by the code.
- Confirm dispersion, Kerr, Raman, and self-steepening terms.
- Confirm units and frequency-grid ordering.
- Tests/evidence: soliton propagation, photon-number conservation, band-cost
  cross-check, source inspection.

### 2. Raman Cost And Terminal Condition

- Re-derive \(J = E_{\mathrm{band}}/E_{\mathrm{total}}\).
- Re-derive the terminal derivative with respect to the output field.
- Confirm `spectral_band_cost` and any peak-band variants.
- Tests/evidence: direct energy-ratio cross-check and finite-difference checks.

### 3. Phase Adjoint Gradient

- Re-derive the adjoint equation at the level needed for confidence.
- Re-derive the input phase chain rule:
  \(dJ/d\phi = 2\Re[\lambda_0^* i u_0]\).
- Verify log-surface chain rule when `log_cost=true`.
- Tests/evidence: Taylor remainder slope and gradient finite-difference tests.

### 4. Regularizers

- Verify discrete GDD second-difference scalar and gradient.
- Verify boundary phase regularizer and edge-fraction derivative.
- Verify that regularizers are added before optional dB transform.
- Tests/evidence: regularized objective finite-difference/Taylor checks.

### 5. Reduced Basis

- Verify \(\phi = Bc\) and \(\nabla_c F = B^T\nabla_\phi F\).
- Confirm basis interpolation/prolongation conventions and gauge handling.
- Tests/evidence: basis tests and reduced-basis result provenance.

### 6. Sharpness And Robustness

- Verify sharpness objective definition and local perturbation convention.
- Verify whether sharpness gradients are analytic, sampled, or mixed.
- Verify Hessian/robustness diagnostics are described with the correct scalar
  surface.
- Tests/evidence: sharpness tests, HVP symmetry/Taylor tests.

### 7. Trust-Region / Hessian Diagnostics

- Verify HVPs are finite-difference Hessian diagnostics, not analytic
  second-adjoint products.
- Verify trust-region model, predicted/actual reduction ratio, and exit states.
- Tests/evidence: trust-region unit/integration tests.

### 8. Multimode

- Verify shared-phase MMF gradient summed across modes.
- Verify mode-coordinate block is intentionally finite-differenced.
- Verify mode-coordinate preflight artifacts.
- Tests/evidence: MMF gradient tests and burst preflight report.

### 9. Multivariable Optimization

- Verify phase, amplitude, and scalar-energy chain rules.
- Verify amplitude parameterization.
- Verify repaired boundary-amplitude quotient gradient.
- Tests/evidence: `scripts/dev/smoke/test_multivar_gradients.jl` on burst.

## Required Runs

Run on burst, through the heavy wrapper:

```bash
julia -t auto --project=. scripts/research/analysis/verification.jl
julia -t auto --project=. scripts/dev/smoke/test_multivar_gradients.jl
julia -t auto --project=. test/phases/test_phase16_mmf.jl
```

Depending on note-finalization decisions, also run:

```bash
julia -t auto --project=. scripts/research/cost_audit/cost_audit_driver.jl
```

Only run the cost-audit matrix if the project decides the missing matrix entries
are worth closing with compute rather than documenting as intentionally open.

## Public Deliverable

Create a new compact public verification document rather than patching the old
monolith blindly:

- location: `docs/reference/current-equation-verification.tex`
- compiled PDF: `docs/reference/current-equation-verification.pdf`
- style: concise, undergraduate-readable, source-linked, with diagrams
- contents:
  - equation
  - derivation sketch
  - implementation path
  - verification test or run artifact
  - status: verified / verified with caveat / not analytic / open

## Stop Criteria

This work is done only when:

- every active analytic equation has a status row
- every claimed analytic gradient has a finite-difference or Taylor check
- every non-analytic derivative path is clearly labeled as finite-difference
- current burst verification reports are saved and referenced
- public research notes can cite the verification document instead of carrying
  all derivations locally
