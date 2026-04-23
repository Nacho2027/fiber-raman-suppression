include(joinpath(@__DIR__, "..", "workflows", "regenerate_standard_images.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
