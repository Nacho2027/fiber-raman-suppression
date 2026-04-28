"""
Thin execution layer for validated front-layer experiment specs.

This currently supports the honest first slices only:

- `single_mode`
- supported variables `[:phase]`
- experimental variables `[:phase, :amplitude]`, `[:phase, :energy]`, and
  `[:phase, :amplitude, :energy]`
- objective `raman_band`
- solver `lbfgs`
"""

if !(@isdefined _EXPERIMENT_RUNNER_JL_LOADED)
const _EXPERIMENT_RUNNER_JL_LOADED = true

using Dates
using FFTW
using JSON3
using SHA

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "experiment_spec.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "run_artifacts.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "multivar_artifacts.jl"))
include(joinpath(@__DIR__, "exploratory_artifacts.jl"))
include(joinpath(@__DIR__, "..", "research", "multivar", "multivar_optimization.jl"))
include(joinpath(@__DIR__, "..", "workflows", "export_run.jl"))

function experiment_output_dir(spec;
                               timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                               create::Bool=true)
    dir = joinpath(spec.output_root, string(spec.output_tag, "_", timestamp))
    create && mkpath(dir)
    return dir
end

function experiment_save_prefix(spec;
                                timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                                create::Bool=true)
    dir = experiment_output_dir(spec; timestamp=timestamp, create=create)
    return joinpath(dir, spec.save_prefix_basename)
end

function experiment_run_directories(spec; require_artifact::Bool=true)
    isdir(spec.output_root) || return String[]
    prefix = string(spec.output_tag, "_")
    dirs = String[]
    for entry in readdir(spec.output_root; join=true)
        isdir(entry) || continue
        startswith(basename(entry), prefix) || continue
        if require_artifact
            try
                resolve_run_artifact_path(entry)
            catch
                continue
            end
        end
        push!(dirs, entry)
    end
    sort!(dirs; by=basename)
    return dirs
end

function latest_experiment_output_dir(spec; require_artifact::Bool=true)
    dirs = experiment_run_directories(spec; require_artifact=require_artifact)
    isempty(dirs) && throw(ArgumentError(
        "no completed runs found for experiment `$(spec.id)` under `$(spec.output_root)`"))
    return last(dirs)
end

function copy_experiment_config_to_output(spec, output_dir; filename::AbstractString="run_config.toml")
    target = joinpath(output_dir, filename)
    cp(spec.config_path, target; force=true)
    return target
end

function _result_sidecar_path(artifact_path::AbstractString)
    endswith(artifact_path, ".jld2") || return string(artifact_path, ".json")
    return string(first(splitext(artifact_path)), ".json")
end

function _artifact_report_error(missing)
    return ArgumentError("experiment artifact validation failed; missing: $(join(missing, ", "))")
end

"""
    validate_experiment_artifacts(run_bundle; throw_on_error=true)

Check the files that make a completed front-layer run usable by a lab user.
This validates existence and naming contracts only; it does not replace
physics/trust checks or visual inspection of the generated standard images.
"""
function validate_experiment_artifacts(run_bundle; throw_on_error::Bool=true)
    spec = run_bundle.spec
    artifact_path = abspath(String(run_bundle.artifact_path))
    save_prefix = abspath(String(run_bundle.save_prefix))
    config_copy = abspath(String(run_bundle.config_copy))
    sidecar_path = hasproperty(run_bundle, :sidecar_path) ?
        abspath(String(run_bundle.sidecar_path)) :
        abspath(_result_sidecar_path(artifact_path))
    trust_report_path = string(save_prefix, "_trust.md")

    missing = String[]
    checked = String[]
    for path in (artifact_path, sidecar_path, config_copy)
        push!(checked, path)
        isfile(path) || push!(missing, path)
    end

    mode = experiment_execution_mode(spec)
    if mode == :phase_only && spec.artifacts.write_trust_report
        push!(checked, trust_report_path)
        isfile(trust_report_path) || push!(missing, trust_report_path)
    end

    standard_images = spec.artifacts.write_standard_images ?
        standard_image_set_status(artifact_path) :
        (dir = dirname(artifact_path), present = String[], missing = String[],
         paths = Dict{String,String}(), complete = true)
    if !standard_images.complete
        append!(missing, [string(standard_images.dir, "/", suffix) for suffix in standard_images.missing])
    end

    extra_artifacts = extra_artifact_hook_file_status(spec, save_prefix)
    for path in extra_artifacts.checked
        _push_unique!(checked, path)
    end
    for path in extra_artifacts.missing
        _push_unique!(missing, path)
    end

    report = (
        complete = isempty(missing),
        checked = checked,
        missing = missing,
        artifact_path = artifact_path,
        sidecar_path = sidecar_path,
        config_copy = config_copy,
        trust_report_path = trust_report_path,
        standard_images = standard_images,
        extra_artifacts = extra_artifacts,
    )

    if !report.complete && throw_on_error
        throw(_artifact_report_error(report.missing))
    end
    return report
