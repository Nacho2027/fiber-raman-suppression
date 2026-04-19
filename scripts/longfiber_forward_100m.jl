"""
Long-Fiber Forward-Solve Baseline at L = 100 m (Phase 16 / Session F)

Forward solves ONLY (no optimization). Purpose is to establish:

  1. Per-solve wall time at (Nt=32768, T=160 ps, reltol=1e-7 from ODE defaults).
     Drives the L-BFGS iteration budget for Task 5 (longfiber_optimize_100m.jl).
  2. Grid adequacy: BC edge fraction and aliasing check (energy at |Δf| > 0.4
     * Nyquist should be < 1%).
  3. Reference J_dB at endpoint for (a) flat phase, (b) phi@2m warm-start —
     these endpoints anchor Task 5's success criterion.

Two solves per run:
  - FLAT  : φ(ω) = 0
  - WARM  : φ(ω) = longfiber_interpolate_phi(phi@2m)

Outputs:
  results/raman/phase16/100m_forward_flat.jld2
  results/raman/phase16/100m_forward_warm.jld2
  results/images/physics_16_02_forward_100m.png

RUNS ON BURST VM. Launch:
  burst-ssh "cd fiber-raman-suppression && git pull && \\
             tmux new -d -s F-100m-forward \\
                 'julia -t auto --project=. scripts/longfiber_forward_100m.jl \\
                       > results/raman/phase16/100m_forward.log 2>&1; burst-stop'"
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

include("longfiber_setup.jl")
include("common.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────

const LF100F_RESULTS_DIR = joinpath("results", "raman", "phase16")
const LF100F_FIGURE_DIR  = joinpath("results", "images")
const LF100F_WARM_START_JLD2 = joinpath("results", "raman", "sweeps", "smf28",
                                        "L2m_P0.05W", "opt_result.jld2")

const LF100F_L          = 100.0
const LF100F_P_CONT     = 0.05
const LF100F_NT         = 32768
const LF100F_TIME_WIN   = 160.0
const LF100F_BETA_ORDER = 2
# Aliasing cutoff: fraction of Nyquist above which we flag high-freq energy.
const LF100F_ALIAS_CUTOFF = 0.4

# ─────────────────────────────────────────────────────────────────────────────
# Aliasing check: fraction of spectral energy at |Δf| > cutoff × Nyquist
# ─────────────────────────────────────────────────────────────────────────────

"""
    spectral_aliasing_fraction(uω, sim; cutoff=0.4) -> Float64

