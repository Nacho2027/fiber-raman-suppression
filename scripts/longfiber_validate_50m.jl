"""
Long-Fiber Validation at L = 50 m (Phase 16 / Session F — stepping stone)

Cheap validation run (~10 min wall on burst VM) that exercises the Phase 16
infrastructure before committing to the expensive L=100m optimization:

1. Forward-solve SMF-28 at L=50m, P=0.05W, FLAT phase, Nt=16384, T=40ps.
2. Forward-solve same config with phi@2m warm-start (interpolated to 50m grid).
3. Report (a) energy conservation (photon-number drift), (b) boundary-condition
   edge energy fraction, (c) J_flat_dB vs J_warm_dB.
4. Run a short L-BFGS (max 30 iter) from the phi@2m warm-start to confirm the
   gradient wire-up is live — J must monotonically decrease in the first 5 iter.
5. Save every result to `results/raman/phase16/50m_validate.jld2`.
6. Emit `results/images/physics_16_01_forward_50m.png` (bar chart of J_dB + J(z)
   flat vs warm endpoints).

RUNS ON BURST VM. Do NOT launch from claude-code-host (CLAUDE.md Rule 1).

Launch:
  burst-ssh "cd fiber-raman-suppression && git pull && \\
             tmux new -d -s F-50m-validate \\
                 'julia -t auto --project=. scripts/longfiber_validate_50m.jl \\
                       > results/raman/phase16/50m_validate.log 2>&1; burst-stop'"
"""

try
    using Revise
catch
end

using Printf
using LinearAlgebra
using FFTW
using Logging
using Statistics
using Dates
using JLD2

ENV["MPLBACKEND"] = "Agg"
using PyPlot
using MultiModeNoise
using Optim

