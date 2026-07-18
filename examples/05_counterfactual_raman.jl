#!/usr/bin/env julia

using CSV
using Dates
using FFTW
using FiberLab
using JLD2
using LinearAlgebra
using Printf
using PyPlot
using SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))

const PRIMARY_GATE = (
    max_rms_duration_ratio = 1.10,
    min_peak_power_ratio = 0.85,
    min_main_lobe_energy_ratio = 0.90,
)
const NUMERICAL_GATE = (max_relative_change = 0.005, min_gap_to_envelope = 10.0)
const TIGHT_SOLVER = (method = "Tsit5", reltol = 1e-10, abstol = 1e-9)
const SCALAR_CROSSCHECK_METHOD = "scalar_fixed_step_rk4ip_v1"
const SCALAR_CROSSCHECK_STEPS = (250, 500, 1000, 2000)
const SCALAR_CROSSCHECK_SHARED_COMPONENTS = (
    "resolved Dω/γ/hRω/one_m_fR/L",
    "grid/launch/self-steepening factor",
    "periodic scalar GNLSE model form",
    "FFTW",
)
const SCALAR_CROSSCHECK_GATE = (
    min_observed_order = 3.5,
    max_relative_field_error = 1e-7,
    max_centroid_shift_error_thz = 1e-8,
    max_error_fraction_of_candidate_gap = 0.01,
)
const NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ = 1e-7
const COLORS = (blue = "#0072B2", orange = "#D55E00",
                purple = "#CC79A7", gray = "#666666")

const COMMITTED_CANDIDATES = (
    neutral = (family = :neutral, tier = :reference, phi2_fs2 = 0.0, phi3_fs3 = 0.0),
    gate_gdd = (family = :gdd, tier = :primary, phi2_fs2 = -6035.0, phi3_fs3 = 0.0),
    gate_gdd_tod = (family = :gdd_tod, tier = :primary,
                    phi2_fs2 = -6555.0, phi3_fs3 = -350_000.0),
)

const DEVELOPMENT_STRESS_SPEC = (
    (name = "power -5%", kwargs = (; power_w = 0.095)),
    (name = "power +5%", kwargs = (; power_w = 0.105)),
    (name = "length -5%", kwargs = (; length_m = 0.475)),
    (name = "length +5%", kwargs = (; length_m = 0.525)),
    (name = "FWHM -5%", kwargs = (; fwhm_s = 0.95 * 185e-15)),
    (name = "FWHM +5%", kwargs = (; fwhm_s = 1.05 * 185e-15)),
    (name = "Raman fraction -5%", kwargs = (; raman_fraction = 0.95 * 0.18)),
    (name = "Raman fraction +5%", kwargs = (; raman_fraction = 1.05 * 0.18)),
    (name = "nonlinearity -5%", kwargs = (; gamma_scale = 0.95)),
    (name = "nonlinearity +5%", kwargs = (; gamma_scale = 1.05)),
    (name = "beta2 only", kwargs = (; preset = :SMF28_beta2_only, beta_order = 2)),
)

# Committed before first execution. Carrier cases change the carrier/grid while
# intentionally holding the preset dispersion and nonlinearity coefficients fixed.
const PREDECLARED_VALIDATION_SPEC = (
    (name = "carrier grid 1532 nm", kwargs = (; wavelength_m = 1532e-9),
     assumption = "carrier/grid perturbation; preset coefficients fixed"),
    (name = "carrier grid 1568 nm", kwargs = (; wavelength_m = 1568e-9),
     assumption = "carrier/grid perturbation; preset coefficients fixed"),
    (name = "repetition 78.2 MHz", kwargs = (; rep_rate_hz = 78.2e6),
     assumption = "repetition-rate perturbation; other inputs fixed"),
    (name = "repetition 82.8 MHz", kwargs = (; rep_rate_hz = 82.8e6),
     assumption = "repetition-rate perturbation; other inputs fixed"),
    (name = "1532 grid + 82.8 MHz",
     kwargs = (; wavelength_m = 1532e-9, rep_rate_hz = 82.8e6),
     assumption = "carrier/grid and repetition-rate perturbation; preset coefficients fixed"),
)

function parse_args(args)
    output_dir = joinpath(ROOT, "results", "counterfactual-raman")
    figure_dir = nothing
    search = false
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--search"
            search = true
        elseif arg in ("--output-dir", "--figure-dir")
            index < length(args) || error("$arg requires a path")
            index += 1
            arg == "--output-dir" ? (output_dir = abspath(args[index])) :
                                     (figure_dir = abspath(args[index]))
        elseif arg in ("-h", "--help")
            println("Usage: julia -t auto --project=. examples/05_counterfactual_raman.jl " *
                    "[--search] [--output-dir DIR] [--figure-dir DIR]")
            exit()
        else
            error("unknown argument: $arg")
        end
        index += 1
    end
    output_dir = abspath(output_dir)
    return (output_dir = output_dir,
            figure_dir = something(figure_dir, joinpath(output_dir, "figures")),
            search = search)
end

function require_fresh_directory(path, label)
    ispath(path) || return path
    isdir(path) || error("$label exists but is not a directory: $path")
    isempty(readdir(path)) || error(
        "$label must be new or empty so a stale completion manifest cannot survive: $path")
    return path
end

function problem_pair(; nt=1024, time_window_ps=10.0, length_m=0.5,
                      power_w=0.1, fwhm_s=185e-15, raman_fraction=0.18,
                      rep_rate_hz=80.5e6, wavelength_m=1550e-9,
                      preset=:SMF28, beta_order=3, gamma_scale=1.0)
    on = fiber_problem(
        Fiber(preset = preset, length_m = length_m, power_w = power_w,
              beta_order = beta_order, raman_fraction = raman_fraction);
        pulse = Pulse(fwhm_s = fwhm_s, rep_rate_hz = rep_rate_hz, shape = :sech_sq),
        grid = Grid(nt = nt, time_window_ps = time_window_ps, policy = :exact),
        wavelength_m = wavelength_m,
        raman_threshold_thz = nothing,
    )
    off = with_raman_fraction(on, 0.0)
    pair = if gamma_scale == 1
        (on, off)
    else
        isfinite(gamma_scale) && gamma_scale >= 0 || error(
            "gamma_scale must be nonnegative")
        explicit(problem) = begin
            fiber = deepcopy(problem.fiber)
            fiber["γ"] .*= gamma_scale
            fiber_field_problem(problem.uω0, fiber, deepcopy(problem.sim);
                                preset = problem.metadata.preset)
        end
        (explicit(on), explicit(off))
    end
    raman_counterfactual_contract(pair...).pass || error(
        "Raman-on/off problems violate the matched counterfactual contract")
    return pair
end

function phase_profile(problem, spec)
    coefficients = [Float64(spec.phi2_fs2), Float64(spec.phi3_fs3)]
    return taylor_phase_basis(problem, (2, 3)) * coefficients
end

