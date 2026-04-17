"""
Generate per-point report cards and the top-level ranked summary from existing
sweep JLD2 payloads. Does NOT re-run optimization.

Reads each `_result.jld2` in `results/raman/sweeps/`, produces a 4-panel report
card PNG plus a human-readable `report.md`, and writes `SWEEP_REPORT.md` with
all points ranked by final suppression depth.

# Run
    julia --project=. scripts/generate_sweep_reports.jl

# Inputs
- Existing per-point `_result.jld2` files in `results/raman/sweeps/`.
- `scripts/visualization.jl` plotting helpers.

# Outputs
- `results/raman/sweeps/<fiber>/<L>_<P>/report_card.png` — 4-panel figure.
- `results/raman/sweeps/<fiber>/<L>_<P>/report.md` — YAML front-matter + metrics.
- `results/raman/sweeps/SWEEP_REPORT.md` — ranked summary of all points.

# Runtime
~2–5 minutes for a 24-point sweep. Pure I/O + matplotlib, no simulation.

# Docs
Docs: docs/interpreting-plots.md
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf
using Dates
using Logging

# Include shared infrastructure
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

using JLD2

# ─────────────────────────────────────────────────────────────────────────────
# Section 1: Constants
# ─────────────────────────────────────────────────────────────────────────────

const SR_SWEEP_DIR = joinpath("results", "raman", "sweeps")

# ─────────────────────────────────────────────────────────────────────────────
# Section 2: Per-point report generation
# ─────────────────────────────────────────────────────────────────────────────

"""
    suppression_quality(J_lin) -> String

Classify Raman suppression quality from linear-scale cost J.
"""
function suppression_quality(J_lin)
    isnan(J_lin) && return "CRASHED"
    J_dB = MultiModeNoise.lin_to_dB(J_lin)
    J_dB < -40 ? "EXCELLENT" : J_dB < -30 ? "GOOD" : J_dB < -20 ? "ACCEPTABLE" : "POOR"
end

"""
    generate_point_report(jld2_path, out_dir)

Load a per-point JLD2 and generate report_card.png + report.md in out_dir.
"""
function generate_point_report(jld2_path, out_dir)
    @info "Processing $jld2_path"

    data = load(jld2_path)

    # Generate report card figure
    png_path = joinpath(out_dir, "report_card.png")
    try
        fig, _ = plot_sweep_report_card(data; save_path=png_path)
        PyPlot.close(fig)
    catch e
        @warn "Failed to generate report card for $jld2_path" exception=e
    end

    # Generate report.md
    md_path = joinpath(out_dir, "report.md")
    write_point_markdown(data, md_path)

    return true
end

"""
    write_point_markdown(data, path)

Write a human-readable markdown report for a single sweep point.
"""
function write_point_markdown(data, path)
    fname    = data["fiber_name"]
    L_m      = data["L_m"]
    P_W      = data["P_cont_W"]
    J_bef    = data["J_before"]
    J_aft    = data["J_after"]
    conv     = data["converged"]
    iters    = data["iterations"]
    Nt       = data["Nt"]
    tw_ps    = data["time_window_ps"]

    J_bef_dB = MultiModeNoise.lin_to_dB(J_bef)
    J_aft_dB = MultiModeNoise.lin_to_dB(J_aft)
    delta_dB = J_aft_dB - J_bef_dB
    quality  = suppression_quality(J_aft)

    grad_norm = haskey(data, "grad_norm") ? data["grad_norm"] : NaN
    E_cons    = haskey(data, "E_conservation") ? data["E_conservation"] : NaN
    bc_in     = haskey(data, "bc_input_frac") ? data["bc_input_frac"] : NaN
    bc_out    = haskey(data, "bc_output_frac") ? data["bc_output_frac"] : NaN
    wall_s    = haskey(data, "wall_time_s") ? data["wall_time_s"] : NaN
    gamma     = haskey(data, "gamma") ? data["gamma"] : NaN
    betas     = haskey(data, "betas") ? data["betas"] : Float64[]
    fwhm_fs   = haskey(data, "fwhm_fs") ? data["fwhm_fs"] : NaN

    md = """
