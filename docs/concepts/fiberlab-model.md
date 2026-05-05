# FiberLab Concepts

FiberLab is the high-level API for fiber-optic optimization experiments.

The inherited propagation code is the physics backend. The user-facing layer is
organized around experiments:

| Concept | Meaning |
|---|---|
| `Fiber` | Regime, preset, length, power, and dispersion order |
| `Pulse` | Input pulse duration, repetition rate, and shape |
| `Grid` | Requested simulation resolution and time window |
| `Control` | What the optimizer can change, such as phase, amplitude, energy, or an extension control |
| `Objective` | What the optimizer is trying to improve |
| `Solver` | Optimization method and iteration policy |
| `Experiment` | Complete runnable FiberLab API object |
| `ArtifactPolicy` | What evidence, plots, sidecars, and exports should be produced |

Configs under `configs/experiments/` are serialized experiments. They are useful
for reproducibility and batch execution, but they should not be treated as the
conceptual center of the project.

Low-level simulation functions remain available for numerical work. New
research workflows should start from the FiberLab concepts first, then lower
into backend-specific data structures only where necessary.
