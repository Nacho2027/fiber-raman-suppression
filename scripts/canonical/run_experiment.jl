include(joinpath(@__DIR__, "..", "workflows", "run_experiment.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    run_experiment_main(ARGS)
end
