#!/usr/bin/env julia
"""
Phase 21 recovery helpers.

Shared utilities for honest-grid sizing, forward validation, result reporting,
and standard-image emission. This file reads existing shared scripts but does
not modify them.
"""

ENV["MPLBACKEND"] = "Agg"

try
    using Revise
catch
end

using Dates
using FFTW
using JLD2
using Logging
using Printf
using LinearAlgebra
using Statistics

using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "longfiber_setup.jl"))

if !(@isdefined _RECOVERY_COMMON_JL_LOADED)
const _RECOVERY_COMMON_JL_LOADED = true

const PH21_ROOT = joinpath(@__DIR__, "..", ".planning", "phases", "21-numerical-recovery")
const PH21_IMAGE_DIR = joinpath(PH21_ROOT, "images")
const PH21_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase21")

mkpath(PH21_ROOT)
mkpath(PH21_IMAGE_DIR)
mkpath(PH21_RESULTS_DIR)

recovery_timestamp() = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")

function recovery_peak_power(P_cont; pulse_fwhm=185e-15, pulse_rep_rate=80.5e6)
    return 0.881374 * P_cont / (pulse_fwhm * pulse_rep_rate)
end

"""
    recovery_starting_window_ps(L_fiber; beta2_abs, gamma, P_cont, ...)

First-principles starting guess for the time window, based on the codebase's
existing walk-off + SPM broadening model but with a more conservative safety
factor than the production sweeps used.
"""
function recovery_starting_window_ps(L_fiber;
    beta2_abs,
    gamma,
    P_cont,
    pulse_fwhm=185e-15,
    pulse_rep_rate=80.5e6,
    safety_factor=4.0,
)
    P_peak = recovery_peak_power(P_cont; pulse_fwhm=pulse_fwhm, pulse_rep_rate=pulse_rep_rate)
    return recommended_time_window(L_fiber;
        safety_factor=safety_factor,
        beta2=beta2_abs,
        gamma=gamma,
        P_peak=P_peak,
        pulse_fwhm=pulse_fwhm,
    )
end

function recovery_dt_min_ps(time_window_ps::Real)
    return time_window_ps <= 80 ? 0.004 : 0.005
end

function recovery_nt_for_window(time_window_ps::Real)
    return nt_for_window(time_window_ps; dt_min_ps=recovery_dt_min_ps(time_window_ps))
end

function recovery_output_field(sol, fiber, sim)
    L = fiber["L"]
    Dω = fiber["Dω"]
    ũω_L = sol["ode_sol"](L)
    return @. cis(Dω * L) * ũω_L
end

function recovery_output_time_field(sol, fiber, sim)
    return ifft(recovery_output_field(sol, fiber, sim), 1)
end

function recovery_edge_fraction(sol, fiber, sim; threshold=1e-3)
    ut = recovery_output_time_field(sol, fiber, sim)
    _, frac = check_boundary_conditions(ut, sim; threshold=threshold)
    return frac
end

function recovery_energy_drift(uω_in, uω_out)
    Ein = sum(abs2.(uω_in))
    Eout = sum(abs2.(uω_out))
    return abs(Eout - Ein) / max(Ein, eps())
end

function recovery_forward_metrics(uω0, phi, fiber, sim, band_mask)
    uω0_shaped = @. uω0 * cis(phi)
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    uωf = recovery_output_field(sol, fiber, sim)
    J_lin, _ = spectral_band_cost(uωf, band_mask)
    return (
        sol = sol,
        uωf = uωf,
        J_lin = J_lin,
        J_dB = 10 * log10(max(J_lin, 1e-15)),
        edge_frac = recovery_edge_fraction(sol, fiber, sim),
        energy_drift = recovery_energy_drift(uω0_shaped, uωf),
    )
end

function recovery_scalarize_phi(phi, Nt)
    if isa(phi, AbstractVector)
        @assert length(phi) == Nt
        return reshape(Float64.(phi), Nt, 1)
    end
    if isa(phi, AbstractMatrix)
        @assert size(phi, 1) == Nt
        if size(phi, 2) == 1
            return Matrix{Float64}(phi)
        end
        return reshape(Float64.(vec(phi[:, 1])), Nt, 1)
    end
    error("unsupported phi container: $(typeof(phi))")
end

function recovery_seed_to_grid(phi_seed, old_Nt, old_tw_ps, Nt, tw_ps)
    return longfiber_interpolate_phi(phi_seed, old_Nt, old_tw_ps, Nt, tw_ps)
end

function recovery_active_band_mask(uω0; threshold=1e-3)
    amp = vec(sum(abs.(uω0), dims=2))
    amax = maximum(amp)
    return amp .>= threshold * max(amax, eps())
end

