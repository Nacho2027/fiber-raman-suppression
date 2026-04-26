include(joinpath(@__DIR__, "..", "workflows", "refine_amp_on_phase.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    refine_amp_on_phase_main(ARGS)
end