Fraction of total energy in |Δf| > cutoff × f_Nyquist. If this is > 1% the grid
is too coarse for the physical bandwidth — bump Nt or reduce power.
"""
function spectral_aliasing_fraction(uω, sim; cutoff::Real = 0.4)
    Nt = sim["Nt"]
    Δt = sim["Δt"]
    f_ny = 0.5 / Δt
    Δf_fft = fftfreq(Nt, 1.0 / Δt)
    hi_mask = abs.(Δf_fft) .> cutoff * f_ny
    E_total = sum(abs2, uω)
    E_hi    = sum(abs2, uω[hi_mask, :])
    return E_hi / max(E_total, eps())
end

# ─────────────────────────────────────────────────────────────────────────────
# Forward solve + full diagnostics
# ─────────────────────────────────────────────────────────────────────────────

function lf100f_forward(uω0_shaped, fiber, sim, band_mask; label::AbstractString)
    t0 = time()
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω_L = sol["ode_sol"](fiber["L"])
    Dω = fiber["Dω"]
    L  = fiber["L"]
    uωf = @. cis(Dω * L) * ũω_L
    wall = time() - t0

    J, _ = spectral_band_cost(uωf, band_mask)
    J_dB = 10 * log10(max(J, 1e-20))

    utf = ifft(uωf, 1)
    ok_bc, bc_frac = check_boundary_conditions(utf, sim)

    alias_frac = spectral_aliasing_fraction(uωf, sim; cutoff = LF100F_ALIAS_CUTOFF)
    alias_frac_in = spectral_aliasing_fraction(uω0_shaped, sim; cutoff = LF100F_ALIAS_CUTOFF)

    E_start = sum(abs2, uω0_shaped)
    E_end   = sum(abs2, uωf)
    drift   = abs(E_end - E_start) / max(E_start, eps())

    @info @sprintf("[%s] wall=%.1fs  J=%.3e (%.2f dB)  BC=%.2e  alias_in=%.2e alias_out=%.2e  E_drift=%.3e",
        label, wall, J, J_dB, bc_frac, alias_frac_in, alias_frac, drift)

    return (
        uωf            = uωf,
        uω_input       = copy(uω0_shaped),
        J              = J,
        J_dB           = J_dB,
        bc_frac        = bc_frac,
        bc_ok          = ok_bc,
        alias_frac_in  = alias_frac_in,
        alias_frac_out = alias_frac,
        wall           = wall,
        E_drift        = drift,
        E_start        = E_start,
        E_end          = E_end,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Load warm-start phi@2m (identical to 50m loader, kept local so the script
# can be run without Task 3 being present)
# ─────────────────────────────────────────────────────────────────────────────

function lf100f_load_warm_start_phi()
    @assert isfile(LF100F_WARM_START_JLD2) "warm-start JLD2 missing: $LF100F_WARM_START_JLD2"
    d = JLD2.load(LF100F_WARM_START_JLD2)
    phi_opt = Matrix{Float64}(d["phi_opt"])
    Nt_old  = Int(d["Nt"])
    tw_old  = Float64(d["time_window_ps"])
    @info @sprintf("warm-start: Nt=%d, tw=%.2f ps", Nt_old, tw_old)
    return (phi_opt = phi_opt, Nt = Nt_old, tw = tw_old)
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure: spectra at z=0 and z=L for flat and warm
# ─────────────────────────────────────────────────────────────────────────────

function lf100f_figure(out_flat, out_warm, sim, band_mask, out_path)
    Nt = sim["Nt"]
    Δf_fft = fftfreq(Nt, 1.0 / sim["Δt"])
    Δf_shift = fftshift(Δf_fft) * 1e-12   # THz

    fig, axes = PyPlot.subplots(2, 1, figsize = (10, 8), sharex = true)

    # Top: |u|² input spectrum (flat = warm by power only; show both)
    ax = axes[1]
    P_flat_in = fftshift(vec(sum(abs2.(out_flat.uω_input), dims = 2)))
    P_warm_in = fftshift(vec(sum(abs2.(out_warm.uω_input), dims = 2)))
    P_norm = maximum(P_flat_in)
    ax.semilogy(Δf_shift, P_flat_in ./ P_norm; lw = 1.2, color = "#888888",
        label = "flat (input)")
    ax.semilogy(Δf_shift, P_warm_in ./ P_norm; lw = 1.2, color = "#4477aa",
        ls = "--", label = "warm (input)")
    ax.axvspan(-25, -5; alpha = 0.10, color = "#cc5544", label = "Raman band")
    ax.set_ylabel("|u(ω)|² / max (input)")
    ax.set_title(@sprintf("L=100 m SMF-28 P=%.3f W — forward-solve spectra", LF100F_P_CONT))
    ax.set_ylim(1e-10, 2)
    ax.grid(true, which = "both", alpha = 0.3)
    ax.legend(loc = "upper right")

    # Bottom: |u|² output spectrum
    ax2 = axes[2]
    P_flat_out = fftshift(vec(sum(abs2.(out_flat.uωf), dims = 2)))
    P_warm_out = fftshift(vec(sum(abs2.(out_warm.uωf), dims = 2)))
    P_norm_out = maximum(P_flat_out)
    ax2.semilogy(Δf_shift, P_flat_out ./ P_norm_out; lw = 1.2, color = "#888888",
        label = @sprintf("flat, J=%.2f dB", out_flat.J_dB))
    ax2.semilogy(Δf_shift, P_warm_out ./ P_norm_out; lw = 1.2, color = "#4477aa",
        label = @sprintf("phi@2m warm, J=%.2f dB", out_warm.J_dB))
    ax2.axvspan(-25, -5; alpha = 0.10, color = "#cc5544")
    ax2.set_xlabel("Δf  [THz]")
    ax2.set_ylabel("|u(ω)|² / max (output)")
    ax2.set_ylim(1e-10, 2)
    ax2.grid(true, which = "both", alpha = 0.3)
    ax2.legend(loc = "upper right")
    ax2.set_xlim(-60, 60)

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
    @info "saved figure $out_path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function lf100f_run()
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Long-fiber 100 m forward baseline — Session F / Phase 16 — start %s", now())
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Julia threads: %d  BLAS threads: %d",
        Threads.nthreads(), BLAS.get_num_threads())

    mkpath(LF100F_RESULTS_DIR)
    mkpath(LF100F_FIGURE_DIR)

    # Problem setup
    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = :SMF28_beta2_only,
        L_fiber      = LF100F_L,
        P_cont       = LF100F_P_CONT,
        Nt           = LF100F_NT,
        time_window  = LF100F_TIME_WIN,
        β_order      = LF100F_BETA_ORDER,
    )

    # Warm-start phi@2m → interpolate
    ws = lf100f_load_warm_start_phi()
    phi_warm = longfiber_interpolate_phi(ws.phi_opt, ws.Nt, ws.tw,
                                         LF100F_NT, LF100F_TIME_WIN)
    @info @sprintf("phi_warm: max|phi|=%.3e, nonzero=%d / %d",
        maximum(abs.(phi_warm)), count(!iszero, phi_warm), LF100F_NT)

    # Flat solve
    fiber_flat = deepcopy(fiber); fiber_flat["zsave"] = nothing
    out_flat = lf100f_forward(copy(uω0), fiber_flat, sim, band_mask; label = "FLAT")

    # Warm solve
    fiber_warm = deepcopy(fiber); fiber_warm["zsave"] = nothing
    uω0_warm = uω0 .* exp.(1im .* phi_warm)
    out_warm = lf100f_forward(uω0_warm, fiber_warm, sim, band_mask; label = "WARM")

    # Checks
    pass_bc_flat     = out_flat.bc_frac    < 1e-4
    pass_bc_warm     = out_warm.bc_frac    < 1e-4
    pass_alias_flat  = out_flat.alias_frac_out < 0.01
    pass_alias_warm  = out_warm.alias_frac_out < 0.01
    pass_energy_flat = out_flat.E_drift    < 0.01
    pass_energy_warm = out_warm.E_drift    < 0.01
    pass_wall        = out_flat.wall       < 300.0   # 5 min per solve budget

    @info "════════════════════════════════════════════════════════════════"
    @info @sprintf("[%s] BC edge energy flat  : %.2e", pass_bc_flat ? "PASS" : "WARN", out_flat.bc_frac)
    @info @sprintf("[%s] BC edge energy warm  : %.2e", pass_bc_warm ? "PASS" : "WARN", out_warm.bc_frac)
    @info @sprintf("[%s] aliasing frac flat   : %.2e", pass_alias_flat ? "PASS" : "FAIL", out_flat.alias_frac_out)
    @info @sprintf("[%s] aliasing frac warm   : %.2e", pass_alias_warm ? "PASS" : "FAIL", out_warm.alias_frac_out)
    @info @sprintf("[%s] energy drift flat    : %.2e", pass_energy_flat ? "PASS" : "FAIL", out_flat.E_drift)
    @info @sprintf("[%s] energy drift warm    : %.2e", pass_energy_warm ? "PASS" : "FAIL", out_warm.E_drift)
    @info @sprintf("[%s] per-solve wall time  : %.1fs (<300 s budget)",
        pass_wall ? "PASS" : "WARN", out_flat.wall)
    @info @sprintf("  J_flat = %.2f dB  J_warm = %.2f dB  Δ = %+.2f dB",
        out_flat.J_dB, out_warm.J_dB, out_warm.J_dB - out_flat.J_dB)
    @info "════════════════════════════════════════════════════════════════"

    # Save
    path_flat = joinpath(LF100F_RESULTS_DIR, "100m_forward_flat.jld2")
    JLD2.jldsave(path_flat;
        L_m            = LF100F_L,
        P_cont_W       = LF100F_P_CONT,
        Nt             = LF100F_NT,
        time_window_ps = LF100F_TIME_WIN,
        β_order        = LF100F_BETA_ORDER,
        label          = "flat",
        J              = out_flat.J,
        J_dB           = out_flat.J_dB,
        uωf            = out_flat.uωf,
        bc_frac        = out_flat.bc_frac,
        alias_frac     = out_flat.alias_frac_out,
        E_drift        = out_flat.E_drift,
        wall_s         = out_flat.wall,
        saved_at       = now(),
    )
    @info "saved $path_flat"

    path_warm = joinpath(LF100F_RESULTS_DIR, "100m_forward_warm.jld2")
    JLD2.jldsave(path_warm;
        L_m            = LF100F_L,
        P_cont_W       = LF100F_P_CONT,
        Nt             = LF100F_NT,
        time_window_ps = LF100F_TIME_WIN,
        β_order        = LF100F_BETA_ORDER,
        label          = "phi@2m_warm",
        phi_warm       = phi_warm,
        J              = out_warm.J,
        J_dB           = out_warm.J_dB,
        uωf            = out_warm.uωf,
        bc_frac        = out_warm.bc_frac,
        alias_frac     = out_warm.alias_frac_out,
        E_drift        = out_warm.E_drift,
        wall_s         = out_warm.wall,
        warm_src_path  = LF100F_WARM_START_JLD2,
        saved_at       = now(),
    )
    @info "saved $path_warm"

    # Figure
    fig_path = joinpath(LF100F_FIGURE_DIR, "physics_16_02_forward_100m.png")
    lf100f_figure(out_flat, out_warm, sim, band_mask, fig_path)

    return (
        pass_all = pass_bc_flat && pass_bc_warm && pass_alias_flat && pass_alias_warm &&
                   pass_energy_flat && pass_energy_warm,
        wall_flat = out_flat.wall,
        wall_warm = out_warm.wall,
    )
end

# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    result = lf100f_run()
    if !result.pass_all
        @warn "100 m forward solve did NOT pass all checks — inspect log before launching Task 5"
    end
    @info @sprintf("per-solve wall budget for Task 5: ~%.1f s/iter (× 2 forward+adjoint) × 100 iter ≈ %.1f min",
        result.wall_flat, 2 * result.wall_flat * 100 / 60)
end