function evaluate_pair(on, off, spec; keep_results=false, saveat=nothing,
                       allow_response_shape_change=false)
    contract = raman_counterfactual_contract(
        on, off; allow_response_shape_change = allow_response_shape_change)
    contract.pass || error("Raman-on/off inputs are not a matched counterfactual")
    phase = phase_profile(on, spec)
    launch = on.uω0 .* cis.(reshape(phase, :, 1))
    quality = pulse_quality_metrics(on.uω0, launch, on.sim)
    quality_status = pulse_quality_check(quality; PRIMARY_GATE...)
    on_result = propagate(with_launch(on, launch); saveat = saveat)
    off_result = propagate(with_launch(off, launch); saveat = saveat)
    spectrum = counterfactual_spectrum_metrics(
        on_result.output_spectrum, off_result.output_spectrum, launch, on)
    on_check, off_check = verify(on_result), verify(off_result)
    row = (
        family = String(spec.family), tier = String(spec.tier),
        phi2_fs2 = Float64(spec.phi2_fs2), phi3_fs3 = Float64(spec.phi3_fs3),
        centroid_on_thz = spectrum.on.centroid_thz,
        centroid_off_thz = spectrum.off.centroid_thz,
        centroid_shift_thz = spectrum.model_attributed_centroid_shift_thz,
        relative_energy_on = spectrum.on.relative_energy,
        relative_energy_off = spectrum.off.relative_energy,
        attributed_energy_change = spectrum.model_attributed_energy_change,
        launch_energy_ratio = quality.energy_ratio,
        rms_duration_ratio = quality.rms_duration_ratio,
        peak_power_ratio = quality.peak_power_ratio,
        main_lobe_energy_ratio = quality.main_lobe_energy_ratio,
        energy_check = quality_status.checks.energy_preserved,
        rms_check = quality_status.checks.rms_duration,
        peak_check = quality_status.checks.peak_power,
        main_lobe_check = quality_status.checks.main_lobe_energy,
        quality_pass = quality_status.pass,
        counterfactual_match = contract.pass,
        response_shape_matched = contract.response_shape_matched,
        declared_response_shape_control = contract.declared_response_shape_control,
        propagation_pass = on_check.pass && off_check.pass,
        max_temporal_edge_fraction = max(on_check.max_temporal_edge_fraction,
                                         off_check.max_temporal_edge_fraction),
        max_spectral_edge_fraction = max(on_check.max_spectral_edge_fraction,
                                         off_check.max_spectral_edge_fraction),
        max_photon_number_drift = max(on_check.max_photon_number_drift,
                                      off_check.max_photon_number_drift),
        on_evidence_sha256 = on_result.evidence_sha256,
        off_evidence_sha256 = off_result.evidence_sha256,
        on_resolved_sha256 = on_result.resolved_sha256,
        off_resolved_sha256 = off_result.resolved_sha256,
    )
    details = keep_results ? (phase = phase, launch = launch, quality = quality,
                              on = on_result, off = off_result,
                              spectrum = spectrum) : nothing
    return row, details
end

reduction_percent(shift, neutral_shift) = 100 * (1 - abs(shift / neutral_shift))

function named_candidates(on, off, candidates=COMMITTED_CANDIDATES)
    rows = NamedTuple[]
    details = Dict{Symbol,Any}()
    for name in propertynames(candidates)
        z_m = range(0, Float64(on.fiber["L"]); length = 25)
        row, detail = evaluate_pair(
            on, off, getproperty(candidates, name); keep_results = true, saveat = z_m)
        push!(rows, merge((candidate = String(name),), row))
        details[name] = detail
    end
    neutral_shift = only(row.centroid_shift_thz for row in rows if row.candidate == "neutral")
    rows = [merge(row, (reduction_percent = reduction_percent(
        row.centroid_shift_thz, neutral_shift),)) for row in rows]
    all(row.propagation_pass for row in rows) || error("a selected propagation failed verification")
    all(row.quality_pass for row in rows) || error("a selected launch failed its quality gate")
    return rows, details, neutral_shift
end

function adjoint_gate(on, off)
    bundle = compose_scenarios(
        ScenarioTerm(:raman_on, fiber_model(on), spectral_centroid_objective(on)),
        ScenarioTerm(:raman_off, fiber_model(off), spectral_centroid_objective(off));
        aggregate = squared_difference_aggregate(:raman_on, :raman_off),
        name = :counterfactual_centroid,
    )
    control = PhaseBasis(taylor_phase_basis(
        on, (2, 3); coefficient_scales_fs = (1000.0, 100_000.0)))
    checks = [check_adjoint_gradient(
        bundle.model, control, bundle.objective, [-6.55, -3.5];
        step = step, atol = 1e-10, rtol = 2e-3) for step in (1e-3, 5e-4)]
    all(check.pass for check in checks) || error(
        "paired counterfactual adjoint check failed")
    return (
        pass = true,
        coordinates = first(checks).coordinates,
        max_absolute_error = maximum(maximum(check.absolute_error) for check in checks),
        max_relative_error = maximum(maximum(check.relative_error) for check in checks),
        checks = [(
            step = check.step,
            adjoint_gradient = check.adjoint_gradient,
            finite_difference_gradient = check.finite_difference_gradient,
            absolute_error = check.absolute_error,
            relative_error = check.relative_error,
            atol = check.atol, rtol = check.rtol,
        ) for check in checks],
    )
end

function search_row(on, off, family, phi2, phi3, stage)
    row, _ = evaluate_pair(on, off, (
        family = family, tier = :search, phi2_fs2 = phi2, phi3_fs3 = phi3))
    return merge((search_stage = stage,), row)
end

function select_best(rows)
    feasible = filter(row -> row.quality_pass && row.propagation_pass, rows)
    isempty(feasible) && error("search found no feasible candidate")
    return sort(feasible; by = row -> (abs(row.centroid_shift_thz),
                                      abs(row.phi3_fs3), abs(row.phi2_fs2)))[1]
end

function search_candidates(on, off)
    phi2_domain = -6900.0:25.0:-5200.0
    coarse_specs = [(phi2, phi3) for phi2 in phi2_domain
                    for phi3 in -600_000.0:50_000.0:600_000.0]
    tod_coarse = [search_row(on, off, :gdd_tod, phi2, phi3, "tod_coarse")
                  for (phi2, phi3) in coarse_specs]
    gdd_coarse = [merge(row, (family = "gdd", search_stage = "gdd_coarse"))
                  for row in tod_coarse if row.phi3_fs3 == 0]
    gdd_center = select_best(gdd_coarse).phi2_fs2
    gdd_refine_phi2 = collect(gdd_center-25:5.0:gdd_center+25)
    gdd_refined = [search_row(on, off, :gdd, phi2, 0.0, "gdd_refine")
                   for phi2 in gdd_refine_phi2]

    refined_specs = Tuple{Float64,Float64}[]
    center = select_best(tod_coarse)
    for phi2 in center.phi2_fs2-25:5.0:center.phi2_fs2+25,
        phi3 in center.phi3_fs3-50_000:25_000.0:center.phi3_fs3+50_000
        -6900 <= phi2 <= -5200 && -600_000 <= phi3 <= 600_000 &&
            push!(refined_specs, (Float64(phi2), Float64(phi3)))
    end
    tod_refined = [merge(row, (family = "gdd_tod", search_stage = "tod_refine"))
                   for row in gdd_refined]
    evaluated_gdd_specs = Set((row.phi2_fs2, row.phi3_fs3) for row in gdd_refined)
    append!(tod_refined, [search_row(on, off, :gdd_tod, phi2, phi3, "tod_refine")
                          for (phi2, phi3) in unique(refined_specs)
                          if (phi2, phi3) ∉ evaluated_gdd_specs])

    gdd_pool = vcat(gdd_coarse, gdd_refined)
    gate_gdd = select_best(gdd_pool)
    tod_pool = vcat(tod_coarse, tod_refined)
    gate_tod = select_best(tod_pool)
    selected = (
        neutral = COMMITTED_CANDIDATES.neutral,
        gate_gdd = (family = :gdd, tier = :primary,
            phi2_fs2 = gate_gdd.phi2_fs2, phi3_fs3 = 0.0),
        gate_gdd_tod = (family = :gdd_tod, tier = :primary,
            phi2_fs2 = gate_tod.phi2_fs2, phi3_fs3 = gate_tod.phi3_fs3),
    )
    selected == COMMITTED_CANDIDATES || error(
        "deterministic search no longer reproduces committed candidates: $selected")
    return vcat(gdd_pool, tod_pool)