end

function _attach_artifact_validation(run_bundle)
    spec = run_bundle.spec
    spec.verification.artifact_validation || return run_bundle

    report = validate_experiment_artifacts(
        run_bundle;
        throw_on_error = spec.verification.block_on_failed_checks,
    )
    if !report.complete
        @warn "Front-layer artifact validation found missing outputs" missing=report.missing
    end
    return (; run_bundle..., artifact_validation = report)
end

function _attach_exploratory_artifacts(run_bundle)
    artifacts = write_exploratory_artifacts(run_bundle.spec, run_bundle)
    isempty(artifacts.paths) && return run_bundle
    return (; run_bundle..., exploratory_artifacts = artifacts)
end

function _export_report_error(missing)
    return ArgumentError("experiment export validation failed; missing/invalid: $(join(missing, ", "))")
end

"""
    validate_experiment_export_bundle(spec, exported; throw_on_error=true)

Validate the neutral phase handoff bundle shape. This is intentionally a
contract check, not a guarantee that a specific SLM can load the profile.
"""
function validate_experiment_export_bundle(spec, exported; throw_on_error::Bool=true)
    contract = export_profile_contract(spec.export_plan.profile)
    missing = String[]
    checked = String[]

    required = (
        phase_profile_csv = String(exported.phase_csv),
        metadata_json = String(exported.metadata_json),
        readme = String(exported.readme),
    )
    for path in values(required)
        abspath_path = abspath(path)
        push!(checked, abspath_path)
        isfile(abspath_path) || push!(missing, abspath_path)
    end

    source_config = joinpath(String(exported.output_dir), "source_run_config.toml")
    push!(checked, abspath(source_config))
    isfile(source_config) || push!(missing, abspath(source_config))

    if isfile(required.phase_profile_csv)
        lines = readlines(required.phase_profile_csv)
        if isempty(lines)
            push!(missing, string(required.phase_profile_csv, " header"))
        else
            header = split(first(lines), ",")
            expected = String.(collect(contract.columns))
            header == expected || push!(missing, string(required.phase_profile_csv, " header"))
        end
    end

    if isfile(required.metadata_json)
        try
            metadata = JSON3.read(read(required.metadata_json, String))
            if !hasproperty(metadata, :export_schema_version)
                push!(missing, string(required.metadata_json, " export_schema_version"))
            end
            if !hasproperty(metadata, :phase_csv) || String(metadata.phase_csv) != basename(required.phase_profile_csv)
                push!(missing, string(required.metadata_json, " phase_csv"))
            end
        catch
            push!(missing, string(required.metadata_json, " parse"))
        end
    end

    report = (
        complete = isempty(missing),
        profile = contract.profile,
        checked = checked,
        missing = missing,
        output_dir = String(exported.output_dir),
        phase_csv = required.phase_profile_csv,
        metadata_json = required.metadata_json,
        readme = required.readme,
        source_config = source_config,
    )

    if !report.complete && throw_on_error
        throw(_export_report_error(report.missing))
    end
    return report
end

