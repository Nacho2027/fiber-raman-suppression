include(joinpath(@__DIR__, "..", "workflows", "scaffold_objective.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_objective_main(ARGS)
end
