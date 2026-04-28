#!/usr/bin/env julia

"""
Set up the mini LaTeX research-note series scaffold under `docs/research-notes`
and generate note-ready summary tables for the strongest currently evidenced
lanes.

This script is intentionally idempotent:

- scaffold files are only created if missing
- generated tables are always refreshed

Run:

    julia --project=. scripts/dev/setup_research_note_series.jl
"""

using Dates
using JLD2
using Printf
using Statistics

ENV["MPLBACKEND"] = "Agg"
using PyPlot

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const OUT_ROOT = joinpath(ROOT, "docs", "research-notes")
const SHARED_ROOT = joinpath(OUT_ROOT, "_shared")
const SNAPSHOT_DATE = "2026-04-24"

const NOTE_SPECS = [
    (
        slug = "01-baseline-raman-suppression",
        title = "Baseline Raman Suppression and Core Optimization Surface",
        status = "established",
        thesis_hint = "Summarize the canonical single-mode phase-only setup, the objective surface, and the standard image vocabulary used everywhere else in the series.",
        sources = [
            "README.md",
            "docs/architecture/cost-function-physics.md",
            "docs/architecture/cost-convention.md",
            "scripts/lib/common.jl",
            "scripts/lib/raman_optimization.jl",
            "scripts/lib/standard_images.jl",
            "scripts/lib/visualization.jl",
        ],
        tables = String[],
    ),
    (
        slug = "02-reduced-basis-continuation",
        title = "Reduced-Basis Continuation and Basin Access",
        status = "established core claim; open portability questions",
        thesis_hint = "Explain why continuation through a structured reduced basis changes basin access, not just interpretability.",
        sources = [
            "agent-docs/phase31-reduced-basis/FINDINGS.md",
            "docs/status/phase-30-status.md",
            "docs/status/phase-32-status.md",
            "docs/synthesis/why-phase-31-changed-the-roadmap.md",
            "scripts/research/sweep_simple/sweep_simple_run.jl",
            "scripts/research/analysis/continuation.jl",
            "results/raman/phase31/followup/path_comparison.jld2",
        ],
        tables = [
            "tables/full_grid_refinement_path_comparison.md",
            "tables/full_grid_refinement_path_comparison.csv",
        ],
    ),
    (
        slug = "03-sharpness-robustness",
        title = "Sharpness, Robustness Penalties, and Hessian Geometry",
        status = "established",
        thesis_hint = "Separate depth from robustness and show what the sharpness penalties did and did not buy.",
        sources = [
            "results/raman/phase22/SUMMARY.md",
            "docs/figures/phase22_pareto.png",
            "scripts/research/sharpness/run.jl",
            "scripts/research/sharpness/summarize.jl",
            "docs/planning-history/phases/22-sharpness-research/SUMMARY.md",
        ],
        tables = String[],
    ),
    (
        slug = "04-trust-region-newton",
        title = "Trust-Region, Newton, and Preconditioning in a Saddle-Dominated Landscape",
        status = "partial",
        thesis_hint = "Focus on honest failure modes, the cold-start limits of local second-order models, and why continuation still matters first.",
        sources = [
            "results/raman/phase33/SYNTHESIS.md",
            "docs/status/phase-34-bounded-rerun-status.md",
            "docs/status/phase-34-preconditioning-caveat.md",
            "docs/synthesis/why-phase-34-still-points-back-to-phase-31.md",
            "scripts/research/trust_region/trust_region_optimize.jl",
            "scripts/research/trust_region/trust_region_pcg.jl",
        ],
        tables = String[],
    ),
    (
        slug = "05-cost-numerics-trust",
        title = "Cost Audit, Numerics Coherence, and Trust Diagnostics",
        status = "established",
        thesis_hint = "State the authoritative objective convention, show the cost-audit comparison surface, and make the trust-report rules explicit.",
        sources = [
            "docs/architecture/cost-convention.md",
            "agent-docs/current-agent-context/NUMERICS.md",
            "agent-docs/cost-convention-consistency/SUMMARY.md",
            "scripts/research/cost_audit/cost_audit_driver.jl",
            "results/cost_audit/",
        ],
        tables = [
            "tables/cost_audit_summary.md",
            "tables/cost_audit_summary.csv",
            "tables/cost_audit_gaps.md",
        ],
    ),
    (
        slug = "06-long-fiber",
        title = "Long-Fiber Single-Mode Raman Suppression",
        status = "partial",
        thesis_hint = "Document the supported long-fiber envelope, the 100 m result, and the matched-quadratic interpretation without overselling convergence.",
        sources = [
            "agent-docs/current-agent-context/LONGFIBER.md",
            "results/raman/phase16/FINDINGS.md",
            "scripts/research/longfiber/longfiber_optimize_100m.jl",
            "scripts/research/propagation/matched_quadratic_100m.jl",
            "scripts/research/propagation/propagation_reach.jl",
        ],
        tables = String[],
    ),
    (
        slug = "07-simple-profiles-transferability",
        title = "Simple Profiles, Universality, and Transferability",
        status = "partial",
        thesis_hint = "Use this note for the low-complexity profile story: when a simple phase is meaningful, when it is sharp luck, and when it transfers only as an initializer.",
        sources = [
            "results/raman/phase17/SUMMARY.md",
            "scripts/research/simple_profile/simple_profile_driver.jl",
            "scripts/research/simple_profile/simple_profile_synthesis.jl",
            "scripts/research/stability_universality/run_phase31_stability.jl",
        ],
        tables = String[],
    ),
    (
        slug = "08-multimode-baselines",
        title = "Multimode Raman Baselines and Cost Choice",
        status = "experimental",
        thesis_hint = "Document the meaningful MMF regime, the recommended primary cost, and the current evidence boundary before promoting MMF more broadly.",
        sources = [
            "docs/status/multimode-baseline-status-2026-04-22.md",
            "agent-docs/multimode-baseline-stabilization/SUMMARY.md",
            "scripts/research/mmf/baseline.jl",
            "scripts/research/mmf/mmf_raman_optimization.jl",
            "src/mmf_cost.jl",
        ],
        tables = String[],
    ),
    (
        slug = "09-multi-parameter-optimization",
        title = "Multi-Parameter Optimization Beyond Phase-Only Shaping",
        status = "experimental",
        thesis_hint = "Explain the joint control space, the current convergence gap versus phase-only, and what the multivar scaffold is actually good for today.",
        sources = [
            "agent-docs/current-agent-context/MULTIVAR.md",
            "scripts/research/multivar/multivar_reference_run.jl",
            "scripts/research/multivar/multivar_optimization.jl",
            "results/raman/multivar/smf28_L2m_P030W/",
            "results/validation/multivar_mv_joint.md",
        ],
        tables = [
            "tables/multivar_comparison.md",
            "tables/multivar_comparison.csv",
        ],
    ),
    (
        slug = "10-recovery-validation",
        title = "Recovery and Honest-Grid Validation",
        status = "established",
        thesis_hint = "Use this note to separate durable recovered results from numerically suspect inherited artifacts.",
        sources = [
            "scripts/research/recovery/recovery_sweep1.jl",
            "results/raman/phase21/phase13/smf28_reanchor.jld2",
            "results/raman/phase21/phase13/hnlf_reanchor.jld2",
            "results/raman/phase21/longfiber100m/sessionf_100m_normalized.jld2",
            "docs/planning-history/phases/21-numerical-recovery/SUMMARY.md",
        ],
        tables = [
            "tables/recovery_anchor_summary.md",
            "tables/recovery_anchor_summary.csv",
        ],
    ),
    (
        slug = "11-performance-appendix",
        title = "Performance Model and Compute Strategy",
        status = "established",
        thesis_hint = "Keep this appendix narrow: forward versus adjoint cost, task-level parallelism, and why single-solve threading is not the main lever.",
        sources = [
            "agent-docs/current-agent-context/PERFORMANCE.md",
            "scripts/research/benchmarks/benchmark_threading.jl",
            "results/phase29/",
        ],
        tables = String[],
    ),
]

