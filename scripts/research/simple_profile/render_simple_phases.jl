#!/usr/bin/env julia
# Renders pedagogical phase-profile figures from the Session E low-resolution
# sweep data. Pure plotting — no simulation.

ENV["MPLBACKEND"] = "Agg"

using JLD2, PyPlot, FFTW, Printf, Statistics

const OUTDIR = joinpath(@__DIR__, "..", "..", "..", "docs", "artifacts",
                        "presentation-2026-04-17", "pedagogical")
mkpath(OUTDIR)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"Shift phase so the carrier frequency (bin 0 in FFT order) sits at the center."
shift_phi(phi) = fftshift(phi)

"Find bin range around the center where |phi| is materially nonzero."
function phase_support(phi_shifted::Vector{Float64}; frac=0.02)
    Nt = length(phi_shifted)
    c = Nt ÷ 2 + 1                    # center bin after fftshift
    thr = frac * maximum(abs, phi_shifted)
    if thr < 1e-12
        return (c - 300):(c + 300)
    end
    # scan outward from the center until |phi| drops below thr
    lo = c; hi = c
    while lo > 1 && abs(phi_shifted[lo - 1]) > thr
        lo -= 1
    end
    while hi < Nt && abs(phi_shifted[hi + 1]) > thr
        hi += 1
    end
    pad = max(20, div(hi - lo, 4))
    lo = max(1, lo - pad)
    hi = min(Nt, hi + pad)
    return lo:hi
end

"Central-difference group delay tau_g(omega) = -d phi / d omega."
function group_delay(phi::Vector{Float64}, dω::Float64 = 1.0)
    g = similar(phi)
    g[1] = (phi[2] - phi[1]) / dω
    g[end] = (phi[end] - phi[end - 1]) / dω
    @inbounds for i in 2:length(phi) - 1
        g[i] = (phi[i + 1] - phi[i - 1]) / (2dω)
    end
    return -g
end

"Manual phase unwrap."
function unwrap_phase(x::Vector{Float64})
    y = copy(x)
    for i in 2:length(y)
        d = y[i] - y[i - 1]
        if d > π
            y[i:end] .-= 2π
        elseif d < -π
            y[i:end] .+= 2π
        end
    end
    return y
end

# ─────────────────────────────────────────────────────────────────────────────
# 1. N_phi sweep — "how the optimized phase fills in with more knobs"
# ─────────────────────────────────────────────────────────────────────────────

function plot_nphi_sweep()
    sweep1 = JLD2.load("results/raman/phase_sweep_simple/sweep1_Nphi.jld2")
    results = sweep1["results"]

    wanted = [4, 16, 32, 128]
    picks = [findfirst(r -> r["N_phi"] == n, results) for n in wanted]
    picks = filter(!isnothing, picks)

    # Use the deepest (N_phi=128) run to define the plot window
    ref = results[findfirst(r -> r["N_phi"] == 128, results)]
    ref_shift = shift_phi(ref["phi_opt"])
    win = phase_support(ref_shift; frac=0.02)
    center = (first(win) + last(win)) ÷ 2
    x = collect(win) .- center

    fig, axes = subplots(length(picks), 1,
                         figsize=(7.5, 2.0 * length(picks)), sharex=true)
    for (row, idx) in enumerate(picks)
        r = results[idx]
        phi_s = shift_phi(r["phi_opt"])
        ax = axes[row]
        ax.plot(x, phi_s[win], "b-", lw=1.6)
        ax.axhline(0, color="0.7", lw=0.5)
        ax.set_ylabel("phi  [rad]", fontsize=9)
        ax.set_title(
            @sprintf("N_phi = %d knobs  -  J = %.1f dB  -  N_eff = %.2f",
                     r["N_phi"], r["J_final"], r["N_eff"]),
            fontsize=10)
        ax.grid(alpha=0.3)
    end
    axes[end].set_xlabel("frequency bin (relative to carrier)", fontsize=10)
    suptitle("Optimized phase vs. number of shaper knobs\n" *
             "SMF-28, L=2m, P=0.2W  -  the shape looks almost the same from 4 to 128 knobs",
             fontsize=11)
    tight_layout(rect=[0, 0, 1, 0.95])
    savefig(joinpath(OUTDIR, "nphi_sweep_phases.png"), dpi=160)
    close(fig)
    println("wrote nphi_sweep_phases.png")

    # Basis coefficients
    fig, axes = subplots(1, length(picks),
                         figsize=(3.0 * length(picks), 3.2))
    for (col, idx) in enumerate(picks)
        r = results[idx]
        ax = axes[col]
        c_opt = r["c_opt"]
        ax.stem(1:length(c_opt), c_opt, basefmt=" ")
        ax.axhline(0, color="0.5", lw=0.5)
        ax.set_title(@sprintf("N_phi = %d", r["N_phi"]), fontsize=10)
        ax.set_xlabel("basis mode index", fontsize=9)
        col == 1 && ax.set_ylabel("coefficient c_k", fontsize=9)
        ax.grid(alpha=0.3)
    end
    suptitle("Basis coefficients — most weight is in the first few modes",
             fontsize=11)
    tight_layout(rect=[0, 0, 1, 0.94])
    savefig(joinpath(OUTDIR, "nphi_sweep_coefficients.png"), dpi=160)
    close(fig)
    println("wrote nphi_sweep_coefficients.png")
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. Pareto candidates — wrapped, unwrapped, group delay
# ─────────────────────────────────────────────────────────────────────────────