end

function tight_solver_pair(on, off)
    tight(problem) = begin
        fiber = deepcopy(problem.fiber)
        fiber["reltol"], fiber["abstol"] = TIGHT_SOLVER.reltol, TIGHT_SOLVER.abstol
        fiber_field_problem(problem.uω0, fiber, deepcopy(problem.sim);
                            preset = problem.metadata.preset)
    end
    pair = (tight(on), tight(off))
    raman_counterfactual_contract(pair...).pass || error(
        "tight-tolerance solver pair is not matched")
    return pair
end

"""Run the benchmark-local, separately coded scalar propagation gate."""
function scalar_crosscheck(candidates, on, off; steps=SCALAR_CROSSCHECK_STEPS)
    schedule = FiberLab._doubling_step_schedule(steps)
    length_m = Float64(on.fiber["L"])
    rows = NamedTuple[]
    evidence = Dict{String,Any}()
    tight_evidence(result, output, output_sha256) = Dict(
        "output" => output, "output_sha256" => output_sha256,
        "resolved_sha256" => result.resolved_sha256,
        "evidence_sha256" => result.evidence_sha256,
        "accepted_steps" => result.accepted_steps,
        "rhs_evaluations" => result.rhs_evaluations,
    )
    for name in propertynames(candidates)
        candidate = String(name)
        spec = getproperty(candidates, name)
        launch = on.uω0 .* cis.(reshape(phase_profile(on, spec), :, 1))
        pair = (with_launch(on, launch), with_launch(off, launch))
        tight_on, tight_off = tight_solver_pair(pair...)
        tight_on_result, tight_off_result = propagate(tight_on), propagate(tight_off)
        tight_on_output = tight_on_result.output_spectrum
        tight_off_output = tight_off_result.output_spectrum
        tight_on_sha256 = FiberLab._array_sha256(tight_on_output)
        tight_off_sha256 = FiberLab._array_sha256(tight_off_output)
        tight_on_centroid = FiberLab._scalar_reference_centroid_thz(
            tight_on_output, tight_on)
        tight_off_centroid = FiberLab._scalar_reference_centroid_thz(
            tight_off_output, tight_off)
        tight_shift = tight_on_centroid - tight_off_centroid
        levels = Dict{String,Any}()
        for step_count in schedule
            reference_on = FiberLab._scalar_rk4_output(pair[1]; steps = step_count)
            reference_off = FiberLab._scalar_rk4_output(pair[2]; steps = step_count)
            reference_on_sha256 = FiberLab._array_sha256(reference_on)
            reference_off_sha256 = FiberLab._array_sha256(reference_off)
            on_centroid = FiberLab._scalar_reference_centroid_thz(reference_on, pair[1])
            off_centroid = FiberLab._scalar_reference_centroid_thz(reference_off, pair[2])
            shift = on_centroid - off_centroid
            on_error = norm(reference_on - tight_on_output) / norm(tight_on_output)
            off_error = norm(reference_off - tight_off_output) / norm(tight_off_output)
            push!(rows, (
                candidate, method = SCALAR_CROSSCHECK_METHOD,
                steps = step_count, step_m = length_m / step_count,
                reference_on_centroid_thz = on_centroid,
                reference_off_centroid_thz = off_centroid,
                reference_centroid_shift_thz = shift,
                tight_on_centroid_thz = tight_on_centroid,
                tight_off_centroid_thz = tight_off_centroid,
                tight_centroid_shift_thz = tight_shift,
                on_relative_field_error = on_error,
                off_relative_field_error = off_error,
                centroid_shift_error_thz = abs(shift - tight_shift),
                reference_on_sha256, reference_off_sha256,
                tight_on_sha256, tight_off_sha256,
                tight_solver = TIGHT_SOLVER.method,
                tight_reltol = TIGHT_SOLVER.reltol,
                tight_abstol = TIGHT_SOLVER.abstol,
                tight_on_resolved_sha256 = tight_on_result.resolved_sha256,
                tight_off_resolved_sha256 = tight_off_result.resolved_sha256,
                tight_on_evidence_sha256 = tight_on_result.evidence_sha256,
                tight_off_evidence_sha256 = tight_off_result.evidence_sha256,
                tight_on_accepted_steps = tight_on_result.accepted_steps,
                tight_off_accepted_steps = tight_off_result.accepted_steps,
                tight_on_rhs_evaluations = tight_on_result.rhs_evaluations,
                tight_off_rhs_evaluations = tight_off_result.rhs_evaluations,
            ))
            levels[string(step_count)] = Dict(
                "step_m" => length_m / step_count,
                "raman_on_output" => reference_on,
                "raman_off_output" => reference_off,
                "raman_on_sha256" => reference_on_sha256,
                "raman_off_sha256" => reference_off_sha256,
            )
        end
        evidence[candidate] = Dict(
            "tight_raman_on" => tight_evidence(
                tight_on_result, tight_on_output, tight_on_sha256),
            "tight_raman_off" => tight_evidence(
                tight_off_result, tight_off_output, tight_off_sha256),
            "fixed_step_levels" => levels,
        )
    end

    observed_orders = [begin
        selected = sort(filter(row -> row.candidate == String(name), rows); by = row -> row.steps)
        differences = abs.(diff([row.reference_centroid_shift_thz for row in selected]))
        all(>(0), differences) || error("scalar cross-check did not resolve convergence")
        orders = log2.(differences[1:end-1] ./ differences[2:end])
        (candidate = String(name), orders = orders, minimum = minimum(orders))
    end for name in propertynames(candidates)]
    fine = filter(row -> row.steps == last(schedule), rows)
    row(name) = only(item for item in fine if item.candidate == name)
    gdd, tod = row("gate_gdd"), row("gate_gdd_tod")
    candidate_gap = abs(gdd.tight_centroid_shift_thz) -
                    abs(tod.tight_centroid_shift_thz)
    tight_ordering = isfinite(candidate_gap) && candidate_gap > 0
    max_field_error = maximum(max(item.on_relative_field_error,
                                  item.off_relative_field_error) for item in fine)
    max_shift_error = maximum(item.centroid_shift_error_thz for item in fine)
    error_fraction = tight_ordering ? max_shift_error / candidate_gap : Inf
    ordering = abs(tod.reference_centroid_shift_thz) <
               abs(gdd.reference_centroid_shift_thz)
    sign_preserved = all(sign(item.reference_centroid_shift_thz) ==
                         sign(item.tight_centroid_shift_thz) for item in fine)
    gate = (
        pass = minimum(item.minimum for item in observed_orders) >=
                   SCALAR_CROSSCHECK_GATE.min_observed_order &&
               max_field_error <= SCALAR_CROSSCHECK_GATE.max_relative_field_error &&
               max_shift_error <= SCALAR_CROSSCHECK_GATE.max_centroid_shift_error_thz &&
               error_fraction <= SCALAR_CROSSCHECK_GATE.max_error_fraction_of_candidate_gap &&
               tight_ordering && ordering && sign_preserved,
        method = SCALAR_CROSSCHECK_METHOD,
        implementation_scope = "separately coded propagation RHS and fixed-step integrator",
        shared_components = SCALAR_CROSSCHECK_SHARED_COMPONENTS,
        tight_solver = TIGHT_SOLVER,
        steps = schedule, finest_steps = last(schedule),
        order_metric = "counterfactual_centroid_shift_thz",
        observed_orders = observed_orders,
        minimum_observed_order = minimum(item.minimum for item in observed_orders),
        finest_max_relative_field_discrepancy = max_field_error,
        finest_max_centroid_shift_discrepancy_thz = max_shift_error,
        candidate_gap_thz = candidate_gap,
        finest_error_fraction_of_candidate_gap = error_fraction,
        tight_ordering_preserved = tight_ordering,
        reference_ordering_preserved = ordering,
        centroid_shift_sign_preserved = sign_preserved,
        thresholds = SCALAR_CROSSCHECK_GATE,
    )
    gate.pass || error("separately coded scalar propagation cross-check failed: $gate")
    return rows, gate, evidence
