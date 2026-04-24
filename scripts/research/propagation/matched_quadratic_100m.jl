#!/usr/bin/env julia
"""
Phase 23 — matched quadratic-chirp baseline at L = 100 m.

Reproduce the Session F warm-start transfer on the trusted long-fiber grid,
then sweep a physically interpretable pure quadratic phase family

    phi_quad(omega) = 0.5 * GDD * omega^2

with `GDD` reported in ps^2. The best trusted quadratic is compared directly
against the warm-start result and gets the same standard-image treatment.
"""

try
    using Revise
catch
end

ENV["MPLBACKEND"] = "Agg"

using Base.Threads
using Dates
using FFTW
using JLD2
using LinearAlgebra
using Logging
using Printf
using PyPlot
using Statistics

using MultiModeNoise

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "longfiber", "longfiber_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))

const MQ_ROOT = abspath(joinpath(@__DIR__, ".."))
const MQ_MAIN_CHECKOUT = abspath(joinpath(MQ_ROOT, "..", "fiber-raman-suppression"))
const MQ_MAIN_CHECKOUT_FALLBACK = "/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression"

const MQ_RESULTS_DIR = joinpath("results", "raman", "phase23")
const MQ_IMAGE_DIR = joinpath(".planning", "phases", "23-matched-baseline", "images")
const MQ_REPORT_PATH = joinpath(MQ_RESULTS_DIR, "matched_quadratic_candidates.md")
const MQ_RUN_NOTES_PATH = joinpath(MQ_RESULTS_DIR, "matched_quadratic_run.md")
const MQ_JLD2_PATH = joinpath(MQ_RESULTS_DIR, "matched_quadratic_100m.jld2")

const MQ_L_M = 100.0
const MQ_P_CONT_W = 0.05
const MQ_NT = 32768
const MQ_TIME_WINDOW_PS = 160.0
const MQ_BETA_ORDER = 2
const MQ_N_ZSAVE = 41
const MQ_EDGE_TRUST_LIMIT = 1e-3

const MQ_GDD_VALUES_PS2 = [-16.0, -8.0, -4.0, -2.0, -1.0, 1.0, 2.0, 4.0, 8.0, 16.0]

const MQ_WARM_REL = joinpath("results", "raman", "sweeps", "smf28", "L2m_P0.05W", "opt_result.jld2")
const MQ_PHASE16_REL = joinpath("results", "raman", "phase16", "100m_validate_fixed.jld2")

function resolve_existing_path(relpath::AbstractString)
    candidates = [
        joinpath(MQ_ROOT, relpath),
        joinpath(MQ_MAIN_CHECKOUT, relpath),
        joinpath(MQ_MAIN_CHECKOUT_FALLBACK, relpath),
    ]
    for path in candidates
        if isfile(path)
            return path
        end
    end
    error("required file not found: $relpath")
end

function angular_frequency_grid(sim)
    Δt_s = sim["Δt"] * 1e-12
    return 2π .* fftfreq(sim["Nt"], 1.0 / Δt_s)
end

quadratic_phase_from_gdd(gdd_ps2, ω_grid) = reshape(0.5 .* (gdd_ps2 * 1e-24) .* ω_grid.^2, :, 1)

function temporal_rms_width(power::AbstractVector, ts_s)
    p = max.(power, 0.0)
    norm_p = sum(p)
    norm_p <= 0 && return 0.0
    t̄ = sum(p .* ts_s) / norm_p
    return sqrt(sum(p .* (ts_s .- t̄).^2) / norm_p)
end

function peak_db_trace(sol)
    ut_z = sol["ut_z"]
    nz = size(ut_z, 1)
    out = Vector{Float64}(undef, nz)
    for i in 1:nz
        power = vec(sum(abs2.(ut_z[i, :, :]), dims = 2))
        out[i] = 10 * log10(max(maximum(power), 1e-30))
    end
    return out
end

