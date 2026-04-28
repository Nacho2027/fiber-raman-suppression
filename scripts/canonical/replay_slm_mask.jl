include(joinpath(@__DIR__, "..", "workflows", "replay_slm_mask.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    replay_slm_mask_main(ARGS)
end
