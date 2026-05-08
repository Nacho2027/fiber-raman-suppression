# FiberLab Examples

These notebooks are runnable Julia examples for the notebook-facing FiberLab API.
Open them from the repository root so `Pkg.activate(project_root)` selects this
project. The standard report writes PNGs under `examples/outputs/` and
`display_report(report)` shows those PNGs inline in the notebook.

Recommended order:

1. `01_raman_band_suppression.ipynb` - full-grid phase control with a Raman-band objective.
2. `02_multivariable_controls.ipynb` - phase, amplitude, and energy controls in one `ControlSpace`.
3. `03_multimode_mode_sum.ipynb` - two-mode propagation with a mode-summed objective.
4. `04_reduced_basis_phase.ipynb` - low-dimensional phase basis instead of full-grid phase pixels.

Each notebook follows the same pattern: build a `fiber_problem`, choose controls,
choose an objective, call `solve`, inspect `metrics(result)`, then call
`standard_report` and `display_report`. The figures are examples, not source
data; rerun the notebook to regenerate them after changing parameters.
