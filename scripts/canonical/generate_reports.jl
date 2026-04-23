include(joinpath(@__DIR__, "..", "workflows", "generate_sweep_reports.jl"))
const generate_sweep_reports_main = main

include(joinpath(@__DIR__, "..", "workflows", "generate_presentation_figures.jl"))
const generate_presentation_figures_main = main

if abspath(PROGRAM_FILE) == @__FILE__
    generate_sweep_reports_main()
    generate_presentation_figures_main()
end
