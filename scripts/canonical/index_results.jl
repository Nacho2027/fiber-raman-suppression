include(joinpath(@__DIR__, "..", "workflows", "index_results.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    index_results_main(ARGS)
end
