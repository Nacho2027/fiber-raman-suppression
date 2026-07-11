# Cost-Function Physics

The main objective penalizes spectral energy in a Raman-shifted band after
propagation. The optimizer changes the input control, usually spectral phase,
to reduce that leakage.

## Current core path

1. Build an input pulse on the simulation grid.
2. Apply the control, usually `phi(omega)`.
3. Propagate through the fiber model.
4. Measure fractional energy in the Raman band.
5. Use the adjoint gradient to update the control.

## Interpretation

A lower Raman-band fraction is useful only if the setup is physically comparable:
same fiber, length, power, grid, objective band, and output checks. Do not mix
costs from incompatible configs as if they were one leaderboard.

## Raman response convention

The built-in silica presets currently use the normalized single-damped-
oscillator model with `fR = 0.18`, `tau1 = 12.2 fs`, and `tau2 = 32 fs`. FiberLab
evaluates its analytic Fourier response on the simulation frequencies; it does
not numerically sample the femtosecond time response. Consequently the DC
delayed fraction remains `fR` when the grid spacing changes.

This compact model is a benchmark, not a universal material law. It follows the
standard transient silica approximation introduced by
[Blow and Wood](https://doi.org/10.1109/3.40655). More detailed silica models
capture structure that one Lorentzian oscillator misses; see
[Hollenbeck and Cantrell](https://doi.org/10.1364/JOSAB.19.002886) and
[Lin and Agrawal](https://doi.org/10.1364/OL.31.003086). Quantitative comparisons
must use the same response model and a grid covering every frequency shift being
interpreted.
