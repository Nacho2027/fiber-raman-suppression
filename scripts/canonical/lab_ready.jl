include(joinpath(@__DIR__, "..", "workflows", "lab_ready.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    lab_ready_main(ARGS)
end
