include(joinpath(@__DIR__, "..", "workflows", "index_telemetry.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    index_telemetry_main(ARGS)
end
