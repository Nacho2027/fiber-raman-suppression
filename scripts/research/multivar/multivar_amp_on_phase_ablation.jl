"""
Focused multivariable closure ablation.

Question:
    Given the phase-only optimum at the canonical SMF-28 L=2 m, P=0.30 W
    point, can amplitude-only shaping improve Raman suppression by at least
    3 dB?

This intentionally skips unrelated energy-only and cold-start cases so the
closure decision for the multivar lane is not blocked by broad screening.
"""

try using Revise catch end
using Dates
using Logging
using Printf
ENV["MPLBACKEND"] = "Agg"
using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))
include(joinpath(@__DIR__, "multivar_optimization.jl"))

const MV_AMP_PHASE_TAG = get(ENV, "MV_AMP_PHASE_TAG", Dates.format(now(UTC), "yyyymmddTHHMMSSZ"))
const MV_AMP_PHASE_OUT = joinpath("results", "raman", "multivar", "amp_on_phase_" * MV_AMP_PHASE_TAG)
const MV_AMP_PHASE_PHASE_ITER = parse(Int, get(ENV, "MV_AMP_PHASE_PHASE_ITER", "50"))
const MV_AMP_PHASE_AMP_ITER = parse(Int, get(ENV, "MV_AMP_PHASE_AMP_ITER", "60"))
const MV_AMP_PHASE_THRESHOLD_DB = parse(Float64, get(ENV, "MV_AMP_PHASE_THRESHOLD_DB", "3.0"))
const MV_AMP_PHASE_DELTA_BOUND = parse(Float64, get(ENV, "MV_AMP_PHASE_DELTA_BOUND", "0.10"))
const MV_AMP_PHASE_LAMBDA_ENERGY = parse(Float64, get(ENV, "MV_AMP_PHASE_LAMBDA_ENERGY", "1.0"))
const MV_AMP_PHASE_L_FIBER = parse(Float64, get(ENV, "MV_AMP_PHASE_L_FIBER", "2.0"))
const MV_AMP_PHASE_P_CONT = parse(Float64, get(ENV, "MV_AMP_PHASE_P_CONT", "0.30"))

const MV_AMP_PHASE_KW = (
    L_fiber = MV_AMP_PHASE_L_FIBER,
    P_cont = MV_AMP_PHASE_P_CONT,
    Nt = 2^13,
    time_window = 20.0,
    β_order = 3,
    gamma_user = 1.1e-3,
    betas_user = [-2.17e-26, 1.2e-40],
    fR = 0.18,
    pulse_fwhm = 185e-15,
)

mkpath(MV_AMP_PHASE_OUT)

