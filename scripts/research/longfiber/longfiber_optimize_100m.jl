"""
Long-Fiber Spectral Phase Optimization at L = 100 m (Phase 16 / Session F)

Core Phase 16 run: L-BFGS on φ(ω) at L=100 m, SMF-28, P=0.05 W, starting from
the phi@2 m multistart seed (identity-warm-start, interpolated to the 100 m
grid). Checkpointing every 5 iter + wall-gate every 10 min so an overnight
crash does not lose progress (D-F-05).

Two modes controlled by ENV var `LF100_MODE`:
  - "fresh"  (default) : start from warm phi@2m, run max 100 iter
  - "resume"           : load highest-iter ckpt in LF100_OUT_DIR, continue
  - "resume_check"     : two-phase run — run 15 iter, reload from ckpt, run
                         remaining iter. Produces both `100m_opt_full_result.jld2`
                         (fresh run) and `100m_opt_resume_result.jld2` (resumed
                         run) so downstream analysis can verify final-J parity.

Uses `longfiber_make_fg!` + `longfiber_checkpoint_cb` from
`longfiber_checkpoint.jl`. DOES NOT modify the shared
`optimize_spectral_phase` helper in `scripts/raman_optimization.jl` (Rule P1);
instead replicates its forward+adjoint glue here so the callback is wired in.

Outputs:
  results/raman/phase16/100m_optim/ckpt_iter_0005.jld2 ... ckpt_iter_XXXX.jld2
  results/raman/phase16/100m_opt_full_result.jld2
  results/raman/phase16/100m_opt_resume_result.jld2  (only in resume_check)
  results/images/physics_16_03_optimization_trace_100m.png

Launch on burst VM with heavy lock:
  burst-ssh "test -e /tmp/burst-heavy-lock && echo LOCKED || \\
             (touch /tmp/burst-heavy-lock && \\
              cd fiber-raman-suppression && git pull && \\
              tmux new -d -s F-100m-opt \\
                  'LF100_MODE=resume_check julia -t auto --project=. \\
                        scripts/research/longfiber/longfiber_optimize_100m.jl \\
                        > results/raman/phase16/100m_opt.log 2>&1; \\
                   rm -f /tmp/burst-heavy-lock; burst-stop')"
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

include(joinpath(@__DIR__, "longfiber_setup.jl"))
include(joinpath(@__DIR__, "longfiber_checkpoint.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))    # needed by standard_images.jl
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))
# NOTE: intentionally NOT including raman_optimization.jl — we replicate the
# fg! body locally so the checkpoint callback can be wired in without editing
# the shared `optimize_spectral_phase` function.

"""
    lf100_save_standard_images(prob, phi_opt; tag, output_dir)

Wrapper around `save_standard_set(...)` enforcing the Project-level rule
that every driver producing a phi_opt MUST emit the canonical 4-PNG set.
"""
function lf100_save_standard_images(prob, phi_opt::AbstractVector{<:Real};
        tag::AbstractString, output_dir::AbstractString)
    save_standard_set(
        phi_opt, prob.uω0, prob.fiber, prob.sim,
        prob.band_mask, prob.Δf, prob.raman_threshold;
        tag = tag,
        fiber_name = "SMF28",
        L_m = LF100_L,
        P_W = LF100_P_CONT,
        output_dir = output_dir,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────

function _env_float(name::AbstractString, default::Float64)
    return parse(Float64, get(ENV, name, string(default)))
end

function _env_int(name::AbstractString, default::Int)
    return parse(Int, get(ENV, name, string(default)))
end

function _lf_default_label(L_m::Real)
    if abs(L_m - round(L_m)) < 1e-9
        return @sprintf("%dm", round(Int, L_m))
    end
    return replace(@sprintf("%.3gm", L_m), "." => "p")
end

function _safe_label(label::AbstractString)
    return replace(strip(label), r"[^A-Za-z0-9_-]" => "_")
end

const LF100_RESULTS_DIR = joinpath("results", "raman", "phase16")
const LF100_FIGURE_DIR  = joinpath("results", "images")
const LF100_WARM_START_JLD2 = joinpath("results", "raman", "sweeps", "smf28",
                                       "L2m_P0.05W", "opt_result.jld2")

const LF100_L          = _env_float("LF100_L", 100.0)
const LF100_P_CONT     = _env_float("LF100_P_CONT", 0.05)
const LF100_NT         = _env_int("LF100_NT", 32768)
const LF100_TIME_WIN   = _env_float("LF100_TIME_WIN", 160.0)
const LF100_RUN_LABEL  = _safe_label(get(ENV, "LF100_RUN_LABEL", _lf_default_label(LF100_L)))
const LF100_CKPT_DIR   = joinpath(LF100_RESULTS_DIR, "$(LF100_RUN_LABEL)_optim")
const LF100_BETA_ORDER = _env_int("LF100_BETA_ORDER", 2)
const LF100_MAX_ITER   = parse(Int, get(ENV, "LF100_MAX_ITER", "100"))
const LF100_CKPT_EVERY = 5
const LF100_CKPT_TIME_GATE_S = 600.0   # 10 min
# Reltol requested by research brief is 1e-7; MultiModeNoise solve_disp_mmf
# hardcodes reltol=1e-8 (tighter), so the plan constraint is satisfied.
const LF100_RELTOL_TAG = 1e-8
const LF100_LBFGS_M    = 20

# ─────────────────────────────────────────────────────────────────────────────
# Cost + gradient: identical in structure to
# `raman_optimization.jl::cost_and_gradient` with `log_cost=true`.  Kept here
# so the shared helper is never patched for this session.
# ─────────────────────────────────────────────────────────────────────────────

"""
    lf100_cost_and_grad(φ_vec, uω0, fiber, sim, band_mask; buffers...) -> (J_dB, g)

