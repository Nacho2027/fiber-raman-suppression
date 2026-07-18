# FiberLab Concepts

FiberLab is the high-level API for adjoint-based inverse design in nonlinear
fiber systems.

The inherited propagation code is the physics backend. The user-facing layer is
organized around experiments:

| Concept | Meaning |
|---|---|
| `Fiber` | Regime, preset, length, power, dispersion order, and optional delayed-Raman fraction override |
| `Pulse` | Input pulse duration, repetition rate, and shape |
| `Grid` | Requested simulation resolution and time window |
| `Control` | What the optimizer can change, such as phase, amplitude, energy, mode weights, or an extension control |
| `Objective` | What scalar quantity the optimizer is trying to improve, together with the adjoint seed when gradient execution is requested |
| `Solver` | Optimization method and iteration policy |
| `Experiment` | Complete runnable FiberLab API object |
| `ArtifactPolicy` | What evidence, plots, sidecars, and exports should be produced |
| `MeasuredSpectrum` | A hashed, explicitly parsed OSA wavelength trace with RBW and floor metadata |
| `SpectrumComparison` | A sealed simulation-to-OSA observation and shape-only comparison policy |

Configs under `configs/experiments/` are serialized experiments. They are useful
for reproducibility and batch execution, but they should not be treated as the
conceptual center of the project.

The historical `raman_band` red-leakage objective is a built-in regression
benchmark. It is not a causal Raman observable. Raman mechanism studies must
pair it with a matched Raman-off scenario and visible component metrics.
For a sealed package-built problem, `with_raman_fraction(problem, 0.0)` creates
that matched counterfactual without changing its launch, grid, dispersion, or
nonlinear coupling. Physical low-dimensional phase studies can use
`taylor_phase_basis`; its coordinates are Taylor coefficients in fsⁿ (or
dimensionless when explicit coefficient scales are supplied), not
grid-normalized polynomial weights.

Shared-control studies use `ScenarioTerm` and `compose_scenarios`. Each term
keeps its own problem/objective digest; there is deliberately no single
`resolved_problem_sha256` for a composition of different physical problems.
Native result sidecars instead record `model_provenance`, including every term,
its source authority, and the exact parameters of the package-defined
aggregate (`weighted_scenario_aggregate` or `squared_difference_aggregate`).
Opaque aggregate closures are rejected because their identity cannot be
serialized truthfully.

Measurement support begins with one concrete seam rather than a generic data
framework. FiberLab can predict a single-mode OSA spectrum from a sealed
`PropagationResult`, including the frequency-to-vacuum-wavelength Jacobian and
an assumed Gaussian wavelength-RBW response. Independent area normalization
removes global scale, so this lane compares spectral shape only; it cannot
claim absolute power, throughput, calibration accuracy, or scientific
readiness.

Low-level simulation functions remain available for numerical work. New
research workflows should start from the FiberLab concepts first, then lower
into backend-specific data structures only where necessary. When a researcher
already has explicit propagation arrays for a custom single-mode or multimode
setup, `fiber_field_problem` wraps those arrays without changing the optimizer
or adjoint API.

Forward propagation accepts any finite real nonlinear-coupling tensor with the
declared shape. The inherited multimode adjoint is narrower: `fiber_model`
requires `gamma[i,j,k,l]` to be invariant under index permutations, as physical
real-mode overlap tensors are. FiberLab rejects a nonsymmetric tensor for
gradient execution instead of returning an unsupported adjoint; the same
problem remains usable through forward-only `propagate`.
