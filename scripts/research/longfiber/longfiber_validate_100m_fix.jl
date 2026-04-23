#!/usr/bin/env julia
"""
Post-hoc refit of the L=100m phi(omega) quadratic analysis (Phase 16, Session F).

The original `longfiber_validate_100m.jl` weighted the least-squares fit by
bins where `abs(phi) > 1e-8`. Since the stored phi vector has plausibly-large
values across the ENTIRE 32768-bin FFT grid (well beyond the ~±5 THz pulse
bandwidth), the fit is dominated by spectral regions that carry no pulse
energy — producing garbage R² and a meaningless a2 ratio.

This script refits weighted by the PULSE AMPLITUDE |uω0(ω)| (analytic sech²
formula at the fiber input), which restricts the fit to the physically
meaningful spectrum. It also restricts the plot x-range to ±10 THz, where
the pulse actually lives.

Reads: /home/ignaciojlizama/raman-wt-F/results/raman/phase16/100m_opt_full_result.jld2
Writes:
  /home/ignaciojlizama/raman-wt-F/results/raman/phase16/100m_validate_fixed.jld2
  /home/ignaciojlizama/raman-wt-F/results/images/physics_16_04_phi_profile_2m_vs_100m.png  (overwrites)
  /home/ignaciojlizama/raman-wt-F/results/raman/phase16/FINDINGS.md  (regenerated)
"""

ENV["MPLBACKEND"] = "Agg"

using JLD2
using FFTW
using PyPlot
using Printf
using LinearAlgebra
using Dates

# ───────── config (must match longfiber_optimize_100m.jl) ─────────
const NT          = 32768
const TW_PS       = 160.0
const DT_PS       = TW_PS / NT                # picoseconds per sample
const DT_S        = DT_PS * 1e-12             # seconds per sample
const FWHM_S      = 185e-15
const T0_S        = FWHM_S / 1.7627           # sech² half-duration
const P_CONT      = 0.05
const REP_RATE    = 80.5e6
const P_PEAK      = 0.881374 * P_CONT / (FWHM_S * REP_RATE)

const PH16_DIR    = "/home/ignaciojlizama/raman-wt-F/results/raman/phase16"
const IMG_DIR     = "/home/ignaciojlizama/raman-wt-F/results/images"

# ───────── analytic sech² pulse amplitude in frequency ─────────
# |U(ω)|² ∝ sech²(π·ω·T0/2).  We want relative magnitude only for weighting.
function analytic_pulse_amplitude(Δf_Hz::AbstractVector{<:Real}, T0::Real, P_peak::Real)
    arg = π .* (2π .* Δf_Hz) .* T0 ./ 2
    U = sqrt(P_peak) .* π .* T0 .* sech.(arg)
    return abs.(U)
end

# ───────── weighted quadratic fit (ω in rad/s) ─────────
function weighted_quadratic_fit(phi::AbstractVector{<:Real}, Δf_Hz::AbstractVector{<:Real};
        weight::AbstractVector{<:Real}, min_weight_rel::Real = 1e-3)
    ω = 2π .* Δf_Hz                       # rad/s
    max_w = maximum(weight)
    w = copy(weight)
    w[w .< min_weight_rel * max_w] .= 0.0 # drop bins outside signal band
    @assert any(w .> 0) "no bins survived weight threshold"

    X = [ones(length(ω))  ω  ω.^2]
    W = Diagonal(w)
    A = X' * W * X
    b = X' * W * phi
    a = A \ b
    a0, a1, a2 = a[1], a[2], a[3]
    fit = X * a
    residual = phi .- fit
    # weighted R²
    phi_mean_w = sum(w .* phi) / sum(w)
    ss_tot = sum(w .* (phi .- phi_mean_w).^2)
    ss_res = sum(w .* residual.^2)
    R2 = ss_tot > 0 ? 1.0 - ss_res / ss_tot : NaN
    n_active = count(>(0), w)

    return (a0 = a0, a1 = a1, a2 = a2, residual = residual,
            R2 = R2, n_active_bins = n_active, total_bins = length(phi))
end

# ───────── unwrap phase for display (keep fit on raw phi though) ─────────
function unwrap_phase(phi::AbstractVector{<:Real})
    out = copy(phi)
    for i in 2:length(out)
        d = out[i] - out[i-1]
        while d > π
            out[i:end] .-= 2π
            d = out[i] - out[i-1]
        end
        while d < -π
            out[i:end] .+= 2π
            d = out[i] - out[i-1]
        end
    end
    return out
end

