"""
Artifact planning for configurable experiments.

The engine should not guess plots. Regimes, objectives, and variables request
named artifact hooks. This module combines those hooks into an inspectable plan
with default view rules and a config override key for future plot tuning.
"""

if !(@isdefined _ARTIFACT_PLAN_JL_LOADED)
const _ARTIFACT_PLAN_JL_LOADED = true

include(joinpath(@__DIR__, "objective_registry.jl"))
include(joinpath(@__DIR__, "variable_registry.jl"))

const ARTIFACT_HOOK_SPECS = Dict{Symbol,Any}(
    :standard_image_set => (
        kind = :image_set,
        filename_hint = "{tag}_phase_profile.png, {tag}_evolution.png, {tag}_phase_diagnostic.png, {tag}_evolution_unshaped.png",
        default_view = "canonical before/after phase Raman inspection set",
        override_key = "plots.standard",
        implemented = true,
    ),
    :trust_report => (
        kind = :report,
        filename_hint = "{tag}_trust.md",
        default_view = "numerical trust checks, conservation, boundary leakage, and gradient checks when enabled",
        override_key = "verification",
        implemented = true,
    ),
    :phase_profile => (
        kind = :plot,
        filename_hint = "{tag}_phase_profile.png",
        default_view = "signal spectral support with wrapped/unwrapped phase and low-power regions treated cautiously",
        override_key = "plots.phase_profile",
        implemented = true,
    ),
    :group_delay => (
        kind = :plot,
        filename_hint = "{tag}_phase_diagnostic.png",
        default_view = "group delay derived from unwrapped phase over meaningful spectral support",
        override_key = "plots.group_delay",
        implemented = true,
    ),
    :spectrum_before_after => (
        kind = :plot,
        filename_hint = "{tag}_phase_profile.png",
        default_view = "normalized spectrum before/after with science band overlays where available",
        override_key = "plots.spectrum",
        implemented = true,
    ),
    :raman_band_overlay => (
        kind = :plot_annotation,
        filename_hint = "{tag}_phase_profile.png",
        default_view = "mark configured Raman band and report integrated leakage",
        override_key = "plots.raman_band",
        implemented = true,
    ),
    :raman_peak_marker => (
        kind = :plot_annotation,
        filename_hint = "{tag}_phase_profile.png",
        default_view = "mark maximum leakage bin inside the Raman band",
        override_key = "plots.raman_peak",
        implemented = true,
    ),
    :convergence_trace => (
        kind = :metric,
        filename_hint = "opt_result.json / opt_result.jld2",
        default_view = "solver objective trace stored with run payload when available",
        override_key = "plots.convergence",
        implemented = true,
    ),
    :amplitude_mask => (
        kind = :plot,
        filename_hint = "{tag}_amplitude_mask.png",
        default_view = "transmission mask over meaningful input spectral support",
        override_key = "plots.amplitude_mask",
        implemented = true,
    ),
    :gain_tilt_profile => (
        kind = :plot,
        filename_hint = "{tag}_gain_tilt_profile.png",
        default_view = "bounded spectral gain/attenuation tilt and shaped input spectrum",
        override_key = "plots.gain_tilt",
        implemented = true,
    ),
    :shaped_input_spectrum => (
        kind = :plot,
        filename_hint = "{tag}_amplitude_mask.png",
        default_view = "unshaped vs shaped input spectrum in the amplitude diagnostic panel",
        override_key = "plots.shaped_input_spectrum",
        implemented = true,
    ),
    :energy_throughput => (
        kind = :metric,
        filename_hint = "{tag}_energy_metrics.json",
        default_view = "input energy, shaped energy, throughput, and soft penalty contribution",
        override_key = "plots.energy",
        implemented = true,
    ),
    :energy_scale => (
        kind = :metric,
        filename_hint = "{tag}_energy_metrics.json",
        default_view = "optimized scalar energy relative to reference input energy",
        override_key = "plots.energy",
        implemented = true,
    ),
    :peak_power => (
        kind = :metric,
        filename_hint = "{tag}_pulse_metrics.json",
        default_view = "before/after peak power in the simulated temporal window",
        override_key = "plots.temporal_pulse",
        implemented = true,
    ),
    :exploratory_summary => (
        kind = :metric,
        filename_hint = "{tag}_explore_summary.json",
        default_view = "generic per-run summary for exploratory configs: variables, objective, metrics, zoom window, and available traces",
        override_key = "plots.explore",
        implemented = true,
    ),
    :exploratory_overview => (
        kind = :plot,
        filename_hint = "{tag}_explore_overview.png",
        default_view = "generic spectrum, temporal pulse, objective trace, and variable summary for novel exploratory work",
        override_key = "plots.explore",
        implemented = true,
    ),
    :mode_resolved_spectra => (
        kind = :plot,
        filename_hint = "{tag}_mode_resolved_spectra.png",
        default_view = "mode spectra; show all modes for small M, otherwise top/worst modes plus aggregate",
        override_key = "plots.modes",
        implemented = false,
    ),
    :per_mode_leakage_table => (
        kind = :table,
        filename_hint = "{tag}_per_mode_leakage.csv",
        default_view = "mode index, leakage metric, and worst/fundamental labels",
        override_key = "plots.modes",
        implemented = false,
    ),
    :mode_weight_bar_chart => (
        kind = :plot,
        filename_hint = "{tag}_mode_weights.png",
        default_view = "optimized modal fractions as a bar chart with simplex normalization check",
        override_key = "plots.mode_weights",
        implemented = false,
    ),
    :modal_power_table => (
        kind = :table,
        filename_hint = "{tag}_modal_power.csv",
        default_view = "input and output modal power fractions",
        override_key = "plots.mode_weights",
        implemented = false,
    ),
    :temporal_pulse_before_after => (
        kind = :plot,
        filename_hint = "{tag}_temporal_pulse.png",
        default_view = "centered around pulse peak; default window contains most pulse energy with margin",
        override_key = "plots.temporal_pulse",
        implemented = false,
    ),
    :pulse_width_metrics => (
        kind = :metric,
        filename_hint = "{tag}_pulse_width_metrics.json",
        default_view = "FWHM, RMS width, peak power, and time-bandwidth product",
        override_key = "plots.temporal_pulse",
        implemented = false,
    ),
)

