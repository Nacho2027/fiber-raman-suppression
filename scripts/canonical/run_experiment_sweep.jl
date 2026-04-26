include(joinpath(@__DIR__, "..", "workflows", "run_experiment_sweep.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_sweep_main(ARGS)
end
