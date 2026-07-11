function save_standard_set end
function plot_merged_evolution end

const _STANDARD_IMAGE_HELPERS_LOADED = Ref(false)

"""
    standard_figures(problem, result; output_dir=nothing, tag=nothing, kwargs...)

Write the lab-standard post-run figure set for a native FiberLab optimization
result. The renderer is intentionally problem/result based: it uses the decoded
physical controls from `result`, applies them to `problem.uω0`, and then calls
the same standard-image path used by the historical optimization drivers.
"""
function standard_figures(problem::FiberFieldProblem,
                          result::NativeAdjointResult;
                          output_dir::Union{Nothing,AbstractString}=nothing,
                          tag::Union{Nothing,AbstractString}=nothing,
                          n_z_samples::Int=32,
                          also_unshaped::Bool=true)
    n_z_samples >= 2 || throw(ArgumentError("standard_figures requires at least two z samples"))
    run_source = result.backend.run_source
    run_source isa NativeRunSource || throw(ArgumentError(
        "standard_figures requires a result produced by solve(problem, ...)"))
    source_problem = run_source.problem
    _resolved_problem_signature(source_problem) == run_source.snapshot_sha256 ||
        throw(ArgumentError("the result's problem snapshot was mutated after execution"))
    expected_metadata = _execution_metadata_from_problem(source_problem).source_metadata
    expected_metadata = merge(
        expected_metadata,
        (snapshot_sha256 = run_source.snapshot_sha256,),
    )
    run_source.metadata == expected_metadata || throw(ArgumentError(
        "result source metadata does not match its problem snapshot"))
    result.plan.experiment.fiber == run_source.metadata.requested_fiber &&
        result.plan.experiment.pulse == run_source.metadata.requested_pulse &&
        result.plan.experiment.grid == run_source.metadata.resolved_grid ||
        throw(ArgumentError("result experiment metadata does not match its model source"))
    _objective_problem_sha256(result.final_step.objective) == run_source.snapshot_sha256 ||
        throw(ArgumentError("standard_figures requires a problem-bound objective"))
    _same_resolved_problem(problem, source_problem) || throw(ArgumentError(
        "the supplied problem does not match the problem snapshot used by this result"))
    problem = source_problem
    target_dir = output_dir === nothing ?
        _standard_output_dir(result) :
        String(output_dir)
    target_tag = tag === nothing ? _standard_tag(result) : String(tag)

    fields = _single_mode_fields(decoded_final(result), problem)
    phase = Matrix{Float64}(fields.phase)
    base_field = Matrix{ComplexF64}(fields.alpha .* fields.amplitude .* problem.uω0)
    objective_kind = result.final_step.objective.name
    band_mask = _standard_band_mask(problem, objective_kind)
    raman_threshold = _standard_raman_threshold(problem)
    lambda0_nm = Float64(problem.sim["λ0"]) * 1e9
    fwhm_fs = _standard_pulse(problem).fwhm_s * 1e15

    _ensure_standard_image_helpers_loaded()
    standard_paths = Base.invokelatest(
        save_standard_set,
        phase,
        base_field,
        problem.fiber,
        problem.sim,
        band_mask,
        fftshift(FFTW.fftfreq(sample_count(problem), 1 / problem.sim["Δt"])),
        raman_threshold;
        tag = target_tag,
        fiber_name = String(problem.metadata.preset),
        L_m = Float64(problem.fiber["L"]),
        P_W = _standard_reference_power(problem),
        output_dir = target_dir,
        lambda0_nm = lambda0_nm,
        fwhm_fs = fwhm_fs,
        n_z_samples = n_z_samples,
        also_unshaped = also_unshaped,
        objective_kind = objective_kind,
    )
    comparison_path = _write_evolution_comparison(
        phase,
        base_field,
        problem;
        output_dir = target_dir,
        tag = target_tag,
        n_z_samples = n_z_samples,
        lambda0_nm = lambda0_nm,
        fwhm_fs = fwhm_fs,
    )
    summary_path = _write_metric_summary(result; output_dir = target_dir, tag = target_tag)
    paths = (
        metric_summary = summary_path,
        evolution_comparison = comparison_path,
        phase_profile = standard_paths.phase_profile,
        evolution = standard_paths.evolution,
        phase_diagnostic = standard_paths.phase_diagnostic,
    )
    haskey(pairs(standard_paths), :evolution_unshaped) || return paths
    return merge(paths, (evolution_unshaped = standard_paths.evolution_unshaped,))
end

function _same_resolved_problem(left::FiberFieldProblem, right::FiberFieldProblem)
    return left.metadata == right.metadata &&
        left.uω0 == right.uω0 &&
        left.fiber == right.fiber &&
        left.sim == right.sim &&
        left.band_mask == right.band_mask &&
        left.frequency_offset_thz == right.frequency_offset_thz &&
        left.raman_threshold_thz == right.raman_threshold_thz
end

"""
    display_report(report)

Display every PNG path in a report NamedTuple inline when the frontend supports
rich display, then return the report unchanged. This is intended for notebooks;
non-notebook Julia sessions still get the printed paths.
"""
function display_report(report::NamedTuple)
    for (name, path) in pairs(report)
        println("$(name): $(path)")
        if path isa AbstractString && isfile(path) && lowercase(splitext(path)[2]) == ".png"
            display("image/png", read(path))
        end
    end
    return report
end

