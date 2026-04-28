"""
Markdown and CSV renderers for the read-only results index.

The scanning and comparison logic stays in `results_index.jl`; this file only
turns already-normalized rows into presentation text.
"""

if !(@isdefined _RESULTS_INDEX_RENDERING_JL_LOADED)
const _RESULTS_INDEX_RENDERING_JL_LOADED = true

using Printf

function _index_float_cell(value)
    if value isa AbstractFloat
        isfinite(value) || return ""
        format = 0 < abs(value) < 0.01 ? "%.4g" : "%.2f"
        return Printf.format(Printf.Format(format), value)
    end
    return string(value)
end

function _csv_cell(value)
    text = if ismissing(value)
        ""
    elseif value isa AbstractFloat
        isfinite(value) ? string(value) : ""
    else
        string(value)
    end
    needs_quotes = any(ch -> ch in (',', '"', '\n', '\r'), text)
    escaped = replace(text, "\"" => "\"\"")
    return needs_quotes ? "\"$escaped\"" : escaped
end

function render_results_index(index; io::Union{Nothing,IO}=nothing)
    lines = String[
        "# Results Index",
        "",
        "- Roots: `$(join(index.roots, "`, `"))`",
        "- Entries: `$(index.total)`",
        "",
        "| Kind | ID | Run Context | Compare Ready | Manifest Missing | Config | Regime | Objective | Variables | Fiber | L [m] | P [W] | J_after [dB] | ΔJ [dB] | Quality | Lab Ready | Readiness | Std Images | Variable Artifacts | Trust | Export | Path |",
        "|---|---|---|---|---|---|---|---|---|---|---:|---:|---:|---:|---|---|---|---|---|---|---|---|",
    ]

    for row in index.rows
        push!(lines, string(
            "| ", row.kind,
            " | ", row.id,
            " | ", row.run_context,
            " | ", ismissing(row.manifest_compare_ready) ? "" : string(row.manifest_compare_ready),
            " | ", row.manifest_missing,
            " | ", row.config_id,
            " | ", row.regime,
            " | ", row.objective_kind,
            " | ", row.variables,
            " | ", row.fiber,
            " | ", _index_float_cell(row.L_m),
            " | ", _index_float_cell(row.P_cont_W),
            " | ", _index_float_cell(row.J_after_dB),
            " | ", _index_float_cell(row.delta_J_dB),
            " | ", row.quality,
            " | ", ismissing(row.lab_ready) ? "" : string(row.lab_ready),
            " | ", row.readiness,
            " | ", ismissing(row.standard_images_complete) ? "" : string(row.standard_images_complete),
            " | ", ismissing(row.variable_artifacts_complete) ? "" : string(row.variable_artifacts_complete),
            " | ", ismissing(row.trust_report_present) ? "" : string(row.trust_report_present),
            " | ", ismissing(row.export_handoff_complete) ? "" : string(row.export_handoff_complete),
            " | ", isempty(row.error) ? row.path : row.error,
            " |"))
    end

    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_results_index_csv(index; io::Union{Nothing,IO}=nothing)
    columns = (
        :kind,
        :id,
        :config_id,
        :regime,
        :objective_kind,
        :variables,
        :solver_kind,
        :timestamp_utc,
        :run_context,
        :manifest_present,
        :manifest_compare_ready,
        :manifest_missing,
        :manifest_path,
        :fiber,
        :L_m,
        :P_cont_W,
        :J_before_dB,
        :J_after_dB,
        :delta_J_dB,
        :quality,
        :converged,
        :iterations,
        :standard_images_complete,
        :variable_artifacts_complete,
        :variable_artifact_hooks,
        :variable_artifact_paths,
        :variable_artifacts_missing,
        :trust_report_present,
        :export_handoff_complete,
        :lab_ready,
        :readiness,
        :trust_report_path,
        :run_config_path,
        :sidecar_path,
        :export_handoff_path,
        :path,
        :error,
    )
    lines = [join(string.(columns), ",")]
    for row in index.rows
        push!(lines, join((_csv_cell(getproperty(row, col)) for col in columns), ","))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_results_comparison(comparison; io::Union{Nothing,IO}=nothing)
    lines = String[
        "# Results Comparison",
        "",
        "- Roots: `$(join(comparison.roots, "`, `"))`",
        "- Runs: `$(comparison.total)`",
        "",
        "| Rank | Lab Ready | Readiness | Run Context | Compare Ready | Manifest Missing | Config | Objective | Variables | Fiber | L [m] | P [W] | J_after [dB] | ΔJ [dB] | Quality | Std Images | Variable Artifacts | Trust | Export | Path |",
        "|---:|---|---|---|---|---|---|---|---|---|---:|---:|---:|---:|---|---|---|---|---|---|",
    ]
    for (rank, row) in enumerate(comparison.rows)
        push!(lines, string(
            "| ", rank,
            " | ", row.lab_ready,
            " | ", row.readiness,
            " | ", row.run_context,
            " | ", ismissing(row.manifest_compare_ready) ? "" : string(row.manifest_compare_ready),
            " | ", row.manifest_missing,
            " | ", row.config_id,
            " | ", row.objective_kind,
            " | ", row.variables,
            " | ", row.fiber,
            " | ", _index_float_cell(row.L_m),
            " | ", _index_float_cell(row.P_cont_W),
            " | ", _index_float_cell(row.J_after_dB),
            " | ", _index_float_cell(row.delta_J_dB),
            " | ", row.quality,
            " | ", row.standard_images_complete,
            " | ", row.variable_artifacts_complete,
            " | ", row.trust_report_present,
            " | ", row.export_handoff_complete,
            " | ", isempty(row.error) ? row.path : row.error,
            " |"))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_results_comparison_csv(comparison; io::Union{Nothing,IO}=nothing)
    columns = (
        :rank,
        :lab_ready,
        :readiness,
        :run_context,
        :manifest_compare_ready,
        :manifest_missing,
        :config_id,
        :objective_kind,
        :variables,
        :fiber,
        :L_m,
        :P_cont_W,
        :J_after_dB,
        :delta_J_dB,
        :quality,
        :standard_images_complete,
        :variable_artifacts_complete,
        :trust_report_present,
        :export_handoff_complete,
        :path,
    )
    lines = [join(string.(columns), ",")]
    for (rank, row) in enumerate(comparison.rows)
        push!(lines, join((_csv_cell(col == :rank ? rank : getproperty(row, col)) for col in columns), ","))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_sweep_comparison(comparison; io::Union{Nothing,IO}=nothing)
    lines = String[
        "# Sweep Comparison",
        "",
        "- Roots: `$(join(comparison.roots, "`, `"))`",
        "- Sweeps: `$(comparison.total)`",
        "",
        "| Rank | Sweep | Cases | Complete | Failed | Skipped | Best Case | Best J_after [dB] | Median J_after [dB] | Path |",
        "|---:|---|---:|---:|---:|---:|---|---:|---:|---|",
    ]
    for (rank, row) in enumerate(comparison.rows)
        push!(lines, string(
            "| ", rank,
            " | ", row.id,
            " | ", row.cases,
            " | ", row.complete,
            " | ", row.failed,
            " | ", row.skipped,
            " | ", row.best_case,
            " | ", _index_float_cell(row.best_J_after_dB),
            " | ", _index_float_cell(row.median_J_after_dB),
            " | ", isempty(row.error) ? row.path : row.error,
            " |"))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

function render_sweep_comparison_csv(comparison; io::Union{Nothing,IO}=nothing)
    columns = (
        :rank,
        :id,
        :cases,
        :complete,
        :failed,
        :skipped,
        :best_case,
        :best_J_after_dB,
        :median_J_after_dB,
        :path,
        :error,
    )
    lines = [join(string.(columns), ",")]
    for (rank, row) in enumerate(comparison.rows)
        push!(lines, join((_csv_cell(col == :rank ? rank : getproperty(row, col)) for col in columns), ","))
    end
    rendered = join(lines, "\n")
    isnothing(io) || println(io, rendered)
    return rendered
end

end # include guard
