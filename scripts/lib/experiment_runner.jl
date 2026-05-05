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
using JLD2
using JSON3
using LinearAlgebra
using SHA

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "experiment_spec.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "adjoint_contracts.jl"))
include(joinpath(@__DIR__, "run_artifacts.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "multivar_artifacts.jl"))
include(joinpath(@__DIR__, "exploratory_artifacts.jl"))
include(joinpath(@__DIR__, "multivar_optimization.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))
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
    artifact_plan = experiment_artifact_plan(spec)
    trust_report_required = any(request -> request.hook == :trust_report, artifact_plan.hooks)
    if trust_report_required && spec.artifacts.write_trust_report
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

function write_longfiber_reach_diagnostic(spec, run_bundle)
    spec.problem.regime == :long_fiber || return nothing

    sim = run_bundle.sim
    fiber = run_bundle.fiber
    Δt_ps = Float64(sim["Δt"])
    Nt = Int(sim["Nt"])
    dt_fs = Δt_ps * 1e3
    time_window_ps = Δt_ps * Nt
    nyquist_THz = 0.5 / Δt_ps
    beta2 = haskey(fiber, "betas") && !isempty(fiber["betas"]) ?
        Float64(fiber["betas"][1]) :
        nothing
    gamma = haskey(fiber, "γ") ? Float64(fiber["γ"][1]) : nothing

    diagnostic = Dict{String,Any}(
        "schema_version" => "longfiber_reach_diagnostic_v1",
        "experiment_id" => spec.id,
        "regime" => string(spec.problem.regime),
        "setup_path" => "core_exact_single_mode",
        "L_fiber_m" => Float64(fiber["L"]),
        "P_cont_W" => Float64(spec.problem.P_cont),
        "Nt" => Nt,
        "time_window_ps" => time_window_ps,
        "dt_fs" => dt_fs,
        "nyquist_THz" => nyquist_THz,
        "beta2_s2_per_m" => beta2,
        "gamma_W_inv_m_inv" => gamma,
        "grid_policy" => string(spec.problem.grid_policy),
        "warnings" => String[
            "Long-fiber runs are length-scaled single-mode physics with exact-grid execution in this front layer.",
            "As L_fiber increases, inspect boundary fractions, temporal-window leakage, solver convergence, and memory/runtime before trusting conclusions.",
            "Large 10-200 m studies may need dedicated checkpointed workflows even though the config contract is the same.",
        ],
    )

    path = string(run_bundle.save_prefix, "_longfiber_reach.json")
    return write_json_file(path, diagnostic)
end

function _attach_longfiber_reach_diagnostic(run_bundle)
    path = write_longfiber_reach_diagnostic(run_bundle.spec, run_bundle)
    path === nothing && return run_bundle
    return (; run_bundle..., longfiber_reach_diagnostic = path)
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
    return write_json_file(path, manifest)
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

    fiber_name = spec.problem.regime == :multimode ?
        get_mmf_fiber_preset(spec.problem.preset).name :
        get_fiber_preset(spec.problem.preset).name

    common_kwargs = (
        fiber_preset = spec.problem.preset,
        fiber_name = fiber_name,
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

    if mode == :phase_only || mode == :long_fiber_phase
        return (;
            common_kwargs...,
            do_plots = true,
        )
    end

    if mode == :reduced_phase
        return (;
            common_kwargs...,
            basis_orders = Tuple(Int(order) for order in get(spec.controls.policy_options, :basis_orders, [2, 3])),
            coefficient_initial = Float64.(get(spec.controls.policy_options, :initial_coefficients, zeros(length(get(spec.controls.policy_options, :basis_orders, [2, 3]))))),
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
    if mode == :vector_search
        return (;
            common_kwargs...,
            variables = spec.controls.variables,
            δ_bound = 0.10,
            vector_initial = spec.solver.vector_initial,
            vector_lower = spec.solver.vector_lower,
            vector_upper = spec.solver.vector_upper,
            vector_x_tol = spec.solver.vector_x_tol,
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

function _load_scalar_extension_cost(contract)
    contract.backend == :scalar_extension || throw(ArgumentError(
        "objective `$(contract.kind)` is not a scalar extension objective"))
    source_path = _extension_source_path(contract)
    isfile(source_path) || throw(ArgumentError("objective extension source not found: $source_path"))
    Base.include(Main, source_path)
    fn = Symbol(contract.function_name)
    Base.invokelatest(isdefined, Main, fn) || throw(ArgumentError(
        "objective extension function `$(contract.function_name)` was not defined by `$source_path`"))
    return (; ext_module = Main, function_name = fn)
end

function _call_scalar_extension_cost(handle, context)
    fn = Base.invokelatest(getfield, handle.ext_module, handle.function_name)
    return Float64(Base.invokelatest(fn, context))
end

function _load_scalar_variable_builder(contract)
    contract.backend in (:scalar_phase_extension, :vector_phase_extension, :vector_control_extension) || throw(ArgumentError(
        "variable `$(contract.kind)` is not an executable scalar/vector control extension variable"))
    source_path = _variable_extension_source_path(contract)
    isfile(source_path) || throw(ArgumentError("variable extension source not found: $source_path"))
    Base.include(Main, source_path)
    fn = Symbol(contract.build_function)
    Base.invokelatest(isdefined, Main, fn) || throw(ArgumentError(
        "variable extension build function `$(contract.build_function)` was not defined by `$source_path`"))
    return (; ext_module = Main, function_name = fn)
end

function _call_scalar_variable_builder(handle, context)
    fn = Base.invokelatest(getfield, handle.ext_module, handle.function_name)
    return Base.invokelatest(fn, context)
end

function _load_variable_projection(contract)
    contract.backend in (:scalar_phase_extension, :vector_phase_extension, :vector_control_extension) || throw(ArgumentError(
        "variable `$(contract.kind)` is not an executable scalar/vector control extension variable"))
    source_path = _variable_extension_source_path(contract)
    isfile(source_path) || throw(ArgumentError("variable extension source not found: $source_path"))
    Base.include(Main, source_path)
    fn = Symbol(contract.projection_function)
    Base.invokelatest(isdefined, Main, fn) || throw(ArgumentError(
        "variable extension projection function `$(contract.projection_function)` was not defined by `$source_path`"))
    return (; ext_module = Main, function_name = fn)
end

function _call_variable_projection(handle, values)
    fn = Base.invokelatest(getfield, handle.ext_module, handle.function_name)
    return Base.invokelatest(fn, values)
end

function _synthetic_extension_context(spec; Nt::Int=32, M::Int=1)
    t = collect(range(-1.0, 1.0; length=Nt))
    spectrum = ComplexF64.(exp.(-8 .* t .^ 2))
    uω0 = repeat(reshape(spectrum, Nt, 1), 1, M)
    sim = Dict{String,Any}(
        "Nt" => Nt,
        "M" => M,
        "Δt" => 0.05,
        "ω0" => 0.0,
    )
    fiber = Dict{String,Any}(
        "L" => 0.0,
        "Dω" => zeros(Nt, M),
        "γ" => [0.0],
    )
    return (
        spec = spec,
        uω0 = uω0,
        u_shaped = copy(uω0),
        uωf = copy(uω0),
        sol = Dict{String,Any}(),
        fiber = fiber,
        sim = sim,
        amplitude = ones(Nt, M),
        phase = zeros(Nt, M),
        gain_tilt = 0.0,
        scalar_variable = isempty(spec.controls.variables) ? :unknown : only(spec.controls.variables),
        scalar_value = 0.0,
        control_values = zeros(max(1, get(first(experiment_variable_contracts(spec)), :dimension, 1))),
        scalar_controls = Dict{String,Float64}(),
        variables = spec.controls.variables,
    )
end

function _doctor_variable_values(contract)
    if contract.backend == :scalar_phase_extension
        return 0.125
    elseif contract.backend in (:vector_phase_extension, :vector_control_extension)
        return collect(range(-0.2, 0.2; length=contract.dimension))
    end
    return nothing
end

function _doctor_projection_values(projected)
    if projected isa Number
        values = [Float64(real(projected))]
    else
        values = Float64.(real.(collect(projected)))
    end
    isempty(values) && throw(ArgumentError("projection returned no values"))
    all(isfinite, values) || throw(ArgumentError("projection returned non-finite values"))
    return values
end

function runtime_check_research_extensions(spec)
    validate_experiment_spec(spec)
    errors = String[]
    warnings = String[]
    checked = String[]

    variable_contracts = experiment_variable_contracts(spec)
    for contract in variable_contracts
        contract.backend in (:scalar_phase_extension, :vector_phase_extension, :vector_control_extension) || continue
        push!(checked, "variable:$(contract.kind)")
        try
            builder = _load_scalar_variable_builder(contract)
            projector = _load_variable_projection(contract)
            raw_values = _doctor_variable_values(contract)
            projected = _call_variable_projection(projector, raw_values)
            values = _doctor_projection_values(projected)
            context = (
                variable = contract.kind,
                scalar_value = Float64(first(values)),
                control_values = values,
                sim = Dict{String,Any}("Nt" => 32, "M" => 1, "Δt" => 0.05, "ω0" => 0.0),
                Nt = 32,
                M = 1,
                uω0 = ComplexF64.(reshape(exp.(-8 .* collect(range(-1.0, 1.0; length=32)) .^ 2), 32, 1)),
                E_ref = 1.0,
            )
            if contract.backend == :scalar_phase_extension
                state = _scalar_control_state(contract.kind, Float64(first(values)), 0.25,
                    context.uω0, context.E_ref,
                    MVConfig(variables=(contract.kind,), log_cost=false),
                    context.sim, context.Nt, context.M, builder)
                size(state.φ) == (context.Nt, context.M) || throw(ArgumentError("scalar variable produced wrong phase shape"))
            else
                length(values) == contract.dimension || throw(ArgumentError(
                    "projection returned $(length(values)) values; expected $(contract.dimension)"))
                state = _vector_control_state(contract.kind, values, context.uω0, context.E_ref,
                    context.sim, context.Nt, context.M, builder)
                size(state.φ) == (context.Nt, context.M) || throw(ArgumentError("vector variable produced wrong phase shape"))
            end
        catch err
            push!(errors, "variable `$(contract.kind)` runtime check failed: $(sprint(showerror, err))")
        end
    end

    objective = experiment_objective_contract(spec)
    if objective.backend == :scalar_extension
        push!(checked, "objective:$(objective.kind)")
        try
            cost = _load_scalar_extension_cost(objective)
            J = _call_scalar_extension_cost(cost, _synthetic_extension_context(spec))
            isfinite(J) || throw(ArgumentError("objective returned non-finite cost"))
        catch err
            push!(errors, "objective `$(objective.kind)` runtime check failed: $(sprint(showerror, err))")
        end
    end

    isempty(checked) && push!(warnings, "no research extension runtime hooks selected by this config")
    return (
        complete = isempty(errors),
        checked = Tuple(checked),
        errors = Tuple(errors),
        warnings = Tuple(warnings),
    )
end

function render_runtime_extension_check(report; io::IO=stdout)
    println(io, "# Runtime Extension Doctor")
    println(io)
    println(io, "- Status: `", report.complete ? "PASS" : "FAIL", "`")
    println(io, "- Checked: `", isempty(report.checked) ? "none" : join(report.checked, ", "), "`")
    if !isempty(report.warnings)
        println(io, "- Warnings: `", join(report.warnings, ", "), "`")
    end
    if !isempty(report.errors)
        println(io, "- Errors:")
        for err in report.errors
            println(io, "  - ", err)
        end
    end
    return nothing
end

function _scalar_extension_output(uω0, physical_A, φ, fiber, sim)
    u_shaped = @. physical_A * cis(φ) * uω0
    sol = MultiModeNoise.solve_disp_mmf(u_shaped, fiber, sim)
    L = fiber["L"]
    Dω = fiber["Dω"]
    ũω_L = sol["ode_sol"](L)
    uωf = similar(uω0)
    @. uωf = cis(Dω * L) * ũω_L
    return u_shaped, uωf, sol
end

function _scalar_extension_context(;
    spec,
    uω0,
    u_shaped,
    uωf,
    sol,
    fiber,
    sim,
    physical_A,
    physical_slope,
    phase,
    scalar_variable,
    scalar_value,
    scalar_controls,
    control_values=nothing,
)
    return (
        spec = spec,
        uω0 = uω0,
        u_shaped = u_shaped,
        uωf = uωf,
        sol = sol,
        fiber = fiber,
        sim = sim,
        amplitude = physical_A,
        phase = phase,
        gain_tilt = physical_slope,
        scalar_variable = scalar_variable,
        scalar_value = scalar_value,
        control_values = isnothing(control_values) ? Float64[scalar_value] : control_values,
        scalar_controls = scalar_controls,
        variables = spec.controls.variables,
    )
end

function _normalized_quadratic_phase_basis(sim, Nt::Int, M::Int)
    frequency = FFTW.fftfreq(Nt, 1 / sim["Δt"])
    denom = max(maximum(abs.(frequency)), eps(Float64))
    basis = (frequency ./ denom) .^ 2
    basis .-= sum(basis) / length(basis)
    basis ./= max(maximum(abs.(basis)), eps(Float64))
    return repeat(reshape(basis, Nt, 1), 1, M)
end

function _scalar_control_state(
    variable::Symbol,
    scalar_value::Real,
    δ_bound::Real,
    uω0,
    E_ref::Real,
    cfg::MVConfig,
    sim,
    Nt::Int,
    M::Int,
    variable_builder=nothing,
)
    if variable == :gain_tilt
        search = _gain_tilt_search_coordinate(scalar_value, δ_bound)
        x = mv_pack(zeros(Nt, M), ones(Nt, M), E_ref, cfg, Nt, M; gain_tilt=search)
        parts = mv_unpack(x, cfg, Nt, M, E_ref)
        physical = mv_physical_amplitude(parts, cfg, sim, Nt, M)
        controls = Dict{String,Float64}("gain_tilt" => Float64(scalar_value))
        return (
            x = x,
            φ = zeros(Nt, M),
            A = physical.A,
            gain_tilt = Float64(scalar_value),
            search_value = search,
            scalar_controls = controls,
            diagnostics = Dict{Symbol,Any}(
                :gain_tilt => Float64(scalar_value),
                :gain_tilt_search => search,
            ),
        )
    elseif variable == :quadratic_phase
        basis = _normalized_quadratic_phase_basis(sim, Nt, M)
        q = Float64(scalar_value)
        controls = Dict{String,Float64}("quadratic_phase" => q)
        return (
            x = [q],
            φ = q .* basis,
            A = ones(Nt, M),
            gain_tilt = 0.0,
            search_value = q,
            scalar_controls = controls,
            diagnostics = Dict{Symbol,Any}(
                :quadratic_phase => q,
                :quadratic_phase_basis_max_abs => Float64(maximum(abs.(basis))),
            ),
        )
    else
        isnothing(variable_builder) && throw(ArgumentError(
            "bounded scalar search does not implement variable `$variable`; pass a scalar variable extension builder"))
        context = (
            variable = variable,
            scalar_value = Float64(scalar_value),
            sim = sim,
            Nt = Nt,
            M = M,
            uω0 = uω0,
            E_ref = Float64(E_ref),
        )
        built = _call_scalar_variable_builder(variable_builder, context)
        φ = hasproperty(built, :phase) ? built.phase :
            hasproperty(built, :φ) ? getproperty(built, :φ) :
            throw(ArgumentError("scalar variable extension `$variable` must return a `phase` matrix"))
        A = hasproperty(built, :amplitude) ? built.amplitude :
            hasproperty(built, :A) ? getproperty(built, :A) :
            ones(Nt, M)
        size(φ) == (Nt, M) || throw(ArgumentError(
            "scalar variable extension `$variable` returned phase with shape $(size(φ)); expected ($Nt, $M)"))
        size(A) == (Nt, M) || throw(ArgumentError(
            "scalar variable extension `$variable` returned amplitude with shape $(size(A)); expected ($Nt, $M)"))
        φ_mat = Float64.(real.(φ))
        A_mat = Float64.(real.(A))
        all(isfinite, φ_mat) || throw(ArgumentError(
            "scalar variable extension `$variable` returned non-finite phase values"))
        all(isfinite, A_mat) || throw(ArgumentError(
            "scalar variable extension `$variable` returned non-finite amplitude values"))
        controls = Dict{String,Float64}(String(variable) => Float64(scalar_value))
        if hasproperty(built, :scalar_controls)
            for (key, value) in pairs(built.scalar_controls)
                controls[String(key)] = Float64(value)
            end
        end
        diagnostics = Dict{Symbol,Any}(:extension_variable => variable)
        if hasproperty(built, :diagnostics)
            for (key, value) in pairs(built.diagnostics)
                diagnostics[Symbol(key)] = value
            end
        end
        return (
            x = [Float64(scalar_value)],
            φ = Matrix{Float64}(φ_mat),
            A = Matrix{Float64}(A_mat),
            gain_tilt = 0.0,
            search_value = Float64(scalar_value),
            scalar_controls = controls,
            diagnostics = diagnostics,
        )
    end
end

function _vector_control_state(
    variable::Symbol,
    values::AbstractVector{<:Real},
    uω0,
    E_ref::Real,
    sim,
    Nt::Int,
    M::Int,
    variable_builder,
)
    context = (
        variable = variable,
        scalar_value = Float64(first(values)),
        control_values = Float64.(values),
        sim = sim,
        Nt = Nt,
        M = M,
        uω0 = uω0,
        E_ref = Float64(E_ref),
    )
    built = _call_scalar_variable_builder(variable_builder, context)
    φ = hasproperty(built, :phase) ? built.phase :
        hasproperty(built, :φ) ? getproperty(built, :φ) :
        throw(ArgumentError("vector variable extension `$variable` must return a `phase` matrix"))
    A = hasproperty(built, :amplitude) ? built.amplitude :
        hasproperty(built, :A) ? getproperty(built, :A) :
        ones(Nt, M)
    size(φ) == (Nt, M) || throw(ArgumentError(
        "vector variable extension `$variable` returned phase with shape $(size(φ)); expected ($Nt, $M)"))
    size(A) == (Nt, M) || throw(ArgumentError(
        "vector variable extension `$variable` returned amplitude with shape $(size(A)); expected ($Nt, $M)"))
    φ_mat = Float64.(real.(φ))
    A_mat = Float64.(real.(A))
    all(isfinite, φ_mat) || throw(ArgumentError(
        "vector variable extension `$variable` returned non-finite phase values"))
    all(isfinite, A_mat) || throw(ArgumentError(
        "vector variable extension `$variable` returned non-finite amplitude values"))

    controls = Dict{String,Float64}(
        string(variable, "[", i, "]") => Float64(value)
        for (i, value) in enumerate(values)
    )
    if hasproperty(built, :scalar_controls)
        for (key, value) in pairs(built.scalar_controls)
            controls[String(key)] = Float64(value)
        end
    end
    diagnostics = Dict{Symbol,Any}(:extension_variable => variable)
    if hasproperty(built, :diagnostics)
        for (key, value) in pairs(built.diagnostics)
            diagnostics[Symbol(key)] = value
        end
    end
    return (
        x = Float64.(values),
        φ = Matrix{Float64}(φ_mat),
        A = Matrix{Float64}(A_mat),
        gain_tilt = 0.0,
        search_value = Float64(first(values)),
        control_values = Float64.(values),
        scalar_controls = controls,
        diagnostics = diagnostics,
    )
end

function _scalar_extension_regularizer_cost(uω0, u_shaped, cfg::MVConfig)
    J_reg = 0.0
    breakdown = Dict{Symbol,Any}()
    if cfg.λ_energy > 0
        E_ref = sum(abs2, uω0)
        E_shaped = sum(abs2, u_shaped)
        E_ref > 0 || throw(ArgumentError("scalar extension energy regularizer requires nonzero reference energy"))
        ratio = E_shaped / E_ref
        J_energy = cfg.λ_energy * (ratio - 1.0)^2
        J_reg += J_energy
        breakdown[:J_energy] = Float64(J_energy)
        breakdown[:energy_ratio] = Float64(ratio)
    end
    return Float64(J_reg), breakdown
end

function _scalar_extension_cost_with_regularizers(handle, context, cfg::MVConfig)
    J_extension = _call_scalar_extension_cost(handle, context)
    J_regularizer, regularizer_breakdown =
        _scalar_extension_regularizer_cost(context.uω0, context.u_shaped, cfg)
    return J_extension + J_regularizer, merge(
        Dict{Symbol,Any}(
            :J_extension => J_extension,
            :J_regularizer => J_regularizer,
        ),
        regularizer_breakdown,
    )
end

function run_scalar_gain_tilt_search(;
    spec=nothing,
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
    scalar_variable_contract = variable_contract(only(variables), :single_mode)
    scalar_extension_variable = scalar_variable_contract.backend == :scalar_phase_extension
    variables in ((:gain_tilt,), (:quadratic_phase,)) || scalar_extension_variable || throw(ArgumentError(
        "bounded scalar search currently supports variables=(:gain_tilt,), variables=(:quadratic_phase,), or one promoted scalar variable extension"))
    scalar_variable = only(variables)
    variable_builder = scalar_extension_variable ? _load_scalar_variable_builder(scalar_variable_contract) : nothing
    objective_contract = spec === nothing ? objective_contract(objective_kind, :single_mode) : experiment_objective_contract(spec)
    custom_cost = objective_contract.backend == :scalar_extension ?
        _load_scalar_extension_cost(objective_contract) :
        nothing
    objective_contract.backend in (:raman_optimization, :scalar_extension) || throw(ArgumentError(
        "bounded scalar search does not support objective backend `$(objective_contract.backend)`"))
    Float64(scalar_lower) < Float64(scalar_upper) || throw(ArgumentError(
        "scalar_lower must be less than scalar_upper"))
    max_abs = Float64(δ_bound)
    scalar_variable != :gain_tilt ||
        abs(Float64(scalar_lower)) < max_abs && abs(Float64(scalar_upper)) < max_abs ||
        throw(ArgumentError("gain-tilt scalar bounds must lie inside (-δ_bound, δ_bound)"))

    t0 = time()
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(; kwargs...)
    Nt, M = sim["Nt"], sim["M"]
    E_ref = sum(abs2, uω0)
    cfg = MVConfig(
        variables = variables,
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
    function objective_for_scalar(scalar_value)
        state = _scalar_control_state(scalar_variable, scalar_value, δ_bound, uω0, E_ref, cfg, sim, Nt, M, variable_builder)
        J, diag = if custom_cost === nothing
            scalar_variable == :gain_tilt || throw(ArgumentError(
                "built-in Raman bounded scalar search currently supports only gain_tilt; use a scalar_extension objective for `$scalar_variable`"))
            J_local, _, diag_local = cost_and_gradient_multivar(state.x, uω0, fiber, sim, band_mask, cfg; E_ref=E_ref)
            J_local, diag_local
        else
            u_shaped, uωf, sol = _scalar_extension_output(uω0, state.A, state.φ, fiber, sim)
            context = _scalar_extension_context(;
                spec = spec,
                uω0 = uω0,
                u_shaped = u_shaped,
                uωf = uωf,
                sol = sol,
                fiber = fiber,
                sim = sim,
                physical_A = state.A,
                physical_slope = state.gain_tilt,
                phase = state.φ,
                scalar_variable = scalar_variable,
                scalar_value = Float64(scalar_value),
                scalar_controls = state.scalar_controls,
            )
            J_custom, regularizer_diag = _scalar_extension_cost_with_regularizers(custom_cost, context, cfg)
            J_custom, merge(Dict{Symbol,Any}(
                :objective_backend => objective_contract.backend,
                :objective_kind => objective_contract.kind,
            ), merge(state.diagnostics, regularizer_diag))
        end
        evals[] += 1
        last_diag[] = diag
        push!(trace, Float64(J))
        return Float64(J)
    end

    result = Optim.optimize(
        objective_for_scalar,
        Float64(scalar_lower),
        Float64(scalar_upper),
        Optim.Brent();
        iterations = max_iter,
        abs_tol = Float64(scalar_x_tol),
        store_trace = false,
    )

    physical_scalar = Float64(Optim.minimizer(result))
    state_opt = _scalar_control_state(scalar_variable, physical_scalar, δ_bound, uω0, E_ref, cfg, sim, Nt, M, variable_builder)
    J_opt, diag_opt = if custom_cost === nothing
        scalar_variable == :gain_tilt || throw(ArgumentError(
            "built-in Raman bounded scalar search currently supports only gain_tilt; use a scalar_extension objective for `$scalar_variable`"))
        J_local, _, diag_local = cost_and_gradient_multivar(state_opt.x, uω0, fiber, sim, band_mask, cfg; E_ref=E_ref)
        J_local, diag_local
    else
        u_shaped, uωf, sol = _scalar_extension_output(uω0, state_opt.A, state_opt.φ, fiber, sim)
        context = _scalar_extension_context(;
            spec = spec,
            uω0 = uω0,
            u_shaped = u_shaped,
            uωf = uωf,
            sol = sol,
            fiber = fiber,
            sim = sim,
            physical_A = state_opt.A,
            physical_slope = state_opt.gain_tilt,
            phase = state_opt.φ,
            scalar_variable = scalar_variable,
            scalar_value = physical_scalar,
            scalar_controls = state_opt.scalar_controls,
        )
        J_custom, regularizer_diag = _scalar_extension_cost_with_regularizers(custom_cost, context, cfg)
        J_custom, merge(Dict{Symbol,Any}(
            :objective_backend => objective_contract.backend,
            :objective_kind => objective_contract.kind,
        ), merge(state_opt.diagnostics, regularizer_diag))
    end

    cfg_linear = deepcopy(cfg)
    cfg_linear.log_cost = false
    state_zero = _scalar_control_state(scalar_variable, 0.0, δ_bound, uω0, E_ref, cfg_linear, sim, Nt, M, variable_builder)
    J_before, J_after_lin = if custom_cost === nothing
        J0, _, _ = cost_and_gradient_multivar(state_zero.x, uω0, fiber, sim, band_mask, cfg_linear; E_ref=E_ref)
        J1, _, _ = cost_and_gradient_multivar(state_opt.x, uω0, fiber, sim, band_mask, cfg_linear; E_ref=E_ref)
        J0, J1
    else
        u_shaped0, uωf0, sol0 = _scalar_extension_output(uω0, state_zero.A, state_zero.φ, fiber, sim)
        context0 = _scalar_extension_context(;
            spec = spec,
            uω0 = uω0,
            u_shaped = u_shaped0,
            uωf = uωf0,
            sol = sol0,
            fiber = fiber,
            sim = sim,
            physical_A = state_zero.A,
            physical_slope = state_zero.gain_tilt,
            phase = state_zero.φ,
            scalar_variable = scalar_variable,
            scalar_value = 0.0,
            scalar_controls = state_zero.scalar_controls,
        )
        J0_custom, _ = _scalar_extension_cost_with_regularizers(custom_cost, context0, cfg_linear)
        J0_custom, Float64(J_opt)
    end
    ΔJ_dB = MultiModeNoise.lin_to_dB(J_after_lin) - MultiModeNoise.lin_to_dB(J_before)

    outcome = (
        result = result,
        cfg = cfg,
        scale = ones(1),
        x_opt = state_opt.x,
        φ_opt = state_opt.φ,
        A_opt = state_opt.A,
        E_opt = E_ref,
        gain_tilt_opt = state_opt.gain_tilt,
        gain_tilt_search = get(state_opt.diagnostics, :gain_tilt_search, 0.0),
        control_scalars = state_opt.scalar_controls,
        E_ref = E_ref,
        J_opt = Float64(J_opt),
        g_norm = 0.0,
        diagnostics = merge(Dict{Symbol,Any}(
            :alpha => 1.0,
            :A_extrema => extrema(state_opt.A),
            :scalar_variable => scalar_variable,
        ), diag_opt),
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
        :objective_kind => objective_contract.kind,
        :objective_backend => objective_contract.backend,
        :objective_label => objective_contract.description,
        :objective_base_term => objective_contract.backend == :scalar_extension ?
            "extension:$(objective_contract.kind)" :
            "J_physics",
        :control_scalars => state_opt.scalar_controls,
        :git_branch => get(_git_manifest_summary(), "branch", "unknown"),
        :git_commit => get(_git_manifest_summary(), "head", "unknown"),
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

function run_vector_phase_extension_search(;
    spec,
    save_prefix::AbstractString,
    variables,
    fiber_name::AbstractString="Custom",
    max_iter::Int=12,
    vector_initial,
    vector_lower,
    vector_upper,
    vector_x_tol::Real=1e-3,
    δ_bound::Real=0.10,
    λ_gdd::Real=0.0,
    λ_boundary::Real=0.0,
    λ_energy::Real=0.0,
    λ_tikhonov::Real=0.0,
    λ_tv::Real=0.0,
    λ_flat::Real=0.0,
    log_cost::Bool=false,
    objective_kind::Symbol=:temporal_peak_scalar,
    validate::Bool=false,
    solver_reltol::Real=1e-8,
    solver_f_abstol=:auto,
    solver_g_abstol=:auto,
    kwargs...,
)
    _ = (validate, solver_reltol, solver_f_abstol, solver_g_abstol, objective_kind)
    length(variables) == 1 || throw(ArgumentError(
        "vector phase extension search requires exactly one variable"))
    vector_variable = only(variables)
    variable = variable_contract(vector_variable, :single_mode)
    variable.backend in (:vector_phase_extension, :vector_control_extension) || throw(ArgumentError(
        "vector extension search requires a vector_phase_extension or vector_control_extension variable"))
    variable_builder = _load_scalar_variable_builder(variable)
    objective = experiment_objective_contract(spec)
    objective.backend == :scalar_extension || throw(ArgumentError(
        "vector phase extension search requires a scalar_extension objective"))
    custom_cost = _load_scalar_extension_cost(objective)

    x0 = Float64.(collect(vector_initial))
    lower = Float64.(collect(vector_lower))
    upper = Float64.(collect(vector_upper))
    length(x0) == length(lower) == length(upper) || throw(ArgumentError(
        "vector_initial/vector_lower/vector_upper must have matching lengths"))

    t0 = time()
    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(; kwargs...)
    Nt, M = sim["Nt"], sim["M"]
    E_ref = sum(abs2, uω0)
    cfg = MVConfig(
        variables = variables,
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
    function bounded_penalty(values)
        below = max.(lower .- values, 0.0)
        above = max.(values .- upper, 0.0)
        return sum(abs2, below) + sum(abs2, above)
    end
    function objective_for_vector(values)
        values = Float64.(values)
        penalty = bounded_penalty(values)
        if penalty > 0
            J_penalty = 1e6 + 1e6 * penalty
            push!(trace, Float64(J_penalty))
            evals[] += 1
            return Float64(J_penalty)
        end
        state = _vector_control_state(vector_variable, values, uω0, E_ref, sim, Nt, M, variable_builder)
        u_shaped, uωf, sol = _scalar_extension_output(uω0, state.A, state.φ, fiber, sim)
        context = _scalar_extension_context(;
            spec = spec,
            uω0 = uω0,
            u_shaped = u_shaped,
            uωf = uωf,
            sol = sol,
            fiber = fiber,
            sim = sim,
            physical_A = state.A,
            physical_slope = 0.0,
            phase = state.φ,
            scalar_variable = vector_variable,
            scalar_value = Float64(first(values)),
            control_values = state.control_values,
            scalar_controls = state.scalar_controls,
        )
        J_custom, regularizer_diag = _scalar_extension_cost_with_regularizers(custom_cost, context, cfg)
        _ = regularizer_diag
        evals[] += 1
        push!(trace, Float64(J_custom))
        return Float64(J_custom)
    end

    result = Optim.optimize(
        objective_for_vector,
        x0,
        Optim.NelderMead(),
        Optim.Options(iterations=max_iter, x_abstol=Float64(vector_x_tol), store_trace=false),
    )

    x_opt = clamp.(Float64.(Optim.minimizer(result)), lower, upper)
    state_opt = _vector_control_state(vector_variable, x_opt, uω0, E_ref, sim, Nt, M, variable_builder)
    u_shaped, uωf, sol = _scalar_extension_output(uω0, state_opt.A, state_opt.φ, fiber, sim)
    context = _scalar_extension_context(;
        spec = spec,
        uω0 = uω0,
        u_shaped = u_shaped,
        uωf = uωf,
        sol = sol,
        fiber = fiber,
        sim = sim,
        physical_A = state_opt.A,
        physical_slope = 0.0,
        phase = state_opt.φ,
        scalar_variable = vector_variable,
        scalar_value = Float64(first(x_opt)),
        control_values = state_opt.control_values,
        scalar_controls = state_opt.scalar_controls,
    )
    J_opt, diag_opt = _scalar_extension_cost_with_regularizers(custom_cost, context, cfg)

    zero_values = zeros(length(x0))
    state_zero = _vector_control_state(vector_variable, zero_values, uω0, E_ref, sim, Nt, M, variable_builder)
    u_shaped0, uωf0, sol0 = _scalar_extension_output(uω0, state_zero.A, state_zero.φ, fiber, sim)
    context0 = _scalar_extension_context(;
        spec = spec,
        uω0 = uω0,
        u_shaped = u_shaped0,
        uωf = uωf0,
        sol = sol0,
        fiber = fiber,
        sim = sim,
        physical_A = state_zero.A,
        physical_slope = 0.0,
        phase = state_zero.φ,
        scalar_variable = vector_variable,
        scalar_value = 0.0,
        control_values = state_zero.control_values,
        scalar_controls = state_zero.scalar_controls,
    )
    J_before, _ = _scalar_extension_cost_with_regularizers(custom_cost, context0, cfg)
    J_after_lin = Float64(J_opt)
    ΔJ_dB = MultiModeNoise.lin_to_dB(J_after_lin) - MultiModeNoise.lin_to_dB(J_before)

    outcome = (
        result = result,
        cfg = cfg,
        scale = ones(length(x0)),
        x_opt = state_opt.x,
        φ_opt = state_opt.φ,
        A_opt = state_opt.A,
        E_opt = sum(abs2, state_opt.A .* uω0),
        gain_tilt_opt = 0.0,
        gain_tilt_search = 0.0,
        control_scalars = state_opt.scalar_controls,
        E_ref = E_ref,
        J_opt = Float64(J_opt),
        g_norm = 0.0,
        diagnostics = merge(Dict{Symbol,Any}(
            :alpha => 1.0,
            :A_extrema => extrema(state_opt.A),
            :vector_variable => vector_variable,
        ), merge(state_opt.diagnostics, diag_opt)),
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
        :objective_kind => objective.kind,
        :objective_backend => objective.backend,
        :objective_label => objective.description,
        :objective_base_term => "extension:$(objective.kind)",
        :control_scalars => state_opt.scalar_controls,
        :git_branch => get(_git_manifest_summary(), "branch", "unknown"),
        :git_commit => get(_git_manifest_summary(), "head", "unknown"),
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

function _mmf_objective_variant(kind::Symbol)
    kind == :mmf_sum && return :sum
    kind == :mmf_fundamental && return :fundamental
    kind == :mmf_worst_mode && return :worst_mode
    throw(ArgumentError("unsupported MMF objective `$(kind)`"))
end

function _safe_mmf_converged(result)
    isnothing(result) && return false
    try
        return Optim.converged(result)
    catch
        return false
    end
end

function _write_mmf_per_mode_leakage_csv(path::AbstractString, trust_ref, trust_opt, mode_weights)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "mode,input_weight_abs2,reference_leakage_lin,reference_leakage_dB,optimized_leakage_lin,optimized_leakage_dB,is_fundamental,is_worst_after")
        per_ref_lin = trust_ref.cost_report.per_mode_lin
        per_ref_dB = trust_ref.cost_report.per_mode_dB
        per_opt_lin = trust_opt.cost_report.per_mode_lin
        per_opt_dB = trust_opt.cost_report.per_mode_dB
        worst_idx = argmax(per_opt_lin)
        for m in eachindex(per_opt_lin)
            println(io, join((
                m,
                Float64(abs2(mode_weights[m])),
                Float64(per_ref_lin[m]),
                Float64(per_ref_dB[m]),
                Float64(per_opt_lin[m]),
                Float64(per_opt_dB[m]),
                m == 1,
                m == worst_idx,
            ), ","))
        end
    end
    return path
end

function _write_mmf_sidecar_json(path::AbstractString; spec, artifact_path, setup, opt, trust_ref, trust_opt, variant::Symbol, wall_time_s::Real)
    payload = Dict{String,Any}(
        "schema_version" => "1.0",
        "artifact_schema" => "mmf_front_layer_v1",
        "generator" => "scripts/lib/experiment_runner.jl",
        "generated_at" => string(now()),
        "result_file" => basename(artifact_path),
        "experiment_id" => spec.id,
        "regime" => "multimode",
        "preset" => string(spec.problem.preset),
        "objective" => Dict(
            "kind" => string(spec.objective.kind),
            "variant" => string(variant),
            "log_cost" => spec.objective.log_cost,
        ),
        "grid" => Dict(
            "Nt" => size(setup.uω0, 1),
            "M" => size(setup.uω0, 2),
            "time_window_ps" => size(setup.uω0, 1) * setup.sim["Δt"],
        ),
        "fiber" => Dict(
            "name" => String(setup.preset.name),
            "L_m" => spec.problem.L_fiber,
        ),
        "pulse" => Dict(
            "P_cont_W" => spec.problem.P_cont,
            "fwhm_fs" => spec.problem.pulse_fwhm * 1e15,
            "rep_rate_Hz" => spec.problem.pulse_rep_rate,
        ),
        "outputs" => Dict(
            "phase" => Dict("storage_key" => "phi_opt", "shape" => [length(opt.φ_opt)], "units" => "rad shared across modes"),
            "mode_weights" => Dict("storage_key" => "mode_weights", "shape" => [length(setup.mode_weights)], "units" => "complex normalized launch coefficients"),
        ),
        "metrics" => Dict(
            "J_before" => trust_ref.cost_report.sum_lin,
            "J_after" => trust_opt.cost_report.sum_lin,
            "delta_J_dB" => trust_opt.cost_report.sum_dB - trust_ref.cost_report.sum_dB,
            "converged" => _safe_mmf_converged(opt.result),
            "iterations" => length(opt.J_history),
            "wall_time_s" => Float64(wall_time_s),
        ),
    )
    return write_json_file(path, _json_safe_value(payload))
end

function run_mmf_front_layer_phase_search(;
    spec,
    save_prefix::AbstractString,
    fiber_preset::Symbol,
    fiber_name::AbstractString,
    L_fiber::Real,
    P_cont::Real,
    Nt::Integer,
    time_window::Real,
    β_order::Integer,
    pulse_fwhm::Real,
    pulse_rep_rate::Real,
    pulse_shape::AbstractString,
    raman_threshold::Real,
    max_iter::Integer,
    objective_kind::Symbol,
    λ_gdd::Real,
    λ_boundary::Real,
    log_cost::Bool,
    kwargs...,
)
    _ = (β_order, kwargs)
    variant = _mmf_objective_variant(objective_kind)
    setup = setup_mmf_raman_problem(;
        preset = fiber_preset,
        L_fiber = L_fiber,
        P_cont = P_cont,
        pulse_fwhm = pulse_fwhm,
        pulse_rep_rate = pulse_rep_rate,
        pulse_shape = pulse_shape,
        Nt = Nt,
        time_window = time_window,
        raman_threshold = raman_threshold,
        auto_time_window = spec.problem.grid_policy == :auto_if_undersized,
    )

    φ0 = zeros(Float64, size(setup.uω0, 1))
    trust_ref = mmf_trust_metrics(φ0, setup)
    t0 = time()
    opt = optimize_mmf_phase(
        setup.uω0,
        setup.mode_weights,
        setup.fiber,
        setup.sim,
        setup.band_mask;
        φ0 = φ0,
        max_iter = max_iter,
        variant = variant,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
        f_calls_limit = max(1, max_iter),
        store_trace = true,
        verbose = false,
    )
    wall_time_s = time() - t0
    trust_opt = mmf_trust_metrics(opt.φ_opt, setup)

    plot_mmf_result(
        φ0,
        opt.φ_opt,
        setup,
        opt;
        save_prefix = String(save_prefix),
        title_suffix = "[$(fiber_name), L=$(L_fiber)m, P=$(P_cont)W]",
        variant = variant,
        log_cost = log_cost,
        λ_gdd = λ_gdd,
        λ_boundary = λ_boundary,
    )
    per_mode_plot = string(save_prefix, "_per_mode_spectrum.png")
    mode_resolved_plot = string(save_prefix, "_mode_resolved_spectra.png")
    isfile(per_mode_plot) && cp(per_mode_plot, mode_resolved_plot; force=true)
    leakage_csv = _write_mmf_per_mode_leakage_csv(
        string(save_prefix, "_per_mode_leakage.csv"),
        trust_ref,
        trust_opt,
        setup.mode_weights,
    )

    save_standard_set(
        opt.φ_opt,
        setup.uω0,
        setup.fiber,
        setup.sim,
        setup.band_mask,
        setup.Δf,
        setup.raman_threshold;
        tag = basename(String(save_prefix)),
        fiber_name = fiber_name,
        L_m = L_fiber,
        P_W = P_cont,
        output_dir = dirname(String(save_prefix)),
        n_z_samples = 8,
        also_unshaped = false,
    )
    # Full MMF unshaped waterfalls are expensive and currently less stable
    # through the PyPlot/PyCall stack. For the front-layer smoke artifact
    # contract, reuse the MMF total-spectrum before/after panel as the
    # unshaped comparison slot until a native MMF waterfall writer is promoted.
    unshaped_path = string(save_prefix, "_evolution_unshaped.png")
    isfile(unshaped_path) || cp(string(save_prefix, "_total_spectrum.png"), unshaped_path; force=true)

    artifact_paths = artifact_paths_for_prefix(save_prefix)
    artifact_path = artifact_paths.jld2
    sidecar_path = artifact_paths.json
    E_ref = sum(abs2, setup.uω0)
    E_opt = sum(abs2, setup.uω0 .* cis.(opt.φ_opt))
    write_jld2_file(artifact_path;
        schema_version = "1.0",
        variables_enabled = ["phase"],
        fiber_name = String(fiber_name),
        L_m = Float64(L_fiber),
        P_cont_W = Float64(P_cont),
        lambda0_nm = 1550.0,
        fwhm_fs = Float64(pulse_fwhm * 1e15),
        Nt = size(setup.uω0, 1),
        M = size(setup.uω0, 2),
        time_window_ps = Float64(size(setup.uω0, 1) * setup.sim["Δt"]),
        objective_kind = String(objective_kind),
        objective_backend = "mmf_raman_optimization",
        objective_label = experiment_objective_contract(spec).description,
        phi_opt = copy(opt.φ_opt),
        amp_opt = ones(Float64, size(setup.uω0)),
        E_opt = Float64(E_opt),
        E_ref = Float64(E_ref),
        c_opt = ComplexF64.(setup.mode_weights),
        uomega0 = ComplexF64.(setup.uω0),
        J_before = Float64(trust_ref.cost_report.sum_lin),
        J_after = Float64(trust_opt.cost_report.sum_lin),
        delta_J_dB = Float64(trust_opt.cost_report.sum_dB - trust_ref.cost_report.sum_dB),
        grad_norm = NaN,
        converged = _safe_mmf_converged(opt.result),
        iterations = length(opt.J_history),
        wall_time_s = Float64(wall_time_s),
        convergence_history = Float64.(opt.J_history),
        band_mask = Bool.(setup.band_mask),
        sim_Dt = Float64(setup.sim["Δt"]),
        sim_omega0 = Float64(setup.sim["ω0"]),
        mode_weights = ComplexF64.(setup.mode_weights),
        ref_per_mode_leakage = Float64.(trust_ref.cost_report.per_mode_lin),
        opt_per_mode_leakage = Float64.(trust_opt.cost_report.per_mode_lin),
        boundary_edge_fraction = Float64(trust_opt.boundary_edge_fraction),
        run_tag = Dates.format(now(), "yyyymmdd_HHMMss"),
    )
    _write_mmf_sidecar_json(
        sidecar_path;
        spec = spec,
        artifact_path = artifact_path,
        setup = setup,
        opt = opt,
        trust_ref = trust_ref,
        trust_opt = trust_opt,
        variant = variant,
        wall_time_s = wall_time_s,
    )

    return (
        setup = setup,
        opt = opt,
        trust_ref = trust_ref,
        trust_opt = trust_opt,
        artifact_path = artifact_path,
        sidecar_path = sidecar_path,
        saved = (jld2 = artifact_path, json = sidecar_path),
        variable_artifacts = (paths = (mode_resolved_plot, leakage_csv), hooks = (:mode_resolved_spectra, :per_mode_leakage_table)),
        J_before = trust_ref.cost_report.sum_lin,
        J_after_lin = trust_opt.cost_report.sum_lin,
        ΔJ_dB = trust_opt.cost_report.sum_dB - trust_ref.cost_report.sum_dB,
        wall_time_s = wall_time_s,
    )
end

function run_supported_experiment(spec;
                                  timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"),
                                  run_context::Symbol=:run,
                                  run_command::AbstractString="",
                                  allow_high_resource::Bool=false)
    validate_experiment_spec(spec)
    mode = experiment_execution_mode(spec)
    if mode == :long_fiber_phase && spec.verification.mode == :burst_required && !allow_high_resource
        throw(ArgumentError(
            "this long_fiber config declares high-resource verification; pass --heavy-ok on suitable compute, or create a smaller standard-verification long-fiber config"))
    elseif mode == :multimode_phase && spec.verification.mode == :burst_required && !allow_high_resource
        throw(ArgumentError(
            "this multimode config declares high-resource verification; pass --heavy-ok on suitable compute, or create a smaller standard-verification MMF config"))
    elseif mode == :amp_on_phase
        throw(ArgumentError(
            "amp_on_phase front-layer configs are validation/dry-run only for now; run the dedicated staged refinement workflow from the compute plan"))
    end

    save_prefix = experiment_save_prefix(spec; timestamp=timestamp)
    output_dir = dirname(save_prefix)
    config_copy = copy_experiment_config_to_output(spec, output_dir)
    kwargs = supported_experiment_run_kwargs(spec)

    @info "Front-layer experiment run" id=spec.id maturity=spec.maturity regime=spec.problem.regime output_dir=output_dir
    if mode == :phase_only || mode == :long_fiber_phase
        setup_fn = mode == :long_fiber_phase ? setup_raman_problem_exact : setup_raman_problem
        result, uω0, fiber, sim, band_mask, Δf = run_optimization(;
            kwargs...,
            problem_setup = setup_fn,
            save_prefix=save_prefix,
        )

        artifact_path = string(save_prefix, "_result.jld2")
        bundle = _attach_longfiber_reach_diagnostic(_attach_export_handoff(_attach_exploratory_artifacts((
            spec = spec,
            output_dir = output_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = artifact_path,
            sidecar_path = _result_sidecar_path(artifact_path),
            result = result,
            uω0 = uω0,
            fiber = fiber,
            sim = sim,
            band_mask = band_mask,
            Δf = Δf,
        ))))
        return _attach_run_manifest(_attach_artifact_validation(bundle); run_context=run_context, run_command=run_command)
    end

    if mode == :reduced_phase
        result, uω0, fiber, sim, band_mask, Δf = run_reduced_phase_optimization(;
            kwargs...,
            save_prefix=save_prefix,
        )

        artifact_path = string(save_prefix, "_result.jld2")
        bundle = _attach_exploratory_artifacts((
            spec = spec,
            output_dir = output_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = artifact_path,
            sidecar_path = _result_sidecar_path(artifact_path),
            result = result,
            uω0 = uω0,
            fiber = fiber,
            sim = sim,
            band_mask = band_mask,
            Δf = Δf,
        ))
        return _attach_run_manifest(_attach_artifact_validation(bundle); run_context=run_context, run_command=run_command)
    end

    if mode == :multimode_phase
        mmf_run = run_mmf_front_layer_phase_search(;
            kwargs...,
            spec = spec,
            save_prefix = save_prefix,
        )
        return _attach_run_manifest(_attach_artifact_validation(_attach_exploratory_artifacts((
            spec = spec,
            output_dir = output_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = mmf_run.artifact_path,
            sidecar_path = mmf_run.sidecar_path,
            variable_artifacts = mmf_run.variable_artifacts,
            setup = mmf_run.setup,
            opt = mmf_run.opt,
            trust_ref = mmf_run.trust_ref,
            trust_opt = mmf_run.trust_opt,
            saved = mmf_run.saved,
            uω0 = mmf_run.setup.uω0,
            fiber = mmf_run.setup.fiber,
            sim = mmf_run.setup.sim,
            band_mask = mmf_run.setup.band_mask,
            Δf = mmf_run.setup.Δf,
            J_before = mmf_run.J_before,
            J_after_lin = mmf_run.J_after_lin,
            ΔJ_dB = mmf_run.ΔJ_dB,
        ))); run_context=run_context, run_command=run_command)
    end

    if mode == :scalar_search
        scalar_run = run_scalar_gain_tilt_search(;
            kwargs...,
            spec=spec,
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

    if mode == :vector_search
        vector_run = run_vector_phase_extension_search(;
            kwargs...,
            spec=spec,
            save_prefix=save_prefix,
        )
        vector_bundle = (; vector_run..., save_prefix=save_prefix, output_dir=output_dir)
        _save_multivar_standard_images(spec, vector_bundle)
        Δf = fftshift(FFTW.fftfreq(vector_run.sim["Nt"], 1 / vector_run.sim["Δt"]))

        return _attach_run_manifest(_attach_artifact_validation(_attach_exploratory_artifacts((
            spec = spec,
            output_dir = output_dir,
            save_prefix = save_prefix,
            config_copy = config_copy,
            artifact_path = vector_run.saved.jld2,
            sidecar_path = vector_run.saved.json,
            variable_artifacts = write_multivar_variable_artifacts(spec, vector_bundle),
            outcome = vector_run.outcome,
            meta = vector_run.meta,
            saved = vector_run.saved,
            uω0 = vector_run.uω0,
            fiber = vector_run.fiber,
            sim = vector_run.sim,
            band_mask = vector_run.band_mask,
            Δf = Δf,
            J_before = vector_run.J_before,
            J_after_lin = vector_run.J_after_lin,
            ΔJ_dB = vector_run.ΔJ_dB,
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