Forward solve → adjoint solve → chain-rule gradient w.r.t. φ. Cost is returned
on the dB scale (10·log₁₀(J)) for stable L-BFGS at deep suppression; gradient
scaled by the chain rule 10/(J·ln 10) so (J, ∇J) are on the same scale.
"""
function lf100_cost_and_grad(φ_vec::Vector{Float64},
        uω0::AbstractMatrix, fiber, sim, band_mask;
        uω0_shaped::AbstractMatrix, uωf_buffer::AbstractMatrix)
    Nt = sim["Nt"]
    M  = sim["M"]
    φ  = reshape(φ_vec, Nt, M)

    @assert all(isfinite, φ) "φ has non-finite values"

    @. uω0_shaped = uω0 * cis(φ)

    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω = sol["ode_sol"]
    L  = fiber["L"]
    Dω = fiber["Dω"]
    ũω_L = ũω(L)
    @. uωf_buffer = cis(Dω * L) * ũω_L

    J, λωL = spectral_band_cost(uωf_buffer, band_mask)

    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
    λ0 = sol_adj(0)

    # ∂J/∂φ(ω) = 2·Re(λ₀* · i · u₀_shaped)
    ∂J_∂φ = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))

    @assert isfinite(J) "cost is not finite"
    @assert all(isfinite, ∂J_∂φ) "gradient has non-finite values"

    # Log-scale cost + chain rule
    J_clamped = max(J, 1e-15)
    J_dB      = 10.0 * log10(J_clamped)
    scale     = 10.0 / (J_clamped * log(10.0))
    g         = vec(∂J_∂φ .* scale)

    return J_dB, g
end

# ─────────────────────────────────────────────────────────────────────────────
# Warm-start phi loader
# ─────────────────────────────────────────────────────────────────────────────

function lf100_load_warm_start_phi()
    @assert isfile(LF100_WARM_START_JLD2) "warm-start JLD2 missing: $LF100_WARM_START_JLD2"
    d = JLD2.load(LF100_WARM_START_JLD2)
    return (
        phi_opt = Matrix{Float64}(d["phi_opt"]),
        Nt      = Int(d["Nt"]),
        tw      = Float64(d["time_window_ps"]),
        P_cont  = Float64(d["P_cont_W"]),
        L       = Float64(d["L_m"]),
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Build problem + warm-start φ
# ─────────────────────────────────────────────────────────────────────────────

function lf100_build_problem()
    uω0, fiber, sim, band_mask, Δf, thr = setup_longfiber_problem(
        fiber_preset = :SMF28_beta2_only,
        L_fiber      = LF100_L,
        P_cont       = LF100_P_CONT,
        Nt           = LF100_NT,
        time_window  = LF100_TIME_WIN,
        β_order      = LF100_BETA_ORDER,
    )

    ws = lf100_load_warm_start_phi()
    phi_warm = longfiber_interpolate_phi(ws.phi_opt, ws.Nt, ws.tw,
                                         LF100_NT, LF100_TIME_WIN)

    fiber["zsave"] = nothing

    # Pre-allocated buffers
    uω0_shaped = similar(uω0)
    uωf_buffer = similar(uω0)

    cg = x -> lf100_cost_and_grad(x, uω0, fiber, sim, band_mask;
        uω0_shaped = uω0_shaped, uωf_buffer = uωf_buffer)

    config_hash = longfiber_config_hash(
        Nt = LF100_NT, time_window = LF100_TIME_WIN,
        L = LF100_L, P = LF100_P_CONT,
        fiber_id = "SMF28_beta2_only", reltol = LF100_RELTOL_TAG,
    )

    return (
        uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
        Δf  = Δf, phi_warm = phi_warm, raman_threshold = thr,
        cg = cg, config_hash = config_hash,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Core runner: one L-BFGS call with checkpoint callback
# ─────────────────────────────────────────────────────────────────────────────

"""
    lf100_run_lbfgs(x0, cg; max_iter, out_dir, config_hash, iter_offset=0)
        -> NamedTuple(result, buf, wall_s, trace_f, trace_g, trace_iter)

