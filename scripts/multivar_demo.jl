"""
Multi-Variable Optimizer Demonstration Run (Session A)

Compares phase-only (existing) vs. joint (phase + amplitude) multi-variable
optimization at the SMF-28 canonical config (Run 2 equivalent:
L=2m, P=0.30W, Nt=2^13, time_window=20 ps, SMF-28 dispersion).

Produces:
  - results/raman/multivar/smf28_L2m_P030W/mv_phaseonly_{result.jld2, slm.json}
  - results/raman/multivar/smf28_L2m_P030W/mv_joint_{result.jld2, slm.json}
  - results/raman/multivar/smf28_L2m_P030W/multivar_vs_phase_comparison.png

Success criteria:
  ΔJ(multivar) − ΔJ(phase-only) ≤ -0.5 dB   (multi-var strictly better)

Run on burst VM:
    julia -t auto --project=. scripts/multivar_demo.jl
"""

try using Revise catch end
using Printf
using LinearAlgebra
using Logging
using Dates
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using MultiModeNoise

# Reference (phase-only) optimizer — UNMODIFIED
include(joinpath(@__DIR__, "raman_optimization.jl"))
# New multi-variable optimizer
include(joinpath(@__DIR__, "multivar_optimization.jl"))

# ── Output directory ────────────────────────────────────────────────────────
const OUT_DIR = joinpath("results", "raman", "multivar", "smf28_L2m_P030W")
mkpath(OUT_DIR)

@info "═══════════════════════════════════════════════════════════════"
@info "  Multi-Variable Demo — SMF-28 L=2m P=0.30W (canonical Run 2)"
@info "═══════════════════════════════════════════════════════════════"

# ── Shared run config ────────────────────────────────────────────────────────
const DEMO_KW = (
    L_fiber = 2.0,
    P_cont = 0.30,
    Nt = 2^13,
    time_window = 20.0,
    β_order = 3,
    gamma_user = 1.1e-3,
    betas_user = [-2.17e-26, 1.2e-40],
    fR = 0.18,
    pulse_fwhm = 185e-15,
)
const MAX_ITER = 50

# ═════════════════════════════════════════════════════════════════════════════
# 1. Phase-only baseline (using UNMODIFIED raman_optimization.jl)
# ═════════════════════════════════════════════════════════════════════════════

@info "▶ Run A: phase-only reference (optimize_spectral_phase)"
t_A = time()
result_A, uω0_A, fiber_A, sim_A, band_mask_A, Δf_A = run_optimization(
    ; DEMO_KW...,
    max_iter = MAX_ITER, validate = false,
    λ_gdd = 1e-4, λ_boundary = 1.0, log_cost = true,
    fiber_name = "SMF-28",
    save_prefix = joinpath(OUT_DIR, "phase_only_opt"),
    do_plots = false,
)
φ_A = reshape(result_A.minimizer, sim_A["Nt"], sim_A["M"])
conv_A = collect(Optim.f_trace(result_A))
J_A_lin, _ = cost_and_gradient(φ_A, uω0_A, fiber_A, sim_A, band_mask_A)
J_A_dB = MultiModeNoise.lin_to_dB(J_A_lin)
J0_lin, _ = cost_and_gradient(zeros(size(φ_A)), uω0_A, fiber_A, sim_A, band_mask_A)
J0_dB = MultiModeNoise.lin_to_dB(J0_lin)
ΔJ_A_dB = J_A_dB - J0_dB
@info @sprintf("  phase-only: J_before=%.1f dB  J_after=%.1f dB  ΔJ=%.2f dB  (%.1f s)",
    J0_dB, J_A_dB, ΔJ_A_dB, time() - t_A)

# ═════════════════════════════════════════════════════════════════════════════
# 2. Joint (phase + amplitude) multi-variable
# ═════════════════════════════════════════════════════════════════════════════

