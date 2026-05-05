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
