"""
Multivar variable-impact ablation at the canonical SMF-28 point.

This is the next step after `multivar_demo.jl`: rather than only comparing
phase-only with joint phase+amplitude, it screens the available single-mode
control families:

- phase
- spectral amplitude mask
- scalar energy
- amplitude/energy applied on top of a fixed phase-only optimum
- warm joint phase+amplitude+energy

The mode-coefficient control is intentionally not included here; the current
single-mode multivar optimizer strips `:mode_coeffs` by design.
"""

try using Revise catch end
using Printf
using LinearAlgebra
using Logging
using Dates
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))
include(joinpath(@__DIR__, "multivar_optimization.jl"))

const MV_ABLATION_TAG = get(ENV, "MV_ABLATION_TAG", Dates.format(now(UTC), "yyyymmddTHHMMSSZ"))
const MV_ABLATION_OUT = joinpath("results", "raman", "multivar", "variable_ablation_" * MV_ABLATION_TAG)
const MV_ABLATION_PHASE_ITER = parse(Int, get(ENV, "MV_ABLATION_PHASE_ITER", "50"))
const MV_ABLATION_MV_ITER = parse(Int, get(ENV, "MV_ABLATION_MV_ITER", "60"))
const MV_ABLATION_ENERGY_ITER = parse(Int, get(ENV, "MV_ABLATION_ENERGY_ITER", "30"))
mkpath(MV_ABLATION_OUT)