const CORE_VALIDATED_ARTIFACT_HOOKS = Set([
    :standard_image_set,
    :trust_report,
    :phase_profile,
    :group_delay,
    :spectrum_before_after,
    :raman_band_overlay,
    :raman_peak_marker,
    :convergence_trace,
])

function artifact_hook_spec(hook::Symbol)
    return get(ARTIFACT_HOOK_SPECS, hook, (
        kind = :custom,
        filename_hint = string("{tag}_", hook),
        default_view = "custom artifact hook; define defaults before promotion",
        override_key = string("plots.", hook),
        implemented = false,
    ))
end

function _push_unique!(items::Vector{String}, item::AbstractString)
    item in items || push!(items, String(item))
    return items
end

function _artifact_hook_materialized_paths(request, save_prefix::AbstractString)
    output_dir = dirname(String(save_prefix))
    tag = basename(String(save_prefix))
    paths = String[]
    for raw_hint in split(String(request.filename_hint), ",")
        hint = strip(raw_hint)
        isempty(hint) && continue
        occursin("{tag}", hint) || continue
        occursin(" / ", hint) && continue
        path = joinpath(output_dir, replace(hint, "{tag}" => tag))
        _push_unique!(paths, path)
    end
    return Tuple(paths)
end

function extra_artifact_hook_file_status(spec, save_prefix::AbstractString)
    plan = experiment_artifact_plan(spec)
    checked = String[]
    missing = String[]
    by_hook = Dict{Symbol,Tuple{Vararg{String}}}()

    for request in plan.hooks
        request.implemented || continue
        request.hook in CORE_VALIDATED_ARTIFACT_HOOKS && continue
        paths = _artifact_hook_materialized_paths(request, save_prefix)
        isempty(paths) && continue
        by_hook[request.hook] = paths
        for path in paths
            abspath_path = abspath(path)
            _push_unique!(checked, abspath_path)
            isfile(abspath_path) || _push_unique!(missing, abspath_path)
        end
    end

    return (
        complete = isempty(missing),
        checked = Tuple(checked),
        missing = Tuple(missing),
        paths = by_hook,
        hooks = Tuple(sort!(collect(keys(by_hook)); by=string)),
    )
end

function _artifact_request(hook::Symbol, source::Symbol, owner::Symbol)
    spec = artifact_hook_spec(hook)
    return (
        hook = hook,
        source = source,
        owner = owner,
        kind = spec.kind,
        filename_hint = spec.filename_hint,
        default_view = spec.default_view,
        override_key = spec.override_key,
        implemented = spec.implemented,
    )
end

function regime_artifact_hooks(spec)
    if spec.problem.regime == :single_mode
        if spec.controls.variables == (:phase,)
            return (:standard_image_set, :trust_report)
        end
        return (:standard_image_set,)
    elseif spec.problem.regime == :long_fiber
        return (:standard_image_set, :trust_report, :longfiber_reach_diagnostic)
    elseif spec.problem.regime == :multimode
        return (:mode_resolved_spectra, :per_mode_leakage_table)
    end
    return Symbol[]
end

function exploratory_artifact_hooks(spec)
    spec.maturity == "supported" && return Symbol[]
    spec.artifacts.bundle in (:standard, :experimental_multivar) ||
        return Symbol[]
    return (:exploratory_summary, :exploratory_overview)
end

function experiment_artifact_plan(spec)
    requests = NamedTuple[]
    for hook in regime_artifact_hooks(spec)
        push!(requests, _artifact_request(hook, :regime, spec.problem.regime))
    end

    objective = objective_contract(spec.objective.kind, spec.problem.regime)
    for hook in objective.artifact_hooks
        push!(requests, _artifact_request(hook, :objective, objective.kind))
    end

    for variable in spec.controls.variables
        contract = variable_contract(variable, spec.problem.regime)
        for hook in contract.artifact_hooks
            push!(requests, _artifact_request(hook, :variable, variable))
        end
    end

    for hook in exploratory_artifact_hooks(spec)
        push!(requests, _artifact_request(hook, :explore, :generic))
    end

    deduped = NamedTuple[]
    seen = Set{Symbol}()
    for request in requests
        request.hook in seen && continue
        push!(seen, request.hook)
        push!(deduped, request)
    end

    return (
        hooks = Tuple(deduped),
        implemented = all(request -> request.implemented, deduped),
        planned = Tuple(request for request in deduped if !request.implemented),
    )
end

function render_experiment_artifact_plan(spec; io::IO=stdout)
    plan = experiment_artifact_plan(spec)
    println(io, "Artifact plan:")
    println(io, "  implemented_now=", plan.implemented)
    for request in plan.hooks
        status = request.implemented ? "implemented" : "planned"
        println(io,
            "  - ", request.hook,
            " [", status, "]",
            " source=", request.source,
            " owner=", request.owner)
        println(io, "    file=", request.filename_hint)
        println(io, "    default_view=", request.default_view)
        println(io, "    override=", request.override_key)
    end
    return nothing
end

end # include guard