function _standard_output_dir(result::NativeAdjointResult)
    result.output_dir !== nothing && return result.output_dir
    return joinpath("results", "fiberlab", _standard_tag(result), "standard_figures")
end

function _standard_tag(result::NativeAdjointResult)
    id = result.plan.experiment.id
    return isempty(id) ? String(result.final_step.objective.name) : id
end

function _standard_reference_power(problem::FiberFieldProblem)
    !ismissing(problem.metadata.requested_fiber) &&
        return problem.metadata.requested_fiber.power_w
    throw(ArgumentError(
        "standard_figures requires recorded launch power; explicit low-level problems must provide a custom renderer"))
end

function _standard_pulse(problem::FiberFieldProblem)
    !ismissing(problem.metadata.requested_pulse) &&
        return problem.metadata.requested_pulse
    throw(ArgumentError(
        "standard_figures requires recorded pulse metadata; explicit low-level problems must provide a custom renderer"))
end

function _standard_raman_threshold(problem::FiberFieldProblem)
    problem.raman_threshold_thz !== nothing && return problem.raman_threshold_thz
    throw(ArgumentError(
        "standard_figures requires a scalar raman_threshold_thz; an arbitrary band mask has no honest threshold label"))
end

function _standard_band_mask(problem::FiberFieldProblem, objective_kind::Symbol)
    problem.band_mask !== nothing && return problem.band_mask
    throw(ArgumentError(
        "standard_figures for objective `$(objective_kind)` requires problem.band_mask; " *
        "build the problem with `band_mask` or `raman_threshold_thz`"))
end

function _write_evolution_comparison(phase, base_field, problem::FiberFieldProblem;
                                     output_dir::AbstractString,
                                     tag::AbstractString,
                                     n_z_samples::Int,
                                     lambda0_nm::Real,
                                     fwhm_fs::Real)
    fiber_evo = deepcopy(problem.fiber)
    fiber_evo["zsave"] = collect(range(0.0, problem.fiber["L"], length = n_z_samples))
    shaped = @. base_field * cis(phase)
    sol_opt = solve_disp_mmf(shaped, fiber_evo, problem.sim)
    sol_unshaped = solve_disp_mmf(base_field, fiber_evo, problem.sim)
    metadata = (
        fiber_name = String(problem.metadata.preset),
        L_m = Float64(problem.fiber["L"]),
        P_cont_W = _standard_reference_power(problem),
        lambda0_nm = Float64(lambda0_nm),
        fwhm_fs = Float64(fwhm_fs),
    )
    path = joinpath(output_dir, "$(tag)_evolution_comparison.png")
    renderer = getfield(@__MODULE__, :plot_merged_evolution)
    Base.invokelatest(
        renderer,
        sol_opt,
        sol_unshaped,
        problem.sim,
        fiber_evo;
        metadata = metadata,
        save_path = path,
    )
    PyPlot.close("all")
    return path
end

function _write_metric_summary(result::NativeAdjointResult;
                               output_dir::AbstractString,
                               tag::AbstractString)
    mkpath(output_dir)
    path = joinpath(output_dir, "$(tag)_metric_summary.png")
    trace = result.convergence_trace
    iterations = [entry.iteration for entry in trace]
    costs = [entry.cost for entry in trace]
    gradients = [entry.gradient_norm for entry in trace]
    fig, axs = PyPlot.subplots(1, 2, figsize = (10, 4))
    axs[1].plot(iterations, costs, marker = "o")
    if all(>(0), costs)
        axs[1].set_yscale("log")
    end
    axs[1].set_xlabel("Iteration")
    axs[1].set_ylabel("Objective")
    axs[1].set_title("Optimization trace")
    axs[1].grid(true, alpha = 0.3)

    labels = ["initial", "final"]
    axs[2].bar(labels, [result.cost_initial, result.cost_final])
    if result.cost_initial > 0 && result.cost_final > 0
        axs[2].set_yscale("log")
    end
    delta_db = result.cost_initial > 0 && result.cost_final > 0 ?
        10 * log10(result.cost_final / result.cost_initial) :
        NaN
    title = isfinite(delta_db) ? @sprintf("Objective change: %.2f dB", delta_db) : "Objective change"
    axs[2].set_title(title)
    axs[2].set_ylabel("Objective")
    if !isempty(gradients)
        axs[2].text(
            0.5,
            0.02,
            @sprintf("final |grad| = %.3g", last(gradients)),
            transform = axs[2].transAxes,
            ha = "center",
            va = "bottom",
        )
    end
    axs[2].grid(true, axis = "y", alpha = 0.3)
    fig.tight_layout()
    fig.savefig(path, dpi = 300, bbox_inches = "tight")
    PyPlot.close(fig)
    return path
end

function _ensure_standard_image_helpers_loaded()
    _STANDARD_IMAGE_HELPERS_LOADED[] && return nothing
    root = normpath(joinpath(@__DIR__, "..", ".."))
    isdefined(@__MODULE__, :_VISUALIZATION_JL_LOADED) ||
        include(joinpath(root, "scripts", "lib", "visualization.jl"))
    isdefined(@__MODULE__, :_STANDARD_IMAGES_JL_LOADED) ||
        include(joinpath(root, "scripts", "lib", "standard_images.jl"))
    _STANDARD_IMAGE_HELPERS_LOADED[] = true
    return nothing
end

standard_report(problem::FiberFieldProblem, result::NativeAdjointResult; kwargs...) =
    standard_figures(problem, result; kwargs...)