const MV_ABLATION_KW = (
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

function _linear_phase_cost(φ, uω0, fiber, sim, band_mask)
    J, _ = cost_and_gradient(φ, uω0, fiber, sim, band_mask; log_cost = false)
    return J
end

function _linear_multivar_cost(outcome, uω0, fiber, sim, band_mask)
    Nt, M = sim["Nt"], sim["M"]
    E_ref = outcome.E_ref
    cfg_linear = deepcopy(outcome.cfg)
    cfg_linear.log_cost = false
    A_baseline_search = outcome.cfg.amp_param === :tanh ? zeros(Nt, M) : ones(Nt, M)
    x0 = mv_pack(zeros(Nt, M), A_baseline_search, E_ref, outcome.cfg, Nt, M)
    J0, _, _ = cost_and_gradient_multivar(x0, uω0, fiber, sim, band_mask, cfg_linear; E_ref = E_ref)
    J1, _, _ = cost_and_gradient_multivar(outcome.x_opt, uω0, fiber, sim, band_mask, cfg_linear; E_ref = E_ref)
    return J0, J1
end

function _trace_dB(outcome)
    raw = try
        collect(Optim.f_trace(outcome.result))
    catch
        Float64[]
    end
    outcome.cfg.log_cost ? raw : MultiModeNoise.lin_to_dB.(raw)
end

function _save_mv_case(
    label::AbstractString,
    outcome,
    uω0_case,
    uω0_original,
    fiber,
    sim,
    band_mask,
    Δf,
    fixed_phase,
    J_reference_dB::Real,
)
    prefix = joinpath(MV_ABLATION_OUT, label)
    J_before, J_after = _linear_multivar_cost(outcome, uω0_case, fiber, sim, band_mask)
    J_before_dB = MultiModeNoise.lin_to_dB(J_before)
    J_after_dB = MultiModeNoise.lin_to_dB(J_after)
    ΔJ_dB = J_after_dB - J_before_dB
    vs_phase_dB = J_after_dB - J_reference_dB

    meta = Dict{Symbol,Any}(
        :fiber_name => "SMF-28",
        :L_m => MV_ABLATION_KW.L_fiber,
        :P_cont_W => MV_ABLATION_KW.P_cont,
        :lambda0_nm => 1550.0,
        :fwhm_fs => MV_ABLATION_KW.pulse_fwhm * 1e15,
        :rep_rate_Hz => 80.5e6,
        :gamma => fiber["γ"][1],
        :betas => haskey(fiber, "betas") ? fiber["betas"] : Float64[],
        :time_window_ps => sim["Nt"] * sim["Δt"],
        :sim_Dt => sim["Δt"],
        :sim_omega0 => sim["ω0"],
        :J_before => J_before,
        :delta_J_dB => ΔJ_dB,
        :band_mask => band_mask,
        :uomega0 => uω0_case,
        :convergence_history => _trace_dB(outcome),
        :run_tag => MV_ABLATION_TAG,
    )
    save_multivar_result(prefix, outcome; meta = meta)

    α = outcome.diagnostics[:alpha]
    uω0_eff = @. α * outcome.A_opt * uω0_original
    φ_total = fixed_phase .+ outcome.φ_opt
    save_standard_set(
        φ_total, uω0_eff, fiber, sim,
        band_mask, Δf, -5.0;
        tag = label,
        fiber_name = "SMF28",
        L_m = MV_ABLATION_KW.L_fiber,
        P_W = MV_ABLATION_KW.P_cont,
        output_dir = MV_ABLATION_OUT,
    )

    return (
        label = String(label),
        variables = join(String.(outcome.cfg.variables), "+"),
        J_before_dB = J_before_dB,
        J_after_dB = J_after_dB,
        ΔJ_dB = ΔJ_dB,
        vs_phase_dB = vs_phase_dB,
        iterations = outcome.iterations,
        wall_time_s = outcome.wall_time_s,
        alpha = outcome.diagnostics[:alpha],
        A_min = outcome.diagnostics[:A_extrema][1],
        A_max = outcome.diagnostics[:A_extrema][2],
    )
end

function _run_case(;
    label::AbstractString,
    variables,
    uω0_case,
    uω0_original,
    fiber_template,
    sim,
    band_mask,
    Δf,
    fixed_phase,
    J_phase_dB::Real,
    max_iter::Int = MV_ABLATION_MV_ITER,
    φ0 = nothing,
    A0 = nothing,
    E0 = nothing,
    δ_bound::Real = 0.10,
    λ_energy::Real = 1.0,
)
    @info "▶ multivar ablation case: $label" variables max_iter
    fiber = deepcopy(fiber_template)
    fiber["zsave"] = nothing
    outcome = optimize_spectral_multivariable(
        uω0_case, fiber, sim, band_mask;
        variables = variables,
        max_iter = max_iter,
        φ0 = φ0,
        A0 = A0,
        E0 = E0,
        δ_bound = δ_bound,
        amp_param = :tanh,
        λ_gdd = 1e-4,
        λ_boundary = 1.0,
        λ_energy = λ_energy,
        λ_tikhonov = 0.0,
        λ_tv = 0.0,
        λ_flat = 0.0,
        log_cost = false,
    )
    row = _save_mv_case(label, outcome, uω0_case, uω0_original, fiber, sim, band_mask, Δf, fixed_phase, J_phase_dB)
    @info @sprintf("case %s: J_after=%.2f dB, ΔJ=%.2f dB, vs phase=%+.2f dB",
        label, row.J_after_dB, row.ΔJ_dB, row.vs_phase_dB)
    return row
end

function _write_summary(rows)
    ranked = sort(rows; by = r -> r.J_after_dB)
    md_path = joinpath(MV_ABLATION_OUT, "variable_ablation_summary.md")
    open(md_path, "w") do io
        println(io, "# Multivar Variable Ablation")
        println(io)
        println(io, "- Tag: `$MV_ABLATION_TAG`")
        println(io, "- Canonical point: SMF-28, L=$(MV_ABLATION_KW.L_fiber)m, P=$(MV_ABLATION_KW.P_cont)W")
        println(io, "- `vs_phase_dB = J_after_dB - J_phase_only_dB`; negative means the case beat phase-only.")
        println(io)
        println(io, "| rank | case | variables | J after dB | ΔJ dB | vs phase dB | iters | A range |")
        println(io, "|---:|---|---|---:|---:|---:|---:|---|")
        for (i, r) in enumerate(ranked)
            println(io, @sprintf("| %d | `%s` | `%s` | %.2f | %.2f | %+.2f | %d | [%.3f, %.3f] |",
                i, r.label, r.variables, r.J_after_dB, r.ΔJ_dB, r.vs_phase_dB,
                r.iterations, r.A_min, r.A_max))
        end
    end
    return md_path
end

@info "═══════════════════════════════════════════════════════════════"
@info "  Multivar Variable Ablation — SMF-28 L=2m P=0.30W"
@info "═══════════════════════════════════════════════════════════════"
@info "output directory: $MV_ABLATION_OUT"

@info "▶ phase-only reference"
t_phase = time()
result_phase, uω0, fiber, sim, band_mask, Δf = run_optimization(
    ; MV_ABLATION_KW...,
    max_iter = MV_ABLATION_PHASE_ITER,
    validate = false,
    λ_gdd = 1e-4,
    λ_boundary = 1.0,
    log_cost = true,
    fiber_name = "SMF-28",
    save_prefix = joinpath(MV_ABLATION_OUT, "phase_only_reference"),
    do_plots = false,
)
φ_phase = reshape(result_phase.minimizer, sim["Nt"], sim["M"])
φ_zero = zeros(size(φ_phase))
J_unshaped = _linear_phase_cost(φ_zero, uω0, fiber, sim, band_mask)
J_phase = _linear_phase_cost(φ_phase, uω0, fiber, sim, band_mask)
J_unshaped_dB = MultiModeNoise.lin_to_dB(J_unshaped)
J_phase_dB = MultiModeNoise.lin_to_dB(J_phase)
@info @sprintf("phase-only reference: %.2f -> %.2f dB (%.1f s)",
    J_unshaped_dB, J_phase_dB, time() - t_phase)

save_standard_set(
    φ_phase, uω0, fiber, sim,
    band_mask, Δf, -5.0;
    tag = "phase_only_reference",
    fiber_name = "SMF28",
    L_m = MV_ABLATION_KW.L_fiber,
    P_W = MV_ABLATION_KW.P_cont,
    output_dir = MV_ABLATION_OUT,
)

uω0_phase = @. uω0 * cis(φ_phase)
E_ref = sum(abs2, uω0)
rows = Any[
    (
        label = "phase_only_reference",
        variables = "phase",
        J_before_dB = J_unshaped_dB,
        J_after_dB = J_phase_dB,
        ΔJ_dB = J_phase_dB - J_unshaped_dB,
        vs_phase_dB = 0.0,
        iterations = Optim.iterations(result_phase),
        wall_time_s = time() - t_phase,
        alpha = 1.0,
        A_min = 1.0,
        A_max = 1.0,
    ),
]

append!(rows, [
    _run_case(
        label = "amp_unshaped",
        variables = (:amplitude,),
        uω0_case = uω0,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_zero,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_MV_ITER,
    ),
    _run_case(
        label = "energy_unshaped",
        variables = (:energy,),
        uω0_case = uω0,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_zero,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_ENERGY_ITER,
    ),
    _run_case(
        label = "amp_energy_unshaped",
        variables = (:amplitude, :energy),
        uω0_case = uω0,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_zero,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_MV_ITER,
    ),
    _run_case(
        label = "amp_on_phase",
        variables = (:amplitude,),
        uω0_case = uω0_phase,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_phase,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_MV_ITER,
    ),
    _run_case(
        label = "energy_on_phase",
        variables = (:energy,),
        uω0_case = uω0_phase,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_phase,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_ENERGY_ITER,
    ),
    _run_case(
        label = "amp_energy_on_phase",
        variables = (:amplitude, :energy),
        uω0_case = uω0_phase,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_phase,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_MV_ITER,
    ),
    _run_case(
        label = "phase_energy_cold",
        variables = (:phase, :energy),
        uω0_case = uω0,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_zero,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_MV_ITER,
    ),
    _run_case(
        label = "phase_amp_energy_warm",
        variables = (:phase, :amplitude, :energy),
        uω0_case = uω0,
        uω0_original = uω0,
        fiber_template = fiber,
        sim = sim,
        band_mask = band_mask,
        Δf = Δf,
        fixed_phase = φ_zero,
        J_phase_dB = J_phase_dB,
        max_iter = MV_ABLATION_MV_ITER,
        φ0 = φ_phase,
        A0 = ones(size(φ_phase)),
        E0 = E_ref,
    ),
])

summary_path = _write_summary(rows)
@info "wrote variable ablation summary: $summary_path"
@info "═══ Multivar variable ablation complete ═══"