# ───────── figure: two panels (absolute phase + residual) ─────────
function plot_phi_profiles(phi_warm, phi_opt, fit_warm, fit_opt,
                            Δf_fft_Hz, amp_weight, out_path;
                            xlim_THz::Real = 10.0)
    Δf_shift = fftshift(Δf_fft_Hz) .* 1e-12

    phi_warm_shift = fftshift(vec(phi_warm))
    phi_opt_shift  = fftshift(vec(phi_opt))
    amp_shift      = fftshift(amp_weight)
    res_warm_shift = fftshift(fit_warm.residual)
    res_opt_shift  = fftshift(fit_opt.residual)

    # Mask to meaningful region for display too
    band = abs.(Δf_shift) .< xlim_THz
    amp_norm = amp_shift ./ maximum(amp_shift)

    fig, axes = PyPlot.subplots(3, 1, figsize = (11, 10), sharex = true)

    # Panel 1: absolute phase profiles (unwrapped), only meaningful bins
    ax = axes[1]
    phi_w_unwrap = unwrap_phase(phi_warm_shift[band])
    phi_o_unwrap = unwrap_phase(phi_opt_shift[band])
    ax.plot(Δf_shift[band], phi_w_unwrap; lw = 1.5, color = "#4477aa",
        label = @sprintf("φ@2m warm    a₂ = %.3e s²", fit_warm.a2))
    ax.plot(Δf_shift[band], phi_o_unwrap; lw = 1.5, color = "#cc5544",
        label = @sprintf("φ@100m opt   a₂ = %.3e s²", fit_opt.a2))
    ax.set_ylabel("φ(ω)  [rad, unwrapped]")
    ax.set_title(@sprintf(
        "Spectral phase profiles — L=100m SMF-28 P=%.3f W — weighted by pulse amplitude",
        P_CONT))
    ax.grid(true, alpha = 0.3)
    ax.legend(loc = "best")

    # Panel 2: pulse amplitude weight (sanity check)
    ax2 = axes[2]
    ax2.plot(Δf_shift[band], amp_norm[band]; lw = 1.0, color = "#555555",
        label = "|U(ω)| / max  (sech² analytic)")
    ax2.set_ylabel("pulse amplitude\n(normalized)")
    ax2.set_yscale("log")
    ax2.set_ylim(1e-6, 1.5)
    ax2.grid(true, alpha = 0.3)
    ax2.legend(loc = "best")

    # Panel 3: residuals
    ax3 = axes[3]
    ax3.plot(Δf_shift[band], res_warm_shift[band]; lw = 1.0, color = "#4477aa",
        label = @sprintf("warm residual   R²=%.3f  (%d active bins)",
                         fit_warm.R2, fit_warm.n_active_bins))
    ax3.plot(Δf_shift[band], res_opt_shift[band]; lw = 1.0, color = "#cc5544",
        label = @sprintf("opt residual   R²=%.3f  (%d active bins)",
                         fit_opt.R2, fit_opt.n_active_bins))
    ax3.axhline(0; color = "k", lw = 0.5, alpha = 0.5)
    ax3.set_xlabel("Δf  [THz]")
    ax3.set_ylabel("Δφ(ω) after quadratic fit  [rad]")
    ax3.grid(true, alpha = 0.3)
    ax3.legend(loc = "best")

    for ax_ in axes
        ax_.set_xlim(-xlim_THz, xlim_THz)
    end

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
    @info "saved $out_path"
end