function _attach_export_handoff(run_bundle)
    spec = run_bundle.spec
    experiment_export_requested(spec) || return run_bundle
    experiment_execution_mode(spec) == :phase_only || throw(ArgumentError(
        "front-layer export handoff currently supports phase-only runs"))

    export_dir = joinpath(run_bundle.output_dir, "export_handoff")
    exported = export_run_bundle(run_bundle.artifact_path, export_dir)
    report = validate_experiment_export_bundle(
        spec,
        exported;
        throw_on_error = spec.verification.block_on_failed_checks,
    )
    if !report.complete
        @warn "Front-layer export validation found missing outputs" missing=report.missing
    end
    return (; run_bundle..., exported = exported, export_validation = report)
end

function _safe_config_sha256(path::AbstractString)
    isfile(path) || return nothing
    try
        return bytes2hex(open(SHA.sha256, path))
    catch
        return nothing
    end
end

function _safe_git_output(args::Cmd)
    try
        return strip(read(args, String))
    catch
        return ""
    end
end

function _git_manifest_summary()
    root = normpath(joinpath(@__DIR__, "..", ".."))
    head = _safe_git_output(`git -C $root rev-parse --short HEAD`)
    branch = _safe_git_output(`git -C $root rev-parse --abbrev-ref HEAD`)
    status = _safe_git_output(`git -C $root status --porcelain --untracked-files=no`)
    return Dict{String,Any}(
        "head" => isempty(head) ? nothing : head,
        "branch" => isempty(branch) ? nothing : branch,
        "dirty" => !isempty(status),
        "untracked_files_checked" => false,
    )
end

function _safe_summary_metrics(artifact_path::AbstractString)
    try
        summary = canonical_run_summary(artifact_path)
        return Dict{String,Any}(
            "J_before_dB" => isfinite(summary.J_before_dB) ? summary.J_before_dB : nothing,
            "J_after_dB" => isfinite(summary.J_after_dB) ? summary.J_after_dB : nothing,
            "delta_J_dB" => isfinite(summary.delta_J_dB) ? summary.delta_J_dB : nothing,
            "converged" => ismissing(summary.converged) ? nothing : summary.converged,
            "iterations" => ismissing(summary.iterations) ? nothing : summary.iterations,
            "quality" => summary.quality,
        )
    catch
        return Dict{String,Any}()
    end
end

function _artifact_validation_manifest(run_bundle)
    if !hasproperty(run_bundle, :artifact_validation)
        return Dict{String,Any}(
            "validated" => false,
            "complete" => nothing,
            "checked" => String[],
            "missing" => String[],
            "standard_images_complete" => nothing,
            "variable_artifacts_complete" => nothing,
            "variable_artifact_hooks" => String[],
        )
    end

    report = run_bundle.artifact_validation
    extra_artifacts = report.extra_artifacts
    return Dict{String,Any}(
        "validated" => true,
        "complete" => report.complete,
        "checked" => String.(report.checked),
        "missing" => String.(report.missing),
        "standard_images_complete" => report.standard_images.complete,
        "variable_artifacts_complete" => extra_artifacts.complete,
        "variable_artifact_hooks" => String.(string.(extra_artifacts.hooks)),
    )
end

function _export_validation_manifest(run_bundle)
    if !hasproperty(run_bundle, :export_validation)
        return Dict{String,Any}(
            "requested" => experiment_export_requested(run_bundle.spec),
            "validated" => false,
            "complete" => false,
            "output_dir" => nothing,
        )
    end

    report = run_bundle.export_validation
    return Dict{String,Any}(
        "requested" => true,
        "validated" => true,
        "complete" => report.complete,
        "output_dir" => report.output_dir,
        "phase_csv" => report.phase_csv,
        "missing" => String.(report.missing),
    )
end

function _post_run_manifest_missing(missing_items)
    return [item for item in string.(collect(missing_items)) if item != "no_manifest_update"]
end