const FIGURE_SPECS = Dict(
    "01-baseline-raman-suppression" => [
        (
            source = "docs/artifacts/presentation-2026-04-17/10-smf28-L2m-P030W-phase-profile.png",
            dest = "smf28_L2m_P030W_phase_profile.png",
            caption = "Canonical SMF-28 phase-profile comparison for an optimized phase-only Raman-suppression run.",
        ),
        (
            source = "docs/artifacts/presentation-2026-04-17/08-smf28-L2m-P030W-evolution-optimized.png",
            dest = "smf28_L2m_P030W_evolution_optimized.png",
            caption = "Optimized spectral evolution for the same canonical SMF-28 run.",
        ),
    ],
    "02-reduced-basis-continuation" => [
        (
            source = "docs/research-notes/02-reduced-basis-continuation/figures/basis_family_depth_summary.png",
            dest = "basis_family_depth_summary.png",
            caption = "Best objective reached by each reduced-basis search family and by the full-grid zero-start baseline.",
        ),
        (
            source = "docs/research-notes/02-reduced-basis-continuation/figures/robustness_transfer_tradeoff.png",
            dest = "robustness_transfer_tradeoff.png",
            caption = "Depth, robustness, and transferability tradeoff for the reduced-basis candidates.",
        ),
        (
            source = "docs/research-notes/02-reduced-basis-continuation/figures/no_optimization_phase_diagnostic.png",
            dest = "no_optimization_phase_diagnostic.png",
            caption = "Flat-phase diagnostic for the no-optimization control reference.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/zero_fullgrid/zero_fullgrid_evolution_unshaped.png",
            dest = "no_optimization_evolution_unshaped.png",
            caption = "Unshaped propagation heat map for the no-optimization control reference.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/poly3_transferable/poly3_transferable_phase_diagnostic.png",
            dest = "transferable_polynomial_phase_diagnostic.png",
            caption = "Standard diagnostic for the simple transferable polynomial profile.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/poly3_transferable/poly3_transferable_evolution.png",
            dest = "transferable_polynomial_evolution.png",
            caption = "Matching propagation heat map for the simple transferable polynomial profile.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/cubic32_reduced/cubic32_reduced_phase_diagnostic.png",
            dest = "cubic32_reduced_phase_diagnostic.png",
            caption = "Standard diagnostic for the moderate cubic-continuation seed.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/cubic32_reduced/cubic32_reduced_evolution.png",
            dest = "cubic32_reduced_evolution.png",
            caption = "Matching propagation heat map for the moderate cubic-continuation seed.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/cubic128_reduced/cubic128_reduced_phase_diagnostic.png",
            dest = "cubic128_reduced_phase_diagnostic.png",
            caption = "Standard diagnostic for the deepest cubic-continuation result.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/cubic128_reduced/cubic128_reduced_evolution.png",
            dest = "cubic128_reduced_evolution.png",
            caption = "Matching propagation heat map for the deepest cubic-continuation result.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/cubic32_fullgrid/cubic32_fullgrid_phase_diagnostic.png",
            dest = "cubic32_fullgrid_phase_diagnostic.png",
            caption = "Standard diagnostic for full-grid refinement from a cubic-continuation seed.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/cubic32_fullgrid/cubic32_fullgrid_evolution.png",
            dest = "cubic32_fullgrid_evolution.png",
            caption = "Matching propagation heat map for full-grid refinement from a cubic-continuation seed.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/zero_fullgrid/zero_fullgrid_phase_diagnostic.png",
            dest = "zero_fullgrid_phase_diagnostic.png",
            caption = "Standard diagnostic for the full-grid zero-start baseline.",
        ),
        (
            source = "agent-docs/stability-universality/standard-images/zero_fullgrid/zero_fullgrid_evolution.png",
            dest = "zero_fullgrid_evolution.png",
            caption = "Matching propagation heat map for the full-grid zero-start baseline.",
        ),
    ],
    "03-sharpness-robustness" => [
        (
            source = "docs/figures/phase22_pareto.png",
            dest = "phase22_pareto.png",
            caption = "Phase 22 robustness-depth Pareto plot across plain, MC, SAM, and Hessian-trace variants.",
        ),
        (
            source = "docs/planning-history/phases/22-sharpness-research/images/smf28_canonical_plain_phase_profile.png",
            dest = "phase22_canonical_plain_phase_profile.png",
            caption = "Standard phase-profile diagnostic for the plain canonical Phase 22 operating point.",
        ),
    ],
    "04-trust-region-newton" => [
        (
            source = "docs/artifacts/presentation-2026-04-17/01-landscape-hessian-eigenvalues.png",
            dest = "landscape_hessian_eigenvalues.png",
            caption = "Landscape Hessian spectrum used as visual context for saddle-dominated optimizer behavior.",
        ),
        (
            source = "results/raman/phase34/continuation_dispersion_ladder/ladder_dispersion_L1p0_to_L2p0_phase_profile.png",
            dest = "phase34_dispersion_ladder_phase_profile.png",
            caption = "Phase 34 continuation-style trust-region run with dispersion preconditioning on the 1 m to 2 m rung.",
        ),
    ],
    "05-cost-numerics-trust" => [
        (
            source = "docs/figures/fig3_linear_vs_log_cost.png",
            dest = "linear_vs_log_cost.png",
            caption = "Linear-cost versus log-dB optimization behavior, illustrating why objective-scale consistency matters.",
        ),
        (
            source = "docs/artifacts/presentation-2026-04-17/04-landscape-gauge-before-after.png",
            dest = "gauge_before_after.png",
            caption = "Gauge-cleaning diagnostic used in the numerical trust and Hessian-analysis workflow.",
        ),
    ],
    "06-long-fiber" => [
        (
            source = "docs/figures/phase21_100m_phase_profile.png",
            dest = "phase21_100m_phase_profile.png",
            caption = "Recovered 100 m SMF-28 phase profile on the honest long-fiber validation path.",
        ),
        (
            source = "docs/planning-history/phases/21-numerical-recovery/images/phase21_sessionf_100m_smf28_l100m_p0p05w_evolution.png",
            dest = "phase21_100m_evolution.png",
            caption = "Optimized spectral evolution for the 100 m long-fiber run.",
        ),
    ],
    "07-simple-profiles-transferability" => [
        (
            source = "docs/artifacts/presentation-2026-04-17/pedagogical/pareto_candidate_1_simplest.png",
            dest = "pareto_candidate_simplest.png",
            caption = "Simple low-complexity candidate profile used as representative visual evidence for the transferability discussion.",
        ),
        (
            source = "docs/artifacts/presentation-2026-04-17/05-landscape-polynomial-residuals.png",
            dest = "polynomial_residuals.png",
            caption = "Polynomial residual structure showing what simple profiles fail to capture.",
        ),
    ],
    "08-multimode-baselines" => [
        (
            source = "docs/artifacts/presentation-2026-04-17/pedagogical/dct_spectrum_two_modes.png",
            dest = "dct_spectrum_two_modes.png",
            caption = "Two-mode spectral diagnostic used as representative multimode visual context until the Phase 36 image set is available.",
        ),
        (
            source = "docs/artifacts/presentation-2026-04-17/12-hnlf-L2m-P005W-evolution-optimized.png",
            dest = "representative_multimode_placeholder_evolution.png",
            caption = "Representative optimized spectral evolution included as a placeholder visual while the durable MMF baseline remains artifact-blocked.",
        ),
    ],
    "09-multi-parameter-optimization" => [
        (
            source = "docs/research-notes/09-multi-parameter-optimization/figures/multivar_objective_comparison.png",
            dest = "multivar_objective_comparison.png",
            caption = "Objective comparison generated from the synced multivariable JLD2 payloads.",
        ),
    ],
    "10-recovery-validation" => [
        (
            source = "docs/figures/phase21_recovered_smf28_phase_profile.png",
            dest = "phase21_recovered_smf28_phase_profile.png",
            caption = "Recovered SMF-28 phase profile after honest-grid validation.",
        ),
        (
            source = "docs/planning-history/phases/21-numerical-recovery/images/phase21_phase13_hnlf_l0.50m_p0.010w_phase_profile.png",
            dest = "phase21_recovered_hnlf_phase_profile.png",
            caption = "Recovered HNLF phase profile after honest-grid validation.",
        ),
    ],
    "11-performance-appendix" => [
        (
            source = "docs/research-notes/11-performance-appendix/figures/phase29_thread_scaling.png",
            dest = "phase29_thread_scaling.png",
            caption = "Thread-scaling summary generated from the Phase 29 solve timing artifacts.",
        ),
    ],
)