# ───────── regenerate FINDINGS.md with corrected numbers ─────────
function write_findings(fix_fields, orig_path)
    open(orig_path, "w") do io
        println(io, "# Phase 16 — Long-Fiber Raman Suppression at L = 100 m")
        println(io)
        println(io, "*Session F — FINDINGS.md regenerated 2026-04-17 (postprocess fix: amplitude-weighted φ fit).*")
        println(io)
        println(io, "## Configuration")
        println(io)
        println(io, "| Quantity | Value |")
        println(io, "|---|---|")
        println(io, "| Fiber | SMF-28 (β₂ only, β₂ = -2.17e-26 s²/m) |")
        println(io, "| Length | 100.0 m |")
        println(io, "| P_cont | 0.05 W |")
        println(io, "| Pulse | 185 fs sech² @ 1550 nm, 80.5 MHz |")
        println(io, "| Grid | Nt = 32768, T = 160.0 ps |")
        println(io, "| β_order | 2 |")
        println(io, "| Warm-start seed | `results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2` |")
        println(io)
        println(io, "## Headline numbers")
        println(io)
        println(io, "| Quantity | Value |")
        println(io, "|---|---|")
        println(io, @sprintf("| J_flat(L=100 m) | %.2f dB |", fix_fields["J_flat_dB"]))
        println(io, @sprintf("| J_warm@2m(L=100 m) | %.2f dB |", fix_fields["J_warm_dB"]))
        println(io, @sprintf("| J_opt@100m (Phase 16 result) | %.2f dB |", fix_fields["J_opt_dB"]))
        println(io, @sprintf("| Δ (opt vs flat) | %.2f dB |",
            fix_fields["J_opt_dB"] - fix_fields["J_flat_dB"]))
        println(io, @sprintf("| Δ (opt vs warm) | %.2f dB |",
            fix_fields["J_opt_dB"] - fix_fields["J_warm_dB"]))
        println(io)
        println(io, "## Convergence")
        println(io)
        println(io, "| Quantity | Value |")
        println(io, "|---|---|")
        println(io, @sprintf("| L-BFGS iterations | %d |", fix_fields["n_iter"]))
        println(io, @sprintf("| converged flag | %s |", fix_fields["converged"]))
        println(io, @sprintf("| final ‖∇J‖ | %.3e |", fix_fields["grad_norm"]))
        println(io, @sprintf("| wall time (fresh) | %.1f min |", fix_fields["wall_fresh_s"]/60))
        println(io)
        println(io, "## Energy conservation")
        println(io)
        println(io, "| Run | Photon-number drift | BC edge fraction |")
        println(io, "|---|---|---|")
        println(io, @sprintf("| flat       | %.2e | %.2e |",
            fix_fields["E_drift_flat"], fix_fields["bc_flat"]))
        println(io, @sprintf("| phi@2m     | %.2e | %.2e |",
            fix_fields["E_drift_warm"], fix_fields["bc_warm"]))
        println(io, @sprintf("| phi@100m   | %.2e | %.2e |",
            fix_fields["E_drift_opt"], fix_fields["bc_opt"]))
        println(io)
        println(io, "## φ(ω) quadratic-fit fingerprint *(corrected)*")
        println(io)
        println(io, "Fit model: φ(ω) ≈ a₀ + a₁·ω + a₂·ω² + Δφ(ω), **weighted by analytic")
        println(io, "sech² pulse amplitude |U(ω)|** over bins with |U|/|U|_max > 1e-3")
        println(io, "(~±5 THz signal band).")
        println(io)
        println(io, @sprintf("Weight drops all bins below 1e-3 of peak amplitude. Active bins: %d / %d (%.1f%% of grid).",
            fix_fields["n_active_bins"], fix_fields["total_bins"],
            100 * fix_fields["n_active_bins"] / fix_fields["total_bins"]))
        println(io)
        println(io, "| Phase | a₀ [rad] | a₁ [s] | a₂ [s²] | R² |")
        println(io, "|---|---|---|---|---|")
        println(io, @sprintf("| phi@2m warm  | %.3e | %.3e | %.3e | %.3f |",
            fix_fields["warm_a0"], fix_fields["warm_a1"],
            fix_fields["warm_a2"], fix_fields["warm_R2"]))
        println(io, @sprintf("| phi@100m opt | %.3e | %.3e | %.3e | %.3f |",
            fix_fields["opt_a0"], fix_fields["opt_a1"],
            fix_fields["opt_a2"], fix_fields["opt_R2"]))
        println(io)
        println(io, "### a₂ scaling — structural-adaptation fingerprint")
        println(io)
        println(io, @sprintf("- Observed ratio a₂(100 m) / a₂(2 m) = %.3f",
            fix_fields["a2_ratio_100_vs_2"]))
        println(io, @sprintf("- Pure-GVD prediction (100 m / 2 m) = %.3f",
            fix_fields["gvd_ratio_100_vs_2"]))
        println(io, @sprintf("- Deviation = %.2f%% from pure GVD rescale",
            fix_fields["a2_deviation_pct"]))
        println(io)
        println(io, "**Interpretation**: Pure-GVD pre-compensation predicts the optimal φ(ω)")
        println(io, "scales with L, so a₂(L_new) = (L_new/L_old)·a₂(L_old). A significant")
        println(io, "deviation signals nonlinear structural adaptation — the publishable")
        println(io, "physics thread (D-F-07).")
        println(io)
        println(io, @sprintf("R² values close to 1 indicate the phase IS mostly quadratic over"))
        println(io, @sprintf("the pulse bandwidth; values far from 1 indicate non-polynomial"))
        println(io, @sprintf("residual structure."))
        println(io)
        println(io, "## Open questions for Phase 17")
        println(io)
        println(io, "- Does the warm-start basin coincide with the global minimum at L=100 m?")
        println(io, "  A multi-start repeat of Phase 16 would nail this.")
        println(io, "- Scaling to L=200 m: does a₂(200)/a₂(100) = 2 (pure GVD)?")
        println(io, "- HNLF analogue at equivalent dispersion length: same physics?")
        println(io, "- Multimode generalization (M > 1): does the shape universality survive?")
        println(io, "- Segmented / piecewise shaping (re-optimize every 5–10 m) — likely much")
        println(io, "  deeper suppression per segment, but requires in-line shapers.")
    end
    @info "rewrote $orig_path"
