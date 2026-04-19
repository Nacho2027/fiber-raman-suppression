#!/usr/bin/env julia
# scripts/longfiber_regenerate_standard_images.jl
# ─────────────────────────────────────────────────────────────────────────────
# Session F post-hoc standard-image generator — matches the Phase 16 JLD2
# schema (L_m, P_cont_W, β_order, Nt, time_window_ps, phi_opt).
#
# The generic scripts/regenerate_standard_images.jl keys off fiber_preset +
# L_fiber + P_cont which are NOT in Session F JLD2s. This script is the
# session-specific bridge; it reconstructs the (fiber, sim, band_mask) via
# `setup_longfiber_problem(...)` from stored config and calls save_standard_set.
#
# Usage (on burst VM, behind heavy-lock):
#   ~/bin/burst-run-heavy F-regenimages \
#       'julia -t auto --project=. scripts/longfiber_regenerate_standard_images.jl'
#
# Expected inputs (per file, all under results/raman/phase16/):
#   - 100m_opt_full_result.jld2 : phi_opt (Nt=32768, 1), L_m, P_cont_W, Nt,
#                                 time_window_ps, β_order
#   - 50m_validate.jld2         : phi_opt (Nt=16384, 1), similar keys
#
# Outputs:
#   results/raman/phase16/standard_images_F_{tag}/{tag}_*.png  × 4

ENV["MPLBACKEND"] = "Agg"

using JLD2, Printf, Logging
using FFTW, LinearAlgebra
using MultiModeNoise

include(joinpath(@__DIR__, "longfiber_setup.jl"))
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))

const PHASE16_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase16")

"""
Regenerate the canonical 4-PNG set for one Session F optimizer JLD2.

`tag_out` is the filename prefix for the images. `label` identifies the
run in logs.
"""
function lf_regen_one(jld2_path::AbstractString; tag_out::AbstractString,
        fiber_preset::Symbol = :SMF28_beta2_only,
        label::AbstractString = tag_out)
    @info "───── regenerating standard images for $label ─────"
    @info "source: $jld2_path"

    isfile(jld2_path) || error("missing JLD2: $jld2_path")
    d = JLD2.load(jld2_path)

    # Required keys
    for k in ("phi_opt", "L_m", "P_cont_W", "Nt", "time_window_ps", "β_order")
        haskey(d, k) || error("$(basename(jld2_path)): missing key `$k`")
    end

    phi_opt = vec(d["phi_opt"])
    L_m     = Float64(d["L_m"])
    P_W     = Float64(d["P_cont_W"])
    Nt      = Int(d["Nt"])
    tw_ps   = Float64(d["time_window_ps"])
    β_order = Int(d["β_order"])

    @info @sprintf("config: L=%.1f m, P=%.3f W, Nt=%d, T=%.1f ps, β_order=%d, preset=%s",
        L_m, P_W, Nt, tw_ps, β_order, fiber_preset)
    @info @sprintf("phi_opt: length=%d, ‖phi‖=%.3e", length(phi_opt), norm(phi_opt))

    # Rebuild problem (bypasses auto-sizing)
    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = fiber_preset,
        L_fiber      = L_m,
        P_cont       = P_W,
        Nt           = Nt,
        time_window  = tw_ps,
        β_order      = β_order,
    )

    output_dir = joinpath(PHASE16_DIR, "standard_images_$(tag_out)")
    save_standard_set(
        phi_opt, uω0, fiber, sim,
        band_mask, Δf, thr;
        tag         = tag_out,
        fiber_name  = "SMF28",
        L_m         = L_m,
        P_W         = P_W,
        output_dir  = output_dir,
    )
    @info "done: $output_dir"
    println()
end

function main()
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Session F — regenerate standard image sets — start %s", string(time()))
    @info @sprintf("Julia threads: %d  BLAS threads: %d",
        Threads.nthreads(), BLAS.get_num_threads())
    @info "═══════════════════════════════════════════════════════════════"

    # 1. L=100m fresh-mode optimum
    lf_regen_one(joinpath(PHASE16_DIR, "100m_opt_full_result.jld2");
        tag_out = "F_100m_opt",
        label   = "L=100m phi_opt (fresh 25-iter from phi@2m)")

    # 2. L=50m validation optimum
    lf_regen_one(joinpath(PHASE16_DIR, "50m_validate.jld2");
        tag_out = "F_50m_opt",
        label   = "L=50m phi_opt (4-iter refinement from phi@2m)")

    @info "all regenerations complete"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