function ensure_dir(path::AbstractString)
    mkpath(path)
    return path
end

function write_if_missing(path::AbstractString, content::AbstractString)
    ensure_dir(dirname(path))
    if !isfile(path)
        open(path, "w") do io
            write(io, content)
        end
    end
    return path
end

function write_generated(path::AbstractString, content::AbstractString)
    ensure_dir(dirname(path))
    open(path, "w") do io
        write(io, content)
    end
    return path
end

function touch_gitkeep(dir::AbstractString)
    ensure_dir(dir)
    path = joinpath(dir, ".gitkeep")
    if !isfile(path)
        open(path, "w") do io
            write(io, "")
        end
    end
    return path
end

function csv_escape(x)
    if x isa AbstractFloat && !isfinite(x)
        return ""
    end
    s = x === missing ? "" : string(x)
    if occursin(',', s) || occursin('"', s) || occursin('\n', s)
        return "\"" * replace(s, "\"" => "\"\"") * "\""
    end
    return s
end

function render_csv(headers::Vector{String}, rows::Vector{<:Vector})
    lines = String[join(csv_escape.(headers), ",")]
    append!(lines, [join(csv_escape.(row), ",") for row in rows])
    return join(lines, "\n") * "\n"
end

function format_cell(x)
    if x === missing
        return "—"
    elseif x isa AbstractFloat
        if !isfinite(x)
            return "—"
        end
        return @sprintf("%.3f", x)
    else
        return string(x)
    end
