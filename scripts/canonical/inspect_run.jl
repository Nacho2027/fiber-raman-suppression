include(joinpath(@__DIR__, "..", "workflows", "inspect_run.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    inspect_run_main(ARGS)
end
