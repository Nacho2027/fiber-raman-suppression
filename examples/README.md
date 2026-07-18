# FiberLab Examples

These notebooks are runnable Julia examples for the notebook-facing FiberLab API.
Open them from the repository root so `Pkg.activate(project_root)` selects this
project. The standard report writes PNGs under `examples/outputs/` and
`display_report(report)` shows those PNGs inline in the notebook.

Recommended order:

1. `01_red_band_objective.ipynb` - historical red-band objective regression; not Raman attribution.
2. `02_multivariable_controls.ipynb` - phase, amplitude, and energy controls in one `ControlSpace`.
3. `03_multimode_mode_sum.ipynb` - two-mode propagation with a mode-summed objective.
4. `04_reduced_basis_phase.ipynb` - low-dimensional phase basis instead of full-grid phase pixels.
5. `05_counterfactual_raman.jl` - falsification-first Raman-on/off centroid benchmark with explicit launch-quality and numerical gates.

Notebooks 1–4 build a `fiber_problem`, choose controls and an objective, call
`solve`, and inspect a standard report. Example 5 is a falsification-first
script with explicit search and validation outputs. Generated figures are not
source data; rerun the corresponding example after changing parameters.