@info "▶ Run B: joint phase+amplitude from cold start (tanh reparam, plain LBFGS)"
# log_cost=false so the log-scale gradient amplification that caused
# cold-start to accept a zero-length step in the previous demo does not kick
# in. At J=7e-1 initial, linear-cost gradient is O(1) and well-conditioned.
outB = run_multivar_optimization(
    ; DEMO_KW...,
    variables = (:phase, :amplitude),
    max_iter = 2 * MAX_ITER,
    validate = false,
    δ_bound = 0.10,
    amp_param = :tanh,
    λ_gdd = 1e-4, λ_boundary = 1.0,
    λ_energy = 1.0, λ_tikhonov = 0.0, λ_tv = 0.0, λ_flat = 0.0,
    log_cost = false,
    fiber_name = "SMF-28",
    save_prefix = joinpath(OUT_DIR, "mv_joint"),
)
J_B_lin = outB.J_after_lin
J_B_dB = MultiModeNoise.lin_to_dB(J_B_lin)
ΔJ_B_dB = outB.ΔJ_dB

# ─────────────────────────────────────────────────────────────────────────────
# 2b. Warm-started multivar run — seeded with phase-only optimum, A=1
# ─────────────────────────────────────────────────────────────────────────────

@info "▶ Run B-warm: phase+amplitude warm-started from phase-only optimum"
# Warm-start uses LINEAR cost (not log) because starting at J≈2e-6 with
# log_cost=true gives gradient scaling ~ 10/(J·ln10) ≈ 2e6 which breaks
# L-BFGS line search. Linear cost near an optimum gives gradient proportional
# to J — well-conditioned.
outB_warm = run_multivar_optimization(
    ; DEMO_KW...,
    variables = (:phase, :amplitude),
    max_iter = 2 * MAX_ITER,
    validate = false,
    δ_bound = 0.10,
    amp_param = :tanh,
    φ0 = φ_A,                         # reuse phase-only optimum
    A0 = ones(sim_A["Nt"], sim_A["M"]),
    λ_gdd = 1e-4, λ_boundary = 1.0,
    λ_energy = 1.0, λ_tikhonov = 0.0, λ_tv = 0.0, λ_flat = 0.0,
    log_cost = false,                 # see comment above
    fiber_name = "SMF-28",
    save_prefix = joinpath(OUT_DIR, "mv_joint_warmstart"),
)
J_Bw_lin = outB_warm.J_after_lin
J_Bw_dB = MultiModeNoise.lin_to_dB(J_Bw_lin)
ΔJ_Bw_dB = outB_warm.ΔJ_dB

# ═════════════════════════════════════════════════════════════════════════════
# 3. Phase-only result in multivar format (for symmetric comparison)
# ═════════════════════════════════════════════════════════════════════════════

@info "▶ Saving phase-only result in multivar JSON+JLD2 format too"
# Create a fake outcome struct mimicking optimize_spectral_multivariable output
struct_stub = (
    result = result_A,
    cfg = MVConfig(variables = (:phase,), log_cost = true),
    scale = ones(length(φ_A)),
    x_opt = vec(φ_A),
    φ_opt = φ_A,
    A_opt = ones(size(φ_A)),
    E_opt = sum(abs2, uω0_A),
    E_ref = sum(abs2, uω0_A),
    J_opt = J_A_dB,
    g_norm = 0.0,
    diagnostics = Dict{Symbol,Any}(:alpha => 1.0, :A_extrema => (1.0, 1.0)),
    wall_time_s = time() - t_A,
    iterations = Optim.iterations(result_A),
)
meta_A = Dict{Symbol,Any}(
    :fiber_name => "SMF-28",
    :L_m => DEMO_KW.L_fiber, :P_cont_W => DEMO_KW.P_cont,
    :lambda0_nm => 1550.0, :fwhm_fs => DEMO_KW.pulse_fwhm * 1e15,
    :rep_rate_Hz => 80.5e6,
    :gamma => DEMO_KW.gamma_user, :betas => DEMO_KW.betas_user,
    :time_window_ps => DEMO_KW.Nt * sim_A["Δt"],
    :sim_Dt => sim_A["Δt"], :sim_omega0 => sim_A["ω0"],
    :J_before => J0_lin, :delta_J_dB => ΔJ_A_dB,
    :band_mask => band_mask_A, :uomega0 => uω0_A,
    :convergence_history => conv_A,
    :run_tag => Dates.format(now(), "yyyymmdd_HHMMss"),
)
save_multivar_result(joinpath(OUT_DIR, "mv_phaseonly"), struct_stub; meta=meta_A)

# ═════════════════════════════════════════════════════════════════════════════
# 4. Comparison figure
# ═════════════════════════════════════════════════════════════════════════════