end

function to_db_if_needed(x)
    x = Float64(x)
    return x > 0 ? 10 * log10(max(x, 1e-15)) : x
end

function render_markdown_table(headers::Vector{String}, rows::Vector{<:Vector})
    lines = String[
        "| " * join(headers, " | ") * " |",
        "|" * join(fill("---", length(headers)), "|") * "|",
    ]
    for row in rows
        push!(lines, "| " * join(format_cell.(row), " | ") * " |")
    end
    return join(lines, "\n") * "\n"
end

function generated_header(title::AbstractString)
    return "# $(title)\n\n" *
           "_Generated by `scripts/dev/setup_research_note_series.jl` on $(SNAPSHOT_DATE)._ \n\n"
end

function shared_preamble_text()
    return join([
        "% Shared preamble for the research-note series.",
        "% Create note-specific content in the per-note directory; keep common macros here.",
        "\\usepackage[margin=1in]{geometry}",
        "\\usepackage[T1]{fontenc}",
        "\\usepackage[utf8]{inputenc}",
        "\\usepackage{amsmath,amssymb}",
        "\\usepackage{booktabs,longtable,array}",
        "\\usepackage{graphicx}",
        "\\usepackage{float}",
        "\\usepackage{enumitem}",
        "\\usepackage{xcolor}",
        "\\usepackage{hyperref}",
        "\\usepackage{caption}",
        "\\usepackage{titlesec}",
        "\\hypersetup{colorlinks=true, linkcolor=blue!60!black, urlcolor=blue!60!black, citecolor=blue!60!black}",
        "\\setlist[itemize]{leftmargin=1.25em, itemsep=0.2em, topsep=0.3em}",
        "\\setlist[enumerate]{leftmargin=1.4em, itemsep=0.2em, topsep=0.3em}",
        "\\setlength{\\parindent}{0pt}",
        "\\setlength{\\parskip}{0.6em}",
        "\\newcommand{\\statusbox}[2]{%",
        "  \\noindent\\fcolorbox{black}{gray!10}{%",
        "    \\parbox{\\dimexpr\\linewidth-2\\fboxsep-2\\fboxrule\\relax}{%",
        "      \\textbf{Status:} #1\\\\#2",
        "    }%",
        "  }",
        "}",
        "",
    ], "\n")
end

function shared_macros_text()
    return join([
        "% Shared notation helpers for the research-note series.",
        "\\newcommand{\\Jlin}{J}",
        "\\newcommand{\\JdB}{J_{\\mathrm{dB}}}",
        "\\newcommand{\\phiopt}{\\phi_{\\mathrm{opt}}}",
        "\\newcommand{\\sigmathreedb}{\\sigma_{3\\mathrm{dB}}}",
        "\\newcommand{\\Nt}{N_t}",
        "\\newcommand{\\Nphi}{N_{\\phi}}",
        "\\newcommand{\\Lfiber}{L}",
        "\\newcommand{\\Pcont}{P}",
        "\\newcommand{\\band}{\\mathcal{B}_{\\mathrm{Raman}}}",
        "\\newcommand{\\todoitem}[1]{\\textcolor{red!70!black}{\\textbf{TODO:} #1}}",
        "",
    ], "\n")
end

function shared_template_text()
    return join([
        "% Shared section skeleton reference.",
        "% Copy or adapt these headings inside each note as needed.",
        "%",
        "% \\section{Question and Thesis}",
        "% \\section{Setup and Common Notation}",
        "% \\section{Math Delta}",
        "% \\section{Implementation Surface}",
        "% \\section{Experimental Strategy}",
        "% \\section{Representative Results}",
        "% \\section{Interpretation}",
        "% \\section{Limitations and Missing Evidence}",
        "% \\section{Reproduction Capsule}",
        "",
    ], "\n")
end

function note_readme_text(note)
    source_lines = ["- `$(src)`" for src in note.sources]
    table_lines = isempty(note.tables) ? ["- none yet"] : ["- `$(tbl)`" for tbl in note.tables]
    return join([
        "# $(note.title)",
        "",
        "- status: `$(note.status)`",
        "- scaffold snapshot: `$(SNAPSHOT_DATE)`",
        "",
        "## Purpose",
        "",
        note.thesis_hint,
        "",
        "## Primary sources",
        "",
        source_lines...,
        "",
        "## Generated tables in this directory",
        "",
        table_lines...,
        "",
        "## Writing rule",
        "",
        "Keep the note short and technical. Separate established claims from partial or provisional evidence explicitly.",
        "",
    ], "\n")
end

