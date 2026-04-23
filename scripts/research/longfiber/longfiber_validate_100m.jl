"""
Long-Fiber Post-Hoc Validation at L = 100 m (Phase 16 / Session F)

Runs AFTER `scripts/research/longfiber/longfiber_optimize_100m.jl` has produced
`results/raman/phase16/100m_opt_full_result.jld2`.

Validates the headline result and extracts the publishable physics:

  1. Energy-conservation check on the 100 m optimum (photon-number drift
     integral < 1%).
  2. Boundary-condition edge-energy metric.
  3. Polynomial fit φ_opt(ω) = a₀ + a₁·ω + a₂·ω² + residual Δφ(ω). Report
     a₂ for both phi@2m (the warm-start seed) and phi@100m (the optimum),
     and report their ratio against the pure-GVD prediction 100m/30m ≈ 3.33
     (or 100m/2m = 50 if a 30m reference is unavailable — fallback documented).
  4. J(z) three-way comparison at 101 z-saves through L = 100 m for:
        - flat phase
        - phi@2m warm-start
        - phi@100m optimum
  5. Two figures + one FINDINGS.md.

Outputs:
  results/raman/phase16/100m_validate.jld2
  results/raman/phase16/100m_Jz_threeway.jld2
  results/images/physics_16_04_phi_profile_2m_vs_100m.png
  results/images/physics_16_05_Jz_comparison.png
  results/raman/phase16/FINDINGS.md

RUNS ON BURST VM. Launch:
  burst-ssh "cd fiber-raman-suppression && git pull && \\
             tmux new -d -s F-100m-validate \\
                 'julia -t auto --project=. scripts/research/longfiber/longfiber_validate_100m.jl \\
                       > results/raman/phase16/100m_validate.log 2>&1; burst-stop'"
"""

try
    using Revise
catch
end

using Printf
using LinearAlgebra
using FFTW
using Logging
using Statistics
using Dates
using JLD2

ENV["MPLBACKEND"] = "Agg"
using PyPlot
using MultiModeNoise