---
fiber: $(fname)
L_m: $(L_m)
P_cont_W: $(P_W)
J_before: $(J_bef)
J_after: $(J_aft)
J_before_dB: $(@sprintf("%.2f", J_bef_dB))
J_after_dB: $(@sprintf("%.2f", J_aft_dB))
delta_dB: $(@sprintf("%.2f", delta_dB))
quality: $(quality)
converged: $(conv)
iterations: $(iters)
Nt: $(Nt)
time_window_ps: $(round(Int, tw_ps))
grad_norm: $(grad_norm)
E_conservation: $(E_cons)
generated: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
---

# $(fname) — L = $(L_m) m, P = $(P_W) W

## Suppression: $(quality)

| Metric | Value |
|--------|-------|
| J before | $(@sprintf("%.4f", J_bef)) ($(@sprintf("%.2f", J_bef_dB)) dB) |
| J after | $(@sprintf("%.4f", J_aft)) ($(@sprintf("%.2f", J_aft_dB)) dB) |
| Delta | $(@sprintf("%.2f", delta_dB)) dB |
| Converged | $(conv ? "Yes" : "No") |
| Iterations | $(iters) |
| Gradient norm | $(@sprintf("%.2e", grad_norm)) |

## Grid Parameters

| Parameter | Value |
|-----------|-------|
| Nt | $(Nt) |
| Time window | $(round(Int, tw_ps)) ps |
| FWHM | $(isnan(fwhm_fs) ? "N/A" : @sprintf("%.0f fs", fwhm_fs)) |

## Diagnostics

| Check | Value | Status |
|-------|-------|--------|
| E conservation | $(@sprintf("%.6f", E_cons)) | $(abs(1.0 - E_cons) < 0.01 ? "OK" : "WARNING") |
| BC input frac | $(@sprintf("%.2e", bc_in)) | $(bc_in < 1e-3 ? "OK" : "WARNING") |
| BC output frac | $(@sprintf("%.2e", bc_out)) | $(bc_out < 1e-3 ? "OK" : "WARNING") |
| Wall time | $(@sprintf("%.1f s", wall_s)) | |

## Fiber Parameters

| Parameter | Value |
|-----------|-------|
| gamma | $(@sprintf("%.4f", gamma)) W^-1 m^-1 |
| betas | $(join([@sprintf("%.4e", b) for b in betas], ", ")) |

---
*Generated by generate_sweep_reports.jl on $(Dates.format(now(), "yyyy-mm-dd"))*
"""

    open(path, "w") do io
        write(io, md)
    end
    @info "  Wrote $path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 3: Per-fiber summary
# ─────────────────────────────────────────────────────────────────────────────

"""
    generate_fiber_summary(fiber_label, agg_path, point_dirs)

Generate SWEEP_SUMMARY.md for one fiber type, ranked by suppression quality.
"""
function generate_fiber_summary(fiber_label, agg_path, fiber_dir)
    agg = load(agg_path)
    L_vals = agg["L_vals"]
    P_vals = agg["P_vals"]
    J_grid = agg["J_after_grid"]
    conv_grid = agg["converged_grid"]
    drift_grid = agg["drift_pct_grid"]
    N_grid = agg["N_sol_grid"]
    Nt_grid = agg["Nt_grid"]
    tw_grid = agg["time_window_grid"]

    # Collect all points into a sortable list
    points = []
    for (i, L) in enumerate(L_vals), (j, P) in enumerate(P_vals)
        J_lin = J_grid[i, j]
        J_dB = isnan(J_lin) ? NaN : MultiModeNoise.lin_to_dB(J_lin)
        push!(points, (
            L = L, P = P,
            J_dB = J_dB,
            quality = suppression_quality(J_lin),
            converged = conv_grid[i, j],
            drift = drift_grid[i, j],
            N_sol = N_grid[i, j],
            Nt = Nt_grid[i, j],
            tw = tw_grid[i, j],
        ))
    end

    # Sort by J_dB (best suppression first; NaN at end)
    sort!(points, by=p -> isnan(p.J_dB) ? Inf : p.J_dB)

    n_total = length(points)
    n_valid = count(p -> !isnan(p.J_dB), points)
    n_conv  = count(p -> p.converged, points)
    n_exc   = count(p -> p.quality == "EXCELLENT", points)
    n_good  = count(p -> p.quality in ("EXCELLENT", "GOOD"), points)
    best_dB = n_valid > 0 ? minimum(p -> isnan(p.J_dB) ? Inf : p.J_dB, points) : NaN
    worst_dB = n_valid > 0 ? maximum(p -> isnan(p.J_dB) ? -Inf : p.J_dB, points) : NaN

    md = """