function note_tex_text(note)
    status_sentence = if note.status == "established"
        "This lane has enough evidence to support a stable technical note, but the prose still needs to distinguish core claims from scope limits."
    elseif note.status == "partial"
        "This lane has meaningful results, but the note should label incomplete evidence and any missing artifacts explicitly."
    else
        "This lane is still experimental. The note should read as a scoped research status note, not as a settled platform claim."
    end
    figure_lines = String[]
    for fig in get(FIGURE_SPECS, note.slug, [])
        push!(figure_lines, "\\begin{figure}[H]")
        push!(figure_lines, "\\centering")
        push!(figure_lines, "\\includegraphics[width=0.92\\linewidth]{figures/$(fig.dest)}")
        push!(figure_lines, "\\caption{$(fig.caption)}")
        push!(figure_lines, "\\end{figure}")
        push!(figure_lines, "")
    end
    isempty(figure_lines) && push!(figure_lines, "\\todoitem{Add at least one representative result figure.}")

    return join([
        "% Scaffold created by scripts/dev/setup_research_note_series.jl",
        "\\documentclass[11pt]{article}",
        "\\input{../_shared/preamble.tex}",
        "\\input{../_shared/macros.tex}",
        "",
        "\\title{$(note.title)}",
        "\\author{Fiber Raman Suppression Project}",
        "\\date{Evidence snapshot: $(SNAPSHOT_DATE)}",
        "",
        "\\begin{document}",
        "\\maketitle",
        "",
        "\\begin{abstract}",
        "TODO: state the research question, the current thesis, and the evidence status in 4--6 sentences.",
        "\\end{abstract}",
        "",
        "\\section*{Claim Status}",
        "\\statusbox{$(note.status)}{$(status_sentence)}",
        "",
        "\\section{Question and Thesis}",
        "\\todoitem{State the narrow question this note answers and the current best-supported thesis.}",
        "",
        "\\section{Setup and Common Notation}",
        "\\todoitem{Recap only the common setup needed for this lane. Avoid re-deriving the whole project.}",
        "",
        "\\section{Math Delta}",
        "\\todoitem{Include only the equations or objective variants unique to this lane.}",
        "",
        "\\section{Implementation Surface}",
        "\\todoitem{Add a short table of key scripts, shared helpers, and result directories.}",
        "",
        "\\section{Experimental Strategy}",
        "\\todoitem{Explain configs, ladders, comparisons, trust gates, and exclusions.}",
        "",
        "\\section{Representative Results}",
        "The following figures are copied from existing result or presentation artifacts so the note starts with concrete visual evidence.",
        "",
        figure_lines...,
        "",
        "\\section{Interpretation}",
        "\\todoitem{Separate established results from provisional interpretation.}",
        "",
        "\\section{Limitations and Missing Evidence}",
        "\\todoitem{Call out artifact gaps, unresolved confounders, and reruns still needed.}",
        "",
        "\\section{Reproduction Capsule}",
        "\\todoitem{Document the canonical command, machine boundary, and expected outputs.}",
        "",
        "\\end{document}",
        "",
    ], "\n")
end

function generate_multivar_figure()
    rows = multivar_rows()
    out = joinpath(OUT_ROOT, "09-multi-parameter-optimization", "figures", "multivar_objective_comparison.png")
    ensure_dir(dirname(out))
    labels = [r.run for r in rows]
    after = [r.after_j_db for r in rows]
    colors = ["#4C78A8", "#72B7B2", "#F58518", "#E45756"][1:length(rows)]
    fig, ax = subplots(figsize=(8.5, 4.8))
    ax.bar(1:length(rows), after, color=colors)
    ax.set_ylabel("Final Raman objective J (dB)")
    ax.set_title("Multivariable runs vs phase-only baseline")
    ax.set_xticks(1:length(rows))
    ax.set_xticklabels(labels, rotation=20, ha="right", fontsize=8)
    ax.grid(true, axis="y", alpha=0.3)
    for (i, v) in enumerate(after)
        ax.text(i, v + 2.0, @sprintf("%.1f dB", v), ha="center", va="bottom", fontsize=8)
    end
    tight_layout()
    savefig(out, dpi=220)
    close(fig)
    return out
end

function generate_performance_figure()
    d = JLD2.load(joinpath(ROOT, "results", "phase29", "solves.jld2"))
    solves = d["solves"]
    thread_counts = sort(unique([k[2] for k in keys(solves)]))
    modes = ["forward", "adjoint", "full_cg"]
    out = joinpath(OUT_ROOT, "11-performance-appendix", "figures", "phase29_thread_scaling.png")
    ensure_dir(dirname(out))
    fig, ax = subplots(figsize=(7.5, 4.6))
    for mode in modes
        med = [median(solves[(mode, n)]) for n in thread_counts]
        ax.plot(thread_counts, med, marker="o", linewidth=1.8, label=mode)
    end
    ax.set_xscale("log", base=2)
    ax.set_xlabel("Julia threads")
    ax.set_ylabel("Median solve time (s)")
    ax.set_title("Phase 29 canonical workload thread scaling")
    ax.grid(true, which="both", alpha=0.3)
    ax.legend()
    tight_layout()
    savefig(out, dpi=220)
    close(fig)
    return out
end

