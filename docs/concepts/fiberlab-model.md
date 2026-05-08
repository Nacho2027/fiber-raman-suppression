# FiberLab Concepts

FiberLab is the high-level API for adjoint-based inverse design in nonlinear
fiber systems.

The inherited propagation code is the physics backend. The user-facing layer is
organized around experiments:

| Concept | Meaning |
|---|---|
| `Fiber` | Regime, preset, length, power, and dispersion order |
| `Pulse` | Input pulse duration, repetition rate, and shape |
| `Grid` | Requested simulation resolution and time window |
| `Control` | What the optimizer can change, such as phase, amplitude, energy, mode weights, or an extension control |
| `Objective` | What scalar quantity the optimizer is trying to improve, together with the adjoint seed when gradient execution is requested |
| `Solver` | Optimization method and iteration policy |
| `Experiment` | Complete runnable FiberLab API object |
| `ArtifactPolicy` | What evidence, plots, sidecars, and exports should be produced |

Configs under `configs/experiments/` are serialized experiments. They are useful
for reproducibility and batch execution, but they should not be treated as the
conceptual center of the project.

Raman-band suppression is a built-in objective and benchmark. It is kept as
regression evidence, not as a restriction on the API model.

Low-level simulation functions remain available for numerical work. New
research workflows should start from the FiberLab concepts first, then lower
into backend-specific data structures only where necessary. When a researcher
already has explicit propagation arrays for a custom single-mode or multimode
setup, `fiber_field_problem` wraps those arrays without changing the optimizer
or adjoint API.