function plot_pareto_candidates()
    sweep2 = JLD2.load("results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2")
    results = sweep2["results"]

    specs = [
        (label="candidate_1_simplest",
         fiber=:SMF28, L=0.25, P=0.02, title="Simplest phase (candidate 1)"),
        (label="candidate_2_middle",
         fiber=:SMF28, L=1.00, P=0.10, title="Middle (candidate 2)"),
        (label="candidate_3_deepest",
         fiber=:SMF28, L=0.25, P=0.10, title="Deepest suppression (candidate 3)"),
    ]

    for spec in specs
        hit = nothing
        for r in results
            cfg = r["config"]
            if cfg[:fiber_preset] == spec.fiber &&
               abs(cfg[:L_fiber] - spec.L) < 1e-6 &&
               abs(cfg[:P_cont] - spec.P) < 1e-6 &&
               cfg[:N_phi] == 57
                hit = r
                break
            end
        end
        hit === nothing && (println("miss: $(spec.label)"); continue)

        phi_s = shift_phi(hit["phi_opt"])
        win = phase_support(phi_s; frac=0.02)
        center = (first(win) + last(win)) ÷ 2
        x = collect(win) .- center
        phi_win = phi_s[win]

        phi_wrap = mod.(phi_win .+ π, 2π) .- π
        phi_unwrap = unwrap_phase(phi_win)
        tau_g = group_delay(phi_unwrap)

        fig, axes = subplots(3, 1, figsize=(8, 7), sharex=true)
        axes[1].plot(x, phi_wrap, "b-", lw=1.4)
        axes[1].axhline(0, color="0.7", lw=0.5)
        axes[1].set_ylabel("phi wrapped [rad]\n(in [-pi, pi])")
        axes[1].set_title(
            @sprintf("%s\nSMF-28, L=%.2f m, P=%.2f W, N_phi=57  -  J = %.2f dB",
                     spec.title, spec.L, spec.P, hit["J_final"]),
            fontsize=11)
        axes[1].grid(alpha=0.3)

        axes[2].plot(x, phi_unwrap, "g-", lw=1.6)
        axes[2].axhline(0, color="0.7", lw=0.5)
        axes[2].set_ylabel("phi unwrapped [rad]\n(true smooth curve)")
        axes[2].grid(alpha=0.3)

        axes[3].plot(x, tau_g, "r-", lw=1.4)
        axes[3].axhline(0, color="0.7", lw=0.5)
        axes[3].set_ylabel("group delay tau_g\n(-dphi/domega)")
        axes[3].set_xlabel("frequency bin (relative to carrier)")
        axes[3].grid(alpha=0.3)

        tight_layout()
        outpath = joinpath(OUTDIR, "pareto_$(spec.label).png")
        savefig(outpath, dpi=160)
        close(fig)
        println("wrote $(basename(outpath))")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. "DC + linear + quadratic" fit to the deepest-suppression phase
# ─────────────────────────────────────────────────────────────────────────────

