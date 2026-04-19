"""
Phase 18 — Numerical trustworthiness audit of every JLD2 under results/raman/**
that stores a phi_opt.

For each phi_opt, re-runs the forward (and adjoint) solver at the reported
optimum and runs four checks:

1. Energy conservation: |∫|u(t)|² dt |_{z=L} − |_{z=0}| / |_{z=0}|
2. Boundary: fraction of output energy in the outer 5% of the time window
3. Grid convergence: |J_dB(Nt) − J_dB(2·Nt)| with sinc-extended phase
4. Adjoint vs. FD (Taylor directional test) at phi_opt

Thresholds and their literature defense live in
.planning/phases/18-numerical-trustworthiness-audit-of-optimization-results/PLAN.md

Writes per-result markdowns to results/validation/<tag>.md and the aggregate
ranking to results/validation/REPORT.md.

Launch (MANDATORY via Rule P5 burst-run wrapper):
    burst-ssh "cd fiber-raman-suppression && git pull && \\
               ~/bin/burst-run-heavy H-audit \\
               'julia -t auto --project=. scripts/validation/validate_results.jl'"
"""

try using Revise catch end
using Printf
using LinearAlgebra
using FFTW
using Random
using Logging
using Dates
using Statistics
ENV["MPLBACKEND"] = "Agg"  # in case common.jl transitively loads PyPlot
using JLD2
using MultiModeNoise