include(joinpath(@__DIR__, "longfiber_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────

const LF100V_RESULTS_DIR = joinpath("results", "raman", "phase16")
const LF100V_FIGURE_DIR  = joinpath("results", "images")
const LF100V_FULL_RESULT = joinpath(LF100V_RESULTS_DIR, "100m_opt_full_result.jld2")
const LF100V_RESUME_RESULT = joinpath(LF100V_RESULTS_DIR, "100m_opt_resume_result.jld2")
const LF100V_WARM_START_JLD2 = joinpath("results", "raman", "sweeps", "smf28",
                                        "L2m_P0.05W", "opt_result.jld2")

const LF100V_L          = 100.0
const LF100V_P_CONT     = 0.05
const LF100V_NT         = 32768
const LF100V_TIME_WIN   = 160.0
const LF100V_BETA_ORDER = 2
const LF100V_N_ZSAVE    = 101
const LF100V_SMF28_BETA2 = -2.17e-26   # from FIBER_PRESETS[:SMF28_beta2_only]

# Theoretical ratio of a₂ coefficients under pure GVD scaling.
# φ_GVD(ω, L) = ½·β₂·ω²·L, so a₂(L1)/a₂(L2) = L1/L2. The warm-start is at 2 m
# and the optimum at 100 m, giving a pure-GVD ratio of 50. If a 30 m a₂ were
# available, the plan's headline 3.33 = 100/30 would apply.
const LF100V_GVD_RATIO_100_VS_2  = 50.0
const LF100V_GVD_RATIO_100_VS_30 = 100.0 / 30.0

# ─────────────────────────────────────────────────────────────────────────────
# Polynomial fit φ(ω) = a0 + a1·ω + a2·ω² over the physical spectrum
# ─────────────────────────────────────────────────────────────────────────────

"""
    lf100v_quadratic_fit(phi, Δf_fft_Hz; weight=nothing) -> (a0, a1, a2, residual, R²)

Fit φ(ω) ≈ a₀ + a₁·ω + a₂·ω² by weighted linear least-squares on the physical
angular-frequency axis (ω = 2π·Δf).  `weight` (default `nothing`) selects
uniform weighting over bins where |phi| > 1e-8 — this keeps the fit focused on
bins where the optimizer actually cared about φ (outside the pulse bandwidth
phi is zero by construction after warm-start interpolation).

Returns the fit coefficients (a₀, a₁, a₂), the residual vector `phi - fit`,
and the coefficient-of-determination R².
"""
function lf100v_quadratic_fit(phi::AbstractVector{<:Real}, Δf_fft_Hz::AbstractVector{<:Real};
        weight::Union{Nothing, AbstractVector} = nothing)
    Nt = length(phi)
    @assert length(Δf_fft_Hz) == Nt

    ω = 2π .* Δf_fft_Hz
    X = hcat(ones(Nt), ω, ω .^ 2)

    w = if weight === nothing
        m = abs.(phi) .> 1e-8
        Float64.(m)
    else
        Float64.(weight)
    end
    @assert length(w) == Nt

    Wsqrt = Diagonal(sqrt.(max.(w, 0.0)))
    a = (Wsqrt * X) \ (Wsqrt * phi)
    a0, a1, a2 = a[1], a[2], a[3]

    fit = X * a
    residual = phi .- fit

    ss_res = sum(w .* residual .^ 2)
    phi_mean = sum(w .* phi) / max(sum(w), eps())
    ss_tot = sum(w .* (phi .- phi_mean) .^ 2)
    R2 = ss_tot > 0 ? 1.0 - ss_res / ss_tot : NaN

    return (a0 = a0, a1 = a1, a2 = a2, residual = residual, R2 = R2)
end

# ─────────────────────────────────────────────────────────────────────────────
# Forward solve with z-saves, for J(z) trace
# ─────────────────────────────────────────────────────────────────────────────

function lf100v_forward_zsaved(uω0_shaped, fiber, sim, band_mask, zsave; label)
    fiber_local = deepcopy(fiber)
    fiber_local["zsave"] = zsave
    @info @sprintf("[%s] z-saved forward solve: %d saves over %.1f m", label, length(zsave), fiber["L"])
    t0 = time()
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_local, sim)
    wall = time() - t0
    uω_z = sol["uω_z"]   # (n_zsave, Nt, M)
    J_z = Float64[spectral_band_cost(uω_z[i, :, :], band_mask)[1] for i in 1:length(zsave)]

    # BC at endpoint
    uω_L = uω_z[end, :, :]
    ut_L = ifft(uω_L, 1)
    _, bc_frac = check_boundary_conditions(ut_L, sim)

    E_start = sum(abs2, uω0_shaped)
    E_end   = sum(abs2, uω_L)
    drift   = abs(E_end - E_start) / max(E_start, eps())

    @info @sprintf("[%s] wall=%.1fs  J_end=%.3e (%.2f dB)  BC=%.2e  E_drift=%.3e",
        label, wall, J_z[end], 10*log10(max(J_z[end], 1e-20)), bc_frac, drift)

    return (J_z = J_z, bc_frac = bc_frac, E_drift = drift, wall = wall)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figures
# ─────────────────────────────────────────────────────────────────────────────

function lf100v_figure_phi(phi_warm, phi_opt, fit_warm, fit_opt, Δf_fft_Hz, out_path)
    Δf_shift = fftshift(Δf_fft_Hz) * 1e-12  # THz for the x-axis

    phi_warm_shift = fftshift(vec(phi_warm))
    phi_opt_shift  = fftshift(vec(phi_opt))
    res_warm_shift = fftshift(fit_warm.residual)
    res_opt_shift  = fftshift(fit_opt.residual)

    fig, axes = PyPlot.subplots(2, 1, figsize = (10, 8), sharex = true)

    ax = axes[1]
    ax.plot(Δf_shift, phi_warm_shift; lw = 1.2, color = "#4477aa",
        label = @sprintf("phi@2m warm   (a₂ = %.3e s²/rad)", fit_warm.a2))
    ax.plot(Δf_shift, phi_opt_shift; lw = 1.2, color = "#cc5544",
        label = @sprintf("phi@100m opt  (a₂ = %.3e s²/rad)", fit_opt.a2))
    ax.set_ylabel("φ(ω)  [rad]")
    ax.set_title("Spectral phase profiles: phi@2m warm-start vs phi@100m optimum")
    ax.grid(true, alpha = 0.3)
    ax.set_xlim(-25, 25)
    ax.legend(loc = "best")

    ax2 = axes[2]
    ax2.plot(Δf_shift, res_warm_shift; lw = 1.0, color = "#4477aa",
        label = @sprintf("warm residual  R²=%.3f", fit_warm.R2))
    ax2.plot(Δf_shift, res_opt_shift; lw = 1.0, color = "#cc5544",
        label = @sprintf("opt residual  R²=%.3f", fit_opt.R2))
    ax2.axhline(0; color = "k", lw = 0.5, alpha = 0.5)
    ax2.set_xlabel("Δf  [THz]")
    ax2.set_ylabel("Δφ(ω) after quadratic fit  [rad]")
    ax2.grid(true, alpha = 0.3)
    ax2.legend(loc = "best")
    ax2.set_xlim(-25, 25)

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
    @info "saved figure $out_path"
end

function lf100v_figure_Jz(zsave, J_flat, J_warm, J_opt, out_path)
    Jz_flat_dB = 10 .* log10.(max.(J_flat, 1e-20))
    Jz_warm_dB = 10 .* log10.(max.(J_warm, 1e-20))
    Jz_opt_dB  = 10 .* log10.(max.(J_opt,  1e-20))

    fig, ax = PyPlot.subplots(figsize = (10, 5))
    ax.plot(zsave, Jz_flat_dB; lw = 1.5, color = "#888888", label = "flat φ(ω) = 0")
    ax.plot(zsave, Jz_warm_dB; lw = 1.5, color = "#4477aa", label = "phi@2m warm-start")
    ax.plot(zsave, Jz_opt_dB;  lw = 1.5, color = "#cc5544", label = "phi@100m optimum")
    ax.set_xlabel("z  [m]")
    ax.set_ylabel("J(z) = E_Raman / E_total  [dB]")
    ax.set_title(@sprintf("L=100 m SMF-28 P=%.3f W — J(z) three-way comparison", LF100V_P_CONT))
    ax.grid(true, alpha = 0.3)
    ax.legend(loc = "best")

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
    @info "saved figure $out_path"
end

# ─────────────────────────────────────────────────────────────────────────────
# FINDINGS.md writer
# ─────────────────────────────────────────────────────────────────────────────

function lf100v_write_findings(path, fields::Dict{String, Any})
    open(path, "w") do io
        println(io, "# Phase 16 — Long-Fiber Raman Suppression at L = 100 m")
        println(io, "")
        println(io, "*Session F — generated $(now()) by `longfiber_validate_100m.jl`.*")
        println(io, "")
        println(io, "## Configuration")
        println(io, "")
        println(io, "| Quantity | Value |")
        println(io, "|---|---|")
        println(io, "| Fiber | SMF-28 (β₂ only, β₂ = $(LF100V_SMF28_BETA2) s²/m) |")
        println(io, "| Length | $(LF100V_L) m |")
        println(io, "| P_cont | $(LF100V_P_CONT) W |")
        println(io, "| Pulse | 185 fs sech² @ 1550 nm, 80.5 MHz |")
        println(io, "| Grid | Nt = $(LF100V_NT), T = $(LF100V_TIME_WIN) ps |")
        println(io, "| β_order | $(LF100V_BETA_ORDER) |")
        println(io, "| Warm-start seed | `results/raman/sweeps/smf28/L2m_P0.05W/opt_result.jld2` |")
        println(io, "")
        println(io, "## Headline numbers")
        println(io, "")
        println(io, "| Quantity | Value |")
        println(io, "|---|---|")
        @printf(io, "| J_flat(L=100 m) | %.2f dB |\n",  fields["J_flat_dB"])
        @printf(io, "| J_warm@2m(L=100 m) | %.2f dB |\n", fields["J_warm_dB"])
        @printf(io, "| J_opt@100m (Phase 16 result) | %.2f dB |\n", fields["J_opt_dB"])
        @printf(io, "| Δ (opt vs flat) | %+.2f dB |\n", fields["J_opt_dB"] - fields["J_flat_dB"])
        @printf(io, "| Δ (opt vs warm) | %+.2f dB |\n", fields["J_opt_dB"] - fields["J_warm_dB"])
        println(io, "")
        println(io, "## Convergence")
        println(io, "")
        println(io, "| Quantity | Value |")
        println(io, "|---|---|")
        @printf(io, "| L-BFGS iterations | %d |\n", fields["n_iter"])
        @printf(io, "| converged flag | %s |\n", string(fields["converged"]))
        @printf(io, "| final ‖∇J‖ | %.3e |\n", fields["grad_norm"])
        @printf(io, "| wall time (fresh) | %.1f min |\n", fields["wall_fresh_min"])
        println(io, "")
        println(io, "## Checkpoint-resume validation")
        println(io, "")
        if haskey(fields, "resume_pass")
            @printf(io, "- resume final J : %.4f dB\n", fields["J_resume_dB"])
            @printf(io, "- reference  J   : %.4f dB\n", fields["J_opt_dB"])
            @printf(io, "- Δrel           : %.2e\n", fields["resume_Δrel"])
            @printf(io, "- verdict        : **%s**\n", fields["resume_pass"] ? "PASS" : "FAIL")
        else
            println(io, "- resume result JLD2 not found; skipped parity check.")
        end
        println(io, "")
        println(io, "## Energy conservation")
        println(io, "")
        println(io, "| Run | Photon-number drift | BC edge fraction |")
        println(io, "|---|---|---|")
        @printf(io, "| flat       | %.2e | %.2e |\n", fields["E_drift_flat"], fields["bc_flat"])
        @printf(io, "| phi@2m     | %.2e | %.2e |\n", fields["E_drift_warm"], fields["bc_warm"])
        @printf(io, "| phi@100m   | %.2e | %.2e |\n", fields["E_drift_opt"],  fields["bc_opt"])
        println(io, "")
        println(io, "## φ(ω) quadratic-fit fingerprint")
        println(io, "")
        println(io, "Fit model: φ(ω) ≈ a₀ + a₁·ω + a₂·ω² + Δφ(ω), weighted by |phi(ω)| > 1e-8.")
        println(io, "")
        println(io, "| Phase | a₀ [rad] | a₁ [s] | a₂ [s²] | R² |")
        println(io, "|---|---|---|---|---|")
        @printf(io, "| phi@2m warm  | %.3e | %.3e | %.3e | %.3f |\n",
            fields["warm_a0"], fields["warm_a1"], fields["warm_a2"], fields["warm_R2"])
        @printf(io, "| phi@100m opt | %.3e | %.3e | %.3e | %.3f |\n",
            fields["opt_a0"], fields["opt_a1"], fields["opt_a2"], fields["opt_R2"])
        println(io, "")
        println(io, "### a₂ scaling — structural-adaptation fingerprint")
        println(io, "")
        @printf(io, "- Observed ratio a₂(100 m) / a₂(2 m) = %.3f\n", fields["a2_ratio_100_vs_2"])
        @printf(io, "- Pure-GVD prediction (100 m / 2 m) = %.3f\n", LF100V_GVD_RATIO_100_VS_2)
        @printf(io, "- Deviation = %+.2f%% from pure GVD rescale\n", fields["a2_deviation_pct"])
        println(io, "")
        println(io, "**Interpretation**: If the ratio is close to the pure-GVD prediction, the")
        println(io, "optimal φ@100 m is a simple quadratic rescale of φ@2 m (pure-GVD hypothesis).")
        println(io, "A significant deviation (> ~20%) signals nonlinear structural adaptation —")
        println(io, "the publishable physics thread for Session F (D-F-07).")
        println(io, "")
        println(io, "## Open questions for Phase 17")
        println(io, "")
        println(io, "- Does the warm-start basin coincide with the global minimum at L=100 m?")
        println(io, "  A multi-start repeat of Phase 16 would nail this.")
        println(io, "- Scaling to L=200 m: does a₂(200)/a₂(100) = 2 (pure GVD)?")
        println(io, "- HNLF analogue at equivalent dispersion length: same physics?")
        println(io, "- Multimode generalization (M > 1): does the shape universality survive?")
    end
    @info "saved $path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function lf100v_run()
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Long-fiber 100 m validation — Session F / Phase 16 — start %s", now())
    @info "═══════════════════════════════════════════════════════════════"

    @assert isfile(LF100V_FULL_RESULT) "missing $LF100V_FULL_RESULT — run Task 5 first"

    d = JLD2.load(LF100V_FULL_RESULT)
    phi_opt  = Matrix{Float64}(d["phi_opt"])
    phi_warm = Matrix{Float64}(d["phi_warm"])
    trace_f  = Vector{Float64}(d["trace_f"])
    n_iter   = Int(d["n_iter"])
    converged = Bool(d["converged"])
    grad_norm = Float64(d["g_residual"])
    wall_fresh = Float64(d["wall_s"])

    # Build problem
    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = :SMF28_beta2_only,
        L_fiber      = LF100V_L,
        P_cont       = LF100V_P_CONT,
        Nt           = LF100V_NT,
        time_window  = LF100V_TIME_WIN,
        β_order      = LF100V_BETA_ORDER,
    )

    # ── Quadratic fits on physical ω axis ────────────────────────────────────
    Δf_fft = fftfreq(LF100V_NT, 1.0 / sim["Δt"])
    fit_warm = lf100v_quadratic_fit(vec(phi_warm), Δf_fft)
    fit_opt  = lf100v_quadratic_fit(vec(phi_opt),  Δf_fft)
    @info @sprintf("phi@2m  : a₀=%.3e a₁=%.3e a₂=%.3e R²=%.3f",
        fit_warm.a0, fit_warm.a1, fit_warm.a2, fit_warm.R2)
    @info @sprintf("phi@100m: a₀=%.3e a₁=%.3e a₂=%.3e R²=%.3f",
        fit_opt.a0, fit_opt.a1, fit_opt.a2, fit_opt.R2)
    a2_ratio = fit_opt.a2 / max(abs(fit_warm.a2), 1e-30) * sign(fit_warm.a2)
    a2_dev_pct = 100.0 * (a2_ratio - LF100V_GVD_RATIO_100_VS_2) / LF100V_GVD_RATIO_100_VS_2
    @info @sprintf("a₂(100m)/a₂(2m) = %.3f  (pure-GVD 100m/2m = %.2f; deviation = %+.2f%%)",
        a2_ratio, LF100V_GVD_RATIO_100_VS_2, a2_dev_pct)

    # ── J(z) three-way ───────────────────────────────────────────────────────
    zsave = collect(range(0.0, LF100V_L; length = LF100V_N_ZSAVE))

    uω0_flat = copy(uω0)
    uω0_warm = uω0 .* exp.(1im .* phi_warm)
    uω0_opt  = uω0 .* exp.(1im .* phi_opt)

    res_flat = lf100v_forward_zsaved(uω0_flat, fiber, sim, band_mask, zsave; label = "FLAT")
    res_warm = lf100v_forward_zsaved(uω0_warm, fiber, sim, band_mask, zsave; label = "WARM")
    res_opt  = lf100v_forward_zsaved(uω0_opt,  fiber, sim, band_mask, zsave; label = "OPT")

    J_flat_dB = 10 * log10(max(res_flat.J_z[end], 1e-20))
    J_warm_dB = 10 * log10(max(res_warm.J_z[end], 1e-20))
    J_opt_dB  = 10 * log10(max(res_opt.J_z[end],  1e-20))

    # ── Resume parity (if resume result exists) ──────────────────────────────
    resume_pass  = nothing
    resume_Δrel  = NaN
    J_resume_dB  = NaN
    if isfile(LF100V_RESUME_RESULT)
        dr = JLD2.load(LF100V_RESUME_RESULT)
        J_resume_dB = Float64(dr["J_final"])
        J_ref_dB    = haskey(dr, "J_ref") ? Float64(dr["J_ref"]) : Float64(d["J_final"])
        resume_Δrel = abs(J_resume_dB - J_ref_dB) / max(abs(J_ref_dB), 1e-20)
        resume_pass = resume_Δrel < 1e-6
        @info @sprintf("resume parity: Δrel=%.2e → %s",
            resume_Δrel, resume_pass ? "PASS" : "FAIL")
    else
        @warn "no resume result JLD2 at $LF100V_RESUME_RESULT — skipping parity check"
    end

    # ── Figures ──────────────────────────────────────────────────────────────
    lf100v_figure_phi(phi_warm, phi_opt, fit_warm, fit_opt, Δf_fft,
        joinpath(LF100V_FIGURE_DIR, "physics_16_04_phi_profile_2m_vs_100m.png"))
    lf100v_figure_Jz(zsave, res_flat.J_z, res_warm.J_z, res_opt.J_z,
        joinpath(LF100V_FIGURE_DIR, "physics_16_05_Jz_comparison.png"))

    # ── Save validate JLD2 ───────────────────────────────────────────────────
    val_path = joinpath(LF100V_RESULTS_DIR, "100m_validate.jld2")
    JLD2.jldsave(val_path;
        phi_warm      = phi_warm,
        phi_opt       = phi_opt,
        fit_warm_a0   = fit_warm.a0,
        fit_warm_a1   = fit_warm.a1,
        fit_warm_a2   = fit_warm.a2,
        fit_warm_R2   = fit_warm.R2,
        fit_opt_a0    = fit_opt.a0,
        fit_opt_a1    = fit_opt.a1,
        fit_opt_a2    = fit_opt.a2,
        fit_opt_R2    = fit_opt.R2,
        a2_ratio_100_vs_2 = a2_ratio,
        a2_deviation_pct  = a2_dev_pct,
        gvd_ratio_100_vs_2  = LF100V_GVD_RATIO_100_VS_2,
        gvd_ratio_100_vs_30 = LF100V_GVD_RATIO_100_VS_30,
        J_flat_dB     = J_flat_dB,
        J_warm_dB     = J_warm_dB,
        J_opt_dB      = J_opt_dB,
        E_drift_flat  = res_flat.E_drift,
        E_drift_warm  = res_warm.E_drift,
        E_drift_opt   = res_opt.E_drift,
        bc_flat       = res_flat.bc_frac,
        bc_warm       = res_warm.bc_frac,
        bc_opt        = res_opt.bc_frac,
        n_iter        = n_iter,
        converged     = converged,
        grad_norm     = grad_norm,
        wall_fresh_s  = wall_fresh,
        saved_at      = now(),
    )
    @info "saved $val_path"

    # ── Save three-way J(z) ──────────────────────────────────────────────────
    jz_path = joinpath(LF100V_RESULTS_DIR, "100m_Jz_threeway.jld2")
    JLD2.jldsave(jz_path;
        zsave  = zsave,
        J_flat = res_flat.J_z,
        J_warm = res_warm.J_z,
        J_opt  = res_opt.J_z,
        L_m    = LF100V_L,
        P_cont_W = LF100V_P_CONT,
        Nt     = LF100V_NT,
        time_window_ps = LF100V_TIME_WIN,
        saved_at = now(),
    )
    @info "saved $jz_path"

    # ── FINDINGS.md ──────────────────────────────────────────────────────────
    fields = Dict{String, Any}(
        "J_flat_dB"     => J_flat_dB,
        "J_warm_dB"     => J_warm_dB,
        "J_opt_dB"      => J_opt_dB,
        "n_iter"        => n_iter,
        "converged"     => converged,
        "grad_norm"     => grad_norm,
        "wall_fresh_min" => wall_fresh / 60,
        "E_drift_flat"  => res_flat.E_drift,
        "E_drift_warm"  => res_warm.E_drift,
        "E_drift_opt"   => res_opt.E_drift,
        "bc_flat"       => res_flat.bc_frac,
        "bc_warm"       => res_warm.bc_frac,
        "bc_opt"        => res_opt.bc_frac,
        "warm_a0"       => fit_warm.a0,
        "warm_a1"       => fit_warm.a1,
        "warm_a2"       => fit_warm.a2,
        "warm_R2"       => fit_warm.R2,
        "opt_a0"        => fit_opt.a0,
        "opt_a1"        => fit_opt.a1,
        "opt_a2"        => fit_opt.a2,
        "opt_R2"        => fit_opt.R2,
        "a2_ratio_100_vs_2" => a2_ratio,
        "a2_deviation_pct"  => a2_dev_pct,
    )
    if resume_pass !== nothing
        fields["resume_pass"] = resume_pass
        fields["resume_Δrel"] = resume_Δrel
        fields["J_resume_dB"] = J_resume_dB
    end
    findings_path = joinpath(LF100V_RESULTS_DIR, "FINDINGS.md")
    lf100v_write_findings(findings_path, fields)

    # PASS/FAIL summary
    pass_energy = res_opt.E_drift < 0.01
    pass_bc     = res_opt.bc_frac < 1e-3   # looser threshold accepted as physics per plan F-06
    pass_R2     = fit_opt.R2 > 0.8

    @info "════════════════════════════════════════════════════════════════"
    @info @sprintf("[%s] energy conservation at optimum (< 1%%)",
        pass_energy ? "PASS" : "FAIL")
    @info @sprintf("[%s] BC edge fraction at optimum     (< 1e-3)",
        pass_bc ? "PASS" : "WARN (accept as physics per F-06)")
    @info @sprintf("[%s] φ_opt quadratic fit R² > 0.8    (R²=%.3f)",
        pass_R2 ? "PASS" : "WARN", fit_opt.R2)
    @info "════════════════════════════════════════════════════════════════"

    return (
        pass_all = pass_energy && pass_R2,
        findings = findings_path,
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = lf100v_run()
    @info @sprintf("100 m validation: findings at %s", result.findings)
end
