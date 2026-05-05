"""
Re-run the 5 canonical production configurations and produce cross-run
comparison figures (convergence overlay, spectral overlay, summary table,
phase decomposition).

Complements `raman_optimization.jl`: where that script targets a single
canonical config, this one walks the 5 pre-registered configs used for all
paper-style figures and saves a unified comparison set.

# Run
    julia --project=. -t auto scripts/workflows/run_comparison.jl

# Inputs
- Pre-registered configs defined at top of file.
- `scripts/lib/common.jl` fiber presets and setup.

# Outputs
- `results/raman/<run_id>/opt_result.jld2` + `.json` — one per config.
- `results/images/comparison_*.png` — overlay figures.
- `results/images/summary_table.md` — J_before / J_after / Δ-dB / iterations.

# Runtime
~25–40 minutes on a 4-core laptop. Burst VM strongly recommended.

# Docs
Docs: docs/guides/supported-workflows.md
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Logging
using Dates
ENV["MPLBACKEND"] = "Agg"  # Non-interactive backend for headless execution
using PyPlot
using FiberLab
using Optim
using JLD2
using JSON3

# Shared workflow dependencies live in ../lib; keep them explicit here so this
# script does not rely on a same-directory include chain.
include(joinpath(@__DIR__, "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "lib", "canonical_runs.jl"))
include(joinpath(@__DIR__, "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "lib", "determinism.jl"))
ensure_deterministic_environment()

const RC_RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")

# Default pulse parameters (must match common.jl defaults)
const RC_PULSE_FWHM    = 185e-15   # s (185 fs)
const RC_PULSE_REP_RATE = 80.5e6   # Hz

if abspath(PROGRAM_FILE) == @__FILE__

mkpath("results/images")

# ─────────────────────────────────────────────────────────────────────────────
# Section 2: Re-run all 5 optimization configs (D-01)
#
# Five configurations spanning moderate to extreme Raman shifting:
#   Run 1: SMF-28 baseline       (L=1m,  P=0.05W, N~2.3)
#   Run 2: SMF-28 high power     (L=2m,  P=0.30W, N~5.6)
#   Run 3: HNLF short fiber      (L=1m,  P=0.05W, N~6.9 from high gamma)
#   Run 4: HNLF moderate fiber   (L=2m,  P=0.05W, N~4.9)
#   Run 5: SMF-28 long fiber     (L=5m,  P=0.15W, cold start)
#
# Each call saves a JLD2 result file and updates manifest.json (Phase 5).
# ─────────────────────────────────────────────────────────────────────────────

@info "═══════════════════════════════════════════════════════════"
@info "  Phase 6: Cross-Run Comparison — Re-running 5 configs"
@info "═══════════════════════════════════════════════════════════"

for spec in canonical_raman_run_specs()
    dir = canonical_run_output_dir(spec.fiber_slug, spec.params_slug)
    @info "\n▶ $(spec.label)"
    run_optimization(;
        spec.kwargs...,
        save_prefix=joinpath(dir, "opt"),
    )
    GC.gc()
end

@info "═══ All 5 optimization runs complete ═══"

# ─────────────────────────────────────────────────────────────────────────────
# Section 3: Load results from manifest + JLD2
# ─────────────────────────────────────────────────────────────────────────────

@info "\n▶ Loading results from manifest.json"
manifest_path = joinpath("results", "raman", "manifest.json")
@assert isfile(manifest_path) "manifest.json not found at $manifest_path — re-run section 2"

manifest_raw = FiberLab.read_run_manifest(manifest_path)
all_runs = FiberLab.load_canonical_runs(manifest_path)
@info "Loaded $(length(all_runs)) runs from manifest"
@assert length(all_runs) >= 5 "Expected ≥ 5 runs, got $(length(all_runs)) — check manifest.json"

# ─────────────────────────────────────────────────────────────────────────────
# Section 4: Compute soliton number N and update manifest (PATT-02 / D-05)
#
# P_peak = 0.881374 * P_cont / (FWHM_s * rep_rate)
# The 0.881374 factor comes from the sech² pulse energy integral
# (see src/simulation/simulate_disp_mmf.jl line 113).
# compute_soliton_number expects PEAK power (P0_W), not average/continuum power.
# ─────────────────────────────────────────────────────────────────────────────

@info "\n▶ Computing soliton numbers"
for run in all_runs
    betas = run["betas"]
    # Pitfall 5 fallback: empty betas from old JLD2 files
    beta2 = if isempty(betas)
        run["fiber_name"] == "SMF-28" ? RC_SMF28_BETAS[1] : RC_HNLF_BETAS[1]
    else
        betas[1]
    end

    fwhm_s  = run["fwhm_fs"] * 1e-15   # fs → s
    P_peak  = peak_power_from_average_power(
        Float64(run["P_cont_W"]), fwhm_s, RC_PULSE_REP_RATE)

    N = compute_soliton_number(Float64(run["gamma"]), P_peak,
                                Float64(run["fwhm_fs"]), Float64(beta2))
    run["soliton_number_N"] = N
    @info @sprintf("  %s L=%.1fm P=%.2fW P_peak=%.1fW → N = %.2f",
        run["fiber_name"], run["L_m"], run["P_cont_W"], P_peak, N)
end

# Update manifest.json with soliton numbers
# JSON3 returns immutable objects, so we rebuild each entry as a Dict
updated_manifest = Vector{Dict{String,Any}}()
for entry in manifest_raw
    entry_dict = Dict{String,Any}(entry)
    # Find the matching loaded run by result_file path
    matching_idx = findfirst(r -> r["result_file"] == entry["result_file"], all_runs)
    if !isnothing(matching_idx)
        entry_dict["soliton_number_N"] = all_runs[matching_idx]["soliton_number_N"]
    end
    push!(updated_manifest, entry_dict)
end
FiberLab.write_run_manifest(manifest_path, updated_manifest)
@info "Updated manifest.json with soliton_number_N for $(length(updated_manifest)) entries"

# ─────────────────────────────────────────────────────────────────────────────
# Section 5: Phase decomposition analysis (PATT-01 / D-04)
#
# Decompose each optimal phase onto GDD/TOD polynomial basis and report
# coefficients and residual fraction.
# sim_Dt in JLD2 is in picoseconds (sim["Δt"] = time_window_ps / Nt).
# decompose_phase_polynomial expects sim_Dt in seconds → multiply by 1e-12.
# ─────────────────────────────────────────────────────────────────────────────

@info "\n▶ Phase decomposition (GDD/TOD polynomial basis):"
for run in all_runs
    sim_Dt_s = Float64(run["sim_Dt"]) * 1e-12   # ps → s
    Nt_run   = Int(run["Nt"])
    result   = decompose_phase_polynomial(run["phi_opt"], run["uomega0"], sim_Dt_s, Nt_run)
    run["gdd_fs2"]           = result.gdd_fs2
    run["tod_fs3"]           = result.tod_fs3
    run["residual_fraction"] = result.residual_fraction
    @info @sprintf("  %s L=%.1fm P=%.2fW: GDD=%.1f fs², TOD=%.1f fs³, residual=%.1f%%",
        run["fiber_name"], run["L_m"], run["P_cont_W"],
        result.gdd_fs2, result.tod_fs3, result.residual_fraction * 100)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section 6: Generate comparison figures
# ─────────────────────────────────────────────────────────────────────────────

@info "\n▶ Generating comparison figures"

# Figure 1: Summary table (XRUN-02)
plot_cross_run_summary_table(all_runs;
    save_path="results/images/cross_run_summary_table.png")
@info "Saved summary table → results/images/cross_run_summary_table.png"
close("all")

# Figure 2: Convergence overlay (XRUN-03)
plot_convergence_overlay(all_runs;
    save_path="results/images/convergence_overlay_all_runs.png")
@info "Saved convergence overlay → results/images/convergence_overlay_all_runs.png"
close("all")

# Figure 3: SMF-28 spectral overlay (XRUN-04)
smf_runs = filter(r -> r["fiber_name"] == "SMF-28", all_runs)
if !isempty(smf_runs)
    plot_spectral_overlay(smf_runs, "SMF-28";
        save_path="results/images/spectral_overlay_SMF28.png")
    @info "Saved SMF-28 spectral overlay → results/images/spectral_overlay_SMF28.png"
else
    @warn "No SMF-28 runs found — spectral_overlay_SMF28.png not generated"
end
close("all")

# Figure 4: HNLF spectral overlay (XRUN-04)
hnlf_runs = filter(r -> r["fiber_name"] == "HNLF", all_runs)
if !isempty(hnlf_runs)
    plot_spectral_overlay(hnlf_runs, "HNLF";
        save_path="results/images/spectral_overlay_HNLF.png")
    @info "Saved HNLF spectral overlay → results/images/spectral_overlay_HNLF.png"
else
    @warn "No HNLF runs found — spectral_overlay_HNLF.png not generated"
end
close("all")

# ─────────────────────────────────────────────────────────────────────────────
# Section 7: Final summary log
# ─────────────────────────────────────────────────────────────────────────────

@info @sprintf("""
┌─────────────────────────────────────────────────────────┐
│  Phase 6: Cross-Run Comparison Complete                 │
├─────────────────────────────────────────────────────────┤
│  Figures saved to results/images/:                      │
│    cross_run_summary_table.png                          │
│    convergence_overlay_all_runs.png                     │
│    spectral_overlay_SMF28.png                           │
│    spectral_overlay_HNLF.png                            │
├─────────────────────────────────────────────────────────┤
│  manifest.json updated with soliton_number_N            │
│  Phase decomposition (GDD/TOD) logged above             │
└─────────────────────────────────────────────────────────┘""")

end # if abspath(PROGRAM_FILE) == @__FILE__