end

function grid_validation_rows(candidates, nominal_on, nominal_rows, nominal_neutral_shift)
    rows = NamedTuple[]
    for row in nominal_rows
        row.candidate == "neutral" && continue
        push!(rows, merge((
            validation_case = "selected grid", nt = sample_count(nominal_on),
            time_window_ps = Float64(nominal_on.sim["time_window"]),
            reltol = Float64(get(nominal_on.fiber, "reltol", 1e-8)),
            abstol = Float64(get(nominal_on.fiber, "abstol", 1e-6)),
            neutral_shift_thz = nominal_neutral_shift,
            nominal_neutral_shift_thz = nominal_neutral_shift,
        ), row))
    end
    cases = (
        (name = "tight ODE tolerances", pair = tight_solver_pair(problem_pair()...)),
        (name = "2048 × 10 ps", pair = problem_pair(nt = 2048, time_window_ps = 10.0)),
        (name = "2048 × 20 ps", pair = problem_pair(nt = 2048, time_window_ps = 20.0)),
        (name = "4096 × 20 ps", pair = problem_pair(nt = 4096, time_window_ps = 20.0)),
    )
    for case in cases
        on, off = case.pair
        neutral, _ = evaluate_pair(on, off, candidates.neutral)
        for name in (:gate_gdd, :gate_gdd_tod)
            row, _ = evaluate_pair(on, off, getproperty(candidates, name))
            push!(rows, merge((validation_case = case.name, candidate = String(name),
                               nt = sample_count(on),
                               time_window_ps = Float64(on.sim["time_window"]),
                               reltol = Float64(get(on.fiber, "reltol", 1e-8)),
                               abstol = Float64(get(on.fiber, "abstol", 1e-6)),
                               neutral_shift_thz = neutral.centroid_shift_thz,
                               nominal_neutral_shift_thz = nominal_neutral_shift), row,
                              (reduction_percent = reduction_percent(
                                  row.centroid_shift_thz, neutral.centroid_shift_thz),)))
        end
    end
    return rows
end

function condition_validation_rows(candidates, conditions)
    rows = NamedTuple[]
    for condition in conditions
        on, off = problem_pair(; condition.kwargs...)
        neutral, _ = evaluate_pair(on, off, candidates.neutral)
        for name in (:gate_gdd, :gate_gdd_tod)
            row, _ = evaluate_pair(on, off, getproperty(candidates, name))
            assumption = hasproperty(condition, :assumption) ? condition.assumption :
                         "single declared parameter perturbation"
            push!(rows, merge((condition = condition.name,
                               condition_assumption = assumption,
                               candidate = String(name)), row,
                              (reduction_percent = reduction_percent(
                                  row.centroid_shift_thz, neutral.centroid_shift_thz),)))
        end
    end
    return rows
end

development_stress_rows(candidates) =
    condition_validation_rows(candidates, DEVELOPMENT_STRESS_SPEC)

function predeclared_validation_rows(candidates)
    rows = condition_validation_rows(candidates, PREDECLARED_VALIDATION_SPEC)
    for condition in unique(row.condition for row in rows)
        pair = filter(row -> row.condition == condition, rows)
        gdd = only(row for row in pair if row.candidate == "gate_gdd")
        tod = only(row for row in pair if row.candidate == "gate_gdd_tod")
        all((gdd.quality_pass, tod.quality_pass, gdd.propagation_pass,
             tod.propagation_pass, abs(tod.centroid_shift_thz) < abs(gdd.centroid_shift_thz))) ||
            error("predeclared validation failed for $condition")
    end
    return rows
end

function explicit_variant(problem; gamma_scale=1.0, instantaneous=false)
    fiber = deepcopy(problem.fiber)
    fiber["γ"] .*= gamma_scale
    if instantaneous
        fraction = Float64(fiber["raman_fraction"])
        omega = 2π .* FFTW.fftfreq(sample_count(problem), 1 / problem.sim["Δt"])
        fiber["hRω"] = fraction .* cis.(-omega .* problem.sim["time_window"] / 2)
        fiber["raman_response_model"] = "instantaneous_delta_negative_control_v1"
    end
    return fiber_field_problem(problem.uω0, fiber, deepcopy(problem.sim);
                               preset = problem.metadata.preset)
end

function negative_control_rows(on, off)
    controls = NamedTuple[]
    gamma_on, gamma_off = explicit_variant(on; gamma_scale=0.0),
                          explicit_variant(off; gamma_scale=0.0)
    instant_on = explicit_variant(on; instantaneous=true)
    short_on, short_off = problem_pair(length_m = 1e-9)
    for (name, pair) in (
        ("gamma = 0", (gamma_on, gamma_off)),
        ("instantaneous response", (instant_on, off)),
        ("length = 1 nm", (short_on, short_off)),
    )
        row, _ = evaluate_pair(
            pair[1], pair[2], COMMITTED_CANDIDATES.neutral;
            allow_response_shape_change = name == "instantaneous response")
        push!(controls, merge((control = name,), row, (
            near_zero = abs(row.centroid_shift_thz) < NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ,
            max_abs_shift_thz = NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ,
        )))
    end
    all(row.near_zero for row in controls) || error("a negative control was not near zero")
    return controls
end

write_rows(path, rows) = (mkpath(dirname(path)); CSV.write(path, rows); path)

function write_selected_evidence(path, details, scalar_evidence, scalar_gate)
    evidence = Dict{String,Any}()
    for name in propertynames(COMMITTED_CANDIDATES)
        detail = details[name]
        run(result) = Dict(
            "z_m" => result.z_m, "spectra" => result.spectra,
            "resolved_sha256" => result.resolved_sha256,
            "evidence_sha256" => result.evidence_sha256,
            "accepted_steps" => result.accepted_steps,
            "rhs_evaluations" => result.rhs_evaluations,
        )
        evidence[String(name)] = Dict(
            "spec" => getproperty(COMMITTED_CANDIDATES, name),
            "phase_rad" => detail.phase, "launch_spectrum" => detail.launch,
            "raman_on" => run(detail.on), "raman_off" => run(detail.off),
            "scalar_fixed_step_crosscheck" => scalar_evidence[String(name)],
        )
    end
    problem = details[:neutral].on.problem
    frequency = Float64.(FFTW.fftfreq(
        sample_count(problem), 1 / problem.sim["Δt"]))
    scalar_metadata = Dict(
        "method" => scalar_gate.method,
        "implementation_scope" => scalar_gate.implementation_scope,
        "steps" => scalar_gate.steps,
        "tight_solver" => Dict(
            "method" => scalar_gate.tight_solver.method,
            "reltol" => scalar_gate.tight_solver.reltol,
            "abstol" => scalar_gate.tight_solver.abstol,
        ),
        "order_metric" => scalar_gate.order_metric,
        "output_axes" => ("frequency", "mode"),
        "output_frame" => "lab",
        "field_units" => "sqrt(W)",
        "shared_components" => scalar_gate.shared_components,
    )
    mkpath(dirname(path))
    JLD2.jldsave(path; schema_version = "counterfactual_selected_evidence_v2",
                 field_units = "sqrt(W)", spectra_axes = ("frequency", "mode", "z"),
                 spectra_frame = "lab", frequency_order = "raw_fftfreq",
                 frequency_units = "THz", z_units = "m",
                 evidence_hash_scheme = "FiberLab propagation_evidence_sha256_v1",
                 scalar_crosscheck_hash_scheme = "FiberLab dense_array_sha256_v1",
                 scalar_crosscheck = scalar_metadata,
                 frequency_offset_thz = frequency, candidates = evidence)
    return path