function experiment_run_manifest_data(run_bundle;
                                      run_context::Symbol=:unknown,
                                      run_command::AbstractString="")
    spec = run_bundle.spec
    check = research_config_check_report(spec)
    mode = experiment_execution_mode(spec)
    artifact_path = abspath(String(run_bundle.artifact_path))
    config_copy = abspath(String(run_bundle.config_copy))
    post_run_missing = _post_run_manifest_missing(check.missing)

    return Dict{String,Any}(
        "schema_version" => "run_manifest_v1",
        "generated_at_utc" => Dates.format(now(UTC), DateFormat("yyyy-mm-ddTHH:MM:SSZ")),
        "run_context" => string(run_context),
        "command" => isempty(run_command) ? nothing : String(run_command),
        "output_dir" => abspath(String(run_bundle.output_dir)),
        "artifact" => artifact_path,
        "sidecar" => hasproperty(run_bundle, :sidecar_path) ? abspath(String(run_bundle.sidecar_path)) : _result_sidecar_path(artifact_path),
        "config" => Dict{String,Any}(
            "id" => spec.id,
            "path" => spec.config_path,
            "copied_path" => config_copy,
            "sha256" => _safe_config_sha256(spec.config_path),
        ),
        "problem" => Dict{String,Any}(
            "regime" => string(spec.problem.regime),
            "preset" => string(spec.problem.preset),
            "L_fiber" => spec.problem.L_fiber,
            "P_cont" => spec.problem.P_cont,
            "Nt" => spec.problem.Nt,
            "time_window" => spec.problem.time_window,
        ),
        "controls" => Dict{String,Any}(
            "variables" => String.(string.(spec.controls.variables)),
            "parameterization" => string(spec.controls.parameterization),
            "policy" => string(spec.controls.policy),
        ),
        "objective" => Dict{String,Any}(
            "kind" => string(spec.objective.kind),
            "log_cost" => spec.objective.log_cost,
        ),
        "solver" => Dict{String,Any}(
            "kind" => string(spec.solver.kind),
            "max_iter" => spec.solver.max_iter,
            "validate_gradient" => spec.solver.validate_gradient,
        ),
        "execution" => Dict{String,Any}(
            "mode" => string(mode),
            "maturity" => spec.maturity,
            "confidence" => string(check.stage),
            "run_path" => string(check.run_path),
            "missing" => String.(post_run_missing),
            "compare_ready" => check.compare_ready,
        ),
        "pre_run_check" => Dict{String,Any}(
            "pass" => check.pass,
            "compare_ready" => check.compare_ready,
            "artifact_plan_implemented" => check.artifact_plan_implemented,
            "artifact_hooks" => String.(string.(check.artifact_hooks)),
            "missing" => String.(string.(check.missing)),
        ),
        "artifacts" => _artifact_validation_manifest(run_bundle),
        "export_handoff" => _export_validation_manifest(run_bundle),
        "metrics" => _safe_summary_metrics(artifact_path),
        "git" => _git_manifest_summary(),
    )
end

function write_experiment_run_manifest(run_bundle;
                                       run_context::Symbol=:unknown,
                                       run_command::AbstractString="")
    manifest = experiment_run_manifest_data(
        run_bundle;
        run_context=run_context,
        run_command=run_command,
    )
    path = joinpath(String(run_bundle.output_dir), "run_manifest.json")
    open(path, "w") do io
        JSON3.pretty(io, manifest)
    end
    return path
end

function _attach_run_manifest(run_bundle; run_context::Symbol=:unknown, run_command::AbstractString="")
    path = write_experiment_run_manifest(run_bundle; run_context=run_context, run_command=run_command)
    return (; run_bundle..., run_manifest_path = path)
end

_experiment_status_word(ok::Bool) = ok ? "complete" : "incomplete"