function forward_with_zsave(phi, uω0, fiber_base, sim, band_mask; n_zsave::Int = MQ_N_ZSAVE)
    fiber = deepcopy(fiber_base)
    fiber["zsave"] = collect(range(0.0, fiber_base["L"], length = n_zsave))
    uω0_shaped = @. uω0 * cis(phi)

    t0 = time()
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    wall_s = time() - t0

    uωf = sol["uω_z"][end, :, :]
    utf = sol["ut_z"][end, :, :]
    J, _ = spectral_band_cost(uωf, band_mask)
    J_dB = 10 * log10(max(J, 1e-30))
    _, bc_frac = check_boundary_conditions(utf, sim)

    E_start = sum(abs2, uω0_shaped)
    E_end = sum(abs2, uωf)
    E_drift = abs(E_end - E_start) / max(E_start, eps())

    ts_s = sim["ts"]
    peak_z_dB = peak_db_trace(sol)
    width_z_s = Float64[
        temporal_rms_width(vec(sum(abs2.(sol["ut_z"][i, :, :]), dims = 2)), ts_s)
        for i in 1:size(sol["ut_z"], 1)
    ]

    return (
        sol = sol,
        fiber = fiber,
        phi = copy(phi),
        J = J,
        J_dB = J_dB,
        bc_frac = bc_frac,
        E_drift = E_drift,
        peak_z_dB = peak_z_dB,
        width_z_s = width_z_s,
        wall_s = wall_s,
    )
end

function build_candidate_specs()
    specs = NamedTuple[]
    for gdd_ps2 in MQ_GDD_VALUES_PS2
        sign_label = gdd_ps2 < 0 ? "m" : "p"
        abs_label = replace(@sprintf("%.2f", abs(gdd_ps2)), "." => "p")
        tag = @sprintf("phase23_gdd_%s%sps2", sign_label, abs_label)
        push!(specs, (
            gdd_ps2 = gdd_ps2,
            a2_s2 = gdd_ps2 * 1e-24,
            tag = tag,
        ))
    end
    return specs
end

function evaluate_candidates(specs, warm_run, uω0, fiber, sim, band_mask, ω_grid)
    results = Vector{NamedTuple}(undef, length(specs))

    @threads for i in eachindex(specs)
        spec = specs[i]
        phi = quadratic_phase_from_gdd(spec.gdd_ps2, ω_grid)
        run = forward_with_zsave(phi, uω0, fiber, sim, band_mask)
        peak_rmse_dB = sqrt(mean((run.peak_z_dB .- warm_run.peak_z_dB).^2))
        width_rel = sqrt(mean(((run.width_z_s .- warm_run.width_z_s) ./ max.(abs.(warm_run.width_z_s), 1e-30)).^2))
        results[i] = (
            gdd_ps2 = spec.gdd_ps2,
            a2_s2 = spec.a2_s2,
            tag = spec.tag,
            J = run.J,
            J_dB = run.J_dB,
            bc_frac = run.bc_frac,
            E_drift = run.E_drift,
            peak_rmse_dB = peak_rmse_dB,
            width_rel = width_rel,
            wall_s = run.wall_s,
        )
    end

    return results
end

function select_best_quadratic(results)
    trusted = filter(r -> r.bc_frac < MQ_EDGE_TRUST_LIMIT, results)
    isempty(trusted) && error("no trusted quadratic candidates; all edge fractions exceed $(MQ_EDGE_TRUST_LIMIT)")
    return trusted[argmin(getfield.(trusted, :J_dB))]
end

function render_standard_images(tag, phi, uω0, fiber, sim, band_mask, Δf, thr)
    save_standard_set(
        vec(phi), uω0, fiber, sim,
        band_mask, Δf, thr;
        tag = tag,
        fiber_name = "SMF28",
        L_m = MQ_L_M,
        P_W = MQ_P_CONT_W,
        output_dir = MQ_IMAGE_DIR,
    )
end

function candidate_markdown(results, warm_ref_dB, matched_tag)
    lines = String[]
    push!(lines, "# Phase 23 Candidate Table")
    push!(lines, "")
    push!(lines, @sprintf("Warm-start rerun reference: %.2f dB", warm_ref_dB))
    push!(lines, "")
    push!(lines, "| tag | GDD [ps^2] | a2 [s^2] | J [dB] | Δ vs warm [dB] | peak RMSE [dB] | BC edge | drift | note |")
    push!(lines, "|---|---:|---:|---:|---:|---:|---:|---:|---|")
    for r in sort(results, by = x -> x.J_dB)
        note = r.tag == matched_tag ? "BEST_J" : ""
        if r.bc_frac >= MQ_EDGE_TRUST_LIMIT
            note = isempty(note) ? "UNTRUSTED" : note * ", UNTRUSTED"
        end
        push!(lines, @sprintf("| %s | %.2f | %.3e | %.2f | %+.2f | %.3f | %.3e | %.3e | %s |",
            r.tag, r.gdd_ps2, r.a2_s2, r.J_dB, r.J_dB - warm_ref_dB,
            r.peak_rmse_dB, r.bc_frac, r.E_drift, note))
    end
    return join(lines, "\n")
