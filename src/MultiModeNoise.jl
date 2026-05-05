"""
    MultiModeNoise

Julia package for simulating nonlinear pulse propagation in single-mode and multimode
optical fibers, with support for:

- **Kerr + Raman nonlinearity** in the interaction picture (split-step via ODE solver)
- **Adjoint-based sensitivity analysis** for gradient computation (spectral phase optimization)
- **YDFA gain modeling** (Yb-doped fiber amplifier via rate equations)
- **Quantum noise analysis** (shot noise, excess noise decomposition via mode overlaps)
- **GRIN fiber mode solving** (graded-index eigenvalue problem)

The primary use case is Raman suppression optimization: finding spectral phase profiles
that minimize energy transfer to Raman-shifted frequencies during fiber propagation.

The high-level FiberLab API is defined in `src/fiberlab/`. Lower-level
simulation functions remain available for backend and numerical work.
"""
module MultiModeNoise

export ArtifactPolicy, Control, Experiment, Fiber, Grid, Objective, Pulse,
       Solver, experiment_config_text, summarize, write_experiment_config,
       OUTPUT_FORMAT_SCHEMA_VERSION, deterministic_environment_status,
       artifact_paths_for_prefix, ensure_deterministic_environment,
       load_run, load_canonical_runs, read_run_manifest, save_run,
       update_run_manifest_entry, upsert_run_manifest_entry!, write_jld2_file,
       write_json_file, write_run_manifest

using Tullio
using SparseArrays
using Arpack
using FiniteDifferences
using NPZ
using DifferentialEquations
using LinearAlgebra
using FFTW
using LoopVectorization
using PyPlot
using Interpolations

include("gain_simulation/gain.jl")

include("simulation/simulate_disp_mmf.jl")
include("simulation/sensitivity_disp_mmf.jl")
include("simulation/simulate_disp_gain_mmf.jl")
include("simulation/fibers.jl")

include("analysis/analysis.jl")
include("analysis/plotting.jl")

include("helpers/helpers.jl")
include("io/artifacts.jl")
include("io/results.jl")
include("runtime/determinism.jl")
include("fiberlab/api.jl")

end
