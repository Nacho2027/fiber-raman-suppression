include(joinpath(@__DIR__, "..", "workflows", "scaffold_variable.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    scaffold_variable_main(ARGS)
end