@info "▶ Plotting comparison figure"
fig, axs = subplots(1, 2, figsize=(13, 4.5))

# Left: convergence
ax1 = axs[1]
conv_B = outB.meta[:convergence_history]
conv_Bw = outB_warm.meta[:convergence_history]
ax1.plot(1:length(conv_A), conv_A, "-o", color="tab:blue", label="phase-only", markersize=3)
if !isempty(conv_B)
    ax1.plot(1:length(conv_B), conv_B, "-s", color="tab:red",
             label="multivar cold-start (tanh)", markersize=3)
end
if !isempty(conv_Bw)
    ax1.plot(1:length(conv_Bw), conv_Bw, "-^", color="tab:green",
             label="multivar warm-start (tanh)", markersize=3)
end
ax1.set_xlabel("iteration")
ax1.set_ylabel("J [dB]")
ax1.set_title("Convergence")
ax1.legend(loc="upper right")
ax1.grid(true, alpha=0.3)

# Right: output spectrum in Raman band for all three
ax2 = axs[2]
fiber_prop = deepcopy(fiber_A)
fiber_prop["zsave"] = [fiber_A["L"]]

# Phase-only output
uω0_A_shaped = @. uω0_A * cis(φ_A)
sol_A = MultiModeNoise.solve_disp_mmf(uω0_A_shaped, fiber_prop, sim_A)
uωf_A = sol_A["uω_z"][end, :, :]

# Joint cold-start output
α_B = outB.outcome.diagnostics[:alpha]
uω0_B_shaped = @. α_B * outB.outcome.A_opt * cis(outB.outcome.φ_opt) * outB.uω0
fiber_prop_B = deepcopy(outB.fiber)
fiber_prop_B["zsave"] = [outB.fiber["L"]]
sol_B = MultiModeNoise.solve_disp_mmf(uω0_B_shaped, fiber_prop_B, outB.sim)
uωf_B = sol_B["uω_z"][end, :, :]

# Joint warm-start output
α_Bw = outB_warm.outcome.diagnostics[:alpha]
uω0_Bw_shaped = @. α_Bw * outB_warm.outcome.A_opt * cis(outB_warm.outcome.φ_opt) * outB_warm.uω0
fiber_prop_Bw = deepcopy(outB_warm.fiber)
fiber_prop_Bw["zsave"] = [outB_warm.fiber["L"]]
sol_Bw = MultiModeNoise.solve_disp_mmf(uω0_Bw_shaped, fiber_prop_Bw, outB_warm.sim)
uωf_Bw = sol_Bw["uω_z"][end, :, :]

import FFTW
Δf_A_shifted = fftshift(FFTW.fftfreq(sim_A["Nt"], 1 / sim_A["Δt"]))
S_A = fftshift(vec(sum(abs2, uωf_A; dims=2)))
S_B = fftshift(vec(sum(abs2, uωf_B; dims=2)))
S_Bw = fftshift(vec(sum(abs2, uωf_Bw; dims=2)))
to_dB(S) = 10 .* log10.(max.(S ./ maximum(S), 1e-15))
ax2.plot(Δf_A_shifted, to_dB(S_A),  "-", color="tab:blue",  label="phase-only",         linewidth=1.3)
ax2.plot(Δf_A_shifted, to_dB(S_B),  "-", color="tab:red",   label="multivar cold-start", linewidth=1.3)
ax2.plot(Δf_A_shifted, to_dB(S_Bw), "-", color="tab:green", label="multivar warm-start", linewidth=1.3)
ax2.axvline(-5.0, color="k", linestyle=":", alpha=0.5, label="Raman threshold")
ax2.set_xlabel("Δf [THz]")
ax2.set_ylabel("|U(f)|² [dB norm]")
ax2.set_title("Output spectrum at z=L")
ax2.set_xlim(-30, 10)
ax2.set_ylim(-60, 5)
ax2.legend(loc="lower right")
ax2.grid(true, alpha=0.3)

fig.suptitle(@sprintf(
    "SMF-28 L=%.1fm P=%.2fW:  phase-only ΔJ=%.2f dB | cold ΔJ=%.2f dB (Δ=%.2f) | warm ΔJ=%.2f dB (Δ=%.2f)",
    DEMO_KW.L_fiber, DEMO_KW.P_cont,
    ΔJ_A_dB, ΔJ_B_dB, ΔJ_B_dB - ΔJ_A_dB,
    ΔJ_Bw_dB, ΔJ_Bw_dB - ΔJ_A_dB))