# $(fiber_label) Sweep Summary

**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
**Grid:** $(length(L_vals)) L values x $(length(P_vals)) P values = $(n_total) points

## Overview

| Metric | Value |
|--------|-------|
| Total points | $(n_total) |
| Valid (no crash) | $(n_valid) |
| Converged | $(n_conv) / $(n_total) |
| Excellent (< -40 dB) | $(n_exc) / $(n_total) |
| Good (< -30 dB) | $(n_good) / $(n_total) |
| Best J | $(@sprintf("%.1f", best_dB)) dB |
| Worst J | $(@sprintf("%.1f", worst_dB)) dB |

## Ranked Results (best suppression first)

| Rank | L [m] | P [W] | J [dB] | Quality | Converged | Iters | Drift% | N_sol | Nt | TW [ps] |
|------|-------|-------|--------|---------|-----------|-------|--------|-------|------|---------|
"""

    for (rank, p) in enumerate(points)
        md *= @sprintf("| %d | %.1f | %.3f | %.1f | %s | %s | — | %.1f%% | %.1f | %d | %d |\n",
            rank, p.L, p.P,
            isnan(p.J_dB) ? NaN : p.J_dB,
            p.quality,
            p.converged ? "Yes" : "No",
            isnan(p.drift) ? NaN : p.drift,
            isnan(p.N_sol) ? NaN : p.N_sol,
            p.Nt, round(Int, isnan(p.tw) ? 0 : p.tw))
    end

    md *= """

---
*Generated by generate_sweep_reports.jl*
"""

    out_path = joinpath(fiber_dir, "SWEEP_SUMMARY.md")
    open(out_path, "w") do io
        write(io, md)
    end
    @info "Wrote $out_path"

    return points
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 4: Combined sweep report
# ─────────────────────────────────────────────────────────────────────────────

"""
    generate_combined_report(smf28_points, hnlf_points)

Generate the top-level SWEEP_REPORT.md combining both fibers + multistart.
"""
function generate_combined_report(smf28_points, hnlf_points)
    md = """
# Sweep Report — Raman Suppression Optimization

**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))

This report summarizes the L x P parameter sweep for Raman suppression via
spectral phase shaping. Each point optimizes the input spectral phase to
minimize energy transfer into the Raman-shifted frequency band.

## SMF-28 Summary

"""

    md *= _format_top_points(smf28_points, "SMF-28", 5)

    md *= """

## HNLF Summary

"""

    md *= _format_top_points(hnlf_points, "HNLF", 5)

    # Multistart section
    ms_path = joinpath(SR_SWEEP_DIR, "multistart_L2m_P030W.jld2")
    if isfile(ms_path)
        ms = load(ms_path)
        ms_results = ms["ms_results"]  # Vector of NamedTuples

        md *= """

## Multi-Start Robustness (SMF-28 L=$(ms["L_m"])m P=$(ms["P_cont_W"])W)

| Start | Sigma | J [dB] | Converged |
|-------|-------|--------|-----------|
"""
        for r in ms_results
            # J_final may be linear (>0) or already dB (<0) depending on log_cost setting
            J_raw = r.J_final
            J_dB = isnan(J_raw) ? NaN : (J_raw < 0 ? J_raw : MultiModeNoise.lin_to_dB(J_raw))
            md *= @sprintf("| %d | %.1f | %.1f | %s |\n",
                r.start_idx, r.sigma, J_dB, r.converged ? "Yes" : "No")
        end

        valid_J_dB = [let j=r.J_final; isnan(j) ? NaN : (j < 0 ? j : MultiModeNoise.lin_to_dB(j)) end
                      for r in ms_results if !isnan(r.J_final)]
        if length(valid_J_dB) > 0
            best_ms = minimum(valid_J_dB)
            worst_ms = maximum(valid_J_dB)
            spread = worst_ms - best_ms
            md *= @sprintf("\n**Spread:** %.1f dB (best: %.1f dB, worst: %.1f dB)\n",
                spread, best_ms, worst_ms)
            md *= spread < 3.0 ? "**Landscape:** Relatively flat — single basin likely.\n" :
                  spread < 10.0 ? "**Landscape:** Moderate variation — some local minima.\n" :
                  "**Landscape:** Wide spread — multiple distinct local minima.\n"
        end
    else
        md *= "\n## Multi-Start\n\nNo multistart data found at $ms_path.\n"
    end

    md *= """

