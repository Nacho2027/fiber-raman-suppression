"""
Canonical staged amplitude-on-phase refinement workflow.

This keeps the old two-stage capability inside the Julia API: first solve the
phase-only Raman problem, then optimize bounded spectral amplitude on top of
the fixed phase and write the standard image/result set.
"""

using Dates
using Logging
using Printf
using FiberLab
using Optim

include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "multivar_optimization.jl"))

function _amp_on_phase_physics_cost_dB(uω0_shaped, fiber, sim, band_mask)
    fiber_eval = deepcopy(fiber)
    fiber_eval["zsave"] = [fiber_eval["L"]]
    sol = FiberLab.solve_disp_mmf(uω0_shaped, fiber_eval, sim)
    uωf = sol["uω_z"][end, :, :]
    J, _ = spectral_band_cost(uωf, band_mask)
    return FiberLab.lin_to_dB(J)
end

function _write_amp_on_phase_summary(;
    tag,
    L_fiber,
    P_cont,
    delta_bound,
    lambda_energy,
    threshold_db,
    phase_dB,
    phase_iterations,
    amp_dB,
    improvement_dB,
    outcome,
    summary_path,
)
    passed = improvement_dB <= -threshold_db
    open(summary_path, "w") do io
        println(io, "# Amplitude-On-Phase Closure Ablation")
        println(io)
        println(io, "- Tag: `$tag`")
        println(io, "- Point: SMF-28, L=$(L_fiber)m, P=$(P_cont)W")
        println(io, "- Amplitude bound: delta=$(delta_bound), lambda_energy=$(lambda_energy)")
        println(io, "- Question: can amplitude-only shaping on top of fixed phase-only optimum improve by at least $(threshold_db) dB?")
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
            println(io, "Recommendation: close or defer this optional multivariable lane for the canonical point.")
        end
    end
    return passed
end

function run_amp_on_phase_refinement(;
    tag::AbstractString=Dates.format(now(UTC), "yyyymmddTHHMMSSZ"),
    output_dir::AbstractString=joinpath("results", "raman", "multivar", "amp_on_phase_" * String(tag)),
    phase_iter::Integer=50,
    amp_iter::Integer=60,
    threshold_db::Real=3.0,
    delta_bound::Real=0.10,
    lambda_energy::Real=1.0,
    L_fiber::Real=2.0,
    P_cont::Real=0.30,
)
    kw = (
        L_fiber = Float64(L_fiber),
        P_cont = Float64(P_cont),
        Nt = 2^13,
        time_window = 20.0,
        β_order = 3,
        gamma_user = 1.1e-3,
        betas_user = [-2.17e-26, 1.2e-40],
        fR = 0.18,
        pulse_fwhm = 185e-15,
    )

    mkpath(output_dir)
    @info "Amplitude-on-phase refinement" tag output_dir L_fiber P_cont phase_iter amp_iter

    result_phase, uω0, fiber, sim, band_mask, Δf = run_optimization(
        ; kw...,
        max_iter = Int(phase_iter),
        validate = false,
        λ_gdd = 1e-4,
        λ_boundary = 1.0,
        log_cost = true,
        fiber_name = "SMF-28",
        save_prefix = joinpath(output_dir, "phase_only_reference"),
        do_plots = false,
    )
    φ_phase = reshape(result_phase.minimizer, sim["Nt"], sim["M"])
    uω0_phase = @. uω0 * cis(φ_phase)
    J_phase_dB = _amp_on_phase_physics_cost_dB(uω0_phase, fiber, sim, band_mask)

    save_standard_set(
        φ_phase, uω0, fiber, sim,
        band_mask, Δf, -5.0;
        tag = "phase_only_reference",
        fiber_name = "SMF28",
        L_m = kw.L_fiber,
        P_W = kw.P_cont,
        output_dir = output_dir,
    )

    fiber_amp = deepcopy(fiber)
    fiber_amp["zsave"] = nothing
    outcome = optimize_spectral_multivariable(
        uω0_phase,
        fiber_amp,
        sim,
        band_mask;
        variables = (:amplitude,),
        max_iter = Int(amp_iter),
        δ_bound = Float64(delta_bound),
        amp_param = :tanh,
        λ_gdd = 1e-4,
        λ_boundary = 1.0,
        λ_energy = Float64(lambda_energy),
        λ_tikhonov = 0.0,
        λ_tv = 0.0,
        λ_flat = 0.0,
        log_cost = false,
    )

    α = outcome.diagnostics[:alpha]
    uω0_amp_phase = @. α * outcome.A_opt * uω0_phase
    J_amp_dB = _amp_on_phase_physics_cost_dB(uω0_amp_phase, fiber, sim, band_mask)
    improvement_dB = J_amp_dB - J_phase_dB

    meta = Dict{Symbol,Any}(
        :fiber_name => "SMF-28",
        :L_m => kw.L_fiber,
        :P_cont_W => kw.P_cont,
        :lambda0_nm => 1550.0,
        :fwhm_fs => kw.pulse_fwhm * 1e15,
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
            FiberLab.lin_to_dB.(collect(Optim.f_trace(outcome.result)))
        catch
            Float64[]
        end,
        :run_tag => String(tag),
    )
    saved = save_multivar_result(joinpath(output_dir, "amp_on_phase"), outcome; meta = meta)

    uω0_amp_base = @. α * outcome.A_opt * uω0
    save_standard_set(
        φ_phase, uω0_amp_base, fiber, sim,
        band_mask, Δf, -5.0;
        tag = "amp_on_phase",
        fiber_name = "SMF28",
        L_m = kw.L_fiber,
        P_W = kw.P_cont,
        output_dir = output_dir,
    )

    summary_path = joinpath(output_dir, "amp_on_phase_summary.md")
    passed = _write_amp_on_phase_summary(
        tag = String(tag),
        L_fiber = kw.L_fiber,
        P_cont = kw.P_cont,
        delta_bound = Float64(delta_bound),
        lambda_energy = Float64(lambda_energy),
        threshold_db = Float64(threshold_db),
        phase_dB = J_phase_dB,
        phase_iterations = Optim.iterations(result_phase),
        amp_dB = J_amp_dB,
        improvement_dB = improvement_dB,
        outcome = outcome,
        summary_path = summary_path,
    )

    return (
        output_dir = output_dir,
        summary = summary_path,
        artifact = saved.jld2,
        sidecar = saved.json,
        passed = passed,
        phase_dB = J_phase_dB,
        amp_dB = J_amp_dB,
        improvement_dB = improvement_dB,
    )
end
