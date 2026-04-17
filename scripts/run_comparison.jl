"""
Re-run the 5 canonical production configurations and produce cross-run
comparison figures (convergence overlay, spectral overlay, summary table,
phase decomposition).

Complements `raman_optimization.jl`: where that script targets a single
canonical config, this one walks the 5 pre-registered configs used for all
paper-style figures and saves a unified comparison set.

# Run
    julia --project=. -t auto scripts/run_comparison.jl

# Inputs
- Pre-registered configs defined at top of file.
- `scripts/common.jl` fiber presets and setup.

# Outputs
- `results/raman/<run_id>/_result.jld2` + `.json` — one per config.
- `results/images/comparison_*.png` — overlay figures.
- `results/images/summary_table.md` — J_before / J_after / Δ-dB / iterations.

# Runtime
~25–40 minutes on a 4-core laptop. Burst VM strongly recommended.

# Docs
Docs: docs/quickstart-optimization.md
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Logging
using Dates
ENV["MPLBACKEND"] = "Agg"  # Non-interactive backend for headless execution
using PyPlot
using MultiModeNoise
using Optim
using JLD2
using JSON3

include("common.jl")
include("visualization.jl")

# NOTE: raman_optimization.jl is included BELOW because its top-level
# include("common.jl") and include("visualization.jl") are safe to re-call
# (both have include guards: _COMMON_JL_LOADED, _VISUALIZATION_JL_LOADED).
# The PROGRAM_FILE guard on line 522 of raman_optimization.jl prevents the
# heavy run block from executing when included from another script.
include("raman_optimization.jl")
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Section 1: Constants (replicate from raman_optimization.jl guarded block)
# These are inside the PROGRAM_FILE guard in raman_optimization.jl and are
# therefore not available when that file is included. We define them here.
# ─────────────────────────────────────────────────────────────────────────────

const RC_RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")

# Fiber parameters — must match raman_optimization.jl exactly
const RC_SMF28_GAMMA = 1.1e-3        # W⁻¹m⁻¹ (1.1 /W/km)
const RC_SMF28_BETAS = [-2.17e-26, 1.2e-40]  # β₂ [s²/m], β₃ [s³/m]

const RC_HNLF_GAMMA = 10.0e-3        # W⁻¹m⁻¹ (10 /W/km)
const RC_HNLF_BETAS = [-0.5e-26, 1.0e-40]   # near-zero dispersion

function rc_run_dir(fiber, params)
    d = joinpath("results", "raman", fiber, params)
    mkpath(d)
    return d
end

# Default pulse parameters (must match common.jl defaults)
const RC_PULSE_FWHM    = 185e-15   # s (185 fs)
const RC_PULSE_REP_RATE = 80.5e6   # Hz
# sech² pulse peak-power factor: P_peak = 0.881374 * P_cont / (FWHM_s * rep_rate)
# Derived from sech² energy integral (see src/simulation/simulate_disp_mmf.jl line 113)
const RC_SECH_FACTOR   = 0.881374

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

# ─── Run 1: SMF-28 baseline ──────────────────────────────────────────────────
dir1 = rc_run_dir("smf28", "L1m_P005W")
@info "\n▶ Run 1: SMF-28 baseline (L=1m, P=0.05W)"
result1, uω0_1, fiber_1, sim_1, band_mask_1, Δf_1 = run_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=50,
    Nt=2^13, β_order=3, time_window=10.0,
    gamma_user=RC_SMF28_GAMMA, betas_user=RC_SMF28_BETAS,
    fiber_name="SMF-28",
    save_prefix=joinpath(dir1, "opt")
)
GC.gc()

# ─── Run 2: SMF-28 high power ────────────────────────────────────────────────
dir2 = rc_run_dir("smf28", "L2m_P030W")
@info "\n▶ Run 2: SMF-28 high power (L=2m, P=0.30W)"
result2, uω0_2, fiber_2, sim_2, band_mask_2, Δf_2 = run_optimization(
    L_fiber=2.0, P_cont=0.30, max_iter=50, validate=false,
    Nt=2^13, β_order=3, time_window=20.0,
    gamma_user=RC_SMF28_GAMMA, betas_user=RC_SMF28_BETAS,
    fiber_name="SMF-28",
    save_prefix=joinpath(dir2, "opt")
)
GC.gc()

# ─── Run 3: HNLF short fiber ─────────────────────────────────────────────────
dir3 = rc_run_dir("hnlf", "L1m_P005W")
@info "\n▶ Run 3: HNLF short fiber (L=1m, P=0.05W)"
result3, uω0_3, fiber_3, sim_3, band_mask_3, Δf_3 = run_optimization(
    L_fiber=1.0, P_cont=0.05, max_iter=80, validate=false,
    Nt=2^14, β_order=3, time_window=15.0,
    gamma_user=RC_HNLF_GAMMA, betas_user=RC_HNLF_BETAS,
    fiber_name="HNLF",
    save_prefix=joinpath(dir3, "opt")
)
GC.gc()

# ─── Run 4: HNLF moderate fiber ──────────────────────────────────────────────
dir4 = rc_run_dir("hnlf", "L2m_P005W")
@info "\n▶ Run 4: HNLF moderate fiber (L=2m, P=0.05W)"
result4, uω0_4, fiber_4, sim_4, band_mask_4, Δf_4 = run_optimization(
    L_fiber=2.0, P_cont=0.05, max_iter=100, validate=false,
    Nt=2^14, β_order=3, time_window=30.0,
    gamma_user=RC_HNLF_GAMMA, betas_user=RC_HNLF_BETAS,
    fiber_name="HNLF",
    save_prefix=joinpath(dir4, "opt")
)
GC.gc()

# ─── Run 5: SMF-28 long fiber (cold start) ───────────────────────────────────
dir5 = rc_run_dir("smf28", "L5m_P015W")
@info "\n▶ Run 5: SMF-28 long fiber (L=5m, P=0.15W, cold start)"
result5, uω0_5, fiber_5, sim_5, band_mask_5, Δf_5 = run_optimization(
    L_fiber=5.0, P_cont=0.15, max_iter=100, validate=false,
    Nt=2^13, β_order=3, time_window=30.0,
    gamma_user=RC_SMF28_GAMMA, betas_user=RC_SMF28_BETAS,
    fiber_name="SMF-28",
    save_prefix=joinpath(dir5, "opt")
)
GC.gc()

@info "═══ All 5 optimization runs complete ═══"

# ─────────────────────────────────────────────────────────────────────────────
# Section 3: Load results from manifest + JLD2
# ─────────────────────────────────────────────────────────────────────────────

@info "\n▶ Loading results from manifest.json"
manifest_path = joinpath("results", "raman", "manifest.json")
@assert isfile(manifest_path) "manifest.json not found at $manifest_path — re-run section 2"

manifest_raw = JSON3.read(read(manifest_path, String), Vector{Dict{String,Any}})

all_runs = Dict{String,Any}[]
for entry in manifest_raw
    jld2_path = entry["result_file"]
    if !isfile(jld2_path)
        @warn "Missing JLD2 file, skipping manifest entry" path=jld2_path
        continue
    end
    jld2_data = JLD2.load(jld2_path)
    # Merge manifest scalars with JLD2 arrays/fields
    merged = merge(Dict{String,Any}(entry), Dict{String,Any}(jld2_data))
    push!(all_runs, merged)
end
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

    # Convert P_cont (average continuum power) to P_peak (sech² pulse peak power)
    fwhm_s  = run["fwhm_fs"] * 1e-15   # fs → s
    P_peak  = RC_SECH_FACTOR * Float64(run["P_cont_W"]) / fwhm_s / RC_PULSE_REP_RATE  # W

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
open(manifest_path, "w") do io
    JSON3.pretty(io, updated_manifest)
end
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