include(joinpath(@__DIR__, "..", "common.jl"))
include(joinpath(@__DIR__, "..", "raman_optimization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Thresholds (defense: PLAN.md)
# ─────────────────────────────────────────────────────────────────────────────

const E_PASS, E_MARGINAL       = 1e-4, 1e-3
const BC_PASS, BC_MARGINAL     = 1e-3, 1e-2
const ΔJDB_PASS, ΔJDB_MARGINAL = 0.3, 1.0   # dB
const TAYLOR_PASS, TAYLOR_MARGINAL = 1e-3, 1e-2

# Fixed RNG seed for the Taylor-test direction — reproducible across runs.
const TAYLOR_SEED = 20260419
const TAYLOR_EPS  = 1e-5

# ─────────────────────────────────────────────────────────────────────────────
# Verdict helpers
# ─────────────────────────────────────────────────────────────────────────────

function verdict_E(x)
    x < E_PASS && return "PASS"
    x < E_MARGINAL && return "MARGINAL"
    return "SUSPECT"
end
function verdict_BC(x)
    x < BC_PASS && return "PASS"
    x < BC_MARGINAL && return "MARGINAL"
    return "SUSPECT"
end
function verdict_dJdB(x)
    x < ΔJDB_PASS && return "PASS"
    x < ΔJDB_MARGINAL && return "MARGINAL"
    return "SUSPECT"
end
function verdict_taylor(x)
    x < TAYLOR_PASS && return "PASS"
    x < TAYLOR_MARGINAL && return "MARGINAL"
    return "SUSPECT"
end

const RANK = Dict("PASS" => 0, "MARGINAL" => 1, "SUSPECT" => 2, "ERROR" => 3)

function worst(verdicts::Vector{String})
    isempty(verdicts) && return "ERROR"
    maxv = "PASS"
    for v in verdicts
        get(RANK, v, 3) > RANK[maxv] && (maxv = v)
    end
    return maxv
end

# ─────────────────────────────────────────────────────────────────────────────
# Problem reconstruction — bypass setup_raman_problem auto-sizing so we can
# restore the *exact* saved grid (Nt, time_window).
# ─────────────────────────────────────────────────────────────────────────────

function fiber_preset_from_name(name::AbstractString)
    n = strip(lowercase(name))
    if occursin("smf", n) && occursin("β", n) && occursin("only", n)
        return :SMF28_beta2_only
    elseif occursin("smf", n)
        return :SMF28
    elseif occursin("hnlf", n) && occursin("zero", n)
        return :HNLF_zero_disp
    elseif occursin("hnlf", n)
        return :HNLF
    end
    return :SMF28   # default
end

"""
    rebuild_problem(; fiber_preset, L_fiber, P_cont, pulse_fwhm, Nt,
                    time_window, λ0=1550e-9, rep_rate=80.5e6,
                    raman_threshold=-5.0)

Deterministic reconstruction of (uω0, fiber, sim, band_mask) without any
auto-sizing — uses the exact Nt and time_window passed in.
"""
function rebuild_problem(; fiber_preset::Symbol, L_fiber::Real, P_cont::Real,
                          pulse_fwhm::Real, Nt::Int, time_window::Real,
                          λ0::Real=1550e-9, rep_rate::Real=80.5e6,
                          pulse_shape::AbstractString="sech_sq",
                          raman_threshold::Real=-5.0,
                          M::Int=1, β_order::Union{Nothing,Int}=nothing)
    preset = FIBER_PRESETS[fiber_preset]
    gamma = preset.gamma
    betas = preset.betas
    fR = preset.fR
    # helpers.jl requires length(betas) ≤ β_order-1 (β_order counts from β₀ = 0);
    # all raman drivers use β_order=length(betas)+1, so we mirror that here.
    β_order_eff = β_order === nothing ? (length(betas) + 1) : β_order

    sim = MultiModeNoise.get_disp_sim_params(λ0, M, Nt, float(time_window), β_order_eff)
    fiber = MultiModeNoise.get_disp_fiber_params_user_defined(
        float(L_fiber), sim; fR=fR, gamma_user=gamma, betas_user=betas
    )
    u0_modes = ones(M) / √M
    _, uω0 = MultiModeNoise.get_initial_state(
        u0_modes, float(P_cont), float(pulse_fwhm), float(rep_rate), pulse_shape, sim
    )
    Δf_fft = fftfreq(Nt, 1 / sim["Δt"])
    band_mask = Δf_fft .< raman_threshold
    return uω0, fiber, sim, band_mask
end

# ─────────────────────────────────────────────────────────────────────────────
# Individual check primitives
# ─────────────────────────────────────────────────────────────────────────────

"""
Compute J, energy conservation, output BC fraction, and output time-domain
field for a shaped input at the given grid.
"""
function forward_checks(φ, uω0, fiber, sim, band_mask)
    # Apply phase
    uω0_shaped = @. uω0 * cis(φ)

    # Input time-domain energy (∫|u(t)|² dt ≈ Δt · Σ|u_n|²)
    ut0 = ifft(uω0_shaped, 1)
    Δt = sim["Δt"]
    E_in = Δt * sum(abs2.(ut0))

    # Forward solve
    fiber["zsave"] = nothing  # avoid deepcopy
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω = sol["ode_sol"]
    L = fiber["L"]
    Dω = fiber["Dω"]
    ũω_L = ũω(L)
    uωf = @. cis(Dω * L) * ũω_L
    utf = ifft(uωf, 1)
    E_out = Δt * sum(abs2.(utf))

    # Cost
    J, _ = spectral_band_cost(uωf, band_mask)

    # Boundary at output: energy in outer 5% of time grid
    Nt = size(utf, 1)
    n_edge = max(1, Nt ÷ 20)
    E_total_t = sum(abs2.(utf))
    E_edges = sum(abs2.(utf[1:n_edge, :])) + sum(abs2.(utf[end-n_edge+1:end, :]))
    edge_frac = E_edges / max(E_total_t, eps())

    E_drift = abs(E_out - E_in) / max(E_in, eps())
    return (J=J, E_drift=E_drift, edge_frac=edge_frac, uωf=uωf, utf=utf,
            uω0_shaped=uω0_shaped)
end

"""
Adjoint gradient at phi — re-uses cost_and_gradient from raman_optimization.jl
with log_cost=false so the gradient is in the "linear J" space (matches the
check: we compare dJ/dphi, not dJ_dB/dphi, to the finite-difference of J).
"""
function adjoint_grad_at_phi(φ, uω0, fiber, sim, band_mask)
    fiber["zsave"] = nothing
    J, g = cost_and_gradient(φ, uω0, fiber, sim, band_mask;
                              λ_gdd=0.0, λ_boundary=0.0, log_cost=false)
    return J, g
end

"""
Zero-pad a phase array defined on an Nt-grid (FFT order) to a target Nt_new
grid. Old bins 1..Nt/2 go to new bins 1..Nt/2; old bins Nt/2+1..Nt go to new
bins Nt_new-Nt/2+1..Nt_new. New high-frequency bins get 0.
"""
function zero_pad_phase(φ::AbstractArray, Nt_new::Int)
    Nt = size(φ, 1)
    @assert Nt_new > Nt
    @assert iseven(Nt) && iseven(Nt_new)
    shape_new = (Nt_new, size(φ, 2))
    φ_new = zeros(eltype(φ), shape_new...)
    half = Nt ÷ 2
    φ_new[1:half, :] .= φ[1:half, :]
    φ_new[(Nt_new - half + 1):end, :] .= φ[(half + 1):end, :]
    return φ_new
end

# ─────────────────────────────────────────────────────────────────────────────
# Full four-check pipeline for a single (φ, metadata)
# ─────────────────────────────────────────────────────────────────────────────

function run_four_checks(φ_opt::AbstractArray, meta::NamedTuple;
                         do_doubling::Bool=true, do_taylor::Bool=true)
    Nt_phi = ndims(φ_opt) == 1 ? length(φ_opt) : size(φ_opt, 1)

    # Two reconstruction modes:
    #   (a) If meta has a finite time_window, use rebuild_problem with the exact
    #       saved Nt and time_window — deterministic, no auto-sizing.
    #   (b) Otherwise (sweeps) call setup_raman_problem so its auto-sizing logic
    #       replicates the original run's grid; then verify the resulting Nt
    #       matches the stored phi length.
    if isfinite(meta.time_window) && meta.Nt > 0
        uω0, fiber, sim, band_mask = rebuild_problem(;
            fiber_preset=meta.fiber_preset,
            L_fiber=meta.L_fiber, P_cont=meta.P_cont,
            pulse_fwhm=meta.pulse_fwhm, Nt=meta.Nt, time_window=meta.time_window,
            λ0=meta.λ0, rep_rate=meta.rep_rate,
        )
    else
        # Replicate sweep_simple_run.jl defaults: Nt=2^14, time_window=10 ps
        Nt_guess = meta.Nt > 0 ? meta.Nt : 2^14
        tw_guess = 10.0
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset=meta.fiber_preset,
            L_fiber=meta.L_fiber, P_cont=meta.P_cont,
            pulse_fwhm=meta.pulse_fwhm, Nt=Nt_guess, time_window=tw_guess,
            λ0=meta.λ0, pulse_rep_rate=meta.rep_rate,
        )
        # Patch meta with the ACTUAL post-auto-size values (captured for markdown)
        Nt_actual = sim["Nt"]
        if Nt_actual != Nt_phi
            error("Nt mismatch: auto-size produced Nt=$Nt_actual but phi_opt has length $Nt_phi")
        end
        meta = (fiber_preset=meta.fiber_preset,
                fiber_name_raw=meta.fiber_name_raw,
                L_fiber=meta.L_fiber, P_cont=meta.P_cont,
                pulse_fwhm=meta.pulse_fwhm,
                Nt=Nt_actual,
                time_window=Nt_actual * sim["Δt"],  # sim["Δt"] already in ps
                λ0=meta.λ0, rep_rate=meta.rep_rate,
                J_reported=meta.J_reported, tag=meta.tag)
    end

    # Ensure phi shape is (Nt, M)
    if ndims(φ_opt) == 1
        φ = reshape(Float64.(φ_opt), length(φ_opt), 1)
    else
        φ = Float64.(φ_opt)
    end
    @assert size(φ, 1) == meta.Nt "phi length $(size(φ,1)) ≠ Nt $(meta.Nt)"

    # --- check 1 + 2: forward at phi ---
    fc = forward_checks(φ, uω0, fiber, sim, band_mask)
    J_recomputed = fc.J
    E_drift = fc.E_drift
    edge_frac = fc.edge_frac

    # --- check 4: adjoint vs FD (Taylor directional test) ---
    #
    # AT a reported optimum, ∇J ≈ 0 so component-wise and directional relative
    # errors explode on machine noise (cf. Plessix 2006, Griewank & Walther 2e
    # §5.6). The research memo's stationary-point prescription is to evaluate
    # the adjoint-vs-FD identity at a NON-stationary reference point. We do:
    #
    #   φ_ref = φ_opt + 0.5·d        (d unit-norm, pulse-band-masked, fixed seed)
    #   ρ(ε) = [J(φ_ref+εd) − J(φ_ref−εd)] / (2·ε·⟨g_adj(φ_ref), d⟩)
    #
    # At φ_ref the gradient is O(J) and ρ → 1 as ε → 0 for a correct adjoint.
    # This validates the adjoint IMPLEMENTATION (what we actually care about),
    # not ∇J(φ_opt) which is a property of the optimizer's convergence.
    #
    # We also report grad_norm at φ_opt as a stationarity diagnostic — small
    # values confirm the reported point is actually an L-BFGS local min.
    taylor_rho = NaN
    taylor_gd = NaN
    taylor_err = NaN
    grad_norm = NaN
    grad_norm_ref = NaN
    if do_taylor
        # 1. stationarity diagnostic at φ_opt
        _, g_adj_opt = adjoint_grad_at_phi(φ, uω0, fiber, sim, band_mask)
        grad_norm = norm(g_adj_opt)

        # 2. build reference direction d
        Random.seed!(TAYLOR_SEED)
        spectral_power = vec(sum(abs2.(uω0), dims=2))
        sig_mask = spectral_power .> 0.001 * maximum(spectral_power)
        d_full = zeros(size(φ))
        for col in 1:size(φ, 2)
            for i in eachindex(sig_mask)
                sig_mask[i] && (d_full[i, col] = randn())
            end
        end
        d_full ./= max(norm(d_full), eps())

        # 3. shift off the stationary point so ⟨g,d⟩ is well above machine noise
        φ_ref = φ .+ 0.5 .* d_full
        _, g_adj_ref = adjoint_grad_at_phi(φ_ref, uω0, fiber, sim, band_mask)
        grad_norm_ref = norm(g_adj_ref)
        gd = dot(g_adj_ref, d_full)

        # 4. centered FD at φ_ref
        ε = TAYLOR_EPS
        J_plus, _  = adjoint_grad_at_phi(φ_ref .+ ε .* d_full, uω0, fiber, sim, band_mask)
        J_minus, _ = adjoint_grad_at_phi(φ_ref .- ε .* d_full, uω0, fiber, sim, band_mask)
        fd_dir = (J_plus - J_minus) / (2ε)

        taylor_gd = gd
        taylor_err = abs(fd_dir - gd)
        if abs(gd) < 1e-14
            denom = max(grad_norm_ref, 1e-16)
            taylor_rho = taylor_err / denom
        else
            taylor_rho = abs(fd_dir / gd - 1.0)
        end
    end

    # --- check 3: grid convergence under Nt doubling ---
    ΔJ_dB = NaN
    J_doubled = NaN
    if do_doubling
        Nt_new = 2 * meta.Nt
        uω0_new, fiber_new, sim_new, band_mask_new = rebuild_problem(;
            fiber_preset=meta.fiber_preset,
            L_fiber=meta.L_fiber, P_cont=meta.P_cont,
            pulse_fwhm=meta.pulse_fwhm, Nt=Nt_new,
            time_window=meta.time_window,
            λ0=meta.λ0, rep_rate=meta.rep_rate,
        )
        # Phase is defined on the original grid; in FFT order the old grid's
        # frequencies coincide with a subset of the new grid's frequencies
        # when time_window is fixed, because Δf = 1/time_window is unchanged.
        # Zero-pad phi into the new high-frequency bins.
        φ_new = zero_pad_phase(φ, Nt_new)
        fc_new = forward_checks(φ_new, uω0_new, fiber_new, sim_new, band_mask_new)
        J_doubled = fc_new.J
        # Both J's in [0,1]; convert to dB (clamp small-J for safety).
        J_dB_old = 10 * log10(max(J_recomputed, 1e-16))
        J_dB_new = 10 * log10(max(J_doubled, 1e-16))
        ΔJ_dB = abs(J_dB_new - J_dB_old)
    end

    return (
        meta=meta,
        J_recomputed=J_recomputed,
        E_drift=E_drift, edge_frac=edge_frac,
        ΔJ_dB=ΔJ_dB, J_doubled=J_doubled,
        grad_norm=grad_norm, grad_norm_ref=grad_norm_ref,
        taylor_rho=taylor_rho, taylor_gd=taylor_gd, taylor_err=taylor_err,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Metadata normalization per JLD2 schema
# ─────────────────────────────────────────────────────────────────────────────

"""
Normalize metadata from a top-level JLD2 payload into a NamedTuple of fields
(uniform SI units) that rebuild_problem understands.

Accepts either a Dict or a raw JLD2 file handle (behaves like Dict).
"""
function normalize_meta(f; override::Dict{Symbol,Any}=Dict{Symbol,Any}(), tag::String="")
    get_or_default(k, d=missing) = haskey(override, k) ? override[k] :
                                   (haskey(f, string(k)) ? f[string(k)] : d)

    # Fiber
    fiber_name_raw = haskey(override, :fiber_name) ? String(override[:fiber_name]) :
                     haskey(f, "fiber_name") ? String(f["fiber_name"]) :
                     haskey(f, "fiber_preset") ? String(f["fiber_preset"]) : "SMF-28"
    fiber_preset = fiber_preset_from_name(fiber_name_raw)

    # Length
    L_fiber = haskey(override, :L_fiber) ? Float64(override[:L_fiber]) :
              haskey(f, "L_m") ? Float64(f["L_m"]) :
              haskey(f, "L_fiber") ? Float64(f["L_fiber"]) : NaN
    # Power
    P_cont = haskey(override, :P_cont) ? Float64(override[:P_cont]) :
             haskey(f, "P_cont_W") ? Float64(f["P_cont_W"]) :
             haskey(f, "P_cont") ? Float64(f["P_cont"]) : NaN
    # Pulse FWHM (seconds)
    pulse_fwhm = haskey(override, :pulse_fwhm) ? Float64(override[:pulse_fwhm]) :
                 haskey(f, "fwhm_fs") ? Float64(f["fwhm_fs"]) * 1e-15 :
                 haskey(f, "pulse_fwhm") ? Float64(f["pulse_fwhm"]) : 185e-15
    # Nt
    Nt_val = haskey(override, :Nt) ? Int(override[:Nt]) :
             haskey(f, "Nt") ? Int(f["Nt"]) : 0
    # time window — two conventions exist (ps or s). phase14/vanilla_snapshot
    # stores :time_window → the numerical value is ps per common.jl.
    time_window = NaN
    if haskey(override, :time_window)
        time_window = Float64(override[:time_window])
    elseif haskey(f, "time_window_ps")
        time_window = Float64(f["time_window_ps"])
    elseif haskey(f, "time_window")
        time_window = Float64(f["time_window"])
    end
    λ0 = haskey(override, :λ0) ? Float64(override[:λ0]) :
         haskey(f, "lambda0_nm") ? Float64(f["lambda0_nm"]) * 1e-9 : 1550e-9
    rep_rate = haskey(override, :rep_rate) ? Float64(override[:rep_rate]) : 80.5e6

    J_reported = haskey(override, :J_reported) ? override[:J_reported] :
                 haskey(f, "J_after") ? f["J_after"] :
                 haskey(f, "J_final") ? f["J_final"] :
                 haskey(f, "J_opt")   ? f["J_opt"]   : missing

    return (
        fiber_preset=fiber_preset, fiber_name_raw=fiber_name_raw,
        L_fiber=L_fiber, P_cont=P_cont, pulse_fwhm=pulse_fwhm,
        Nt=Nt_val, time_window=time_window,
        λ0=λ0, rep_rate=rep_rate,
        J_reported=J_reported, tag=tag,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Per-result markdown emitter
# ─────────────────────────────────────────────────────────────────────────────

function fmt_J_dB(J)
    J isa Real || return "(n/a)"
    (J ≤ 0 || !isfinite(J)) && return @sprintf("%.4g (non-positive)", J)
    return @sprintf("%.4f dB", 10 * log10(max(J, 1e-16)))
end

function emit_markdown(out_path::String, tag::String, source::String, meta::NamedTuple, r::NamedTuple)
    v_E  = verdict_E(r.E_drift)
    v_BC = verdict_BC(r.edge_frac)
    v_dJ = isnan(r.ΔJ_dB) ? "n/a" : verdict_dJdB(r.ΔJ_dB)
    v_TY = isnan(r.taylor_rho) ? "n/a" : verdict_taylor(r.taylor_rho)
    all_v = filter(v -> v != "n/a", String[v_E, v_BC, v_dJ, v_TY])
    overall = worst(all_v)

    lines = String[]
    push!(lines, "# $tag")
    push!(lines, "")
    push!(lines, "**Source JLD2:** `$source`  ")
    push!(lines, "**Fiber:** $(meta.fiber_name_raw) (preset `:$(meta.fiber_preset)`)  ")
    push!(lines, @sprintf("**Grid:** Nt=%d, time_window=%.2f ps  ",
                          meta.Nt, meta.time_window))
    push!(lines, @sprintf("**Pulse:** L=%.3g m, P=%.4g W, FWHM=%.1f fs  ",
                          meta.L_fiber, meta.P_cont, meta.pulse_fwhm * 1e15))
    push!(lines, @sprintf("**J reported:** %s  ",
                          meta.J_reported === missing ? "n/a" :
                          (meta.J_reported isa Real && 0 ≤ meta.J_reported ≤ 1) ?
                              @sprintf("%.6e (%.3f dB)", meta.J_reported,
                                       10*log10(max(meta.J_reported, 1e-16))) :
                              string(meta.J_reported)))
    push!(lines, @sprintf("**J recomputed at φ_opt:** %.6e (%s)",
                          r.J_recomputed, fmt_J_dB(r.J_recomputed)))
    push!(lines, "")
    push!(lines, "## Verdict: **$overall**")
    push!(lines, "")
    push!(lines, "| # | Check | Value | Threshold (P/M/S) | Verdict |")
    push!(lines, "|---|---|---|---|---|")
    push!(lines, @sprintf("| 1 | Energy drift \$|ΔE|/E\$ | %.3e | <1e-4 / <1e-3 / ≥1e-3 | **%s** |",
                          r.E_drift, v_E))
    push!(lines, @sprintf("| 2 | Output BC edge fraction | %.3e | <1e-3 / <1e-2 / ≥1e-2 | **%s** |",
                          r.edge_frac, v_BC))
    if !isnan(r.ΔJ_dB)
        push!(lines, @sprintf("| 3 | \$|ΔJ_{dB}|\$ under Nt→2·Nt | %.3f dB | <0.3 / <1.0 / ≥1.0 dB | **%s** |",
                              r.ΔJ_dB, v_dJ))
    else
        push!(lines, "| 3 | Nt doubling | skipped | — | n/a |")
    end
    if !isnan(r.taylor_rho)
        push!(lines, @sprintf("| 4 | Taylor \$\\|ρ − 1\\|\$ at φ_ref | %.3e | <1e-3 / <1e-2 / ≥1e-2 | **%s** |",
                              r.taylor_rho, v_TY))
    else
        push!(lines, "| 4 | Taylor test | skipped | — | n/a |")
    end
    push!(lines, "")
    push!(lines, "### Details")
    push!(lines, @sprintf("- J_doubled = %.6e (%s)", r.J_doubled,
                           isnan(r.J_doubled) ? "n/a" : fmt_J_dB(r.J_doubled)))
    push!(lines, @sprintf("- Adjoint ‖g‖ at φ_opt = %.3e  (stationarity diagnostic — small is good)", r.grad_norm))
    push!(lines, @sprintf("- Adjoint ‖g‖ at φ_ref = φ_opt+0.5·d = %.3e  (used for Taylor test)",
                          r.grad_norm_ref))
    push!(lines, @sprintf("- Taylor ⟨g,d⟩ at φ_ref = %.3e, |FD − ⟨g,d⟩| = %.3e",
                          r.taylor_gd, r.taylor_err))
    push!(lines, "")
    push!(lines, "_Taylor test rationale: at φ_opt the adjoint gradient is near-zero " *
                "(by definition of an optimum), so component-wise adjoint-vs-FD relative " *
                "error would be floating-point noise. Following Plessix (Geophys. J. Int. " *
                "167, 495, 2006) §3.3 and Griewank & Walther *Evaluating Derivatives* 2e " *
                "§5.6, the adjoint is validated at a shifted reference point " *
                "φ_ref = φ_opt + 0.5·d where d is a unit-norm random direction masked to " *
                "the input-pulse spectral support._")
    push!(lines, "")
    push!(lines, "_Generated by `scripts/validation/validate_results.jl` "
               * "on $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))_")

    open(out_path, "w") do io
        write(io, join(lines, "\n"))
    end
    @info "  wrote $out_path ($overall)"

    return (tag=tag, source=source, overall=overall,
            E_drift=r.E_drift, edge_frac=r.edge_frac,
            ΔJ_dB=r.ΔJ_dB, taylor_rho=r.taylor_rho,
            J_recomputed=r.J_recomputed, J_reported=meta.J_reported,
            meta=meta)
end

# ─────────────────────────────────────────────────────────────────────────────
# Dispatch: which files to validate, and how to extract each phi_opt
# ─────────────────────────────────────────────────────────────────────────────

const REPO_ROOT = abspath(joinpath(@__DIR__, "..", ".."))
const OUT_DIR   = joinpath(REPO_ROOT, "results", "validation")
mkpath(OUT_DIR)

function safe_tag(s::AbstractString)
    x = replace(String(s), r"[^A-Za-z0-9_]" => "_")
    return x
end

"""
Normalize phase into shape (Nt, M) with M=1 if phi came in as a flat Vector.
"""
function _as_phi_matrix(x)
    if ndims(x) == 1
        return reshape(Float64.(x), length(x), 1)
    end
    return Float64.(x)
end

# Returns a Vector of (tag, source_rel, phi_opt, meta_override_dict)
function collect_entries()
    entries = []

    # --- Singletons ---
    singletons = [
        ("multivar_mv_joint",             "results/raman/multivar/smf28_L2m_P030W/mv_joint_result.jld2"),
        ("multivar_mv_joint_warmstart",   "results/raman/multivar/smf28_L2m_P030W/mv_joint_warmstart_result.jld2"),
        ("multivar_mv_phaseonly",         "results/raman/multivar/smf28_L2m_P030W/mv_phaseonly_result.jld2"),
        ("multivar_phase_only_opt",       "results/raman/multivar/smf28_L2m_P030W/phase_only_opt_result.jld2"),
        ("phase13_hessian_hnlf",          "results/raman/phase13/hessian_hnlf_canonical.jld2"),
        ("phase13_hessian_smf28",         "results/raman/phase13/hessian_smf28_canonical.jld2"),
        ("phase14_vanilla_snapshot",      "results/raman/phase14/vanilla_snapshot.jld2"),
    ]
    for (tag, relpath) in singletons
        full = joinpath(REPO_ROOT, relpath)
        if !isfile(full)
            @warn "missing: $full"
            continue
        end
        f = JLD2.jldopen(full, "r") do io
            Dict(k => io[k] for k in keys(io))
        end
        haskey(f, "phi_opt") || (@warn "no phi_opt in $relpath"; continue)
        push!(entries, (tag=tag, source=relpath, phi=_as_phi_matrix(f["phi_opt"]),
                        payload=f, override=Dict{Symbol,Any}()))
    end

    # --- Sweeps: sweep1_Nphi (7) + sweep2_LP_fiber (36) ---
    for (sweep_name, relpath) in [
            ("sweep1_Nphi",     "results/raman/phase_sweep_simple/sweep1_Nphi.jld2"),
            ("sweep2_LP_fiber", "results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2"),
        ]
        full = joinpath(REPO_ROOT, relpath)
        if !isfile(full)
            @warn "missing: $full"
            continue
        end
        results_list = JLD2.jldopen(full, "r") do io
            io["results"]
        end
        for (i, entry) in enumerate(results_list)
            haskey(entry, "phi_opt") || continue
            cfg = get(entry, "config", Dict{String,Any}())
            # sweep-level config uses symbols; entries sometimes use strings.
            _get(d, s, d2=nothing) = haskey(d, s) ? d[s] :
                                      haskey(d, Symbol(s)) ? d[Symbol(s)] : d2
            fiber_name = _get(cfg, "fiber_preset", "SMF28")
            # preset symbols come back from saved data as strings
            fiber_name_str = String(fiber_name)
            L_fiber = Float64(_get(cfg, "L_fiber",
                              _get(entry, "L_fiber", NaN)))
            P_cont = Float64(_get(cfg, "P_cont",
                              _get(entry, "P_cont", NaN)))
            Nt_e = Int(_get(entry, "Nt", 16384))
            tw_e = Float64(_get(entry, "time_window_ps",
                           _get(cfg, "time_window_ps", 40.0)))
            fwhm_e = Float64(_get(entry, "fwhm_fs",
                             _get(cfg, "fwhm_fs", 185.0))) * 1e-15
            kind = _get(cfg, "kind", "unknown")
            Nphi = _get(cfg, "N_phi", _get(entry, "N_phi", Nt_e))
            tag = @sprintf("%s_%03d_%s_L%.3g_P%.3g_Nphi%s_%s",
                           sweep_name, i, safe_tag(fiber_name_str),
                           L_fiber, P_cont,
                           string(Nphi), String(kind))
            override = Dict{Symbol,Any}(
                :fiber_name => fiber_name_str,
                :L_fiber    => L_fiber,
                :P_cont     => P_cont,
                :pulse_fwhm => fwhm_e,
                :Nt         => Nt_e,
                :time_window=> tw_e,
                :J_reported => _get(entry, "J_final",
                              _get(entry, "J_after", missing)),
            )
            push!(entries, (tag=tag, source="$relpath[$i]",
                            phi=_as_phi_matrix(entry["phi_opt"]),
                            payload=entry, override=override))
        end
    end

    return entries
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    @info "Phase 18 validator starting at $(now()) on $(gethostname())"
    @info "Threads.nthreads() = $(Threads.nthreads())"

    entries = collect_entries()
    @info "Collected $(length(entries)) phi_opt entries"

    # Env-var driven controls (for smoke tests):
    limit = get(ENV, "VALIDATE_LIMIT", "")
    if !isempty(limit)
        n = parse(Int, limit)
        entries = entries[1:min(n, end)]
        @info "VALIDATE_LIMIT=$n — processing first $(length(entries)) entries only"
    end
    filter_tag = get(ENV, "VALIDATE_TAG", "")
    if !isempty(filter_tag)
        entries = filter(e -> occursin(filter_tag, e.tag), entries)
        @info "VALIDATE_TAG=$filter_tag — $(length(entries)) entries remain"
    end

    summaries = []
    for (i, e) in enumerate(entries)
        @info @sprintf("[%d/%d] %s", i, length(entries), e.tag)
        try
            meta = normalize_meta(e.payload; override=e.override, tag=e.tag)
            # sanity
            if !isfinite(meta.L_fiber) || !isfinite(meta.P_cont) || meta.Nt == 0
                @warn "  incomplete metadata — skipping" meta
                continue
            end
            r = run_four_checks(e.phi, meta)
            out_path = joinpath(OUT_DIR, "$(e.tag).md")
            s = emit_markdown(out_path, e.tag, e.source, r.meta, r)
            push!(summaries, s)
        catch err
            @error "  FAILED on entry" exception=(err, catch_backtrace()) tag=e.tag
            push!(summaries, (tag=e.tag, source=e.source, overall="ERROR",
                              E_drift=NaN, edge_frac=NaN, ΔJ_dB=NaN,
                              taylor_rho=NaN, J_recomputed=NaN,
                              J_reported=missing,
                              meta=(L_fiber=NaN, P_cont=NaN, Nt=0,
                                    time_window=NaN, fiber_name_raw="ERROR",
                                    fiber_preset=:ERROR, pulse_fwhm=NaN,
                                    λ0=NaN, rep_rate=NaN, J_reported=missing,
                                    tag=e.tag)))
        end
    end

    # Aggregate report
    emit_aggregate_report(summaries)
    @info "Done. $(length(summaries)) entries processed."
    return summaries
end

function emit_aggregate_report(summaries)
    by = Dict("PASS"=>0, "MARGINAL"=>0, "SUSPECT"=>0, "ERROR"=>0)
    for s in summaries
        by[s.overall] = get(by, s.overall, 0) + 1
    end

    # Sort: SUSPECT first, then MARGINAL, then PASS; within a band by worst metric.
    function sort_key(s)
        r = RANK[s.overall]
        # Tiebreak by Taylor rho (worst-metric surrogate)
        t = isnan(s.taylor_rho) ? 0.0 : s.taylor_rho
        return (-r, -t)
    end
    sorted = sort(summaries, by=sort_key)

    lines = String[]
    push!(lines, "# Numerical Trustworthiness Audit — Top-level Report")
    push!(lines, "")
    push!(lines, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS")) on $(gethostname())  ")
    push!(lines, "**Source script:** `scripts/validation/validate_results.jl`  ")
    push!(lines, "**Plan + thresholds:** `.planning/phases/18-numerical-trustworthiness-audit-of-optimization-results/PLAN.md`")
    push!(lines, "")
    push!(lines, "## Counts")
    push!(lines, "")
    push!(lines, "| Verdict | Count |")
    push!(lines, "|---|---|")
    for v in ("PASS", "MARGINAL", "SUSPECT", "ERROR")
        push!(lines, @sprintf("| **%s** | %d |", v, by[v]))
    end
    push!(lines, @sprintf("| **Total** | %d |", length(summaries)))
    push!(lines, "")
    push!(lines, "## Ranking (worst first)")
    push!(lines, "")
    push!(lines, "| # | Verdict | Tag | J reported | J recomputed | |ΔE|/E | edge | |ΔJ_dB| | |ρ−1| | Markdown |")
    push!(lines, "|---|---|---|---|---|---|---|---|---|---|")
    for (i, s) in enumerate(sorted)
        Jr = s.J_reported
        Jr_s = if Jr === missing
            "n/a"
        elseif Jr isa Real && Jr > 0 && Jr < 1
            @sprintf("%.3e (%.2f dB)", Jr, 10*log10(max(Jr, 1e-16)))
        else
            string(Jr)
        end
        Jnew_s = isnan(s.J_recomputed) ? "n/a" :
                 @sprintf("%.3e (%.2f dB)", s.J_recomputed,
                          10*log10(max(s.J_recomputed, 1e-16)))
        push!(lines, @sprintf("| %d | **%s** | `%s` | %s | %s | %.2e | %.2e | %s | %s | [md](./%s.md) |",
                              i, s.overall, s.tag, Jr_s, Jnew_s,
                              s.E_drift, s.edge_frac,
                              isnan(s.ΔJ_dB) ? "n/a" : @sprintf("%.3f", s.ΔJ_dB),
                              isnan(s.taylor_rho) ? "n/a" : @sprintf("%.2e", s.taylor_rho),
                              s.tag))
    end
    push!(lines, "")
    push!(lines, "## Worst offenders")
    push!(lines, "")
    suspect = filter(s -> s.overall == "SUSPECT", sorted)
    if isempty(suspect)
        push!(lines, "_None — no SUSPECT verdicts._")
    else
        for s in suspect
            reason = String[]
            if s.E_drift > E_MARGINAL
                push!(reason, @sprintf("energy drift %.2e exceeds physical floor", s.E_drift))
            end
            if s.edge_frac > BC_MARGINAL
                push!(reason, @sprintf("edge fraction %.2e — pulse walks off", s.edge_frac))
            end
            if !isnan(s.ΔJ_dB) && s.ΔJ_dB > ΔJDB_MARGINAL
                push!(reason, @sprintf("Nt-doubling shifts J by %.2f dB", s.ΔJ_dB))
            end
            if !isnan(s.taylor_rho) && s.taylor_rho > TAYLOR_MARGINAL
                push!(reason, @sprintf("Taylor |ρ−1|=%.2e (adjoint bug suspected)", s.taylor_rho))
            end
            push!(lines, @sprintf("- `%s` — %s", s.tag, join(reason, "; ")))
        end
    end
    push!(lines, "")
    push!(lines, "## Thresholds (cited defense in PLAN.md)")
    push!(lines, "")
    push!(lines, "| Check | PASS | MARGINAL | SUSPECT |")
    push!(lines, "|---|---|---|---|")
    push!(lines, "| Energy drift | <1e-4 | 1e-4 … 1e-3 | ≥1e-3 |")
    push!(lines, "| Edge fraction | <1e-3 | 1e-3 … 1e-2 | ≥1e-2 |")
    push!(lines, "| |ΔJ_dB| under Nt→2·Nt | <0.3 dB | 0.3 … 1.0 dB | ≥1.0 dB |")
    push!(lines, "| Taylor |ρ−1| | <1e-3 | 1e-3 … 1e-2 | ≥1e-2 |")

    out_path = joinpath(OUT_DIR, "REPORT.md")
    open(out_path, "w") do io
        write(io, join(lines, "\n"))
    end
    @info "Aggregate report written: $out_path"
end

# Run only if invoked directly.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
