# FiberLab API

The active product direction is a Julia API for adjoint-based inverse design in
nonlinear fiber systems. Raman-band suppression is a built-in benchmark and
regression lane, not the conceptual center of the API.

Start API-facing work from `src/fiberlab/` and the exported concepts:
`Fiber`, `Pulse`, `Grid`, `Control`, `Objective`, `Solver`, `Experiment`,
`ArtifactPolicy`, and the adjoint contract primitives in
`src/fiberlab/adjoints.jl`.

Read `docs/architecture/adjoint-inverse-design.md` before changing the public
API. The core contract is:

```text
optimizer coordinates -> control decode -> forward propagation -> objective
cost -> terminal adjoint -> adjoint propagation -> physical gradient ->
control pullback -> optimizer update
```

Public UX should make this feel simple, but implementation should stay
defensive:

- gradient solvers require objective terminal adjoints;
- gradient solvers require control pullbacks;
- finite differences are verification tools, not the high-dimensional
  optimization identity;
- multivariable optimization is continuous control blocks packed into one
  optimizer vector;
- ablation is a comparison workflow across control subsets, not discrete
  variable-selection optimization;
- figures and artifacts are part of the contract, not afterthoughts.

Treat older `scripts/lib/` runner code as transitional implementation. Do not
make that directory the conceptual center of new work. Configs in
`configs/experiments/` serialize experiments for reproducibility; they are a
bridge, not the primary API.