function generate_no_optimization_control_figure()
    out = joinpath(OUT_ROOT, "02-reduced-basis-continuation", "figures", "no_optimization_phase_diagnostic.png")
    ensure_dir(dirname(out))
    lambda_nm = collect(range(1490.0, 1610.0; length=500))
    time_ps = collect(range(-15.0, 15.0; length=500))
    center_nm = 1550.0
    fwhm_nm = 18.0
    sigma_nm = fwhm_nm / (2 * sqrt(2 * log(2)))
    spectrum = exp.(-0.5 .* ((lambda_nm .- center_nm) ./ sigma_nm).^2)
    pulse = exp.(-0.5 .* (time_ps ./ 0.18).^2)

    fig, axs = subplots(3, 2, figsize=(10, 10))
    axs[1, 1].plot(lambda_nm, zeros(length(lambda_nm)), color="#333333", linewidth=2)
    axs[1, 1].set_title("Applied spectral phase")
    axs[1, 1].set_ylabel("phase [rad]")
    axs[1, 1].set_xlabel("wavelength [nm]")
    axs[1, 1].grid(true, alpha=0.25)
    axs[1, 1].set_ylim(-1, 1)

    axs[1, 2].plot(lambda_nm, spectrum, color="#4C78A8", linewidth=2)
    axs[1, 2].set_title("Unshaped input spectrum")
    axs[1, 2].set_ylabel("normalized power")
    axs[1, 2].set_xlabel("wavelength [nm]")
    axs[1, 2].grid(true, alpha=0.25)

    axs[2, 1].plot(time_ps, pulse, color="#F58518", linewidth=2)
    axs[2, 1].set_title("Transform-limited input pulse")
    axs[2, 1].set_ylabel("normalized power")
    axs[2, 1].set_xlabel("time [ps]")
    axs[2, 1].grid(true, alpha=0.25)

    axs[2, 2].plot(lambda_nm, zeros(length(lambda_nm)), color="#333333", linewidth=2)
    axs[2, 2].set_title("Group delay")
    axs[2, 2].set_ylabel("delay [fs]")
    axs[2, 2].set_xlabel("wavelength [nm]")
    axs[2, 2].grid(true, alpha=0.25)
    axs[2, 2].set_ylim(-1, 1)

    axs[3, 1].plot(lambda_nm, zeros(length(lambda_nm)), color="#333333", linewidth=2)
    axs[3, 1].set_title("Instantaneous frequency shift")
    axs[3, 1].set_ylabel("shift [THz]")
    axs[3, 1].set_xlabel("wavelength [nm]")
    axs[3, 1].grid(true, alpha=0.25)
    axs[3, 1].set_ylim(-1, 1)

    axs[3, 2].axis("off")
    axs[3, 2].text(0.02, 0.72, "No optimization control", fontsize=16, weight="bold")
    axs[3, 2].text(0.02, 0.52, "Applied phase: phi(w) = 0", fontsize=12)
    axs[3, 2].text(0.02, 0.38, "No reduced basis, no full-grid polish", fontsize=12)
    axs[3, 2].text(0.02, 0.24, "Pair with the unshaped evolution heat map", fontsize=12)

    tight_layout()
    savefig(out, dpi=220)
    close(fig)
    return out
end

function generate_derived_figures()
    generate_no_optimization_control_figure()
    generate_multivar_figure()
    generate_performance_figure()
end

function copy_note_figures(note)
    note_root = joinpath(OUT_ROOT, note.slug)
    figure_root = joinpath(note_root, "figures")
    ensure_dir(figure_root)
    for fig in get(FIGURE_SPECS, note.slug, [])
        src = normpath(joinpath(ROOT, fig.source))
        dst = joinpath(figure_root, fig.dest)
        if !isfile(src)
            @warn "missing figure source" note=note.slug source=fig.source
            continue
        end
        if abspath(src) != abspath(dst)
            cp(src, dst; force=true)
        end
    end
end

function root_readme_text()
    lines = String[
        "# Research Notes",
        "",
        "This tree holds the mini LaTeX research-note series scaffold for the Raman-suppression project.",
        "",
        "- shared LaTeX files live in `_shared/`",
        "- each numbered note directory contains a `.tex` stub, a local `README.md`, and `figures/` / `tables/` subdirectories",
        "- generated note-ready tables are refreshed by `scripts/dev/setup_research_note_series.jl`",
        "- outward-facing quality rules live in `QUALITY-STANDARD.md`",
        "",
        "## Notes",
        "",
    ]
    for note in NOTE_SPECS
        push!(lines, "- `$(note.slug)` — $(note.title) (`$(note.status)`)")
    end
    push!(lines, "")
    push!(lines, "## Refresh command")
    push!(lines, "")
    push!(lines, "```bash")
    push!(lines, "julia --project=. scripts/dev/setup_research_note_series.jl")
    push!(lines, "```")
    push!(lines, "")
    return join(lines, "\n")
end

function pretty_phase31_path(path_name::AbstractString)
    mapping = Dict(
        "cubic128_full" => "cubic128 -> full-grid",
        "cubic32_full" => "cubic32 -> full-grid",
        "linear64_cubic128_full" => "linear64 -> cubic128 -> full-grid",
        "linear64_full" => "linear64 -> full-grid",
        "full_zero" => "zero -> full-grid",
    )
    return get(mapping, path_name, path_name)
end

function phase31_followup_rows()
    path = joinpath(ROOT, "results", "raman", "phase31", "followup", "path_comparison.jld2")
    d = JLD2.load(path)
    rows = d["rows"]
    order = Dict(
        "cubic128_full" => 1,
        "cubic32_full" => 2,
        "linear64_cubic128_full" => 3,
        "linear64_full" => 4,
        "full_zero" => 5,
    )
    sort!(rows; by = r -> get(order, String(r["path_name"]), 99))
    out = NamedTuple[]
    for r in rows
        final_j_db = Float64(r["final_J_dB"])
        hnlf_eval_db = Float64(r["J_transfer_HNLF"])
        push!(out, (
            path = pretty_phase31_path(String(r["path_name"])),
            final_j_db = final_j_db,
            depth_gain_vs_seed_db = Float64(r["depth_gain_vs_seed_dB"]),
            sigma_3db = Float64(r["sigma_3dB"]),
            hnlf_eval_db = hnlf_eval_db,
            hnlf_gap_db = hnlf_eval_db - final_j_db,
            iterations = Int(r["final_iterations"]),
            converged = Bool(r["final_converged"]),
        ))
    end
    return out
end

