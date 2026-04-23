include(joinpath(@__DIR__, "..", "workflows", "generate_sweep_reports.jl"))
include(joinpath(@__DIR__, "..", "workflows", "generate_presentation_figures.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    generate_sweep_reports_main()
    generate_presentation_figures_main()
end
