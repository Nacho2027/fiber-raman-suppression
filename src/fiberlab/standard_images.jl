# Package-owned renderer behind `standard_report` and `standard_figures`.

if !(@isdefined _STANDARD_IMAGES_JL_LOADED)
const _STANDARD_IMAGES_JL_LOADED = true

using PyPlot
using Printf

# The package loads visualization before this file. Compatibility adapters in
# `scripts/lib/` preserve that order for transitional orchestration code.

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
    objective_kind::Symbol = :raman_band,
    phi_before = zero(phi_opt),
    uω0_after = nothing,
    objective_values = nothing,
    objective_scale::Symbol = :linear,
    objective_label = nothing,
    mode_idx = :sum,
)
    mkpath(output_dir)
    after_input = uω0_after === nothing ? uω0_base : uω0_after

    metadata = (
        fiber_name = String(fiber_name),
        L_m        = float(L_m),
        P_cont_W   = float(P_W),
        lambda0_nm = float(lambda0_nm),
        fwhm_fs    = float(fwhm_fs),
    )

    results = Dict{Symbol,String}()
    mode_views = mode_idx isa Tuple ? mode_idx : (mode_idx, mode_idx)
    length(mode_views) == 2 || throw(ArgumentError(
        "mode_idx tuple must contain exactly (before, after) views"))

    # ── (1) 6-panel before/after optimization result ───────────────────────
    path_6panel = joinpath(output_dir, "$(tag)_phase_profile.png")
    plot_optimization_result_v2(
        phi_before, phi_opt, uω0_base, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path = path_6panel,
        metadata  = metadata,
        objective_kind = objective_kind,
        uω0_after = after_input,
        objective_values = objective_values,
        objective_scale = objective_scale,
        objective_label = objective_label,
        mode_idx = mode_views,
    )
    results[:phase_profile] = path_6panel
    @info "standard image wrote" kind="phase_profile (6-panel)" path=path_6panel

    # ── (2) spectral-evolution waterfall for the optimized field ──────────
    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(range(0.0, fiber["L"], length=n_z_samples))

    uω0_shaped = @. after_input * cis(phi_opt)
    sol_opt = FiberLab.solve_disp_mmf(uω0_shaped, fiber_evo, sim)

    plot_spectral_evolution(
        sol_opt, sim, fiber_evo;
        title="Optimized spectral evolution",
        mode_idx=mode_views[2],
    )
    path_evo = joinpath(output_dir, "$(tag)_evolution.png")
    savefig(path_evo; dpi=450, bbox_inches="tight")
    PyPlot.close("all")
    results[:evolution] = path_evo
    @info "standard image wrote" kind="evolution (optimized)" path=path_evo

    # ── (3) phase diagnostic (wrapped / unwrapped / group delay) ──────────
    path_diag = joinpath(output_dir, "$(tag)_phase_diagnostic.png")
    plot_phase_diagnostic(
        phi_opt, after_input, sim;
        save_path = path_diag,
        metadata  = metadata,
        objective_kind = objective_kind,
        raman_threshold_thz = raman_threshold,
        mode_idx = mode_views[2],
    )
    results[:phase_diagnostic] = path_diag
    @info "standard image wrote" kind="phase diagnostic" path=path_diag

    # ── (4) unshaped evolution waterfall (for comparison) ─────────────────
    if also_unshaped
        uω0_reference = @. uω0_base * cis(phi_before)
        sol_un = FiberLab.solve_disp_mmf(uω0_reference, fiber_evo, sim)
        plot_spectral_evolution(
            sol_un, sim, fiber_evo;
            title="Reference spectral evolution",
            mode_idx=mode_views[1],
        )
        path_un = joinpath(output_dir, "$(tag)_evolution_unshaped.png")
        savefig(path_un; dpi=450, bbox_inches="tight")
        PyPlot.close("all")
        results[:evolution_unshaped] = path_un
        @info "standard image wrote" kind="evolution (unshaped)" path=path_un
    end

    return (; results...)
end

end  # include guard
