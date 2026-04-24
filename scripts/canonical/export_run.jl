include(joinpath(@__DIR__, "..", "workflows", "export_run.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    export_run_main(ARGS)
end
