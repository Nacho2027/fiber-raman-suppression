include(joinpath(@__DIR__, "..", "workflows", "run_sweep.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    run_sweep_main(ARGS)
end