fig.tight_layout()
cmp_path = joinpath(OUT_DIR, "multivar_vs_phase_comparison.png")
savefig(cmp_path, dpi=200)
@info "Saved comparison figure: $cmp_path"

# ═════════════════════════════════════════════════════════════════════════════
# 5. Success criterion + final summary
# ═════════════════════════════════════════════════════════════════════════════

improvement_cold = ΔJ_B_dB  - ΔJ_A_dB   # negative = multivar cold better
improvement_warm = ΔJ_Bw_dB - ΔJ_A_dB   # negative = warm-start better
best_improvement = min(improvement_cold, improvement_warm)

@info @sprintf("""
═══════════════════════════════════════════════════════════════
  DEMO RESULTS
───────────────────────────────────────────────────────────────
  Phase-only            ΔJ = %.2f dB
  Multivariate (cold)   ΔJ = %.2f dB   (Δ vs phase-only = %+.2f dB)
  Multivariate (warm)   ΔJ = %.2f dB   (Δ vs phase-only = %+.2f dB)
  Best improvement          = %.2f dB  (negative = multivar wins)
  Success criterion (≤ -0.5 dB): %s
═══════════════════════════════════════════════════════════════
""",
    ΔJ_A_dB,
    ΔJ_B_dB,  improvement_cold,
    ΔJ_Bw_dB, improvement_warm,
    best_improvement,
    best_improvement ≤ -0.5 ? "PASS" : "FAIL — gap smaller than threshold")

if best_improvement > -0.5
    @warn "Demo did not meet success criterion. Possible causes: local minimum, regularizer over-constraint, or multivar genuinely not helpful at this config."
end

# ═════════════════════════════════════════════════════════════════════════════
# 6. Mandatory standard output images (Project-level rule, 2026-04-17)
# ═════════════════════════════════════════════════════════════════════════════
# `save_standard_set` takes a `phi_opt` and renders the 4 canonical PNGs the
# group expects. Our phase-only run propagates uω0·cis(φ) directly. Our
# multivar runs propagate α·A·cis(φ)·uω0, so we fold (α·A) into the "base"
# input when calling — that way the standard visualization reflects what was
# actually propagated, not just the phase component.

@info "▶ Generating standard output images (Project-rule 2026-04-17)"
include(joinpath(@__DIR__, "standard_images.jl"))

# Phase-only run — base uω0, phi=φ_A
save_standard_set(
    φ_A, uω0_A, fiber_A, sim_A,
    band_mask_A, Δf_A, -5.0;
    tag = "phase_only_L2m_P0p3W",
    fiber_name = "SMF28",
    L_m = DEMO_KW.L_fiber, P_W = DEMO_KW.P_cont,
    output_dir = OUT_DIR,
)

# Multivar cold-start — effective base = α·A·uω0
let αB = outB.outcome.diagnostics[:alpha], AB = outB.outcome.A_opt
    uω0_B_eff = @. αB * AB * outB.uω0
    save_standard_set(
        outB.outcome.φ_opt, uω0_B_eff, outB.fiber, outB.sim,
        outB.band_mask, Δf_A, -5.0;
        tag = "mv_cold_L2m_P0p3W",
        fiber_name = "SMF28",
        L_m = DEMO_KW.L_fiber, P_W = DEMO_KW.P_cont,
        output_dir = OUT_DIR,
    )
end

# Multivar warm-start — same convention
let αBw = outB_warm.outcome.diagnostics[:alpha], ABw = outB_warm.outcome.A_opt
    uω0_Bw_eff = @. αBw * ABw * outB_warm.uω0
    save_standard_set(
        outB_warm.outcome.φ_opt, uω0_Bw_eff, outB_warm.fiber, outB_warm.sim,
        outB_warm.band_mask, Δf_A, -5.0;
        tag = "mv_warm_L2m_P0p3W",
        fiber_name = "SMF28",
        L_m = DEMO_KW.L_fiber, P_W = DEMO_KW.P_cont,
        output_dir = OUT_DIR,
    )
end

@info "═══ Multivar demo complete ═══"