end

function numerical_validation_gate(rows)
    selected = Dict(row.candidate => row for row in rows
                    if row.validation_case == "selected grid")
    envelope = maximum(abs(abs(row.centroid_shift_thz) -
                           abs(selected[row.candidate].centroid_shift_thz)) for row in rows)
    gap = abs(selected["gate_gdd"].centroid_shift_thz) -
          abs(selected["gate_gdd_tod"].centroid_shift_thz)
    ordering = all(begin
        pair = filter(row -> row.validation_case == case, rows)
        abs(only(row.centroid_shift_thz for row in pair if row.candidate == "gate_gdd_tod")) <
            abs(only(row.centroid_shift_thz for row in pair if row.candidate == "gate_gdd"))
    end for case in unique(row.validation_case for row in rows))
    max_relative_change = maximum(abs(row.centroid_shift_thz /
        selected[row.candidate].centroid_shift_thz - 1) for row in rows)
    result = (pass = ordering &&
                     max_relative_change <= NUMERICAL_GATE.max_relative_change &&
                     gap > NUMERICAL_GATE.min_gap_to_envelope * envelope,
              ordering_preserved = ordering, max_relative_change = max_relative_change,
              numerical_envelope_thz = envelope, candidate_gap_thz = gap,
              gap_to_envelope_ratio = gap / max(envelope, eps(Float64)),
              thresholds = NUMERICAL_GATE)
    result.pass || error("post-selection numerical validation failed: $result")
    return result
end

function benchmark_provenance(on, off)
    requested_fiber = on.metadata.requested_fiber
    requested_pulse = on.metadata.requested_pulse
    requested_grid = on.metadata.requested_grid
    raman = summarize(on).raman_response
    preset = FiberLab.SINGLE_MODE_FIBER_PRESETS[on.metadata.preset]
    beta_count = requested_fiber.beta_order - 1
    length(preset.betas) <= beta_count || error(
        "preset has more dispersion coefficients than the requested beta order")
    betas = vcat(Float64.(preset.betas), zeros(beta_count - length(preset.betas)))
    length(betas) == beta_count || error("resolved beta provenance is incomplete")
    git_commit = try
        readchomp(`git -C $ROOT rev-parse HEAD`)
    catch
        "unavailable"
    end
    git_dirty = try
        !isempty(readchomp(`git -C $ROOT status --porcelain`))
    catch
        true
    end
    return Dict(
        "package_version" => string(Base.pkgversion(FiberLab)),
        "julia_version" => string(VERSION),
        "git_commit" => git_commit, "git_dirty" => git_dirty,
        "problem" => Dict(
            "preset" => String(on.metadata.preset), "regime" => "single_mode",
            "length_m" => requested_fiber.length_m,
            "average_power_w" => requested_fiber.power_w,
            "pulse_fwhm_s" => requested_pulse.fwhm_s,
            "repetition_rate_hz" => requested_pulse.rep_rate_hz,
            "pulse_shape" => String(requested_pulse.shape),
            "wavelength_m" => Float64(on.sim["λ0"]),
            "nt" => requested_grid.nt,
            "time_window_ps" => requested_grid.time_window_ps,
            "delta_t_ps" => Float64(on.sim["Δt"]),
            "beta_order" => requested_fiber.beta_order,
            "raman_fraction" => raman.fraction,
            "raman_model" => raman.model,
            "raman_tau1_fs" => raman.tau1_fs,
            "raman_tau2_fs" => raman.tau2_fs,
        ),
        "solver" => Dict("kind" => "Tsit5", "reltol" =>
            Float64(get(on.fiber, "reltol", 1e-8)), "abstol" =>
            Float64(get(on.fiber, "abstol", 1e-6))),
        "resolved_physics" => Dict(
            "gamma_w_inv_m" => vec(Float64.(on.fiber["γ"])),
            "beta_orders" => collect(2:(length(betas) + 1)),
            "beta_coefficients_si" => betas,
            "carrier_validation_policy" =>
                "carrier/grid changes hold preset dispersion and nonlinearity coefficients fixed",
        ),
        "counterfactual_contract" => raman_counterfactual_contract(on, off),
        "search" => Dict(
            "phi2_bounds_fs2" => [-6900.0, -5200.0],
            "phi2_coarse_step_fs2" => 25.0, "phi2_refine_step_fs2" => 5.0,
            "phi3_bounds_fs3" => [-600_000.0, 600_000.0],
            "phi3_coarse_step_fs3" => 50_000.0,
            "phi3_refine_step_fs3" => 25_000.0,
            "phi3_zero_included" => true,
            "claim_scope" => "best sampled feasible point in the declared search",
        ),
    )
end

function configure_plots!()
    rc = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
    for (key, value) in (
        "font.size" => 9, "axes.labelsize" => 10, "axes.titlesize" => 11,
        "xtick.labelsize" => 8, "ytick.labelsize" => 8,
        "axes.spines.top" => false, "axes.spines.right" => false,
        "axes.grid" => true, "grid.alpha" => 0.18,
        "savefig.dpi" => 360, "savefig.bbox" => "tight",
    )
        rc[key] = value
    end
    return nothing
end

function save_plot(fig, figure_dir, name)
    path = joinpath(figure_dir, name)
    fig.savefig(path, dpi = 360, bbox_inches = "tight", facecolor = "white")
    PyPlot.close(fig)
    return path
end

function label_endpoint(ax, x, y, text, color; offset=(4, 0))
    ax.annotate(text, (last(x), last(y)); xytext = offset,
                textcoords = "offset points", color = color,
                fontsize = 8, va = "center", clip_on = false)
end