function render_experiment_completion_summary(run_bundle; io::IO=stdout)
    println(io, "Experiment run complete")
    println(io, "Output directory: ", run_bundle.output_dir)
    println(io, "Artifact: ", run_bundle.artifact_path)

    if hasproperty(run_bundle, :artifact_validation)
        report = run_bundle.artifact_validation
        println(io, "Artifact validation: ", _experiment_status_word(report.complete))
        println(io, "Standard images: ", _experiment_status_word(report.standard_images.complete))
        if !isempty(report.extra_artifacts.hooks)
            println(io, "Variable artifacts: ", _experiment_status_word(report.extra_artifacts.complete))
        end
        if !report.complete
            println(io, "Missing artifacts: ", join(report.missing, ", "))
        end
    else
        println(io, "Artifact validation: not run")
    end

    if hasproperty(run_bundle, :exported)
        println(io, "Export handoff: ", run_bundle.exported.output_dir)
        if hasproperty(run_bundle, :export_validation)
            println(io, "Export validation: ", _experiment_status_word(run_bundle.export_validation.complete))
        end
    end
    if hasproperty(run_bundle, :run_manifest_path)
        println(io, "Run manifest: ", run_bundle.run_manifest_path)
    end
    return nothing
end

function supported_experiment_run_kwargs(spec)
    validate_experiment_spec(spec)

    λ_gdd = get(spec.objective.regularizers, :gdd, 0.0)
    λ_boundary = get(spec.objective.regularizers, :boundary, 0.0)
    mode = experiment_execution_mode(spec)

    common_kwargs = (
        fiber_preset = spec.problem.preset,
        fiber_name = get_fiber_preset(spec.problem.preset).name,
        L_fiber = spec.problem.L_fiber,
        P_cont = spec.problem.P_cont,
        Nt = spec.problem.Nt,
        time_window = spec.problem.time_window,
        β_order = spec.problem.β_order,
        pulse_fwhm = spec.problem.pulse_fwhm,
        pulse_rep_rate = spec.problem.pulse_rep_rate,
        pulse_shape = spec.problem.pulse_shape,
        raman_threshold = spec.problem.raman_threshold,
        max_iter = spec.solver.max_iter,
        validate = spec.solver.validate_gradient || spec.verification.gradient_check,
        objective_kind = spec.objective.kind,
        λ_gdd = λ_gdd,
        λ_boundary = Float64(λ_boundary),
        log_cost = spec.objective.log_cost,
        solver_reltol = spec.solver.reltol,
        solver_f_abstol = spec.solver.f_abstol,
        solver_g_abstol = spec.solver.g_abstol,
    )

    if mode == :phase_only
        return (;
            common_kwargs...,
            do_plots = true,
        )
    end

    λ_energy = Float64(get(spec.objective.regularizers, :energy, 0.0))
    if mode == :scalar_search
        return (;
            common_kwargs...,
            variables = spec.controls.variables,
            δ_bound = 0.10,
            scalar_lower = spec.solver.scalar_lower,
            scalar_upper = spec.solver.scalar_upper,
            scalar_x_tol = spec.solver.scalar_x_tol,
            λ_energy = λ_energy,
            λ_tikhonov = Float64(get(spec.objective.regularizers, :tikhonov, 0.0)),
            λ_tv = Float64(get(spec.objective.regularizers, :tv, 0.0)),
            λ_flat = Float64(get(spec.objective.regularizers, :flat, 0.0)),
        )
    end

    return (;
        common_kwargs...,
        variables = spec.controls.variables,
        δ_bound = 0.10,
        amp_param = :tanh,
        λ_energy = λ_energy,
        λ_tikhonov = Float64(get(spec.objective.regularizers, :tikhonov, 0.0)),
        λ_tv = Float64(get(spec.objective.regularizers, :tv, 0.0)),
        λ_flat = Float64(get(spec.objective.regularizers, :flat, 0.0)),
    )
end

function _gain_tilt_search_coordinate(physical_slope::Real, δ_bound::Real)
    δ = Float64(δ_bound)
    δ > 0 || throw(ArgumentError("gain-tilt δ_bound must be positive"))
    ratio = clamp(Float64(physical_slope) / δ, -1.0 + 1e-9, 1.0 - 1e-9)
    return atanh(ratio)
end

