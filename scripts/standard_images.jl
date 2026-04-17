#!/usr/bin/env julia
# scripts/standard_images.jl
# ─────────────────────────────────────────────────────────────────────────────
# Canonical post-run visualization helper. Every optimization driver MUST call
# `save_standard_set(...)` after saving its phi_opt. This produces the two
# "standard output" figures the group is used to:
#
#   1. {tag}_phase_profile.png    — 6-panel before/after optimization result
#                                   (wrapped + unwrapped + group-delay, input
#                                    vs output, all on one sheet).
#                                   Comes from plot_optimization_result_v2().
#
#   2. {tag}_evolution.png        — colorful spectral-evolution waterfall for
#                                   the OPTIMIZED field (spectrum vs
#                                   propagation distance).
#                                   Comes from plot_spectral_evolution().
#
# Plus two extras the group has requested before:
#
#   3. {tag}_phase_diagnostic.png — 3-view phase plot (wrapped, unwrapped,
#                                   group delay) of phi_opt alone.
#
#   4. {tag}_evolution_unshaped.png — comparison waterfall with phi ≡ 0, so
#                                     the viewer can see what the optimization
#                                     suppressed.
#
# Usage (inside a driver, after phi_opt is known):
#
#     include(joinpath(@__DIR__, "common.jl"))
#     include(joinpath(@__DIR__, "visualization.jl"))
#     include(joinpath(@__DIR__, "standard_images.jl"))
#
#     uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
#         L_fiber=L, P_cont=P, fiber_preset=:SMF28, Nt=2^14, β_order=3
#     )
#     # ... run optimization, produce phi_opt ...
#
#     save_standard_set(phi_opt, uω0, fiber, sim,
#                       band_mask, Δf, raman_threshold;
#                       tag="my_run_L2m_P0p2W",
#                       fiber_name="SMF28", L_m=2.0, P_W=0.2,
#                       output_dir="results/raman/my_run/")
# ─────────────────────────────────────────────────────────────────────────────

if !(@isdefined _STANDARD_IMAGES_JL_LOADED)
const _STANDARD_IMAGES_JL_LOADED = true

using PyPlot
using Printf

# Parent scripts must have already included common.jl and visualization.jl
# before including this file.

"""
    save_standard_set(phi_opt, uω0_base, fiber, sim,
                      band_mask, Δf, raman_threshold;
                      tag, fiber_name, L_m, P_W,
                      output_dir,
                      lambda0_nm=1550.0, fwhm_fs=185.0,
                      n_z_samples=32,
                      also_unshaped=true)

Render the canonical post-run image set into `output_dir`.

Creates `output_dir` if needed. All filenames are prefixed with `tag`.

# Arguments
- `phi_opt::Vector{Float64}` — optimized spectral phase (length Nt)
- `uω0_base::Matrix{ComplexF64}` — base (unshaped) pulse in frequency
- `fiber::Dict`, `sim::Dict` — simulation containers
- `band_mask::Vector{Bool}`, `Δf::Vector{Float64}`, `raman_threshold::Float64`
    — from setup_raman_problem
- `tag::String` — short identifier used as filename prefix (e.g., "smf28_L2m_P0p2W")
- `fiber_name::String`, `L_m::Float64`, `P_W::Float64` — physical metadata for plot captions
- `output_dir::String` — where to write the PNGs
- `lambda0_nm`, `fwhm_fs` — metadata for plot captions (defaults match project standards)
- `n_z_samples::Int` — number of propagation distances in the evolution waterfall
- `also_unshaped::Bool` — if true, also render the unshaped-case waterfall for comparison

# Returns
`NamedTuple` with paths to each image written.
"""
function save_standard_set(
    phi_opt, uω0_base, fiber, sim,
    band_mask, Δf, raman_threshold;
    tag::AbstractString,
    fiber_name::AbstractString,
    L_m::Real,
    P_W::Real,
    output_dir::AbstractString,
    lambda0_nm::Real = 1550.0,
    fwhm_fs::Real = 185.0,
    n_z_samples::Int = 32,
    also_unshaped::Bool = true,
)
    mkpath(output_dir)

    metadata = (
        fiber_name = String(fiber_name),
        L_m        = float(L_m),
        P_cont_W   = float(P_W),
        lambda0_nm = float(lambda0_nm),
        fwhm_fs    = float(fwhm_fs),
    )

    results = Dict{Symbol,String}()

    # ── (1) 6-panel before/after optimization result ───────────────────────
    path_6panel = joinpath(output_dir, "$(tag)_phase_profile.png")
    plot_optimization_result_v2(
        zero(phi_opt), phi_opt, uω0_base, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path = path_6panel,
        metadata  = metadata,
    )
    results[:phase_profile] = path_6panel
    @info "standard image wrote" kind="phase_profile (6-panel)" path=path_6panel

    # ── (2) spectral-evolution waterfall for the optimized field ──────────
    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(range(0.0, fiber["L"], length=n_z_samples))

    uω0_shaped = @. uω0_base * cis(phi_opt)
    sol_opt = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_evo, sim)

    plot_spectral_evolution(sol_opt, sim, fiber_evo)
    path_evo = joinpath(output_dir, "$(tag)_evolution.png")
    savefig(path_evo; dpi=300, bbox_inches="tight")
    PyPlot.close("all")
    results[:evolution] = path_evo
    @info "standard image wrote" kind="evolution (optimized)" path=path_evo

    # ── (3) phase diagnostic (wrapped / unwrapped / group delay) ──────────
    path_diag = joinpath(output_dir, "$(tag)_phase_diagnostic.png")
    plot_phase_diagnostic(
        phi_opt, uω0_base, sim;
        save_path = path_diag,
        metadata  = metadata,
    )
    results[:phase_diagnostic] = path_diag
    @info "standard image wrote" kind="phase diagnostic" path=path_diag

    # ── (4) unshaped evolution waterfall (for comparison) ─────────────────
    if also_unshaped
        uω0_flat = uω0_base
        sol_un = MultiModeNoise.solve_disp_mmf(uω0_flat, fiber_evo, sim)
        plot_spectral_evolution(sol_un, sim, fiber_evo)
        path_un = joinpath(output_dir, "$(tag)_evolution_unshaped.png")
        savefig(path_un; dpi=300, bbox_inches="tight")
        PyPlot.close("all")
        results[:evolution_unshaped] = path_un
        @info "standard image wrote" kind="evolution (unshaped)" path=path_un
    end

    return (; results...)
end

end  # include guard