function plot_search_frontier(search_rows, selected_rows, figure_dir)
    fig, axes = PyPlot.subplots(1, 2, figsize = (10.2, 3.8))
    ax, gate_ax = axes
    families = (("gdd", "GDD", COLORS.blue),
                ("gdd_tod", "GDD + TOD", COLORS.orange))
    if isempty(search_rows)
        ax.text(0.5, 0.5, "Run with --search to regenerate\nthe sampled frontier",
                ha = "center", va = "center", transform = ax.transAxes)
        gate_ax.text(0.5, 0.5, "Selection-search data not requested",
                     ha = "center", va = "center", transform = gate_ax.transAxes)
    else
        base_ok(row) = row.energy_check && row.rms_check && row.main_lobe_check &&
                       row.propagation_pass
        for (family, label, color) in families
            points = filter(row -> row.family == family && base_ok(row), search_rows)
            ax.scatter([row.peak_power_ratio for row in points],
                       [abs(row.centroid_shift_thz) for row in points];
                       s = 8, alpha = 0.12, color = color, linewidths = 0)
            thresholds = collect(0.80:0.005:0.95)
            residual = [begin
                feasible = filter(row -> row.peak_power_ratio >= threshold, points)
                isempty(feasible) ? NaN : minimum(abs(row.centroid_shift_thz) for row in feasible)
            end for threshold in thresholds]
            valid = isfinite.(residual)
            if any(valid)
                gate_ax.plot(thresholds[valid], residual[valid]; color = color, linewidth = 2)
                label_endpoint(gate_ax, thresholds[valid], residual[valid], label, color)
            end
        end
        for row in filter(row -> row.candidate in ("gate_gdd", "gate_gdd_tod"),
                          selected_rows)
            color = row.family == "gdd" ? COLORS.blue : COLORS.orange
            ax.scatter([row.peak_power_ratio], [abs(row.centroid_shift_thz)];
                       s = 44, marker = "D", color = color, edgecolors = "white",
                       linewidths = 0.7, zorder = 4)
            ax.annotate(row.family == "gdd" ? "selected GDD" : "selected GDD + TOD",
                        (row.peak_power_ratio, abs(row.centroid_shift_thz));
                        xytext = (5, row.family == "gdd" ? 7 : -10),
                        textcoords = "offset points", color = color, fontsize = 8)
        end
        ax.axvline(0.85; color = COLORS.gray, linewidth = 0.8, linestyle = "--")
        gate_ax.axvline(0.85; color = COLORS.gray, linewidth = 0.8, linestyle = "--")
        gate_ax.text(0.851, 0.98, "primary", transform = gate_ax.get_xaxis_transform(),
                     color = COLORS.gray, fontsize = 7, va = "top")
    end
    ax.set(xlabel = "Launch peak / neutral peak",
           ylabel = "Residual |ΔC| [THz]", title = "Sampled feasible search")
    gate_ax.set(xlabel = "Required launch-peak ratio",
                ylabel = "Best sampled residual |ΔC| [THz]",
                title = "Constraint-sensitivity frontier")
    ax.set_yscale("log")
    gate_ax.set_yscale("log")
    fig.suptitle("Sampled GDD + TOD lowers the residual at the declared launch gate",
                 y = 1.01, fontsize = 12)
    fig.tight_layout()
    return save_plot(fig, figure_dir, "01_search_frontier.png")
end

function shifted_bin_fraction(field, launch)
    return fftshift(vec(sum(abs2, field; dims = 2))) ./ sum(abs2, launch)
end

function plot_counterfactual_spectra(details, figure_dir; selection_reproduced)
    names = (:neutral, :gate_gdd, :gate_gdd_tod)
    selected = selection_reproduced ? "Best sampled" : "Committed"
    titles = ("Neutral launch", "$selected GDD", "$selected GDD + TOD")
    fig, axes = PyPlot.subplots(2, 3, figsize = (11.2, 6.1), sharex = true,
                               sharey = "row")
    for (column, (name, title)) in enumerate(zip(names, titles))
        detail = details[name]
        frequency = fftshift(FFTW.fftfreq(
            sample_count(detail.on.problem), 1 / detail.on.problem.sim["Δt"]))
        on_power = shifted_bin_fraction(detail.on.output_spectrum, detail.launch)
        off_power = shifted_bin_fraction(detail.off.output_spectrum, detail.launch)
        floor_value = max(maximum(on_power), maximum(off_power)) * 1e-9
        on_db = 10log10.(max.(on_power, floor_value))
        off_db = 10log10.(max.(off_power, floor_value))
        top, bottom = axes[1, column], axes[2, column]
        top.plot(frequency, on_db; color = COLORS.orange, linewidth = 1.35)
        top.plot(frequency, off_db; color = COLORS.blue, linewidth = 1.15,
                 linestyle = "--")
        top.axvline(detail.spectrum.on.centroid_thz; color = COLORS.orange,
                    linewidth = 0.8, alpha = 0.8)
        top.axvline(detail.spectrum.off.centroid_thz; color = COLORS.blue,
                    linewidth = 0.8, alpha = 0.8, linestyle = "--")
        top.set_title(@sprintf("%s\nC_on=%+.3f, C_off=%+.3f THz", title,
                              detail.spectrum.on.centroid_thz,
                              detail.spectrum.off.centroid_thz))
        difference = 1e3 .* (on_power .- off_power)
        bottom.plot(frequency, difference; color = COLORS.purple, linewidth = 1.2)
        bottom.axhline(0; color = "#999999", linewidth = 0.7)
        bottom.fill_between(frequency, 0, difference; color = COLORS.purple, alpha = 0.16)
        bottom.text(0.04, 0.90,
                    @sprintf("ΔC = %+.3f THz", detail.spectrum.model_attributed_centroid_shift_thz),
                    transform = bottom.transAxes, va = "top", fontsize = 8)
        top.set_xlim(extrema(frequency)...)
    end
    axes[1, 1].text(0.03, 0.08, "delayed response on", color = COLORS.orange,
                    transform = axes[1, 1].transAxes, fontsize = 8)
    axes[1, 1].text(0.03, 0.02, "response off", color = COLORS.blue,
                    transform = axes[1, 1].transAxes, fontsize = 8)
    axes[1, 1].set_ylabel("Output-bin / total-launch energy [dB]")
    axes[2, 1].set_ylabel("On − off / total-launch energy [×10⁻³]")
    for column in 1:3
        axes[2, column].set_xlabel("Frequency offset [THz]")
    end
    fig.suptitle("Whole-spectrum matched counterfactual (no selected-band crop)",
                 y = 1.01, fontsize = 12)
    fig.tight_layout()
    return save_plot(fig, figure_dir, "02_counterfactual_spectra.png")
end

function pair_advantage(rows, condition)
    pair = filter(row -> row.condition == condition, rows)
    gdd = only(row for row in pair if row.candidate == "gate_gdd")
    tod = only(row for row in pair if row.candidate == "gate_gdd_tod")
    return (gain = 100 * (1 - abs(tod.centroid_shift_thz) /
                          abs(gdd.centroid_shift_thz)),
            pass = gdd.quality_pass && tod.quality_pass &&
                   gdd.propagation_pass && tod.propagation_pass)
end

function plot_validation(grid_rows, stress_rows, predeclared_rows, figure_dir)
    fig, axes = PyPlot.subplots(1, 3, figsize = (13.0, 4.1))
    cases = unique(row.validation_case for row in grid_rows)
    x = collect(eachindex(cases))
    for (candidate, label, color) in (("gate_gdd", "GDD", COLORS.blue),
                                      ("gate_gdd_tod", "GDD + TOD", COLORS.orange))
        values = [abs(only(row.centroid_shift_thz for row in grid_rows
                           if row.validation_case == case && row.candidate == candidate))
                  for case in cases]
        axes[1].plot(x, values; color = color, marker = "o", linewidth = 1.4)
        label_endpoint(axes[1], x, values, label, color)
    end
    axes[1].set_xticks(x)
    axes[1].set_xticklabels(cases)
    axes[1].set(ylabel = "Residual |ΔC| [THz]", title = "Numerical validation")
    axes[1].tick_params(axis = "x", rotation = 48)

    conditions = unique(row.condition for row in stress_rows)
    stress_x = collect(eachindex(conditions))
    stress = [pair_advantage(stress_rows, condition) for condition in conditions]
    stress_values = [item.gain for item in stress]
    axes[2].plot(stress_x, stress_values; color = COLORS.orange,
                 linewidth = 1.1, alpha = 0.75)
    for (index, item) in enumerate(stress)
        axes[2].plot(index, item.gain; marker = "o", color = COLORS.orange,
                     markerfacecolor = item.pass ? COLORS.orange : "white", markersize = 5)
    end
    label_endpoint(axes[2], stress_x, stress_values, "primary gate", COLORS.orange)
    short_labels = replace.(conditions, "Raman fraction" => "fR",
                            "nonlinearity" => "γ")
    axes[2].axhline(0; color = "#999999", linewidth = 0.7)
    axes[2].set_xticks(stress_x)
    axes[2].set_xticklabels(short_labels)
    axes[2].set(ylabel = "TOD residual reduction vs GDD [%]",
                title = "Seen development stress tests")
    axes[2].tick_params(axis = "x", rotation = 52)
    axes[2].text(0.02, 0.03, "open = launch-quality failure",
                 transform = axes[2].transAxes, fontsize = 7, color = COLORS.gray)

    validation_conditions = unique(row.condition for row in predeclared_rows)
    validation_x = collect(eachindex(validation_conditions))
    validation = [pair_advantage(predeclared_rows, condition)
                  for condition in validation_conditions]
    values = [item.gain for item in validation]
    axes[3].axhline(0; color = "#999999", linewidth = 0.7)
    axes[3].plot(validation_x, values; color = COLORS.purple, marker = "o",
                 linewidth = 1.4)
    for (index, value) in enumerate(values)
        axes[3].text(index, value + 0.12, @sprintf("%.1f", value),
                     ha = "center", fontsize = 7, color = COLORS.purple)
    end
    axes[3].set_xticks(validation_x)
    axes[3].set_xticklabels(validation_conditions)
    axes[3].set(ylabel = "TOD residual reduction vs GDD [%]",
                title = "Predeclared validation set")
    axes[3].tick_params(axis = "x", rotation = 48)
    fig.suptitle("Numerical stability, seen stress tests, and predeclared checks",
                 y = 1.02, fontsize = 12)
    fig.tight_layout()
    return save_plot(fig, figure_dir, "03_validation.png")
