#!/usr/bin/env julia
# Visualize the Session E Pareto candidates in the project's STANDARD output
# format (opt_phase, opt_evolution, phase_diagnostic). This runs the forward
# propagation with the saved phi_opt and produces the same diagnostic PNGs
# that the canonical raman_optimization.jl run produces.
#
# Designed to run on fiber-raman-burst (single-threaded forward solves are
# light; one shaped + one unshaped run per candidate).
#
# Output directory: presentation-2026-04-17/standard-format/

ENV["MPLBACKEND"] = "Agg"

using JLD2, PyPlot, FFTW, Printf, Logging

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))

using MultiModeNoise

const ROOT   = joinpath(@__DIR__, "..")
const OUTDIR = joinpath(ROOT, "presentation-2026-04-17", "standard-format")
mkpath(OUTDIR)

# Candidates to visualize — matches phase_sweep_simple/candidates.md
const CANDIDATES = [
    (tag="candidate_1_L0p25_P0p02_simple", fiber=:SMF28, L=0.25, P=0.02,
     J_expected=-63.02, title="Simplest phase"),
    (tag="candidate_3_L0p25_P0p10_deepest", fiber=:SMF28, L=0.25, P=0.10,
     J_expected=-82.33, title="Deepest suppression"),
    (tag="canonical_L2p0_P0p20_reference",  fiber=:SMF28, L=2.0, P=0.20,
     J_expected=-68.01, title="Canonical reference from Sweep 1"),
]

# ─────────────────────────────────────────────────────────────────────────────

function load_phi_opt(fiber::Symbol, L::Float64, P::Float64)
    # First try sweep2_LP_fiber.jld2 (for Pareto candidates)
    data = JLD2.load(joinpath(ROOT, "results", "raman", "phase_sweep_simple",
                              "sweep2_LP_fiber.jld2"))
    for r in data["results"]
        cfg = r["config"]
        if cfg[:fiber_preset] == fiber &&
           abs(cfg[:L_fiber] - L) < 1e-6 &&
           abs(cfg[:P_cont] - P) < 1e-6 &&
           cfg[:N_phi] == 57
            return (r["phi_opt"], r["J_final"], 57, r["c_opt"])
        end
    end

    # Fall back to sweep1_Nphi (canonical SMF-28 L=2m P=0.2W reference)
    data = JLD2.load(joinpath(ROOT, "results", "raman", "phase_sweep_simple",
                              "sweep1_Nphi.jld2"))
    for r in data["results"]
        cfg = r["config"]
        if cfg[:fiber_preset] == fiber &&
           abs(cfg[:L_fiber] - L) < 1e-6 &&
           abs(cfg[:P_cont] - P) < 1e-6 &&
           r["N_phi"] == 128
            return (r["phi_opt"], r["J_final"], 128, r["c_opt"])
        end
    end
    error("No phi_opt found for $fiber L=$L P=$P")
end

# ─────────────────────────────────────────────────────────────────────────────
# Plot 1 — Standard phase diagnostic (wrapped / unwrapped / group delay)
# ─────────────────────────────────────────────────────────────────────────────

function save_phase_plots(phi_opt, uω0, sim, tag, J_expected, N_phi_used,
                          title, fiber_name, L_m, P_cont_W)
    outdir_c = joinpath(OUTDIR, tag)
    mkpath(outdir_c)

    metadata = (
        fiber_name = fiber_name,
        L_m        = L_m,
        P_cont_W   = P_cont_W,
        lambda0_nm = 1550.0,
        fwhm_fs    = 185.0,
    )

    plot_phase_diagnostic(phi_opt, uω0, sim;
        save_path = joinpath(outdir_c, "phase_diagnostic.png"),
        metadata  = metadata)
    println("  wrote $tag/phase_diagnostic.png")
end

# ─────────────────────────────────────────────────────────────────────────────
# Plot 2 — Spectral and temporal evolution (waterfall) for unshaped + shaped
# ─────────────────────────────────────────────────────────────────────────────

function save_evolution_plots(phi_opt, uω0_base, fiber, sim, tag, title)
    outdir_c = joinpath(OUTDIR, tag)
    mkpath(outdir_c)

    # z-resolved run for waterfall (32 z-samples is plenty)
    fiber_evo = deepcopy(fiber)
    fiber_evo["zsave"] = collect(range(0.0, fiber["L"], length=32))

    for (label, phi) in [("unshaped", zero(phi_opt)), ("optimized", phi_opt)]
        uω0_shaped = @. uω0_base * cis(phi)
        sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_evo, sim)

        fig_s = plot_spectral_evolution(sol, sim, fiber_evo)
        savefig(joinpath(outdir_c, "evolution_spectral_$label.png"),
                dpi=300, bbox_inches="tight")
        close(fig_s)

        fig_t = plot_temporal_evolution(sol, sim, fiber_evo)
        savefig(joinpath(outdir_c, "evolution_temporal_$label.png"),
                dpi=300, bbox_inches="tight")
        close(fig_t)
        println("  wrote $tag/evolution_{spectral,temporal}_$label.png")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Plot 3 — before/after side-by-side (the "opt_phase" equivalent in standard
# output)
# ─────────────────────────────────────────────────────────────────────────────

function save_comparison_plot(phi_opt, uω0_base, fiber, sim,
                              band_mask, Δf, raman_threshold, tag,
                              fiber_name, L_m, P_cont_W)
    outdir_c = joinpath(OUTDIR, tag)
    mkpath(outdir_c)
    metadata = (
        fiber_name = fiber_name,
        L_m        = L_m,
        P_cont_W   = P_cont_W,
        lambda0_nm = 1550.0,
        fwhm_fs    = 185.0,
    )
    plot_optimization_result_v2(
        zero(phi_opt), phi_opt, uω0_base, fiber, sim,
        band_mask, Δf, raman_threshold;
        save_path = joinpath(outdir_c, "opt_result.png"),
        metadata  = metadata)
    println("  wrote $tag/opt_result.png")
end

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────

@info "Rendering $(length(CANDIDATES)) candidates into $OUTDIR"

for cand in CANDIDATES
    println("\n=== $(cand.tag) ===")

    phi_opt, J_actual, N_phi_used, c_opt = load_phi_opt(cand.fiber, cand.L, cand.P)

    # Set up with matching params. Nt=16384 matches the sweep runs; time_window
    # auto-sizes on SPM for long fibers.
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        Nt          = 2^14,
        time_window = 10.0,
        β_order     = 3,
        L_fiber     = cand.L,
        P_cont      = cand.P,
        fiber_preset = cand.fiber,
    )

    println("  loaded phi_opt: length=$(length(phi_opt)), J_saved=$(J_actual) dB")
    println("  sim Nt=$(sim["Nt"])  time_window=$(sim["ts"][end]*2*1e12) ps")

    fname = String(cand.fiber)
    save_phase_plots(phi_opt, uω0, sim, cand.tag, J_actual, N_phi_used,
                     cand.title, fname, cand.L, cand.P)
    save_evolution_plots(phi_opt, uω0, fiber, sim, cand.tag, cand.title)
    save_comparison_plot(phi_opt, uω0, fiber, sim, band_mask, Δf,
                         raman_threshold, cand.tag, fname, cand.L, cand.P)
end

println("\nAll candidates rendered under: $OUTDIR")