"""
    recovery_remove_linear_phase(phi, uω0, sim)

Gauge-fix a seed by subtracting a weighted affine fit in frequency over the
input spectral support. This prevents the honest-grid search from inflating the
time window purely because an old `phi_opt` carries an arbitrary group delay.
"""
function recovery_remove_linear_phase(phi, uω0, sim)
    phi_vec = vec(phi)
    mask = recovery_active_band_mask(uω0)
    fs = fftfreq(sim["Nt"], 1 / sim["Δt"])
    ω = 2π .* fs
    w = vec(sum(abs.(uω0), dims=2))
    use = findall(mask)
    X = hcat(ones(length(use)), ω[use])
    W = Diagonal(w[use])
    coeffs = (X' * W * X) \ (X' * W * phi_vec[use])
    fitted = coeffs[1] .+ coeffs[2] .* ω
    return reshape(phi_vec .- fitted, sim["Nt"], 1)
end

function recovery_fiber_params(fiber_preset::Symbol)
    preset = get_fiber_preset(fiber_preset)
    return (
        gamma = preset.gamma,
        beta2_abs = abs(preset.betas[1]),
        name = preset.name,
    )
end

"""
    recovery_find_honest_grid(...)

Pick `(Nt, time_window)` by formula first, then validate on the actual solver.
The candidate window is doubled until both the flat pulse and every provided
seed phase have output edge fraction below `threshold`.
"""
function recovery_find_honest_grid(;
    fiber_preset::Symbol,
    L_fiber::Real,
    P_cont::Real,
    β_order::Integer,
    phi_seeds::Vector,
    old_Nt::Integer,
    old_tw_ps::Real,
    pulse_fwhm::Real=185e-15,
    pulse_rep_rate::Real=80.5e6,
    threshold::Real=1e-3,
    max_rounds::Int=5,
    min_time_window_ps::Union{Nothing,Real}=nothing,
)
    fp = recovery_fiber_params(fiber_preset)
    tw = recovery_starting_window_ps(L_fiber;
        beta2_abs=fp.beta2_abs, gamma=fp.gamma, P_cont=P_cont,
        pulse_fwhm=pulse_fwhm, pulse_rep_rate=pulse_rep_rate,
    )
    if min_time_window_ps !== nothing
        tw = max(tw, min_time_window_ps)
    end

    for round in 1:max_rounds
        Nt = recovery_nt_for_window(tw)
        uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(;
            fiber_preset=fiber_preset,
            L_fiber=L_fiber,
            P_cont=P_cont,
            Nt=Nt,
            time_window=tw,
            β_order=β_order,
            pulse_fwhm=pulse_fwhm,
            pulse_rep_rate=pulse_rep_rate,
        )

        flat = recovery_forward_metrics(uω0, zero(uω0), fiber, sim, band_mask)
        seed_edges = Float64[]
        for phi_seed in phi_seeds
            phi0 = recovery_seed_to_grid(phi_seed, old_Nt, old_tw_ps, Nt, tw)
            phi0 = recovery_remove_linear_phase(phi0, uω0, sim)
            push!(seed_edges, recovery_forward_metrics(uω0, phi0, fiber, sim, band_mask).edge_frac)
        end
        max_seed_edge = isempty(seed_edges) ? 0.0 : maximum(seed_edges)

        @info @sprintf("honest-grid round=%d preset=%s L=%.3fm P=%.3fW Nt=%d tw=%.1fps flat_edge=%.3e max_seed_edge=%.3e",
            round, String(fiber_preset), L_fiber, P_cont, Nt, tw, flat.edge_frac, max_seed_edge)

        if max(flat.edge_frac, max_seed_edge) < threshold
            return (
                Nt=Nt,
                time_window_ps=tw,
                uω0=uω0,
                fiber=fiber,
                sim=sim,
                band_mask=band_mask,
                Δf=Δf,
                raman_threshold=raman_threshold,
                flat_edge_frac=flat.edge_frac,
                max_seed_edge_frac=max_seed_edge,
            )
        end

        tw *= 2
    end

    error("failed to find honest grid for $(fiber_preset), L=$(L_fiber), P=$(P_cont) within $(max_rounds) rounds")
end

function recovery_save_standard_set(phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold;
    tag, fiber_name, L_m, P_W)
    return save_standard_set(
        phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold;
        tag=tag,
        fiber_name=fiber_name,
        L_m=L_m,
        P_W=P_W,
        output_dir=PH21_IMAGE_DIR,
    )
end

function recovery_result_path(name::AbstractString)
    path = joinpath(PH21_RESULTS_DIR, name)
    mkpath(dirname(path))
    return path
end

function recovery_write_markdown(path::AbstractString, lines::Vector{String})
    mkpath(dirname(path))
    open(path, "w") do io
        for line in lines
            println(io, line)
        end
    end
end

function recovery_key_or_nothing(d::AbstractDict, candidates::Vector{String})
    for k in candidates
        if haskey(d, k)
            return d[k]
        end
    end
    return nothing
end

end