end

function plot_scalar_crosscheck(rows, gate, figure_dir)
    fig, axes = PyPlot.subplots(1, 2, figsize = (10.6, 3.9))
    styles = (
        ("neutral", "Neutral", COLORS.gray, "o"),
        ("gate_gdd", "GDD", COLORS.blue, "s"),
        ("gate_gdd_tod", "GDD + TOD", COLORS.orange, "D"),
    )

    convergence_differences = Float64[]
    convergence_steps = Float64[]
    for (candidate, label, color, marker) in styles
        selected = sort(filter(row -> row.candidate == candidate, rows);
                        by = row -> row.step_m)
        step_m = [row.step_m for row in selected]
        shifts = [row.reference_centroid_shift_thz for row in selected]
        differences = abs.(diff(shifts))
        coarse_steps = step_m[2:end]
        append!(convergence_steps, coarse_steps)
        append!(convergence_differences, differences)
        axes[1].loglog(coarse_steps, differences; color, marker, linewidth = 1.4,
                       markersize = 4.5)
        label_endpoint(axes[1], coarse_steps, differences, label, color;
                       offset = (5, candidate == "neutral" ? 5 :
                                    candidate == "gate_gdd" ? 0 : -6))
    end
    guide_x = extrema(convergence_steps)
    guide_y0 = 0.35 * minimum(convergence_differences)
    guide_y = guide_y0 .* (collect(guide_x) ./ first(guide_x)) .^ 4
    axes[1].loglog(collect(guide_x), guide_y; color = COLORS.purple,
                   linewidth = 1.0, linestyle = "--")
    axes[1].annotate("slope 4", (last(guide_x), last(guide_y));
                     xytext = (-4, -9), textcoords = "offset points",
                     ha = "right", color = COLORS.purple, fontsize = 8)
    axes[1].text(0.03, 0.95,
                 @sprintf("minimum observed order = %.3f",
                          gate.minimum_observed_order),
                 transform = axes[1].transAxes, va = "top", fontsize = 8)
    axes[1].set(xlabel = "Fixed step h [m]",
                ylabel = "Successive |ΔCₕ − ΔCₕ⁄₂| [THz]",
                title = "Fourth-order ΔC self-convergence")

    finest = filter(row -> row.steps == gate.finest_steps, rows)
    field_errors = Float64[]
    for (index, (candidate, _, color, _)) in enumerate(styles)
        row = only(item for item in finest if item.candidate == candidate)
        x = (index - 0.08, index + 0.08)
        errors = (row.on_relative_field_error, row.off_relative_field_error)
        append!(field_errors, errors)
        axes[2].plot(collect(x), collect(errors); color, linewidth = 0.8, alpha = 0.45)
        axes[2].scatter([first(x)], [first(errors)]; color, marker = "o", s = 28,
                        label = index == 1 ? "delayed response on" : "_nolegend_")
        axes[2].scatter([last(x)], [last(errors)]; color, marker = "^", s = 32,
                        label = index == 1 ? "response off" : "_nolegend_")
    end
    field_gate = gate.thresholds.max_relative_field_error
    axes[2].axhline(field_gate; color = COLORS.purple, linewidth = 1.0,
                    linestyle = "--")
    axes[2].text(0.02, field_gate * 1.08,
                 @sprintf("acceptance gate = %.0e", field_gate),
                 transform = axes[2].get_yaxis_transform(),
                 color = COLORS.purple, fontsize = 8)
    axes[2].set_yscale("log")
    axes[2].set_ylim(minimum(field_errors) / 2, field_gate * 4)
    axes[2].set_xticks(1:3)
    axes[2].set_xticklabels(("Neutral", "GDD", "GDD + TOD"))
    axes[2].legend(frameon = false, loc = "upper right", fontsize = 7)
    axes[2].set(ylabel = "Relative L₂ field discrepancy",
                title = "Finest step vs tight Tsit5")
    axes[2].text(0.03, 0.95,
                 @sprintf("max finest-step ΔC discrepancy = %.2g THz",
                          gate.finest_max_centroid_shift_discrepancy_thz),
                 transform = axes[2].transAxes, va = "top", fontsize = 8)

    fig.suptitle("Separately coded scalar RK4-IP converges and agrees with tight Tsit5",
                 y = 0.99, fontsize = 12)
    fig.text(0.5, 0.015,
             "Shared: " * join(gate.shared_components, ", "),
             ha = "center", fontsize = 8, color = COLORS.gray)
    fig.tight_layout(rect = (0, 0.07, 1, 0.93))
    return save_plot(fig, figure_dir, "04_scalar_crosscheck.png")
end

function make_figures(search_rows, rows, details, grid_rows, stress_rows,
                      predeclared_rows, scalar_rows, scalar_gate, figure_dir;
                      selection_reproduced)
    configure_plots!()
    paths = (
        search_frontier = plot_search_frontier(search_rows, rows, figure_dir),
        counterfactual_spectra = plot_counterfactual_spectra(
            details, figure_dir; selection_reproduced),
        validation = plot_validation(grid_rows, stress_rows, predeclared_rows, figure_dir),
        scalar_crosscheck = plot_scalar_crosscheck(
            scalar_rows, scalar_gate, figure_dir),
    )
    return Dict(String(name) => path for (name, path) in pairs(paths))
end