end

function plot_overlay(warm_run, quad_run, sim, out_path)
    fig, axes = subplots(2, 2, figsize = (13, 10), height_ratios = [3, 1.3])

    _, _, _ = plot_spectral_evolution(warm_run.sol, sim, warm_run.fiber;
        ax = axes[1, 1], fig = fig)
    λ_limits = axes[1, 1].get_xlim()
    axes[1, 1].set_title(@sprintf("Warm-start evolution (%.2f dB)", warm_run.J_dB))

    _, _, _ = plot_spectral_evolution(quad_run.sol, sim, quad_run.fiber;
        ax = axes[1, 2], fig = fig, wavelength_limits = λ_limits)
    axes[1, 2].set_title(@sprintf("Best quadratic evolution (%.2f dB)", quad_run.J_dB))

    z = collect(warm_run.fiber["zsave"])
    axes[2, 1].plot(z, warm_run.peak_z_dB, color = "#4477aa", lw = 1.8, label = "warm-start")
    axes[2, 1].plot(z, quad_run.peak_z_dB, color = "#cc5544", lw = 1.8, label = "quadratic")
    axes[2, 1].set_xlabel("z [m]")
    axes[2, 1].set_ylabel("Peak power [dB]")
    axes[2, 1].set_title("Peak-power trajectory")
    axes[2, 1].grid(true, alpha = 0.3)
    axes[2, 1].legend(loc = "best")

    axes[2, 2].plot(z, warm_run.width_z_s .* 1e12, color = "#4477aa", lw = 1.8, label = "warm-start")
    axes[2, 2].plot(z, quad_run.width_z_s .* 1e12, color = "#cc5544", lw = 1.8, label = "quadratic")
    axes[2, 2].set_xlabel("z [m]")
    axes[2, 2].set_ylabel("RMS width [ps]")
    axes[2, 2].set_title("Temporal broadening")
    axes[2, 2].grid(true, alpha = 0.3)
    axes[2, 2].legend(loc = "best")

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
end

function verdict_label(quad_dB, warm_dB)
    Δ = quad_dB - warm_dB
    if abs(Δ) <= 3
        return "mostly pre-chirp"
    elseif Δ >= 10
        return "structure matters"
    else
        return "partially explained by pre-chirp"
    end
end

function write_run_report(path, phase16_metrics, matched, warm_run)
    Δ = matched.J_dB - warm_run.J_dB
    verdict = verdict_label(matched.J_dB, warm_run.J_dB)
    open(path, "w") do io
        println(io, "# Phase 23 Run Notes")
        println(io)
        println(io, @sprintf("- Session F reference warm-start: %.2f dB", phase16_metrics["J_warm_dB"]))
        println(io, @sprintf("- Phase 23 warm-start rerun: %.2f dB", warm_run.J_dB))
        println(io, @sprintf("- Best trusted quadratic GDD: %.2f ps^2", matched.gdd_ps2))
        println(io, @sprintf("- Best trusted quadratic: %.2f dB", matched.J_dB))
        println(io, @sprintf("- Delta vs warm-start: %+.2f dB", Δ))
        println(io, @sprintf("- Peak-trajectory RMSE: %.3f dB", matched.peak_rmse_dB))
        println(io, @sprintf("- Boundary edge fractions: warm=%.3e, matched=%.3e", warm_run.bc_frac, matched.bc_frac))
        println(io, @sprintf("- Verdict bucket: %s", verdict))
    end
end