function cost_audit_rows()
    variants = ["linear", "log_dB", "sharp", "curvature"]
    configs = ["A", "B", "C"]
    existing = NamedTuple[]
    missing = NamedTuple[]
    for cfg in configs
        for variant in variants
            path = joinpath(ROOT, "results", "cost_audit", cfg, "$(variant)_result.jld2")
            if isfile(path)
                d = JLD2.load(path)
                push!(existing, (
                    config = cfg,
                    variant = variant,
                    log_cost = Bool(d["log_cost_used"]),
                    start_j_db = Float64(d["J_start_dB"]),
                    final_j_db = Float64(d["J_final_dB"]),
                    delta_j_db = Float64(d["delta_J_dB"]),
                    iterations = Int(d["iterations"]),
                    converged = Bool(d["converged"]),
                    iter_to_90pct = Int(d["iter_to_90pct"]),
                    wall_s = Float64(d["wall_s"]),
                    cond_proxy = Float64(d["cond_proxy"]),
                ))
            else
                push!(missing, (config = cfg, variant = variant))
            end
        end
    end
    sort!(existing; by = r -> (r.config, r.variant))
    return existing, missing
end

function multivar_rows()
    base = joinpath(ROOT, "results", "raman", "multivar", "smf28_L2m_P030W")
    specs = [
        ("phase_only_opt_result.jld2", "phase_only_legacy", "phase"),
        ("mv_phaseonly_result.jld2", "phase_only_multivar_schema", "phase"),
        ("mv_joint_result.jld2", "multivar_cold_start", "phase+amplitude"),
        ("mv_joint_warmstart_result.jld2", "multivar_warm_start", "phase+amplitude"),
    ]
    out = NamedTuple[]
    for (fname, run_label, control_label) in specs
        path = joinpath(base, fname)
        isfile(path) || continue
        d = JLD2.load(path)
        before_db = to_db_if_needed(d["J_before"])
        after_db = to_db_if_needed(d["J_after"])
        push!(out, (
            run = run_label,
            controls = control_label,
            before_j_db = before_db,
            after_j_db = after_db,
            delta_j_db = Float64(d["delta_J_dB"]),
            iterations = Int(d["iterations"]),
            converged = Bool(d["converged"]),
            wall_s = Float64(d["wall_time_s"]),
        ))
    end
    return out
end

function recovery_rows()
    specs = [
        (
            label = "phase13_smf28_reanchor",
            path = joinpath(ROOT, "results", "raman", "phase21", "phase13", "smf28_reanchor.jld2"),
            regime = "SMF-28, L=2.0 m, P=0.2 W",
            reference_key = nothing,
        ),
        (
            label = "phase13_hnlf_reanchor",
            path = joinpath(ROOT, "results", "raman", "phase21", "phase13", "hnlf_reanchor.jld2"),
            regime = "HNLF, L=0.5 m, P=0.01 W",
            reference_key = nothing,
        ),
        (
            label = "longfiber100m_normalized",
            path = joinpath(ROOT, "results", "raman", "phase21", "longfiber100m", "sessionf_100m_normalized.jld2"),
            regime = "SMF-28, L=100.0 m, P=0.05 W",
            reference_key = "stored_J_opt_dB",
        ),
    ]
    out = NamedTuple[]
    for spec in specs
        isfile(spec.path) || continue
        d = JLD2.load(spec.path)
        reference = spec.reference_key === nothing ? missing : Float64(d[spec.reference_key])
        iterations = haskey(d, "iterations") ? Int(d["iterations"]) : missing
        converged = haskey(d, "converged") ? Bool(d["converged"]) : (haskey(d, "stored_converged") ? Bool(d["stored_converged"]) : missing)
        nt = haskey(d, "Nt") ? Int(d["Nt"]) : missing
        tw = haskey(d, "time_window_ps") ? Float64(d["time_window_ps"]) : missing
        push!(out, (
            artifact = spec.label,
            regime = spec.regime,
            recovered_j_db = Float64(d["J_honest_dB"]),
            reference_j_db = reference,
            edge_frac = Float64(d["edge_frac"]),
            energy_drift = Float64(d["energy_drift"]),
            iterations = iterations,
            converged = converged,
            nt = nt,
            time_window_ps = tw,
        ))
    end
    return out
end

function write_phase31_tables()
    rows = phase31_followup_rows()
    note_root = joinpath(OUT_ROOT, "02-reduced-basis-continuation", "tables")
    headers = [
        "path",
        "final_j_db",
        "depth_gain_vs_seed_db",
        "sigma_3db",
        "hnlf_eval_db",
        "hnlf_gap_db",
        "iterations",
        "converged",
    ]
    csv_rows = [[r.path, r.final_j_db, r.depth_gain_vs_seed_db, r.sigma_3db, r.hnlf_eval_db, r.hnlf_gap_db, r.iterations, r.converged] for r in rows]
    md_rows = [[r.path, r.final_j_db, r.depth_gain_vs_seed_db, r.sigma_3db, r.hnlf_eval_db, r.hnlf_gap_db, r.iterations, r.converged] for r in rows]
    md = generated_header("Full-Grid Refinement Path Comparison") *
         "Columns:\n\n" *
         "- `final_j_db`: final canonical Raman objective in dB\n" *
         "- `depth_gain_vs_seed_db`: improvement relative to the seed used for the path\n" *
         "- `hnlf_eval_db`: HNLF evaluation of the final phase\n" *
         "- `hnlf_gap_db`: `hnlf_eval_db - final_j_db`\n\n" *
         render_markdown_table(
            ["Path", "Final J (dB)", "Gain vs seed (dB)", "σ_3dB", "HNLF eval (dB)", "HNLF gap (dB)", "Iters", "Converged"],
            md_rows,
         )
    write_generated(joinpath(note_root, "full_grid_refinement_path_comparison.md"), md)
    write_generated(joinpath(note_root, "full_grid_refinement_path_comparison.csv"), render_csv(headers, csv_rows))
end

