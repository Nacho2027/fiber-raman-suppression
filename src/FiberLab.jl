"""
    FiberLab

Julia API for adjoint-based inverse design in nonlinear single-mode and
multimode fiber systems, with support for:

- **Kerr + Raman nonlinearity** in the interaction picture (split-step via ODE solver)
- **Adjoint-based sensitivity analysis** for gradient computation
- **YDFA gain modeling** (Yb-doped fiber amplifier via rate equations)
- **Quantum noise analysis** (shot noise, excess noise decomposition via mode overlaps)
- **GRIN fiber mode solving** (graded-index eigenvalue problem)

The conceptual center is the adjoint contract: controls decode optimizer
coordinates, objectives define costs and terminal adjoint seeds, and models map
those seeds to physical gradients. Built-in physics helpers are conveniences
that use the same contracts available to notebook code.

The high-level FiberLab API is defined in `src/fiberlab/`. Lower-level
simulation functions remain available for backend and numerical work.
"""
module FiberLab

export AbstractControlMap, AbstractFeasibilityMap, AbstractFiberObjective, AdjointObjective,
       AbstractExecutionBackend, AdjointModel, AdjointStepResult,
       AdjointGradientCheckResult, AmplitudeBasis, ArtifactPolicy, CheckReport,
       ConfigRunnerBackend, Control, ControlBlock, ControlEvaluation,
       ControlGradient, ControlMap, ControlSpace, CoordinateBounds,
       ControlContract, DefaultAssumption,
       Experiment, ExperimentPlan, Fiber, FiberLabBackendError,
       FeasibilityEvaluation, FeasibilityMap,
       FiberFieldProblem, FiberProblem, FiberLabCheckError, FiberLabResult, FullGridPhase, Grid, Objective,
       NativeAdjointBackend, NativeAdjointResult, NativeArtifactContext,
       ObjectiveMap, PhaseBasis, PositiveScalar, PropagationResult, Pulse,
       MeasuredSpectrum, SpectrumComparison,
       NoExecutionBackend, ObjectiveContract, ScalarObjective, Solver,
       ScalarControl, SingleModeFiberProblem, LabProfile, TrustCheck, TrustReport,
       assert_adjoint_ready, check, check_adjoint_gradient,
       control_bounds, control_contract, control_slices, decode,
       decoded_final, default_assumptions, dimension, evaluate_control, execute,
       evaluate_feasibility, experiment_config_text, feasibility_check,
       feasibility_penalty, feasibility_physical_gradient,
       figure_hooks, figure_paths, has_control_pullback,
       has_objective_terminal_adjoint, has_pullback, has_terminal_adjoint,
       has_feasibility_check, has_penalty, has_physical_gradient, has_projection,
       amplitude_control, bounded_profile_control, controls, energy_control,
       fiber_field_problem, fiber_problem, fiber_model, field_objective,
       frequency_offsets, gradient_vector, metrics, mode_count, objective_contract,
       objective_value, plan,
       initial_coordinates, phase_control, fourier_basis, polynomial_basis,
       project, pullback, pullback_gradient,
       propagate,
       spectral_density, load_osa_spectrum, compare_spectrum, write_spectrum_report,
       registered_control_kinds, run_adjoint_step,
       registered_objective_kinds,
       register_control!, register_objective!,
       fundamental_mode_objective, mode_sum_objective, raman_band_objective,
       raman_peak_objective, temporal_width_objective, worst_mode_objective,
       sample_count, single_mode_fiber_problem, single_mode_phase_model, single_mode_shaper_model,
       display_report, standard_figures, standard_report,
       spectral_shaper_model, trust_check,
       solve, summarize, terminal_adjoint, verify,
       write_experiment_config,
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
import DifferentialEquations: solve
using LinearAlgebra
using Optim
using FFTW
using LoopVectorization
using PyPlot
using Interpolations
using Printf
using SHA

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
include("fiberlab/adjoints.jl")
include("fiberlab/feasibility.jl")
include("fiberlab/contracts.jl")
include("fiberlab/defaults.jl")
include("fiberlab/run_result.jl")
include("fiberlab/execution.jl")
include("fiberlab/native_execution.jl")
include("fiberlab/trust.jl")
include("fiberlab/physics_helpers.jl")
include("fiberlab/physics_models.jl")
include("fiberlab/propagation.jl")
include("fiberlab/spectral_measurements.jl")
include("fiberlab/design_api.jl")
include("fiberlab/standard_figures.jl")

end
