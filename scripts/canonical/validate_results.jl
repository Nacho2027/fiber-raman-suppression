include(joinpath(@__DIR__, "..", "validation", "validate_results.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
