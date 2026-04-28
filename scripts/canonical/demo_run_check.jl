include(joinpath(@__DIR__, "..", "workflows", "demo_run_check.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    demo_run_check_main(ARGS)
end
