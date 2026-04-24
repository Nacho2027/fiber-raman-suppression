include(joinpath(@__DIR__, "..", "workflows", "optimize_raman.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    canonical_optimize_main(ARGS)
end
