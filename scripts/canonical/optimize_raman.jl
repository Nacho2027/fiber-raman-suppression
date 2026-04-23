include(joinpath(@__DIR__, "..", "lib", "raman_optimization.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
