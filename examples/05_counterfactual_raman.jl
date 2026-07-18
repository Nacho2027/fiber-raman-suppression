#!/usr/bin/env julia

using CSV
using Dates
using FFTW
using FiberLab
using JLD2
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
const NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ = 1e-7
const COLORS = (blue = "#0072B2", orange = "#D55E00",
                purple = "#CC79A7", gray = "#666666")

const COMMITTED_CANDIDATES = (
    neutral = (family = :neutral, tier = :reference, phi2_fs2 = 0.0, phi3_fs3 = 0.0),
    gate_gdd = (family = :gdd, tier = :primary, phi2_fs2 = -6030.0, phi3_fs3 = 0.0),
    gate_gdd_tod = (family = :gdd_tod, tier = :primary,
                    phi2_fs2 = -6550.0, phi3_fs3 = -350_000.0),
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

function strict_solver_pair(on, off)
    strict(problem) = begin
        fiber = deepcopy(problem.fiber)
        fiber["reltol"], fiber["abstol"] = 1e-10, 1e-9
        fiber_field_problem(problem.uω0, fiber, deepcopy(problem.sim);
                            preset = problem.metadata.preset)
    end
    pair = (strict(on), strict(off))
    raman_counterfactual_contract(pair...).pass || error("strict solver pair is not matched")
    return pair
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
        (name = "strict ODE tolerances", pair = strict_solver_pair(problem_pair()...)),
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

function write_selected_evidence(path, details)
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
        )
    end
    problem = details[:neutral].on.problem
    frequency = Float64.(FFTW.fftfreq(
        sample_count(problem), 1 / problem.sim["Δt"]))
    mkpath(dirname(path))
    JLD2.jldsave(path; schema_version = "counterfactual_selected_evidence_v1",
                 field_units = "sqrt(W)", spectra_axes = ("frequency", "mode", "z"),
                 spectra_frame = "lab", frequency_order = "raw_fftfreq",
                 frequency_units = "THz", z_units = "m",
                 evidence_hash_scheme = "FiberLab propagation_evidence_sha256_v1",
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
    betas = Float64.(get(on.fiber, "betas", Float64[]))
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
    axes[1].set(xticks = x, xticklabels = cases,
                ylabel = "Residual |ΔC| [THz]", title = "Numerical validation")
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
    axes[2].set(xticks = stress_x, xticklabels = short_labels,
                ylabel = "TOD residual reduction vs GDD [%]",
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
    axes[3].set(xticks = validation_x, xticklabels = validation_conditions,
                ylabel = "TOD residual reduction vs GDD [%]",
                title = "Predeclared validation set")
    axes[3].tick_params(axis = "x", rotation = 48)
    fig.suptitle("Numerical stability, seen stress tests, and predeclared checks",
                 y = 1.02, fontsize = 12)
    fig.tight_layout()
    return save_plot(fig, figure_dir, "03_validation.png")
end

function make_figures(search_rows, rows, details, grid_rows, stress_rows,
                      predeclared_rows, figure_dir; selection_reproduced)
    configure_plots!()
    paths = (
        search_frontier = plot_search_frontier(search_rows, rows, figure_dir),
        counterfactual_spectra = plot_counterfactual_spectra(
            details, figure_dir; selection_reproduced),
        validation = plot_validation(grid_rows, stress_rows, predeclared_rows, figure_dir),
    )
    return Dict(String(name) => path for (name, path) in pairs(paths))
end

function write_report(path, rows, selection_reproduced, numerical_gate,
                      predeclared_rows, negative_rows, adjoint)
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
        println(io, "Predeclared cases passed: $(length(unique(
            item.condition for item in predeclared_rows))).")
        max_negative = maximum(abs(item.centroid_shift_thz) for item in negative_rows)
        println(io, @sprintf("Negative controls passed: %d/%d (max |ΔC| %.3g THz; threshold %.1g THz).",
                            count(item -> item.near_zero, negative_rows), length(negative_rows),
                            max_negative, NEGATIVE_CONTROL_MAX_ABS_SHIFT_THZ))
        println(io, "\nScope: one scalar SMF28 preset model with a single-oscillator " *
                    "delayed response; no measured fiber, launch, device, or independent solver.")
    end
    return path
end

function main(args=ARGS)
    options = parse_args(args)
    mkpath(options.output_dir)
    mkpath(options.figure_dir)
    on, off = problem_pair()
    search_rows = options.search ? search_candidates(on, off) : NamedTuple[]
    rows, details, neutral_shift = named_candidates(on, off)
    adjoint = adjoint_gate(on, off)
    grid_rows = grid_validation_rows(
        COMMITTED_CANDIDATES, on, rows, neutral_shift)
    numerical_gate = numerical_validation_gate(grid_rows)
    stress_rows = development_stress_rows(COMMITTED_CANDIDATES)
    predeclared_rows = predeclared_validation_rows(COMMITTED_CANDIDATES)
    negative_rows = negative_control_rows(on, off)
    evidence_path = write_selected_evidence(
        joinpath(options.output_dir, "selected_evidence.jld2"), details)
    figures = make_figures(search_rows, rows, details, grid_rows, stress_rows,
                           predeclared_rows, options.figure_dir;
                           selection_reproduced = options.search)
    relative_figures = Dict(name => relpath(path, options.output_dir)
                            for (name, path) in figures)
    evidence_sha256 = open(evidence_path) do io
        bytes2hex(SHA.sha256(io))
    end
    report_path = write_report(joinpath(options.output_dir, "REPORT.md"), rows,
                               options.search, numerical_gate, predeclared_rows,
                               negative_rows, adjoint)

    write_rows(joinpath(options.output_dir, "candidates.csv"), rows)
    write_rows(joinpath(options.output_dir, "numerical_validation.csv"), grid_rows)
    write_rows(joinpath(options.output_dir, "development_stress.csv"), stress_rows)
    write_rows(joinpath(options.output_dir, "predeclared_validation.csv"), predeclared_rows)
    write_rows(joinpath(options.output_dir, "negative_controls.csv"), negative_rows)
    isempty(search_rows) || write_rows(joinpath(options.output_dir, "selection_search.csv"), search_rows)

    payload = Dict(
        "schema_version" => "1.0",
        "generated_utc" => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        "primary_endpoint" => "Raman-on minus Raman-off whole-spectrum centroid (THz)",
        "interpretation" => "model counterfactual; not experimental Raman decomposition",
        "selection_reproduced" => options.search,
        "provenance" => benchmark_provenance(on, off),
        "quality_gate" => PRIMARY_GATE,
        "candidates" => rows, "adjoint_check" => adjoint,
        "post_selection_numerical_validation" => grid_rows,
        "numerical_validation_gate" => numerical_gate,
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
            "no independent GNLSE cross-solver validation",
        ],
    )
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
            stress = stress_rows, predeclared = predeclared_rows,
            negative = negative_rows, search = search_rows, figures = figures,
            evidence = evidence_path, report = report_path, adjoint = adjoint)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main()