end

function main()
    @info "loading validate + full_result JLD2s"
    v = JLD2.load(joinpath(PH16_DIR, "100m_validate.jld2"))
    fr = JLD2.load(joinpath(PH16_DIR, "100m_opt_full_result.jld2"))

    phi_warm = vec(v["phi_warm"])
    phi_opt  = vec(v["phi_opt"])

    Δf_fft_Hz = fftfreq(NT, 1.0 / DT_S)  # Hz, FFT order

    amp_weight = analytic_pulse_amplitude(Δf_fft_Hz, T0_S, P_PEAK)

    @info "fitting with amplitude weight"
    fit_warm = weighted_quadratic_fit(phi_warm, Δf_fft_Hz;
        weight = amp_weight, min_weight_rel = 1e-3)
    fit_opt  = weighted_quadratic_fit(phi_opt, Δf_fft_Hz;
        weight = amp_weight, min_weight_rel = 1e-3)

    println()
    @info @sprintf("phi@2m   a₀=%.3e  a₁=%.3e  a₂=%.3e  R²=%.3f  bins=%d/%d",
        fit_warm.a0, fit_warm.a1, fit_warm.a2, fit_warm.R2,
        fit_warm.n_active_bins, fit_warm.total_bins)
    @info @sprintf("phi@100m a₀=%.3e  a₁=%.3e  a₂=%.3e  R²=%.3f  bins=%d/%d",
        fit_opt.a0, fit_opt.a1, fit_opt.a2, fit_opt.R2,
        fit_opt.n_active_bins, fit_opt.total_bins)

    a2_ratio_100_2 = fit_opt.a2 / fit_warm.a2
    gvd_ratio_100_2 = 100.0 / 2.0
    dev_pct = 100 * (a2_ratio_100_2 - gvd_ratio_100_2) / gvd_ratio_100_2
    @info @sprintf("a₂(100m)/a₂(2m) = %.3f  (pure-GVD 100m/2m = %.1f; deviation = %.2f%%)",
        a2_ratio_100_2, gvd_ratio_100_2, dev_pct)

    plot_phi_profiles(phi_warm, phi_opt, fit_warm, fit_opt,
        Δf_fft_Hz, amp_weight,
        joinpath(IMG_DIR, "physics_16_04_phi_profile_2m_vs_100m.png");
        xlim_THz = 10.0)

    fields = Dict{String, Any}(
        "warm_a0" => fit_warm.a0,  "warm_a1" => fit_warm.a1,
        "warm_a2" => fit_warm.a2,  "warm_R2" => fit_warm.R2,
        "opt_a0"  => fit_opt.a0,   "opt_a1"  => fit_opt.a1,
        "opt_a2"  => fit_opt.a2,   "opt_R2"  => fit_opt.R2,
        "n_active_bins" => fit_opt.n_active_bins,
        "total_bins"    => fit_opt.total_bins,
        "a2_ratio_100_vs_2" => a2_ratio_100_2,
        "gvd_ratio_100_vs_2" => gvd_ratio_100_2,
        "a2_deviation_pct"  => dev_pct,
        "J_flat_dB" => v["J_flat_dB"], "J_warm_dB" => v["J_warm_dB"],
        "J_opt_dB"  => v["J_opt_dB"],
        "E_drift_flat" => v["E_drift_flat"],
        "E_drift_warm" => v["E_drift_warm"],
        "E_drift_opt"  => v["E_drift_opt"],
        "bc_flat" => v["bc_flat"], "bc_warm" => v["bc_warm"], "bc_opt" => v["bc_opt"],
        "n_iter" => v["n_iter"], "converged" => v["converged"],
        "grad_norm" => v["grad_norm"], "wall_fresh_s" => v["wall_fresh_s"],
    )

    JLD2.jldopen(joinpath(PH16_DIR, "100m_validate_fixed.jld2"), "w") do f
        for (k, v) in fields
            f[k] = v
        end
        f["saved_at"] = now()
    end
    @info "saved 100m_validate_fixed.jld2"

    write_findings(fields, joinpath(PH16_DIR, "FINDINGS.md"))
end

main()