include("longfiber_setup.jl")
include("longfiber_checkpoint.jl")
include("common.jl")
include("raman_optimization.jl")
include("visualization.jl")
include("standard_images.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────

const LF50_RESULTS_DIR = joinpath("results", "raman", "phase16")
const LF50_FIGURE_DIR  = joinpath("results", "images")
const LF50_WARM_START_JLD2 = joinpath("results", "raman", "sweeps", "smf28",
                                      "L2m_P0.05W", "opt_result.jld2")

const LF50_L          = 50.0
const LF50_P_CONT     = 0.05
const LF50_NT         = 16384
const LF50_TIME_WIN   = 40.0         # ps
const LF50_BETA_ORDER = 2             # β₂ only (D-F-01)
const LF50_MAX_ITER   = 30

# ─────────────────────────────────────────────────────────────────────────────
# Helper: photon-number integral (proxy for energy conservation)
# ─────────────────────────────────────────────────────────────────────────────

"""
    photon_number(uω, sim) -> Float64

Proxy for photon number: ∑ |u|² / (ħ ω). For a narrowband pulse this is
approximately ∑|u|²/ω₀ — sufficient to detect >1% drift. We return the L²
energy (∑|u|²) since ω₀ is constant; the relative drift is what matters.
"""
photon_number(uω, sim) = sum(abs2, uω)

# ─────────────────────────────────────────────────────────────────────────────
# Forward solve helper: returns (uωf, J, bc_frac, photon_end)
# ─────────────────────────────────────────────────────────────────────────────

function lf50_forward_solve(uω0_shaped, fiber, sim, band_mask; label::AbstractString)
    t0 = time()
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω_L = sol["ode_sol"](fiber["L"])
    Dω = fiber["Dω"]
    L  = fiber["L"]
    uωf = @. cis(Dω * L) * ũω_L
    wall = time() - t0

    # J at output (frequency domain)
    J, _ = spectral_band_cost(uωf, band_mask)

    # BC check in time domain
    utf = ifft(uωf, 1)
    ok, bc_frac = check_boundary_conditions(utf, sim)

    E_start = photon_number(uω0_shaped, sim)
    E_end   = photon_number(uωf, sim)
    drift   = abs(E_end - E_start) / max(E_start, eps())

    J_dB = 10 * log10(max(J, 1e-20))

    @info @sprintf("[%s] wall=%.1fs  J=%.3e (%.2f dB)  BC_edge=%.2e  E_drift=%.3e",
        label, wall, J, J_dB, bc_frac, drift)

    return (
        uωf        = uωf,
        J          = J,
        J_dB       = J_dB,
        bc_frac    = bc_frac,
        bc_ok      = ok,
        wall       = wall,
        E_drift    = drift,
        E_start    = E_start,
        E_end      = E_end,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Load warm-start phi@2m
# ─────────────────────────────────────────────────────────────────────────────

function lf50_load_warm_start_phi()
    @assert isfile(LF50_WARM_START_JLD2) "warm-start JLD2 missing: $LF50_WARM_START_JLD2"
    d = JLD2.load(LF50_WARM_START_JLD2)
    phi_opt  = Matrix{Float64}(d["phi_opt"])
    Nt_old   = Int(d["Nt"])
    tw_old   = Float64(d["time_window_ps"])
    P_src    = Float64(d["P_cont_W"])
    L_src    = Float64(d["L_m"])
    J_after  = haskey(d, "J_after") ? Float64(d["J_after"]) : NaN
    @info @sprintf("warm-start loaded: L=%.2f m, P=%.4f W, Nt=%d, tw=%.2f ps, J_after=%.3e",
        L_src, P_src, Nt_old, tw_old, J_after)
    return (phi_opt = phi_opt, Nt = Nt_old, tw = tw_old,
            P_cont = P_src, L = L_src, J_after = J_after)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure
# ─────────────────────────────────────────────────────────────────────────────

function lf50_figure(J_flat_dB, J_warm_dB, J_opt_dB, trace_f, out_path)
    fig, axes = PyPlot.subplots(1, 2, figsize = (11, 4))

    ax = axes[1]
    labels = ["flat", "phi@2m warm", "LBFGS 30 iter"]
    vals   = [J_flat_dB, J_warm_dB, J_opt_dB]
    bars   = ax.bar(labels, vals, color = ["#888888", "#4477aa", "#cc5544"])
    ax.set_ylabel("J at L=50 m [dB]")
    ax.set_title("L=50 m SMF-28 P=0.05 W — Raman band energy fraction")
    ax.grid(true, axis = "y", alpha = 0.3)
    for (b, v) in zip(bars, vals)
        ax.text(b.get_x() + b.get_width()/2, v, @sprintf("%.2f", v),
            ha = "center", va = "bottom", fontsize = 9)
    end

    ax2 = axes[2]
    if !isempty(trace_f)
        iters = 0:(length(trace_f)-1)
        f_dB = 10 .* log10.(max.(trace_f, 1e-20))
        ax2.plot(iters, f_dB, "o-", color = "#cc5544")
        ax2.set_xlabel("L-BFGS iteration")
        ax2.set_ylabel("J [dB]")
        ax2.set_title("Optimization trace (warm-start)")
        ax2.grid(true, alpha = 0.3)
    else
        ax2.text(0.5, 0.5, "no trace", transform = ax2.transAxes, ha = "center")
    end

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
    @info "saved figure $out_path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function lf50_run()
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Long-fiber 50 m validation — Session F / Phase 16 — start %s", now())
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Julia threads: %d  BLAS threads: %d",
        Threads.nthreads(), BLAS.get_num_threads())

    mkpath(LF50_RESULTS_DIR)
    mkpath(LF50_FIGURE_DIR)

    # 1. Build 50 m problem (no auto-override)
    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = :SMF28_beta2_only,
        L_fiber      = LF50_L,
        P_cont       = LF50_P_CONT,
        Nt           = LF50_NT,
        time_window  = LF50_TIME_WIN,
        β_order      = LF50_BETA_ORDER,
    )

    # 2. Warm-start phi@2m → interpolate to 50 m grid
    ws = lf50_load_warm_start_phi()
    phi_warm = longfiber_interpolate_phi(ws.phi_opt, ws.Nt, ws.tw, LF50_NT, LF50_TIME_WIN)
    @info @sprintf("phi_warm: size=%s, max|phi|=%.3e, nonzero=%d",
        size(phi_warm), maximum(abs.(phi_warm)), count(!iszero, phi_warm))

    # 3. Forward solves
    uω0_flat = copy(uω0)
    uω0_warm = uω0 .* exp.(1im .* phi_warm)

    fiber_flat = deepcopy(fiber)
    fiber_flat["zsave"] = nothing
    out_flat = lf50_forward_solve(uω0_flat, fiber_flat, sim, band_mask; label = "FLAT")

    fiber_warm = deepcopy(fiber)
    fiber_warm["zsave"] = nothing
    out_warm = lf50_forward_solve(uω0_warm, fiber_warm, sim, band_mask; label = "WARM")

    # 4. Short L-BFGS from warm start
    @info "────── short L-BFGS (max $LF50_MAX_ITER iter) from phi@2m warm-start ──────"
    t_opt_start = time()
    fiber_opt = deepcopy(fiber)
    result = optimize_spectral_phase(uω0, fiber_opt, sim, band_mask;
        φ0 = phi_warm, max_iter = LF50_MAX_ITER, store_trace = true, log_cost = true)
    t_opt = time() - t_opt_start

    phi_opt   = reshape(Optim.minimizer(result), LF50_NT, 1)
    f_trace   = [tr.value for tr in Optim.trace(result)]
    n_iter    = Optim.iterations(result)
    converged = Optim.converged(result)
    grad_norm = Optim.g_residual(result)

    # Re-evaluate J at phi_opt on a clean forward solve (so we have uωf / BC)
    uω0_opt   = uω0 .* exp.(1im .* phi_opt)
    fiber_post = deepcopy(fiber)
    fiber_post["zsave"] = nothing
    out_opt = lf50_forward_solve(uω0_opt, fiber_post, sim, band_mask; label = "OPT")

    @info @sprintf("L-BFGS done: wall=%.1fs, iter=%d, converged=%s, grad_norm=%.2e",
        t_opt, n_iter, converged, grad_norm)

    # 5. Monotonicity check on first 5 iterations
    mono_first5 = true
    if length(f_trace) >= 5
        diffs = diff(f_trace[1:5])
        mono_first5 = all(d <= 0.0 + 1e-9 for d in diffs)
    end

    # 6. PASS / FAIL summary
    pass_energy_flat = out_flat.E_drift < 0.01
    pass_energy_warm = out_warm.E_drift < 0.01
    pass_warm_better = out_warm.J_dB < out_flat.J_dB
    pass_opt_better  = out_opt.J_dB  <= out_warm.J_dB + 0.01
    pass_monotonic   = mono_first5

    @info "════════════════════════════════════════════════════════════════"
    @info @sprintf("[%s] energy conservation (flat)    : drift=%.2e",
        pass_energy_flat ? "PASS" : "FAIL", out_flat.E_drift)
    @info @sprintf("[%s] energy conservation (warm)    : drift=%.2e",
        pass_energy_warm ? "PASS" : "FAIL", out_warm.E_drift)
    @info @sprintf("[%s] warm-start beats flat         : J_flat=%.2f dB, J_warm=%.2f dB",
        pass_warm_better ? "PASS" : "FAIL", out_flat.J_dB, out_warm.J_dB)
    @info @sprintf("[%s] LBFGS reduces warm-start      : J_warm=%.2f dB, J_opt=%.2f dB",
        pass_opt_better ? "PASS" : "FAIL", out_warm.J_dB, out_opt.J_dB)
    @info @sprintf("[%s] first-5-iter monotonic trace  : Δf ≤ 0 for each step",
        pass_monotonic ? "PASS" : "FAIL")
    @info "════════════════════════════════════════════════════════════════"

    # 7. Save
    out_jld2 = joinpath(LF50_RESULTS_DIR, "50m_validate.jld2")
    JLD2.jldsave(out_jld2;
        L_m            = LF50_L,
        P_cont_W       = LF50_P_CONT,
        Nt             = LF50_NT,
        time_window_ps = LF50_TIME_WIN,
        β_order        = LF50_BETA_ORDER,
        phi_warm       = phi_warm,
        phi_opt        = phi_opt,
        f_trace        = f_trace,
        J_flat         = out_flat.J,
        J_warm         = out_warm.J,
        J_opt          = out_opt.J,
        J_flat_dB      = out_flat.J_dB,
        J_warm_dB      = out_warm.J_dB,
        J_opt_dB       = out_opt.J_dB,
        bc_flat        = out_flat.bc_frac,
        bc_warm        = out_warm.bc_frac,
        bc_opt         = out_opt.bc_frac,
        E_drift_flat   = out_flat.E_drift,
        E_drift_warm   = out_warm.E_drift,
        E_drift_opt    = out_opt.E_drift,
        wall_flat      = out_flat.wall,
        wall_warm      = out_warm.wall,
        wall_opt_total = t_opt,
        iter_opt       = n_iter,
        converged      = converged,
        grad_norm      = grad_norm,
        pass_energy_flat = pass_energy_flat,
        pass_energy_warm = pass_energy_warm,
        pass_warm_better = pass_warm_better,
        pass_opt_better  = pass_opt_better,
        pass_monotonic   = pass_monotonic,
        warm_src_path  = LF50_WARM_START_JLD2,
        saved_at       = now(),
    )
    @info "saved $out_jld2"

    # 8. Figure
    fig_path = joinpath(LF50_FIGURE_DIR, "physics_16_01_forward_50m.png")
    lf50_figure(out_flat.J_dB, out_warm.J_dB, out_opt.J_dB, f_trace, fig_path)

    # 9. MANDATORY canonical image set (Project rule 2, 2026-04-17)
    save_standard_set(
        vec(phi_opt), uω0, fiber, sim,
        band_mask, Δf, thr;
        tag = "F_50m_opt",
        fiber_name = "SMF28",
        L_m = LF50_L,
        P_W = LF50_P_CONT,
        output_dir = joinpath(LF50_RESULTS_DIR, "standard_images_F_50m_opt"),
    )

    return (
        pass_all = pass_energy_flat && pass_energy_warm && pass_warm_better &&
                   pass_opt_better && pass_monotonic,
        jld2     = out_jld2,
        fig      = fig_path,
    )
end

# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    result = lf50_run()
    if !result.pass_all
        @error "50 m validation did NOT pass all checks — see log above"
        exit(1)
    end
    @info "50 m validation: ALL PASS"
end