function run_scalar_gain_tilt_search(;
    save_prefix::AbstractString,
    variables=(:gain_tilt,),
    fiber_name::AbstractString="Custom",
    max_iter::Int=12,
    δ_bound::Real=0.10,
    scalar_lower::Real=-0.09,
    scalar_upper::Real=0.09,
    scalar_x_tol::Real=1e-3,
    λ_gdd::Real=0.0,
    λ_boundary::Real=0.0,
    λ_energy::Real=0.0,
    λ_tikhonov::Real=0.0,
    λ_tv::Real=0.0,
    λ_flat::Real=0.0,
    log_cost::Bool=true,
    objective_kind::Symbol=:raman_band,
    validate::Bool=false,
    solver_reltol::Real=1e-8,
    solver_f_abstol=:auto,
    solver_g_abstol=:auto,
    kwargs...,
)
    _ = (validate, solver_reltol, solver_f_abstol, solver_g_abstol)
    variables == (:gain_tilt,) || throw(ArgumentError(
        "bounded scalar search currently supports variables=(:gain_tilt,)"))
    objective_kind == :raman_band || throw(ArgumentError(
        "bounded scalar search currently supports objective_kind=:raman_band"))
    Float64(scalar_lower) < Float64(scalar_upper) || throw(ArgumentError(
        "scalar_lower must be less than scalar_upper"))
    max_abs = Float64(δ_bound)
    abs(Float64(scalar_lower)) < max_abs && abs(Float64(scalar_upper)) < max_abs ||
        throw(ArgumentError("gain-tilt scalar bounds must lie inside (-δ_bound, δ_bound)"))

    t0 = time()
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(; kwargs...)
    Nt, M = sim["Nt"], sim["M"]
    E_ref = sum(abs2, uω0)
    cfg = MVConfig(
        variables = (:gain_tilt,),
        δ_bound = Float64(δ_bound),
        log_cost = log_cost,
        λ_gdd = Float64(λ_gdd),
        λ_boundary = Float64(λ_boundary),
        λ_energy = Float64(λ_energy),
        λ_tikhonov = Float64(λ_tikhonov),
        λ_tv = Float64(λ_tv),
        λ_flat = Float64(λ_flat),
    )

    trace = Float64[]
    evals = Ref(0)
    last_diag = Ref{Any}(nothing)
    function objective_for_slope(slope)
        search = _gain_tilt_search_coordinate(slope, δ_bound)
        x = mv_pack(zeros(Nt, M), ones(Nt, M), E_ref, cfg, Nt, M; gain_tilt=search)
        J, _, diag = cost_and_gradient_multivar(x, uω0, fiber, sim, band_mask, cfg; E_ref=E_ref)
        evals[] += 1
        last_diag[] = diag
        push!(trace, Float64(J))
        return Float64(J)
    end

    result = Optim.optimize(
        objective_for_slope,
        Float64(scalar_lower),
        Float64(scalar_upper),
        Optim.Brent();
        iterations = max_iter,
        abs_tol = Float64(scalar_x_tol),
        store_trace = false,
    )

    physical_slope = Float64(Optim.minimizer(result))
    search_opt = _gain_tilt_search_coordinate(physical_slope, δ_bound)
    x_opt = mv_pack(zeros(Nt, M), ones(Nt, M), E_ref, cfg, Nt, M; gain_tilt=search_opt)
    J_opt, _, diag_opt = cost_and_gradient_multivar(x_opt, uω0, fiber, sim, band_mask, cfg; E_ref=E_ref)
    parts = mv_unpack(x_opt, cfg, Nt, M, E_ref)
    physical = mv_physical_amplitude(parts, cfg, sim, Nt, M)

    cfg_linear = deepcopy(cfg)
    cfg_linear.log_cost = false
    x_zero = mv_pack(zeros(Nt, M), ones(Nt, M), E_ref, cfg_linear, Nt, M; gain_tilt=0.0)
    J_before, _, _ = cost_and_gradient_multivar(x_zero, uω0, fiber, sim, band_mask, cfg_linear; E_ref=E_ref)
    J_after_lin, _, _ = cost_and_gradient_multivar(x_opt, uω0, fiber, sim, band_mask, cfg_linear; E_ref=E_ref)
    ΔJ_dB = MultiModeNoise.lin_to_dB(J_after_lin) - MultiModeNoise.lin_to_dB(J_before)

    outcome = (
        result = result,
        cfg = cfg,
        scale = ones(1),
        x_opt = x_opt,
        φ_opt = zeros(Nt, M),
        A_opt = physical.A,
        E_opt = E_ref,
        gain_tilt_opt = physical_slope,
        gain_tilt_search = search_opt,
        E_ref = E_ref,
        J_opt = Float64(J_opt),
        g_norm = NaN,
        diagnostics = merge(Dict{Symbol,Any}(:alpha => 1.0, :A_extrema => extrema(physical.A)), diag_opt),
        wall_time_s = time() - t0,
        iterations = result.iterations,
    )

    _λ0 = get(kwargs, :λ0, 1550e-9)
    _P_cont = get(kwargs, :P_cont, 0.05)
    _pulse_fwhm = get(kwargs, :pulse_fwhm, 185e-15)
    _L_fiber = get(kwargs, :L_fiber, 1.0)
    _rep_rate = get(kwargs, :pulse_rep_rate, 80.5e6)
    meta = Dict{Symbol,Any}(
        :fiber_name => fiber_name,
        :L_m => _L_fiber,
        :P_cont_W => _P_cont,
        :lambda0_nm => _λ0 * 1e9,
        :fwhm_fs => _pulse_fwhm * 1e15,
        :rep_rate_Hz => _rep_rate,
        :gamma => fiber["γ"][1],
        :betas => haskey(fiber, "betas") ? fiber["betas"] : Float64[],
        :time_window_ps => Nt * sim["Δt"],
        :sim_Dt => sim["Δt"],
        :sim_omega0 => sim["ω0"],
        :J_before => J_before,
        :J_after_lin => J_after_lin,
        :delta_J_dB => ΔJ_dB,
        :band_mask => band_mask,
        :uomega0 => uω0,
        :convergence_history => trace,
        :run_tag => Dates.format(now(), "yyyymmdd_HHMMss"),
    )
    saved = save_multivar_result(save_prefix, outcome; meta=meta)

    return (outcome=outcome, meta=meta, saved=saved,
            uω0=uω0, fiber=fiber, sim=sim, band_mask=band_mask,
            J_before=J_before, J_after_lin=J_after_lin, ΔJ_dB=ΔJ_dB,
            search_trace=trace, evaluations=evals[])
