ENV["MPLBACKEND"] = "Agg"

using Printf
using JLD2
using PyPlot

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "determinism.jl"))
include(joinpath(@__DIR__, "..", "longfiber", "longfiber_setup.jl"))

ensure_deterministic_environment(verbose=false)

const SU_DOCS = joinpath(@__DIR__, "..", "..", "..", "agent-docs", "stability-universality")
const SU_STD_DIR = joinpath(SU_DOCS, "standard-images")
const SU_PHASE17 = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase17")
const SU_PHASE16 = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase16")

const PHASE31_EXISTING = Dict(
    "poly3_transferable"   => ("Simple transferable polynomial baseline", joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase31", "sweep_A", "images", "p31A_polynomial_N003")),
    "cubic32_reduced"      => ("Reduced-basis cubic N=32",               joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase31", "sweep_A", "images", "p31A_cubic_N032")),
    "cubic128_reduced"     => ("Reduced-basis cubic N=128",              joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase31", "sweep_A", "images", "p31A_cubic_N128")),
    "cubic32_fullgrid"     => ("Full-grid continuation from cubic32",    joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase31", "followup", "images", "p31x_cubic32_full_step1_full_grid")),
    "zero_fullgrid"        => ("Full-grid zero-start reference",          joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase31", "followup", "images", "p31x_full_zero_step1_full_grid")),
)

const IMAGE_SUFFIXES = [
    "_phase_profile.png",
    "_evolution.png",
    "_phase_diagnostic.png",
    "_evolution_unshaped.png",
]

function copy_existing_bundle(label::AbstractString, desc::AbstractString, prefix::AbstractString)
    out_dir = joinpath(SU_STD_DIR, label)
    mkpath(out_dir)
    copied = String[]
    for suffix in IMAGE_SUFFIXES
        src = prefix * suffix
        dst = joinpath(out_dir, label * suffix)
        isfile(src) || error("missing source image: $src")
        cp(src, dst; force=true)
        push!(copied, dst)
    end
    return (label=String(label), description=String(desc), output_dir=out_dir, files=copied)
end

function render_phase17_bundle()
    path = joinpath(SU_PHASE17, "baseline.jld2")
    isfile(path) || error("missing $path")
    d = JLD2.load(path)
    phi_opt = Matrix{Float64}(d["phi_opt"])
    fiber_name = String(d["fiber_name"])
    L_m = Float64(d["L_m"])
    P_W = Float64(d["P_cont_W"])

    uω0, fiber, sim, band_mask, Δf, thr = setup_raman_problem_exact(;
        Nt=8192,
        time_window=10.0,
        β_order=3,
        L_fiber=L_m,
        P_cont=P_W,
        fiber_preset=:SMF28,
    )

    out_dir = joinpath(SU_STD_DIR, "simple_phase17")
    mkpath(out_dir)
    save_standard_set(
        phi_opt, uω0, fiber, sim, band_mask, Δf, thr;
        tag="simple_phase17",
        fiber_name=replace(fiber_name, "-" => ""),
        L_m=L_m,
        P_W=P_W,
        output_dir=out_dir,
    )
    PyPlot.close("all")
    return (
        label="simple_phase17",
        description="Phase 17 simple baseline optimum",
        output_dir=out_dir,
        files=[joinpath(out_dir, "simple_phase17" * suffix) for suffix in IMAGE_SUFFIXES],
    )
end

function render_phase16_bundle()
    path = joinpath(SU_PHASE16, "100m_opt_full_result.jld2")
    isfile(path) || error("missing $path")
    d = JLD2.load(path)
    phi_opt = vec(Float64.(d["phi_opt"]))
    L_m = Float64(d["L_m"])
    P_W = Float64(d["P_cont_W"])
    Nt = Int(d["Nt"])
    tw_ps = Float64(d["time_window_ps"])
    β_order = Int(d["β_order"])

    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(;
        fiber_preset=:SMF28_beta2_only,
        L_fiber=L_m,
        P_cont=P_W,
        Nt=Nt,
        time_window=tw_ps,
        β_order=β_order,
    )

    out_dir = joinpath(SU_STD_DIR, "longfiber100m_phase16")
    mkpath(out_dir)
    save_standard_set(
        phi_opt, uω0, fiber, sim, band_mask, Δf, thr;
        tag="longfiber100m_phase16",
        fiber_name="SMF28",
        L_m=L_m,
        P_W=P_W,
        output_dir=out_dir,
    )
    PyPlot.close("all")
    return (
        label="longfiber100m_phase16",
        description="Phase 16 long-fiber 100 m optimum",
        output_dir=out_dir,
        files=[joinpath(out_dir, "longfiber100m_phase16" * suffix) for suffix in IMAGE_SUFFIXES],
    )
end

function write_index(entries)
    path = joinpath(SU_STD_DIR, "INDEX.md")
    open(path, "w") do io
        println(io, "# Candidate Standard Images")
        println(io)
        println(io, "These are the familiar `save_standard_set(...)` bundles for the main masks discussed in the stability/universality work.")
        println(io)
        println(io, "How to read each bundle:")
        println(io, "- `_phase_profile.png`: the main 6-panel phase/spectrum sheet.")
        println(io, "- `_evolution.png`: optimized spectral-evolution heatmap.")
        println(io, "- `_phase_diagnostic.png`: wrapped, unwrapped, and group-delay views of the phase alone.")
        println(io, "- `_evolution_unshaped.png`: unshaped comparison heatmap.")
        println(io)
        println(io, "Short reading rule:")
        println(io, "- Start with `_phase_profile.png`.")
        println(io, "- Then compare `_evolution.png` against `_evolution_unshaped.png` to see whether the mask changed the Raman growth in a clean way.")
        println(io, "- Use `_phase_diagnostic.png` only after that, to judge whether the phase looks smooth/simple or dense/fine-scale.")
        println(io)
        for e in entries
            println(io, "## `", e.label, "`")
            println(io)
            println(io, e.description)
            println(io)
            for f in e.files
                println(io, "- `", basename(f), "`")
            end
            println(io)
        end
        println(io, "Related summary heatmap:")
        println(io, "- `../figures/robustness_heatmap.png`")
    end
    return path
end

function main()
    mkpath(SU_STD_DIR)
    entries = Any[]

    for (label, (desc, prefix)) in PHASE31_EXISTING
        push!(entries, copy_existing_bundle(label, desc, prefix))
    end
    push!(entries, render_phase17_bundle())
    push!(entries, render_phase16_bundle())

    order = Dict(
        "poly3_transferable" => 1,
        "cubic32_reduced" => 2,
        "cubic128_reduced" => 3,
        "cubic32_fullgrid" => 4,
        "zero_fullgrid" => 5,
        "simple_phase17" => 6,
        "longfiber100m_phase16" => 7,
    )
    sort!(entries, by = e -> order[e.label])

    index_path = write_index(entries)
    println("wrote ", index_path)
    for e in entries
        println("bundle ", e.label, " -> ", e.output_dir)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
