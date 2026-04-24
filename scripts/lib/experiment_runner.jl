"""
Thin execution layer for validated front-layer experiment specs.

This currently supports the honest first slice only:

- `single_mode`
- variables `[:phase]`
- objective `raman_band`
- solver `lbfgs`
"""

if !(@isdefined _EXPERIMENT_RUNNER_JL_LOADED)
const _EXPERIMENT_RUNNER_JL_LOADED = true

using Dates
using FFTW

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "experiment_spec.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "run_artifacts.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))

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

    report = (
        complete = isempty(missing),
        checked = checked,
        missing = missing,
        artifact_path = artifact_path,
        sidecar_path = sidecar_path,
        config_copy = config_copy,
        trust_report_path = trust_report_path,
        standard_images = standard_images,
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

_experiment_status_word(ok::Bool) = ok ? "complete" : "incomplete"

function render_experiment_completion_summary(run_bundle; io::IO=stdout)
    println(io, "Experiment run complete")
    println(io, "Output directory: ", run_bundle.output_dir)
    println(io, "Artifact: ", run_bundle.artifact_path)

    if hasproperty(run_bundle, :artifact_validation)
        report = run_bundle.artifact_validation
        println(io, "Artifact validation: ", _experiment_status_word(report.complete))
        println(io, "Standard images: ", _experiment_status_word(report.standard_images.complete))
        if !report.complete
            println(io, "Missing artifacts: ", join(report.missing, ", "))
        end
    else
        println(io, "Artifact validation: not run")
    end

    if hasproperty(run_bundle, :exported)
        println(io, "Export handoff: ", run_bundle.exported.output_dir)
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
        λ_gdd = λ_gdd,
        λ_boundary = Float64(λ_boundary),
        log_cost = spec.objective.log_cost,
    )

    if mode == :phase_only
        return (;
            common_kwargs...,
            do_plots = true,
        )
    end

    λ_energy = Float64(get(spec.objective.regularizers, :energy, 0.0))
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
                                  timestamp::AbstractString=Dates.format(now(UTC), "yyyymmdd_HHMMss"))
    validate_experiment_spec(spec)

    save_prefix = experiment_save_prefix(spec; timestamp=timestamp)
    output_dir = dirname(save_prefix)
    config_copy = copy_experiment_config_to_output(spec, output_dir)
    kwargs = supported_experiment_run_kwargs(spec)
    mode = experiment_execution_mode(spec)

    @info "Front-layer experiment run" id=spec.id maturity=spec.maturity regime=spec.problem.regime output_dir=output_dir
    if mode == :phase_only
        result, uω0, fiber, sim, band_mask, Δf = run_optimization(;
            kwargs...,
            save_prefix=save_prefix,
        )

        artifact_path = string(save_prefix, "_result.jld2")
        return _attach_artifact_validation((
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
        ))
    end

    include(joinpath(@__DIR__, "..", "research", "multivar", "multivar_optimization.jl"))
    mv_run = run_multivar_optimization(;
        kwargs...,
        save_prefix=save_prefix,
    )
    _save_multivar_standard_images(spec, mv_run)
    Δf = fftshift(FFTW.fftfreq(mv_run.sim["Nt"], 1 / mv_run.sim["Δt"]))

    return _attach_artifact_validation((
        spec = spec,
        output_dir = output_dir,
        save_prefix = save_prefix,
        config_copy = config_copy,
        artifact_path = mv_run.saved.jld2,
        sidecar_path = mv_run.saved.json,
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
    ))
end

end # include guard
