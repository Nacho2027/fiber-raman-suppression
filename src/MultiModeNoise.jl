module MultiModeNoise

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
using FiniteDifferences
using Interpolations

include("simulation/simulate_disp_mmf.jl")
include("simulation/sensitivity_disp_mmf.jl")
include("simulation/simulate_disp_gain_mmf.jl")
include("simulation/fibers.jl")

include("analysis/analysis.jl")
include("analysis/plotting.jl")

include("helpers/helpers.jl")

include("gain_simulation/gain.jl")

end