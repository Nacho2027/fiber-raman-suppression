---
topic: stability-universality
status: proposed-tests
created: 2026-04-23
---

# Next Stability And Universality Tests

These are concrete tests for deciding whether a phase profile is scientifically useful. They should be run first on existing saved `phi_opt` artifacts before launching new optimizations.

## Candidate Set

Use a small, interpretable panel:

1. `poly3_transferable`: Phase 31 polynomial `N_phi = 3`
2. `cubic32_robustish`: Phase 31 cubic `N_phi = 32`
3. `cubic128_deep`: Phase 31 cubic `N_phi = 128`
4. `cubic32_fullgrid`: Phase 31 follow-up `cubic32 -> full-grid`
5. `zero_fullgrid`: Phase 31 follow-up `zero -> full-grid`
6. `simple_phase17`: Phase 17 simple profile
7. `longfiber_phase16`: Phase 16 100 m profile, only if the test is sized for that regime

Always include `phi = 0` and a fitted quadratic/GDD-only mask as baselines.

## Test 1: Honest Fixed-Mask Transfer Matrix

Evaluate each candidate without reoptimization on:

- same fiber, `L` perturbed by `-10%, -5%, +5%, +10%`
- same fiber, `P` perturbed by `-10%, -5%, +5%, +10%`
- pulse FWHM perturbed by `-5%, +5%`
- `beta2` perturbed by `-5%, +5%`
- matched HNLF operating point already used in Phase 31

Report:

- `J_dB` at target
- gap to the target's own best known reoptimized result, if available
- gap to flat phase
- photon drift and pre-attenuator edge fraction

Pass levels:

- `universal`: within 3 dB of target reoptimized result on most targets
- `transferable`: at least 20 dB better than flat on most targets, even if not near target optimum
- `local-only`: good only near native operating point

## Test 2: Hardware Error Robustness

Apply forward-only perturbation tests to each fixed mask:

- additive Gaussian phase noise: `sigma = 0.005, 0.01, 0.02, 0.05, 0.1, 0.2 rad`
- low-order calibration drift: random offsets in GDD/TOD/FOD coefficients
- pixel quantization: 8-bit, 10-bit, 12-bit wrapped phase
- finite-pixel shaper resampling: 32, 64, 128, 256, 512 pixels across the active bandwidth
- smooth spectral blur: convolve the wrapped mask with 1, 2, 4 pixel kernels

Report:

- median, 90th percentile, and worst-case `Delta J_dB`
- `sigma_3dB`
- smallest pixel count that keeps loss under 3 dB
- smallest bit depth that keeps loss under 3 dB

This test directly separates publishable masks from numerical needles.

## Test 3: Gauge-Fixed Complexity Audit

Before comparing shapes, remove:

- constant phase
- linear phase / group delay

Then compute on the signal-bearing mask:

- polynomial fit `R^2` for orders 2 through 6
- DCT energy concentration: number of modes for 90%, 95%, 99%
- total variation of group delay
- RMS curvature and peak curvature
- stationary-point count
- residual spectrum slope after subtracting best low-order polynomial

Useful profiles should sit on a depth-complexity Pareto front. Profiles with high-frequency residuals that vanish under smoothing are likely optimizer-specific.

## Test 4: Smoothing And Low-Pass Survival

For each candidate, remove high-frequency structure in controlled ways:

- truncate DCT modes above `K = 2, 4, 8, 16, 32, 64, 128`
- fit cubic splines with `N_phi = 8, 16, 32, 64, 128`
- low-pass the group-delay curve instead of the phase curve

Then evaluate fixed-mask `J`.

Interpretation:

- If most suppression survives at low `K`, the mask has a simple physical core.
- If suppression collapses only when local spline features are removed, the local structure is probably real but not globally polynomial.
- If suppression collapses under tiny smoothing, the mask is probably too fragile for a fixed experimental recipe.

## Test 5: Propagation-Mechanism Diagnostics

For each profile, save and inspect standard images plus a small metrics table:

- peak power versus `z`
- temporal FWHM versus `z`
- spectral centroid versus `z`
- Raman-band energy versus `z`
- position of maximum compression
- earliest `z` where Raman-band growth exceeds fixed threshold

The goal is to replace "the optimizer found a phase" with a mechanism:

- stretches pulse and lowers peak power
- delays compression/fission beyond the fiber end
- makes compression occur away from the Raman gain condition
- creates destructive timing between Kerr broadening and Raman transfer
- avoids boundary/attenuator artifacts

## Test 6: Reoptimization From Mask As Prior

For each candidate and target, compare:

- fixed-mask evaluation
- L-BFGS from zero
- L-BFGS warm-start from candidate
- optional reduced-basis continuation from candidate's basis family

Report:

- final `J_dB`
- iterations / solves
- final shape distance from seed after gauge-fix
- whether the warm-start reaches a better basin than zero-start

This distinguishes a universal fixed mask from a useful initialization prior.

## Test 7: Ambient Saddle And Negative-Curvature Probe

For selected high-performing masks only:

- estimate leftmost Hessian eigenpair in the relevant control space
- classify minimum-like vs indefinite
- perturb along negative curvature and reoptimize
- measure whether the escaped profile is simpler, deeper, or more robust

Do not run this broadly until cheaper tests identify candidates worth the cost.

## Recommended First Batch

Run a forward-only evaluation batch, not new optimization:

1. Candidate set: `poly3_transferable`, `cubic32_robustish`, `cubic128_deep`, `cubic32_fullgrid`, `simple_phase17`
2. Tests: fixed-mask transfer, hardware noise, DCT truncation, spline resampling
3. Output: one CSV plus a short agent summary ranking candidates by:
   - native depth
   - transfer gap
   - `sigma_3dB`
   - minimum pixel count
   - simplest surviving representation

Only after that should the project spend burst time on multistart or second-order follow-up.