function write_report(path, rows, selection_reproduced, numerical_gate,
                      scalar_gate, predeclared_rows, negative_rows, adjoint)
    row(name) = only(item for item in rows if item.candidate == name)
    neutral, gdd, tod = row("neutral"), row("gate_gdd"), row("gate_gdd_tod")
    selection = selection_reproduced ? "Best sampled feasible" :
                "Committed (selection search not rerun)"
    residual_gain = 100 * (1 - abs(tod.centroid_shift_thz / gdd.centroid_shift_thz))
    open(path, "w") do io
        println(io, "# Counterfactual delayed-response benchmark\n")
        println(io, "Primary endpoint: `ΔC = C_on - C_off`, the matched-model " *
                    "whole-spectrum centroid difference. It is not an experimental decomposition.\n")
        println(io, "| Candidate | ΔC [THz] | Reduction vs neutral | Launch peak ratio |")
        println(io, "|---|---:|---:|---:|")
        for item in (neutral, gdd, tod)
            println(io, @sprintf("| %s | %+.6f | %.3f%% | %.4f |", item.candidate,
                                item.centroid_shift_thz, item.reduction_percent,
                                item.peak_power_ratio))
        end
        println(io, @sprintf("\n%s GDD + TOD has %.2f%% lower residual |ΔC| than GDD.",
                            selection, residual_gain))
        println(io, "All selected launches pass the declared energy, RMS-duration, peak, " *
                    "and main-lobe gates; these are launch constraints, not output-utility claims.")
        println(io, @sprintf("Adjoint check passed (max relative error %.3g); numerical ordering passed with a %.1f× candidate-gap/envelope ratio.",
                            adjoint.max_relative_error, numerical_gate.gap_to_envelope_ratio))
        println(io, @sprintf(
            "Separately coded scalar fixed-step propagation passed (minimum observed ΔC self-convergence order %.3f; at the finest %d-step level, max relative field discrepancy %.3g and max ΔC discrepancy %.3g THz versus tight Tsit5).",
            scalar_gate.minimum_observed_order,
            scalar_gate.finest_steps,
            scalar_gate.finest_max_relative_field_discrepancy,
            scalar_gate.finest_max_centroid_shift_discrepancy_thz,
        ))
        println(io, "The finest-step cross-implementation discrepancies are not the " *
                    "broader grid/tolerance numerical envelope reported above.")
        println(io, "Predeclared cases passed: $(length(unique(
            item.condition for item in predeclared_rows))).")
        max_negative = maximum(abs(item.centroid_shift_thz) for item in negative_rows)
        println(io, @sprintf("Negative controls passed: %d/%d (max |ΔC| %.3g THz; threshold %.1g THz).",
                            count(item -> item.near_zero, negative_rows), length(negative_rows),
                            max_negative, NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ))
        println(io, "\nScope: one scalar SMF28 preset model with a single-oscillator " *
                    "delayed response. The fixed-step cross-check shares " *
                    join(scalar_gate.shared_components, ", ") *
                    "; there is no external solver, independent model construction, " *
                    "or measured fiber, launch, or device validation.")
    end
    return path
end

function main(args=ARGS)
    options = parse_args(args)
    on, off = problem_pair()
    provenance = benchmark_provenance(on, off)
    provenance["git_dirty"] && error(
        "benchmark must start from a clean Git worktree")
    require_fresh_directory(options.output_dir, "output directory")
    options.figure_dir == options.output_dir ||
        require_fresh_directory(options.figure_dir, "figure directory")
    mkpath(options.output_dir)
    mkpath(options.figure_dir)
    search_rows = options.search ? search_candidates(on, off) : NamedTuple[]
    rows, details, neutral_shift = named_candidates(on, off)
    adjoint = adjoint_gate(on, off)
    grid_rows = grid_validation_rows(
        COMMITTED_CANDIDATES, on, rows, neutral_shift)
    numerical_gate = numerical_validation_gate(grid_rows)
    scalar_rows, scalar_gate, scalar_evidence = scalar_crosscheck(
        COMMITTED_CANDIDATES, on, off)
    stress_rows = development_stress_rows(COMMITTED_CANDIDATES)
    predeclared_rows = predeclared_validation_rows(COMMITTED_CANDIDATES)
    negative_rows = negative_control_rows(on, off)
    evidence_path = write_selected_evidence(
        joinpath(options.output_dir, "selected_evidence.jld2"), details,
        scalar_evidence, scalar_gate)
    figures = make_figures(search_rows, rows, details, grid_rows, stress_rows,
                           predeclared_rows, scalar_rows, scalar_gate,
                           options.figure_dir;
                           selection_reproduced = options.search)
    relative_figures = Dict(name => relpath(path, options.output_dir)
                            for (name, path) in figures)
    evidence_sha256 = open(evidence_path) do io
        bytes2hex(SHA.sha256(io))
    end
    report_path = write_report(
        joinpath(options.output_dir, "REPORT.md"), rows, options.search,
        numerical_gate, scalar_gate, predeclared_rows, negative_rows, adjoint)

    write_rows(joinpath(options.output_dir, "candidates.csv"), rows)
    write_rows(joinpath(options.output_dir, "numerical_validation.csv"), grid_rows)
    write_rows(joinpath(options.output_dir, "scalar_crosscheck.csv"), scalar_rows)
    write_rows(joinpath(options.output_dir, "development_stress.csv"), stress_rows)
    write_rows(joinpath(options.output_dir, "predeclared_validation.csv"), predeclared_rows)
    write_rows(joinpath(options.output_dir, "negative_controls.csv"), negative_rows)
    isempty(search_rows) || write_rows(joinpath(options.output_dir, "selection_search.csv"), search_rows)

    payload = Dict(
        "schema_version" => "1.1",
        "generated_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "primary_endpoint" => "Raman-on minus Raman-off whole-spectrum centroid (THz)",
        "interpretation" => "model counterfactual; not experimental Raman decomposition",
        "selection_reproduced" => options.search,
        "provenance" => provenance,
        "quality_gate" => PRIMARY_GATE,
        "candidates" => rows, "adjoint_check" => adjoint,
        "post_selection_numerical_validation" => grid_rows,
        "numerical_validation_gate" => numerical_gate,
        "scalar_crosscheck" => scalar_rows,
        "scalar_crosscheck_gate" => scalar_gate,
        "development_stress_spec" => DEVELOPMENT_STRESS_SPEC,
        "development_stress_tests" => stress_rows,
        "predeclared_validation_spec" => PREDECLARED_VALIDATION_SPEC,
        "predeclared_validation" => predeclared_rows,
        "negative_control_max_abs_shift_thz" => NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ,
        "negative_controls" => negative_rows,
        "selected_evidence" => Dict(
            "path" => relpath(evidence_path, options.output_dir),
            "sha256" => evidence_sha256,
        ),
        "figures" => relative_figures,
        "report" => relpath(report_path, options.output_dir),
        "limitations" => [
            "scalar single-mode SMF28 model",
            "single-damped-oscillator silica Raman response",
            "no measured launch, fiber characterization, or device calibration",
            "fixed-step scalar cross-check shares " *
                join(scalar_gate.shared_components, ", "),
            "no external-package, independent model-construction, or alternative-model validation",
        ],
    )
    final_provenance = benchmark_provenance(on, off)
    final_provenance["git_commit"] == provenance["git_commit"] || error(
        "Git commit changed while the benchmark was running")
    final_provenance["git_dirty"] && error(
        "tracked or unignored files changed while the benchmark was running")
    write_json_file(joinpath(options.output_dir, "benchmark.json"), payload)
    println(@sprintf("neutral ΔC = %.9f THz", neutral_shift))
    for row in rows
        println(@sprintf("%-20s ΔC=% .9f THz  reduction=%6.2f%%  peak=%.4f",
                         row.candidate, row.centroid_shift_thz,
                         row.reduction_percent, row.peak_power_ratio))
    end
    println("adjoint check: ", adjoint.pass,
            "; max relative error = ", adjoint.max_relative_error)
    println("data written to ", options.output_dir)
    return (options = options, candidates = rows, details = details,
            grid = grid_rows, numerical_gate = numerical_gate,
            scalar_crosscheck = scalar_rows, scalar_crosscheck_gate = scalar_gate,
            stress = stress_rows, predeclared = predeclared_rows,
            negative = negative_rows, search = search_rows, figures = figures,
            evidence = evidence_path, report = report_path, adjoint = adjoint)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main()