function write_cost_audit_tables()
    rows, missing = cost_audit_rows()
    note_root = joinpath(OUT_ROOT, "05-cost-numerics-trust", "tables")
    headers = [
        "config",
        "variant",
        "log_cost",
        "start_j_db",
        "final_j_db",
        "delta_j_db",
        "iterations",
        "converged",
        "iter_to_90pct",
        "wall_s",
        "cond_proxy",
    ]
    csv_rows = [[r.config, r.variant, r.log_cost, r.start_j_db, r.final_j_db, r.delta_j_db, r.iterations, r.converged, r.iter_to_90pct, r.wall_s, r.cond_proxy] for r in rows]
    md_rows = [[r.config, r.variant, r.log_cost, r.start_j_db, r.final_j_db, r.delta_j_db, r.iterations, r.converged, r.iter_to_90pct, r.wall_s, r.cond_proxy] for r in rows]
    md = generated_header("Cost Audit Summary") *
         "This table reflects the cost-audit artifacts currently present under `results/cost_audit/`.\n\n" *
         render_markdown_table(
            ["Cfg", "Variant", "log_cost", "Start J (dB)", "Final J (dB)", "ΔJ (dB)", "Iters", "Conv.", "Iter@90%", "Wall s", "Cond proxy"],
            md_rows,
         )
    write_generated(joinpath(note_root, "cost_audit_summary.md"), md)
    write_generated(joinpath(note_root, "cost_audit_summary.csv"), render_csv(headers, csv_rows))

    gap_lines = String[
        "# Cost Audit Artifact Gaps",
        "",
        "_Generated by `scripts/dev/setup_research_note_series.jl` on $(SNAPSHOT_DATE)._ ",
        "",
        "Expected matrix from `scripts/research/cost_audit/cost_audit_driver.jl`: configs `A,B,C` × variants `linear, log_dB, sharp, curvature`.",
        "",
    ]
    if isempty(missing)
        push!(gap_lines, "- no missing result files detected")
    else
        push!(gap_lines, "Missing result payloads:")
        for m in missing
            push!(gap_lines, "- `results/cost_audit/$(m.config)/$(m.variant)_result.jld2`")
        end
    end
    push!(gap_lines, "")
    write_generated(joinpath(note_root, "cost_audit_gaps.md"), join(gap_lines, "\n"))
end

function write_multivar_tables()
    rows = multivar_rows()
    note_root = joinpath(OUT_ROOT, "09-multi-parameter-optimization", "tables")
    headers = [
        "run",
        "controls",
        "before_j_db",
        "after_j_db",
        "delta_j_db",
        "iterations",
        "converged",
        "wall_s",
    ]
    csv_rows = [[r.run, r.controls, r.before_j_db, r.after_j_db, r.delta_j_db, r.iterations, r.converged, r.wall_s] for r in rows]
    md_rows = [[r.run, r.controls, r.before_j_db, r.after_j_db, r.delta_j_db, r.iterations, r.converged, r.wall_s] for r in rows]
    md = generated_header("Multivariable Comparison") *
         "This table normalizes the currently synced multivar artifacts onto one comparison surface.\n\n" *
         render_markdown_table(
            ["Run", "Controls", "Before J (dB)", "After J (dB)", "ΔJ (dB)", "Iters", "Conv.", "Wall s"],
            md_rows,
         )
    write_generated(joinpath(note_root, "multivar_comparison.md"), md)
    write_generated(joinpath(note_root, "multivar_comparison.csv"), render_csv(headers, csv_rows))
end

function write_recovery_tables()
    rows = recovery_rows()
    note_root = joinpath(OUT_ROOT, "10-recovery-validation", "tables")
    headers = [
        "artifact",
        "regime",
        "recovered_j_db",
        "reference_j_db",
        "edge_frac",
        "energy_drift",
        "iterations",
        "converged",
        "nt",
        "time_window_ps",
    ]
    csv_rows = [[r.artifact, r.regime, r.recovered_j_db, r.reference_j_db, r.edge_frac, r.energy_drift, r.iterations, r.converged, r.nt, r.time_window_ps] for r in rows]
    md_rows = [[r.artifact, r.regime, r.recovered_j_db, r.reference_j_db, r.edge_frac, r.energy_drift, r.iterations, r.converged, r.nt, r.time_window_ps] for r in rows]
    md = generated_header("Recovery Anchor Summary") *
         "This table collects the honest-grid recovery artifacts currently present in the synced workspace.\n\n" *
         render_markdown_table(
            ["Artifact", "Regime", "Recovered J (dB)", "Reference J (dB)", "Edge frac", "Energy drift", "Iters", "Conv.", "Nt", "TW ps"],
            md_rows,
         )
    write_generated(joinpath(note_root, "recovery_anchor_summary.md"), md)
    write_generated(joinpath(note_root, "recovery_anchor_summary.csv"), render_csv(headers, csv_rows))
end

function scaffold_notes()
    ensure_dir(OUT_ROOT)
    ensure_dir(SHARED_ROOT)

    write_if_missing(joinpath(OUT_ROOT, "README.md"), root_readme_text())
    write_if_missing(joinpath(SHARED_ROOT, "preamble.tex"), shared_preamble_text())
    write_if_missing(joinpath(SHARED_ROOT, "macros.tex"), shared_macros_text())
    write_if_missing(joinpath(SHARED_ROOT, "note-template.tex"), shared_template_text())

    for note in NOTE_SPECS
        note_root = ensure_dir(joinpath(OUT_ROOT, note.slug))
        touch_gitkeep(joinpath(note_root, "figures"))
        touch_gitkeep(joinpath(note_root, "tables"))
        copy_note_figures(note)
        write_if_missing(joinpath(note_root, "README.md"), note_readme_text(note))
        tex_name = "$(note.slug).tex"
        write_if_missing(joinpath(note_root, tex_name), note_tex_text(note))
    end
end

function main()
    generate_derived_figures()
    scaffold_notes()
    write_phase31_tables()
    write_cost_audit_tables()
    write_multivar_tables()
    write_recovery_tables()

    println("Research-note scaffold ready under: " * OUT_ROOT)
    println("Generated tables refreshed for notes 02, 05, 09, and 10.")
end

main()