function _physics_cost_dB(uω0_shaped, fiber, sim, band_mask)
    fiber_eval = deepcopy(fiber)
    fiber_eval["zsave"] = [fiber_eval["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_eval, sim)
    uωf = sol["uω_z"][end, :, :]
    J, _ = spectral_band_cost(uωf, band_mask)
    return MultiModeNoise.lin_to_dB(J)
end

function _write_summary(; phase_dB, phase_iterations, amp_dB, improvement_dB, outcome, summary_path)
    passed = improvement_dB <= -MV_AMP_PHASE_THRESHOLD_DB
    open(summary_path, "w") do io
        println(io, "# Amplitude-On-Phase Closure Ablation")
        println(io)
        println(io, "- Tag: `$MV_AMP_PHASE_TAG`")
        println(io, "- Point: SMF-28, L=$(MV_AMP_PHASE_KW.L_fiber)m, P=$(MV_AMP_PHASE_KW.P_cont)W")
        println(io, "- Amplitude bound: δ=$(MV_AMP_PHASE_DELTA_BOUND), λ_energy=$(MV_AMP_PHASE_LAMBDA_ENERGY)")
        println(io, "- Question: can amplitude-only shaping on top of fixed phase-only optimum improve by at least $(MV_AMP_PHASE_THRESHOLD_DB) dB?")
        println(io)
        println(io, "| case | J after dB | vs phase-only dB | iterations | A range |")
        println(io, "|---|---:|---:|---:|---|")
        println(io, @sprintf("| phase_only_reference | %.2f | %+0.2f | %d | [1.000, 1.000] |",
            phase_dB, 0.0, phase_iterations))
        println(io, @sprintf("| amp_on_phase | %.2f | %+0.2f | %d | [%.3f, %.3f] |",
            amp_dB,
            improvement_dB,
            outcome.iterations,
            outcome.diagnostics[:A_extrema][1],
            outcome.diagnostics[:A_extrema][2]))
        println(io)
        println(io, passed ? "Verdict: PASS. Amplitude-on-phase beat phase-only by the required threshold." :
            "Verdict: FAIL. Amplitude-on-phase did not beat phase-only by the required threshold.")
        println(io)
        if !passed
            println(io, "Recommendation: close or defer the current multivariable lane for this canonical point; keep it out of lab-ready workflows.")
        end
    end
    return passed
end

@info "═══════════════════════════════════════════════════════════════"
@info "  Amplitude-on-phase ablation — SMF-28 L=$(MV_AMP_PHASE_KW.L_fiber)m P=$(MV_AMP_PHASE_KW.P_cont)W"
@info "═══════════════════════════════════════════════════════════════"
@info "output directory: $MV_AMP_PHASE_OUT"

@info "▶ phase-only reference"
result_phase, uω0, fiber, sim, band_mask, Δf = run_optimization(
    ; MV_AMP_PHASE_KW...,
    max_iter = MV_AMP_PHASE_PHASE_ITER,
    validate = false,
    λ_gdd = 1e-4,
    λ_boundary = 1.0,
    log_cost = true,
    fiber_name = "SMF-28",
    save_prefix = joinpath(MV_AMP_PHASE_OUT, "phase_only_reference"),
    do_plots = false,
)
φ_phase = reshape(result_phase.minimizer, sim["Nt"], sim["M"])
uω0_phase = @. uω0 * cis(φ_phase)
J_phase_dB = _physics_cost_dB(uω0_phase, fiber, sim, band_mask)
@info @sprintf("phase-only physics objective: %.2f dB", J_phase_dB)

save_standard_set(
    φ_phase, uω0, fiber, sim,
    band_mask, Δf, -5.0;
    tag = "phase_only_reference",
    fiber_name = "SMF28",
    L_m = MV_AMP_PHASE_KW.L_fiber,
    P_W = MV_AMP_PHASE_KW.P_cont,
    output_dir = MV_AMP_PHASE_OUT,
)

@info "▶ amplitude-only on fixed phase"
fiber_amp = deepcopy(fiber)
fiber_amp["zsave"] = nothing
outcome = optimize_spectral_multivariable(
    uω0_phase,
    fiber_amp,
    sim,
    band_mask;
    variables = (:amplitude,),
    max_iter = MV_AMP_PHASE_AMP_ITER,
    δ_bound = MV_AMP_PHASE_DELTA_BOUND,
    amp_param = :tanh,
    λ_gdd = 1e-4,
    λ_boundary = 1.0,
    λ_energy = MV_AMP_PHASE_LAMBDA_ENERGY,
    λ_tikhonov = 0.0,
    λ_tv = 0.0,
    λ_flat = 0.0,
    log_cost = false,
)

α = outcome.diagnostics[:alpha]
uω0_amp_phase = @. α * outcome.A_opt * uω0_phase
J_amp_dB = _physics_cost_dB(uω0_amp_phase, fiber, sim, band_mask)
improvement_dB = J_amp_dB - J_phase_dB
@info @sprintf("amp-on-phase physics objective: %.2f dB (vs phase-only: %+.2f dB)",
    J_amp_dB, improvement_dB)

meta = Dict{Symbol,Any}(
    :fiber_name => "SMF-28",
    :L_m => MV_AMP_PHASE_KW.L_fiber,
    :P_cont_W => MV_AMP_PHASE_KW.P_cont,
    :lambda0_nm => 1550.0,
    :fwhm_fs => MV_AMP_PHASE_KW.pulse_fwhm * 1e15,
    :rep_rate_Hz => 80.5e6,
    :gamma => fiber["γ"][1],
    :betas => haskey(fiber, "betas") ? fiber["betas"] : Float64[],
    :time_window_ps => sim["Nt"] * sim["Δt"],
    :sim_Dt => sim["Δt"],
    :sim_omega0 => sim["ω0"],
    :J_before => 10.0 ^ (J_phase_dB / 10.0),
    :delta_J_dB => improvement_dB,
    :band_mask => band_mask,
    :uomega0 => uω0_phase,
    :convergence_history => try
        MultiModeNoise.lin_to_dB.(collect(Optim.f_trace(outcome.result)))
    catch
        Float64[]
    end,
    :run_tag => MV_AMP_PHASE_TAG,
)
save_multivar_result(joinpath(MV_AMP_PHASE_OUT, "amp_on_phase"), outcome; meta = meta)

uω0_amp_base = @. α * outcome.A_opt * uω0
save_standard_set(
    φ_phase, uω0_amp_base, fiber, sim,
    band_mask, Δf, -5.0;
    tag = "amp_on_phase",
    fiber_name = "SMF28",
    L_m = MV_AMP_PHASE_KW.L_fiber,
    P_W = MV_AMP_PHASE_KW.P_cont,
    output_dir = MV_AMP_PHASE_OUT,
)

summary_path = joinpath(MV_AMP_PHASE_OUT, "amp_on_phase_summary.md")
passed = _write_summary(
    phase_dB = J_phase_dB,
    phase_iterations = Optim.iterations(result_phase),
    amp_dB = J_amp_dB,
    improvement_dB = improvement_dB,
    outcome = outcome,
    summary_path = summary_path,
)
@info "wrote summary: $summary_path"
@info passed ? "═══ amplitude-on-phase ablation PASS ═══" : "═══ amplitude-on-phase ablation FAIL ═══"