end

function _save_multivar_standard_images(spec, result_bundle)
    outcome = result_bundle.outcome
    alpha = Float64(get(outcome.diagnostics, :alpha, 1.0))
    uω0_for_images = alpha .* outcome.A_opt .* result_bundle.uω0
    Δf = fftshift(FFTW.fftfreq(result_bundle.sim["Nt"], 1 / result_bundle.sim["Δt"]))

    save_standard_set(
        outcome.φ_opt,
        uω0_for_images,
        result_bundle.fiber,
        result_bundle.sim,
        result_bundle.band_mask,
        Δf,
        spec.problem.raman_threshold;
        tag = basename(result_bundle.save_prefix),
        fiber_name = get_fiber_preset(spec.problem.preset).name,
        L_m = spec.problem.L_fiber,
        P_W = spec.problem.P_cont,
        output_dir = dirname(result_bundle.save_prefix),
        lambda0_nm = Float64(get(result_bundle.meta, :lambda0_nm, 1550.0)),
        fwhm_fs = Float64(get(result_bundle.meta, :fwhm_fs, 185.0)),
    )
end

function run_supported_experiment(spec;
                                  timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                                  run_context::Symbol=:run,
                                  run_command::AbstractString="")
    validate_experiment_spec(spec)
    mode = experiment_execution_mode(spec)
    if mode == :long_fiber_phase
        throw(ArgumentError(
            "long_fiber front-layer configs are validation/dry-run only for now; stage and run long-fiber jobs on burst through the dedicated long-fiber workflow"))
    elseif mode == :multimode_phase
        throw(ArgumentError(
            "multimode front-layer configs are validation/dry-run only for now; stage and run MMF jobs through the dedicated multimode baseline workflow"))
    elseif mode == :amp_on_phase
        throw(ArgumentError(
            "amp_on_phase front-layer configs are validation/dry-run only for now; run the dedicated staged refinement workflow from the compute plan"))
    end

    save_prefix = experiment_save_prefix(spec; timestamp=timestamp)
    output_dir = dirname(save_prefix)
    config_copy = copy_experiment_config_to_output(spec, output_dir)
    kwargs = supported_experiment_run_kwargs(spec)

    @info "Front-layer experiment run" id=spec.id maturity=spec.maturity regime=spec.problem.regime output_dir=output_dir
    if mode == :phase_only
        result, uω0, fiber, sim, band_mask, Δf = run_optimization(;
            kwargs...,
            save_prefix=save_prefix,
        )

        artifact_path = string(save_prefix, "_result.jld2")
        return _attach_run_manifest(_attach_artifact_validation(_attach_export_handoff(_attach_exploratory_artifacts((
            spec = spec,
            output_dir = output_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = artifact_path,
            result = result,
            uω0 = uω0,
            fiber = fiber,
            sim = sim,
            band_mask = band_mask,
            Δf = Δf,
        )))); run_context=run_context, run_command=run_command)
    end

    if mode == :scalar_search
        scalar_run = run_scalar_gain_tilt_search(;
            kwargs...,
            save_prefix=save_prefix,
        )
        scalar_bundle = (; scalar_run..., save_prefix=save_prefix, output_dir=output_dir)
        _save_multivar_standard_images(spec, scalar_bundle)
        Δf = fftshift(FFTW.fftfreq(scalar_run.sim["Nt"], 1 / scalar_run.sim["Δt"]))

        return _attach_run_manifest(_attach_artifact_validation(_attach_exploratory_artifacts((
            spec = spec,
            output_dir = output_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = scalar_run.saved.jld2,
            sidecar_path = scalar_run.saved.json,
            variable_artifacts = write_multivar_variable_artifacts(spec, scalar_bundle),
            outcome = scalar_run.outcome,
            meta = scalar_run.meta,
            saved = scalar_run.saved,
            uω0 = scalar_run.uω0,
            fiber = scalar_run.fiber,
            sim = scalar_run.sim,
            band_mask = scalar_run.band_mask,
            Δf = Δf,
            J_before = scalar_run.J_before,
            J_after_lin = scalar_run.J_after_lin,
            ΔJ_dB = scalar_run.ΔJ_dB,
        ))); run_context=run_context, run_command=run_command)
    end

    mv_run = run_multivar_optimization(;
        kwargs...,
        save_prefix=save_prefix,
    )
    mv_bundle = (; mv_run..., save_prefix=save_prefix, output_dir=output_dir)
    _save_multivar_standard_images(spec, mv_bundle)
    Δf = fftshift(FFTW.fftfreq(mv_run.sim["Nt"], 1 / mv_run.sim["Δt"]))

    return _attach_run_manifest(_attach_artifact_validation(_attach_exploratory_artifacts((
        spec = spec,
        output_dir = output_dir,
        save_prefix = save_prefix,
        config_copy = config_copy,
        artifact_path = mv_run.saved.jld2,
        sidecar_path = mv_run.saved.json,
        variable_artifacts = write_multivar_variable_artifacts(spec, mv_bundle),
        outcome = mv_run.outcome,
        meta = mv_run.meta,
        saved = mv_run.saved,
        uω0 = mv_run.uω0,
        fiber = mv_run.fiber,
        sim = mv_run.sim,
        band_mask = mv_run.band_mask,
        Δf = Δf,
        J_before = mv_run.J_before,
        J_after_lin = mv_run.J_after_lin,
        ΔJ_dB = mv_run.ΔJ_dB,
    ))); run_context=run_context, run_command=run_command)
end

end # include guard