function plot_dc_linear_quadratic_fit()
    sweep2 = JLD2.load("results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2")
    results = sweep2["results"]

    deepest = nothing
    for r in results
        cfg = r["config"]
        if cfg[:fiber_preset] == :SMF28 &&
           abs(cfg[:L_fiber] - 0.25) < 1e-6 &&
           abs(cfg[:P_cont] - 0.10) < 1e-6 &&
           cfg[:N_phi] == 57
            deepest = r
            break
        end
    end
    deepest === nothing && (println("deepest candidate not found"); return)

    phi_s = shift_phi(deepest["phi_opt"])
    win = phase_support(phi_s; frac=0.02)
    center = (first(win) + last(win)) ÷ 2
    x = Float64.(collect(win) .- center)
    phi_win = unwrap_phase(phi_s[win])

    # Least-squares fit phi ≈ a0 + a1*w + a2*w^2
    M = hcat(ones(length(x)), x, x.^2)
    coef = M \ phi_win
    fit = M * coef
    residual = phi_win .- fit
    rms_r = sqrt(mean(residual.^2))

    fig, axes = subplots(2, 1, figsize=(8, 6.3), sharex=true)
    axes[1].plot(x, phi_win, "k-", lw=1.9,
                 label="optimized phase phi(omega)")
    axes[1].plot(x, fit, "r--", lw=1.6,
                 label=@sprintf("fit: %.3g + %.3g*w + %.3g*w^2",
                                coef[1], coef[2], coef[3]))
    axes[1].axhline(0, color="0.7", lw=0.5)
    axes[1].set_ylabel("phi(omega) [rad]")
    axes[1].legend(loc="best", fontsize=9)
    axes[1].grid(alpha=0.3)
    axes[1].set_title("The optimized phase is almost a pure DC + linear + quadratic\n" *
                      "(SMF-28 L=0.25m P=0.1W, J = -82.33 dB)",
                      fontsize=11)

    axes[2].plot(x, residual, "b-", lw=1.3)
    axes[2].axhline(0, color="0.5", lw=0.5)
    axes[2].set_ylabel("residual: phi - fit [rad]")
    axes[2].set_xlabel("frequency bin (relative to carrier)")
    axes[2].grid(alpha=0.3)
    axes[2].set_title(@sprintf(
        "residual rms = %.3f rad  -  compare to phi peak-to-peak of %.1f rad",
        rms_r, maximum(phi_win) - minimum(phi_win)),
        fontsize=10)

    tight_layout()
    savefig(joinpath(OUTDIR, "dc_linear_quadratic_fit.png"), dpi=160)
    close(fig)
    println("wrote dc_linear_quadratic_fit.png")
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. DCT spectrum of phi_opt — THIS is where "N_eff ≈ 2" becomes visible
# ─────────────────────────────────────────────────────────────────────────────

function plot_dct_spectrum()
    sweep1 = JLD2.load("results/raman/phase_sweep_simple/sweep1_Nphi.jld2")
    results = sweep1["results"]
    wanted = [4, 16, 32, 128]
    picks = [findfirst(r -> r["N_phi"] == n, results) for n in wanted]
    picks = filter(!isnothing, picks)

    # Use N_phi=128 run to define the pulse bandwidth window
    ref = results[findfirst(r -> r["N_phi"] == 128, results)]
    ref_shift = shift_phi(ref["phi_opt"])
    win = phase_support(ref_shift; frac=0.02)

    fig, axes = subplots(length(picks), 1,
                         figsize=(8, 2.0 * length(picks)), sharex=true)
    for (row, idx) in enumerate(picks)
        r = results[idx]
        phi_s = shift_phi(r["phi_opt"])
        phi_win = phi_s[win]
        # normalize so first coefficient dominates visualization
        dct_coefs = FFTW.r2r(phi_win, FFTW.REDFT10) ./ length(phi_win)
        N_show = min(30, length(dct_coefs))
        ax = axes[row]
        ax.stem(0:N_show-1, dct_coefs[1:N_show], basefmt=" ")
        ax.axhline(0, color="0.7", lw=0.5)
        ax.set_ylabel("DCT c_k  [rad]", fontsize=9)
        ax.set_title(@sprintf("N_phi = %d knobs  -  J = %.1f dB  -  N_eff = %.2f",
                              r["N_phi"], r["J_final"], r["N_eff"]),
                     fontsize=10)
        ax.grid(alpha=0.3)
    end
    axes[end].set_xlabel("DCT mode index k (0 = DC, 1 = cos(pi*n/N), 2 = cos(2*pi*n/N), ...)",
                         fontsize=10)
    suptitle("DCT spectrum of the optimized phase\n" *
             "Modes 0 (DC) and 2 (quadratic-like) dominate - that's the 'N_eff = 2'",
             fontsize=11)
    tight_layout(rect=[0, 0, 1, 0.94])
    savefig(joinpath(OUTDIR, "dct_spectrum_two_modes.png"), dpi=160)
    close(fig)
    println("wrote dct_spectrum_two_modes.png")
end

# ─────────────────────────────────────────────────────────────────────────────

plot_nphi_sweep()
plot_pareto_candidates()
plot_dc_linear_quadratic_fit()
plot_dct_spectrum()

println("\nAll outputs in: $OUTDIR")