---

## File Index

Each sweep point directory contains:
- `opt_result.jld2` — Full optimization data (phi_opt, uomega0, convergence, etc.)
- `report_card.png` — 4-panel visual summary (spectrum, phase, convergence, metrics)
- `report.md` — Machine-readable YAML frontmatter + human-readable summary

Per-fiber summaries:
- `sweeps/smf28/SWEEP_SUMMARY.md` — SMF-28 ranked table
- `sweeps/hnlf/SWEEP_SUMMARY.md` — HNLF ranked table

---
*Generated by generate_sweep_reports.jl*
"""

    out_path = joinpath(SR_SWEEP_DIR, "SWEEP_REPORT.md")
    open(out_path, "w") do io
        write(io, md)
    end
    @info "Wrote $out_path"
end

"""Format top N points for the combined report."""
function _format_top_points(points, label, n)
    valid = filter(p -> !isnan(p.J_dB), points)
    n_show = min(n, length(valid))

    n_total = length(points)
    n_conv = count(p -> p.converged, points)
    n_good = count(p -> p.quality in ("EXCELLENT", "GOOD"), points)

    md = @sprintf("**%d/%d converged, %d/%d with J < -30 dB**\n\n",
        n_conv, n_total, n_good, n_total)

    md *= "**Top $(n_show) points:**\n\n"
    md *= "| L [m] | P [W] | J [dB] | Quality | N_sol |\n"
    md *= "|-------|-------|--------|---------|-------|\n"

    for p in valid[1:n_show]
        md *= @sprintf("| %.1f | %.3f | %.1f | %s | %.1f |\n",
            p.L, p.P, p.J_dB, p.quality, isnan(p.N_sol) ? 0.0 : p.N_sol)
    end

    if n_show < length(valid)
        md *= @sprintf("\n*...and %d more points. See per-fiber SWEEP_SUMMARY.md for full ranking.*\n",
            length(valid) - n_show)
    end

    return md
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 5: Main entry point
# ─────────────────────────────────────────────────────────────────────────────

function main()
    @info "Starting sweep report generation"

    smf28_points = NamedTuple[]
    hnlf_points = NamedTuple[]

    for (fiber_key, fiber_label) in [("smf28", "SMF-28"), ("hnlf", "HNLF")]
        fiber_dir = joinpath(SR_SWEEP_DIR, fiber_key)
        agg_path = joinpath(SR_SWEEP_DIR, "sweep_results_$(fiber_key).jld2")

        if !isfile(agg_path)
            @warn "No aggregate data for $fiber_label at $agg_path — skipping"
            continue
        end

        # Generate per-fiber summary
        points = generate_fiber_summary(fiber_label, agg_path, fiber_dir)
        if fiber_key == "smf28"
            smf28_points = points
        else
            hnlf_points = points
        end

        # Generate per-point reports
        point_dirs = filter(isdir, [joinpath(fiber_dir, d) for d in readdir(fiber_dir)])
        n_processed = 0
        n_skipped = 0

        for dir_path in point_dirs
            jld2_path = joinpath(dir_path, "opt_result.jld2")
            if !isfile(jld2_path)
                @warn "No JLD2 in $dir_path — skipping"
                n_skipped += 1
                continue
            end

            try
                generate_point_report(jld2_path, dir_path)
                n_processed += 1
            catch e
                @warn "Failed on $dir_path" exception=e
                n_skipped += 1
            end
        end

        @info @sprintf("%s: %d points processed, %d skipped", fiber_label, n_processed, n_skipped)
    end

    # Generate combined report
    generate_combined_report(smf28_points, hnlf_points)

    @info "Sweep report generation complete"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