Run L-BFGS from `x0` for up to `max_iter` iterations, checkpointing every
`LF100_CKPT_EVERY` iterations (or every `LF100_CKPT_TIME_GATE_S` seconds)
into `out_dir`.  `iter_offset` lets a resumed run continue the iteration
counter used in checkpoint file names.
"""
function lf100_run_lbfgs(x0::Vector{Float64}, cg;
        max_iter::Integer, out_dir::AbstractString,
        config_hash::UInt64, iter_offset::Integer = 0)

    buf = CheckpointBuf(length(x0); config_hash = config_hash)
    buf.iter = iter_offset
    fg! = longfiber_make_fg!(buf, cg)
    cb  = longfiber_checkpoint_cb(buf, out_dir;
        every = LF100_CKPT_EVERY, time_gate_s = LF100_CKPT_TIME_GATE_S)

    t_start = time()
    buf.t_start = t_start
    buf.last_ckpt_s = t_start

    result = Optim.optimize(
        Optim.only_fg!(fg!), x0, Optim.LBFGS(; m = LF100_LBFGS_M),
        Optim.Options(
            iterations = max_iter,
            g_tol      = 1e-8,
            callback   = cb,
            store_trace = true,
            show_trace = true,
        ),
    )
    wall_s = time() - t_start

    trace_f    = [tr.value for tr in Optim.trace(result)]
    trace_g    = [tr.g_norm for tr in Optim.trace(result)]
    trace_iter = [tr.iteration for tr in Optim.trace(result)]

    @info @sprintf("L-BFGS stopped: wall=%.1fs iter=%d conv=%s grad_norm=%.2e J=%.2f dB",
        wall_s, Optim.iterations(result), string(Optim.converged(result)),
        Optim.g_residual(result), Optim.minimum(result))

    # Final checkpoint (even if not on stride)
    final_ckpt = joinpath(out_dir, @sprintf("ckpt_iter_%04d_final.jld2", buf.iter))
    JLD2.jldsave(final_ckpt;
        x           = copy(buf.x_last),
        f           = buf.f_last,
        g           = copy(buf.g_last),
        iter        = buf.iter,
        elapsed     = wall_s,
        config_hash = config_hash,
        saved_at    = now(),
        is_final    = true,
    )
    @info "final checkpoint → $final_ckpt"

    return (
        result = result, buf = buf, wall_s = wall_s,
        trace_f = trace_f, trace_g = trace_g, trace_iter = trace_iter,
        final_ckpt = final_ckpt,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure: f, g_norm, per-iter wall (via trace) — with resume marker
# ─────────────────────────────────────────────────────────────────────────────

function lf100_figure(run_fresh, run_resume, resume_split_iter, out_path)
    fig, axes = PyPlot.subplots(2, 1, figsize = (10, 7), sharex = true)

    ax = axes[1]
    ax.plot(run_fresh.trace_iter, run_fresh.trace_f; lw = 1.5,
        color = "#2266aa", label = "fresh run")
    if run_resume !== nothing
        # Shift resumed trace so its x-axis continues after split
        shifted = run_resume.trace_iter .+ resume_split_iter
        ax.plot(shifted, run_resume.trace_f; lw = 1.5, ls = "--",
            color = "#cc5544", label = "resumed run")
        ax.axvline(resume_split_iter; color = "k", ls = ":",
            alpha = 0.6, label = "resume split")
    end
    ax.set_ylabel("J [dB]  (cost)")
    ax.set_title(@sprintf("L=%.0f m SMF-28 P=%.3f W — L-BFGS convergence", LF100_L, LF100_P_CONT))
    ax.grid(true, alpha = 0.3)
    ax.legend(loc = "upper right")

    ax2 = axes[2]
    ax2.semilogy(run_fresh.trace_iter, max.(run_fresh.trace_g, 1e-30);
        lw = 1.5, color = "#2266aa", label = "fresh ‖∇J‖")
    if run_resume !== nothing
        shifted = run_resume.trace_iter .+ resume_split_iter
        ax2.semilogy(shifted, max.(run_resume.trace_g, 1e-30);
            lw = 1.5, ls = "--", color = "#cc5544", label = "resumed ‖∇J‖")
        ax2.axvline(resume_split_iter; color = "k", ls = ":", alpha = 0.6)
    end
    ax2.set_xlabel("iteration")
    ax2.set_ylabel("‖∇J‖")
    ax2.grid(true, which = "both", alpha = 0.3)
    ax2.legend(loc = "upper right")

    fig.tight_layout()
    mkpath(dirname(out_path))
    fig.savefig(out_path; dpi = 300, bbox_inches = "tight")
    close(fig)
    @info "saved figure $out_path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Modes: fresh / resume / resume_check
# ─────────────────────────────────────────────────────────────────────────────

function lf100_mode_fresh()
    prob = lf100_build_problem()
    mkpath(LF100_CKPT_DIR)

    x0 = vec(prob.phi_warm)
    @info @sprintf("Fresh run: starting from phi@2m warm-start, ‖x0‖=%.3e, N=%d",
        norm(x0), length(x0))

    run_fresh = lf100_run_lbfgs(x0, prob.cg;
        max_iter    = LF100_MAX_ITER,
        out_dir     = LF100_CKPT_DIR,
        config_hash = prob.config_hash,
        iter_offset = 0,
    )

    phi_opt = reshape(Optim.minimizer(run_fresh.result), LF100_NT, 1)
    out_path = joinpath(LF100_RESULTS_DIR, "$(LF100_RUN_LABEL)_opt_full_result.jld2")
    JLD2.jldsave(out_path;
        phi_opt        = phi_opt,
        phi_warm       = prob.phi_warm,
        J_final        = Optim.minimum(run_fresh.result),
        J_final_lin    = 10.0 ^ (Optim.minimum(run_fresh.result) / 10),
        trace_f        = run_fresh.trace_f,
        trace_g        = run_fresh.trace_g,
        trace_iter     = run_fresh.trace_iter,
        n_iter         = Optim.iterations(run_fresh.result),
        converged      = Optim.converged(run_fresh.result),
        g_residual     = Optim.g_residual(run_fresh.result),
        wall_s         = run_fresh.wall_s,
        config_hash    = prob.config_hash,
        L_m            = LF100_L,
        P_cont_W       = LF100_P_CONT,
        Nt             = LF100_NT,
        time_window_ps = LF100_TIME_WIN,
        β_order        = LF100_BETA_ORDER,
        saved_at       = now(),
    )
    @info "saved $out_path"

    lf100_figure(run_fresh, nothing, 0,
        joinpath(LF100_FIGURE_DIR, "physics_16_03_optimization_trace_$(LF100_RUN_LABEL).png"))

    # MANDATORY canonical image set (Project rule 2, 2026-04-17).
    lf100_save_standard_images(prob, vec(phi_opt); tag = "F_$(LF100_RUN_LABEL)_opt",
        output_dir = joinpath(LF100_RESULTS_DIR, "standard_images_F_$(LF100_RUN_LABEL)_opt"))

    return (run_fresh = run_fresh, run_resume = nothing)
end

function lf100_mode_resume()
    prob = lf100_build_problem()
    mkpath(LF100_CKPT_DIR)

    resume = longfiber_resume_from_ckpt(LF100_CKPT_DIR;
        expected_config_hash = prob.config_hash)
    @info @sprintf("Resuming from iter=%d, f=%.3e dB", resume.iter, resume.f)

    remaining = max(0, LF100_MAX_ITER - resume.iter)
    @assert remaining > 0 "nothing left to do: resume iter=$(resume.iter) ≥ max=$(LF100_MAX_ITER)"

    run_resume = lf100_run_lbfgs(resume.x, prob.cg;
        max_iter    = remaining,
        out_dir     = LF100_CKPT_DIR,
        config_hash = prob.config_hash,
        iter_offset = resume.iter,
    )

    phi_opt = reshape(Optim.minimizer(run_resume.result), LF100_NT, 1)
    out_path = joinpath(LF100_RESULTS_DIR, "$(LF100_RUN_LABEL)_opt_resume_result.jld2")
    JLD2.jldsave(out_path;
        phi_opt        = phi_opt,
        phi_warm       = prob.phi_warm,
        J_final        = Optim.minimum(run_resume.result),
        trace_f        = run_resume.trace_f,
        trace_g        = run_resume.trace_g,
        trace_iter     = run_resume.trace_iter,
        n_iter         = Optim.iterations(run_resume.result),
        converged      = Optim.converged(run_resume.result),
        g_residual     = Optim.g_residual(run_resume.result),
        wall_s         = run_resume.wall_s,
        config_hash    = prob.config_hash,
        resume_from    = resume.path,
        resume_iter    = resume.iter,
        L_m            = LF100_L,
        P_cont_W       = LF100_P_CONT,
        Nt             = LF100_NT,
        time_window_ps = LF100_TIME_WIN,
        saved_at       = now(),
    )
    @info "saved $out_path"

    lf100_save_standard_images(prob, vec(phi_opt); tag = "F_$(LF100_RUN_LABEL)_resume",
        output_dir = joinpath(LF100_RESULTS_DIR, "standard_images_F_$(LF100_RUN_LABEL)_resume"))

    return (run_fresh = nothing, run_resume = run_resume)
end

function lf100_mode_resume_check()
    prob = lf100_build_problem()

    # Phase A: fresh, run 15 iter into a resume-check subdir.
    check_dir = joinpath(LF100_CKPT_DIR, "resume_check_phaseA")
    mkpath(check_dir)
    x0 = vec(prob.phi_warm)
    @info "═════ Phase A (resume_check): 15 iter fresh ═════"
    run_A = lf100_run_lbfgs(x0, prob.cg;
        max_iter    = 15,
        out_dir     = check_dir,
        config_hash = prob.config_hash,
        iter_offset = 0,
    )

    # Phase B: resume from the highest-iter checkpoint in check_dir.
    @info "═════ Phase B (resume_check): resume and continue ═════"
    resume = longfiber_resume_from_ckpt(check_dir;
        expected_config_hash = prob.config_hash)
    run_B = lf100_run_lbfgs(resume.x, prob.cg;
        max_iter    = LF100_MAX_ITER - resume.iter,
        out_dir     = check_dir,
        config_hash = prob.config_hash,
        iter_offset = resume.iter,
    )

    # ALSO do an uninterrupted reference run in the main CKPT_DIR so we have a
    # baseline to compare final J against (1e-6 relative tolerance per plan).
    @info "═════ Phase C (resume_check): uninterrupted reference run in main CKPT_DIR ═════"
    mkpath(LF100_CKPT_DIR)
    run_ref = lf100_run_lbfgs(vec(prob.phi_warm), prob.cg;
        max_iter    = LF100_MAX_ITER,
        out_dir     = LF100_CKPT_DIR,
        config_hash = prob.config_hash,
        iter_offset = 0,
    )

    J_ref    = Optim.minimum(run_ref.result)
    J_resume = Optim.minimum(run_B.result)
    Δrel     = abs(J_resume - J_ref) / max(abs(J_ref), 1e-20)
    @info @sprintf("resume-check: J_ref=%.4f dB, J_resume=%.4f dB, Δrel=%.2e",
        J_ref, J_resume, Δrel)
    pass_resume = Δrel < 1e-6
    @info @sprintf("[%s] resume-check final-J parity (< 1e-6 relative)",
        pass_resume ? "PASS" : "FAIL")

    # Save fresh/full reference
    phi_opt_ref = reshape(Optim.minimizer(run_ref.result), LF100_NT, 1)
    full_path = joinpath(LF100_RESULTS_DIR, "$(LF100_RUN_LABEL)_opt_full_result.jld2")
    JLD2.jldsave(full_path;
        phi_opt        = phi_opt_ref,
        phi_warm       = prob.phi_warm,
        J_final        = J_ref,
        trace_f        = run_ref.trace_f,
        trace_g        = run_ref.trace_g,
        trace_iter     = run_ref.trace_iter,
        n_iter         = Optim.iterations(run_ref.result),
        converged      = Optim.converged(run_ref.result),
        g_residual     = Optim.g_residual(run_ref.result),
        wall_s         = run_ref.wall_s,
        config_hash    = prob.config_hash,
        L_m            = LF100_L,
        P_cont_W       = LF100_P_CONT,
        Nt             = LF100_NT,
        time_window_ps = LF100_TIME_WIN,
        β_order        = LF100_BETA_ORDER,
        saved_at       = now(),
    )
    @info "saved $full_path"

    # Save resumed run result for comparison
    phi_opt_res = reshape(Optim.minimizer(run_B.result), LF100_NT, 1)
    resume_path = joinpath(LF100_RESULTS_DIR, "$(LF100_RUN_LABEL)_opt_resume_result.jld2")
    JLD2.jldsave(resume_path;
        phi_opt        = phi_opt_res,
        phi_warm       = prob.phi_warm,
        J_final        = J_resume,
        trace_f_A      = run_A.trace_f,
        trace_f_B      = run_B.trace_f,
        trace_g_A      = run_A.trace_g,
        trace_g_B      = run_B.trace_g,
        trace_iter_A   = run_A.trace_iter,
        trace_iter_B   = run_B.trace_iter,
        resume_split_iter = 15,
        J_ref          = J_ref,
        Δrel           = Δrel,
        pass_resume    = pass_resume,
        n_iter_total   = Optim.iterations(run_A.result) + Optim.iterations(run_B.result),
        wall_s_total   = run_A.wall_s + run_B.wall_s,
        config_hash    = prob.config_hash,
        L_m            = LF100_L,
        P_cont_W       = LF100_P_CONT,
        Nt             = LF100_NT,
        time_window_ps = LF100_TIME_WIN,
        saved_at       = now(),
    )
    @info "saved $resume_path"

    # Figure uses the resume-check traces (Phase A + Phase B)
    lf100_figure(run_A, run_B, 15,
        joinpath(LF100_FIGURE_DIR, "physics_16_03_optimization_trace_$(LF100_RUN_LABEL).png"))

    # MANDATORY canonical image set (Project rule 2, 2026-04-17).
    lf100_save_standard_images(prob, vec(phi_opt_ref); tag = "F_$(LF100_RUN_LABEL)_opt",
        output_dir = joinpath(LF100_RESULTS_DIR, "standard_images_F_$(LF100_RUN_LABEL)_opt"))

    return (run_fresh = run_ref, run_resume = run_B, pass_resume = pass_resume)
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point: dispatch on LF100_MODE
# ─────────────────────────────────────────────────────────────────────────────

function lf100_main()
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Long-fiber %.0f m optimization — Session F / Phase 16 — start %s", LF100_L, now())
    @info "═══════════════════════════════════════════════════════════════"
    @info @sprintf("Julia threads: %d  BLAS threads: %d",
        Threads.nthreads(), BLAS.get_num_threads())

    mkpath(LF100_RESULTS_DIR)

    mode = get(ENV, "LF100_MODE", "fresh")
    @info "mode = $mode"
    if mode == "fresh"
        return lf100_mode_fresh()
    elseif mode == "resume"
        return lf100_mode_resume()
    elseif mode == "resume_check"
        return lf100_mode_resume_check()
    else
        error("unknown LF100_MODE=$mode — valid: fresh | resume | resume_check")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    result = lf100_main()
    if hasproperty(result, :pass_resume) && result.pass_resume === false
        @error "resume-check parity check FAILED — inspect traces and ckpts"
        exit(1)
    end
    @info @sprintf("100 m optimization run: done at %s", now())
end