function main()
    mkpath(MQ_RESULTS_DIR)
    mkpath(MQ_IMAGE_DIR)

    warm_src = resolve_existing_path(MQ_WARM_REL)
    phase16_src = resolve_existing_path(MQ_PHASE16_REL)
    phase16_metrics = load(phase16_src)
    warm_seed = load(warm_src)

    @info @sprintf("Warm-start source: %s", warm_src)
    @info @sprintf("Phase16 metrics source: %s", phase16_src)
    @info @sprintf("Quadratic sweep GDD values [ps^2]: %s", join(MQ_GDD_VALUES_PS2, ", "))

    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = :SMF28_beta2_only,
        L_fiber = MQ_L_M,
        P_cont = MQ_P_CONT_W,
        Nt = MQ_NT,
        time_window = MQ_TIME_WINDOW_PS,
        β_order = MQ_BETA_ORDER,
    )

    φ_warm = longfiber_interpolate_phi(
        warm_seed["phi_opt"],
        Int(warm_seed["Nt"]),
        Float64(warm_seed["time_window_ps"]),
        MQ_NT,
        MQ_TIME_WINDOW_PS,
    )

    ω_grid = angular_frequency_grid(sim)
    warm_run = forward_with_zsave(φ_warm, uω0, fiber, sim, band_mask)
    @info @sprintf("Warm rerun: J = %.2f dB, bc = %.3e, drift = %.3e, phase16 ref = %.2f dB",
        warm_run.J_dB, warm_run.bc_frac, warm_run.E_drift, phase16_metrics["J_warm_dB"])

    specs = build_candidate_specs()
    results = evaluate_candidates(specs, warm_run, uω0, fiber, sim, band_mask, ω_grid)
    best = select_best_quadratic(results)

    φ_best = quadratic_phase_from_gdd(best.gdd_ps2, ω_grid)
    best_run = forward_with_zsave(φ_best, uω0, fiber, sim, band_mask)
    @info @sprintf("Best trusted quadratic: GDD = %.2f ps^2, J = %.2f dB, peak RMSE = %.3f dB",
        best.gdd_ps2, best_run.J_dB, best.peak_rmse_dB)

    render_standard_images("phase23_warm_rerun", φ_warm, uω0, fiber, sim, band_mask, Δf, thr)
    for spec in specs
        φ = quadratic_phase_from_gdd(spec.gdd_ps2, ω_grid)
        render_standard_images(spec.tag, φ, uω0, fiber, sim, band_mask, Δf, thr)
    end
    render_standard_images("phase23_quadratic_best", φ_best, uω0, fiber, sim, band_mask, Δf, thr)

    overlay_path = joinpath(MQ_IMAGE_DIR, "phase23_warm_vs_matched_overlay.png")
    plot_overlay(warm_run, best_run, sim, overlay_path)

    open(MQ_REPORT_PATH, "w") do io
        write(io, candidate_markdown(results, warm_run.J_dB, best.tag))
    end
    write_run_report(MQ_RUN_NOTES_PATH, phase16_metrics, best, warm_run)

    tags = String[r.tag for r in results]
    gdd_values = Float64[r.gdd_ps2 for r in results]
    a2_values = Float64[r.a2_s2 for r in results]
    J_dB_values = Float64[r.J_dB for r in results]
    bc_values = Float64[r.bc_frac for r in results]
    drift_values = Float64[r.E_drift for r in results]
    peak_rmse_values = Float64[r.peak_rmse_dB for r in results]
    width_rel_values = Float64[r.width_rel for r in results]

    JLD2.jldsave(MQ_JLD2_PATH;
        saved_at = now(),
        warm_source = warm_src,
        phase16_source = phase16_src,
        warm_reference_phase16_dB = phase16_metrics["J_warm_dB"],
        warm_rerun_dB = warm_run.J_dB,
        warm_rerun_bc = warm_run.bc_frac,
        warm_rerun_drift = warm_run.E_drift,
        candidate_tags = tags,
        candidate_gdd_ps2 = gdd_values,
        candidate_a2_s2 = a2_values,
        candidate_J_dB = J_dB_values,
        candidate_bc = bc_values,
        candidate_drift = drift_values,
        candidate_peak_rmse_dB = peak_rmse_values,
        candidate_width_rel = width_rel_values,
        matched_tag = best.tag,
        matched_gdd_ps2 = best.gdd_ps2,
        matched_a2_s2 = best.a2_s2,
        matched_J_dB = best_run.J_dB,
        matched_bc = best_run.bc_frac,
        matched_drift = best_run.E_drift,
        matched_peak_rmse_dB = best.peak_rmse_dB,
        verdict = verdict_label(best_run.J_dB, warm_run.J_dB),
    )

    return (
        warm_run = warm_run,
        best_run = best_run,
        best = best,
        results = results,
        overlay_path = overlay_path,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = main()
    @info @sprintf("Phase 23 complete: warm=%.2f dB matched=%.2f dB",
        result.warm_run.J_dB, result.best_run.J_dB)
end
