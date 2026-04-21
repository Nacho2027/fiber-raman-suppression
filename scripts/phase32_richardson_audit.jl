#!/usr/bin/env julia
# ─────────────────────────────────────────────────────────────────────────────
# Phase 32 Plan 02 — Experiment 0: Richardson applicability audit.
#
# Cheap forward-solve-only prerequisite to Experiment 1 / 2. Loads a canonical
# SMF-28 phi_opt, re-evaluates J(phi_opt) on four FFT grids
#   Nt ∈ {2^12, 2^13, 2^14, 2^15}
# and fits a power law `J(Nt) = C + A * Nt^{-p}`. Verdict is APPLICABLE iff
#   R² ≥ 0.95 AND 0.5 ≤ p ≤ 8.0
# Below that, Richardson extrapolation is not trustworthy on this problem and
# is abandoned per RESEARCH §6 Experiment 0.
#
# NO OPTIMIZATION calls unless the cached phi_opt probe fails (fallback: one
# 20-iter L-BFGS run to generate a reference phi on Nt=2^13). The primary path
# loads an existing JLD2 and does forward solves only.
#
# HEAVY RUN — use burst-run-heavy wrapper per CLAUDE.md Rule P5:
#   burst-ssh "cd fiber-raman-suppression && git pull && \
#              ~/bin/burst-run-heavy P-32-accel-expt0 \
#              'julia -t auto --project=. scripts/phase32_richardson_audit.jl'"
# Stop the burst VM on exit (`burst-stop`, Rule 3).
#
# Outputs:
#   results/phase32/richardson_audit.jld2   — the audit dict (Nt_values, J_values,
#                                              p_fit, R2, verdict)
#   .planning/phases/32-.../32-RESULTS.md   — appends an `## Experiment 0`
#                                              section with the populated
#                                              p + R² + verdict.
#
# Load-time cost: zero. The top-level `main()` only runs under the
#                 `abspath(PROGRAM_FILE) == @__FILE__` guard.
# ─────────────────────────────────────────────────────────────────────────────

try using Revise catch end

using Printf
using Logging
using LinearAlgebra
using Statistics
using FFTW
ENV["MPLBACKEND"] = "Agg"
using PyPlot
using JLD2
using MultiModeNoise

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "longfiber_setup.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "acceleration.jl"))

ensure_deterministic_environment()

# ─────────────────────────────────────────────────────────────────────────────
# Module-level constants — canonical SMF-28 benchmark (Phase 13)
# ─────────────────────────────────────────────────────────────────────────────

const P32R_NT_LADDER      = [2^12, 2^13, 2^14, 2^15]   # four grids
const P32R_L_FIBER        = 2.0                        # metres (phase13 canonical)
const P32R_P_CONT         = 0.2                        # W
const P32R_TIME_WINDOW    = 10.0                       # ps (tight window OK @ L=2m)
const P32R_BETA_ORDER     = 3
const P32R_PROBE_PATHS    = [
    "results/raman/phase13/hessian_smf28_canonical.jld2",
    "results/raman/phase15/benchmark.jld2",
]
const P32R_OUTDIR         = joinpath("results", "phase32")
const P32R_OUT_JLD2       = joinpath(P32R_OUTDIR, "richardson_audit.jld2")
const P32R_RESULTS_PATH   = joinpath(@__DIR__, "..", ".planning", "phases",
    "32-extrapolation-and-acceleration-for-parameter-studies-and-con",
    "32-RESULTS.md")

# Verdict thresholds (RESEARCH §6 Expt 0).
const P32R_R2_MIN         = 0.95
const P32R_P_MIN          = 0.5
const P32R_P_MAX          = 8.0

# ─────────────────────────────────────────────────────────────────────────────
# Probe for a cached SMF-28 phi_opt
# ─────────────────────────────────────────────────────────────────────────────

"""
    _probe_reference_phi() -> (phi_ref::Vector{Float64}, Nt_ref::Int, tw_ref_ps::Float64, source::String)

Return a reference phi_opt from the first cache hit in `P32R_PROBE_PATHS`, or
`(nothing, 0, 0.0, "")` if no cache is usable. Only the `phi_opt` field + its
associated grid (Nt from the array length; time_window assumed = P32R_TIME_WINDOW)
are needed — we are upsampling the phi to each audit grid via
`longfiber_interpolate_phi`, not replaying the original optimization.
"""
function _probe_reference_phi()
    for path in P32R_PROBE_PATHS
        isfile(path) || continue
        try
            JLD2.jldopen(path, "r") do f
                haskey(f, "phi_opt") || return nothing
                phi = Vector{Float64}(vec(f["phi_opt"]))
                Nt  = length(phi)
                @info "Richardson audit: loaded reference phi_opt" source=path Nt=Nt
                return (phi, Nt, P32R_TIME_WINDOW, path)
            end
        catch err
            @warn "probe failed" path=path err=err
        end
    end
    return nothing
end

"""
    _fallback_reference_phi() -> (phi_ref, Nt, tw_ps, source)

Short L-BFGS run to generate a reference phi_opt on Nt=2^13. Used only when
the cache probe turns up nothing. Deliberately small (20 iters) — we only
need *some* reasonable phi to audit the grid-convergence of J.
"""
function _fallback_reference_phi()
    include(joinpath(@__DIR__, "raman_optimization.jl"))
    Nt = 2^13
    uω0, fiber, sim, band_mask, _, _ = setup_longfiber_problem(
        fiber_preset = :SMF28,
        L_fiber      = P32R_L_FIBER,
        P_cont       = P32R_P_CONT,
        Nt           = Nt,
        time_window  = P32R_TIME_WINDOW,
        β_order      = P32R_BETA_ORDER,
    )
    @info "Richardson audit: running 20-iter L-BFGS fallback"
    φ0 = zeros(Float64, Nt, sim["M"])
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0 = φ0, max_iter = 20, log_cost = true, store_trace = false)
    return (Vector{Float64}(vec(result.minimizer)), Nt, P32R_TIME_WINDOW,
            "fallback_lbfgs_20iter")
end

# ─────────────────────────────────────────────────────────────────────────────
# Forward-solve J(phi) on a target grid
# ─────────────────────────────────────────────────────────────────────────────

"""
    _forward_J_on_grid(phi_ref, Nt_ref, tw_ref, Nt_target, tw_target) -> Float64

Zero-pad-in-frequency interpolate `phi_ref` onto `(Nt_target, tw_target)` via
`longfiber_interpolate_phi`, then evaluate `J_linear = E_band / E_total` from
a single forward solve at L = P32R_L_FIBER. Returns a positive linear J.

This is cost-only — no gradient, no optimization. Each call is ~ one
`solve_disp_mmf` at the target Nt.
"""
function _forward_J_on_grid(phi_ref::AbstractVector, Nt_ref::Int, tw_ref::Real,
                            Nt_target::Int, tw_target::Real)
    phi_target_mat = longfiber_interpolate_phi(
        phi_ref, Nt_ref, float(tw_ref), Nt_target, float(tw_target)
    )  # Matrix{Float64}(Nt_target, 1)

    uω0, fiber, sim, band_mask, _, _ = setup_longfiber_problem(
        fiber_preset = :SMF28,
        L_fiber      = P32R_L_FIBER,
        P_cont       = P32R_P_CONT,
        Nt           = Nt_target,
        time_window  = float(tw_target),
        β_order      = P32R_BETA_ORDER,
    )
    @assert sim["Nt"] == Nt_target "grid mismatch post-setup"

    phi_vec = Vector{Float64}(vec(phi_target_mat))
    J_lin, _ = cost_and_gradient(reshape(phi_vec, Nt_target, sim["M"]),
                                 uω0, fiber, sim, band_mask;
                                 log_cost = false)
    return float(J_lin)
end

# ─────────────────────────────────────────────────────────────────────────────
# Power-law fit — J(Nt) = C + A * Nt^{-p}
# ─────────────────────────────────────────────────────────────────────────────

"""
    _fit_power_law(Nt_values, J_values) -> (p::Float64, R²::Float64, C_best::Float64, A_best::Float64)

Fit `J(Nt) = C + A * Nt^{-p}` by grid-searching C and doing log-log linear
regression on the residual `J - C`. The sweep ranges `C ∈ [0, min(J) * (1 - 1e-6)]`
with 200 samples — the physical constraint is `C ≥ 0` (J is a probability-
like ratio) and `C < min(J)` (otherwise the residual goes non-positive).
The best C is the one that maximizes R² on the log-log fit.

Returns the best (p, R², C, A) tuple.
"""
function _fit_power_law(Nt_values::AbstractVector{<:Integer},
                        J_values::AbstractVector{<:Real})
    @assert length(Nt_values) == length(J_values) >= 3 "need ≥ 3 points"
    Jmin = minimum(J_values)
    @assert Jmin > 0 "J values must be positive; got min $Jmin"

    # Sweep C in [0, Jmin * (1 - 1e-6)].
    C_grid = collect(range(0.0, Jmin * (1.0 - 1e-6); length = 200))
    best = (p = NaN, R2 = -Inf, C = NaN, A = NaN)

    for C in C_grid
        resid = J_values .- C
        any(r -> r <= 0, resid) && continue
        x = log.(Float64.(Nt_values))
        y = log.(Float64.(resid))
        n = length(x)
        x̄ = mean(x); ȳ = mean(y)
        xc = x .- x̄; yc = y .- ȳ
        sxx = dot(xc, xc); sxy = dot(xc, yc)
        sxx < 1e-30 && continue
        slope = sxy / sxx                # slope = -p
        intercept = ȳ - slope * x̄
        yhat = slope .* x .+ intercept
        ss_res = sum((y .- yhat).^2)
        ss_tot = sum(yc.^2)
        ss_tot < 1e-30 && continue
        R2 = 1.0 - ss_res / ss_tot
        if R2 > best.R2
            best = (p = -slope, R2 = R2, C = C, A = exp(intercept))
        end
    end
    return (best.p, best.R2, best.C, best.A)
end

# ─────────────────────────────────────────────────────────────────────────────
# Verdict + persistence
# ─────────────────────────────────────────────────────────────────────────────

function _classify_richardson(p::Real, R2::Real)
    isfinite(p) || return "NOT_APPLICABLE"
    isfinite(R2) || return "NOT_APPLICABLE"
    (R2 >= P32R_R2_MIN) && (P32R_P_MIN <= p <= P32R_P_MAX) && return "APPLICABLE"
    return "NOT_APPLICABLE"
end

function _save_audit_jld2(audit::Dict{String,Any})
    mkpath(dirname(P32R_OUT_JLD2))
    JLD2.jldsave(P32R_OUT_JLD2;
        Nt_values = audit["Nt_values"],
        J_values  = audit["J_values"],
        p_fit     = audit["p_fit"],
        R2        = audit["R2"],
        C_fit     = audit["C_fit"],
        A_fit     = audit["A_fit"],
        verdict   = audit["verdict"],
        source    = audit["source"],
    )
    @info "Wrote richardson_audit.jld2" path=P32R_OUT_JLD2
end

"""
    _append_results_md(audit)

Append/replace the `## Experiment 0` section in `32-RESULTS.md`. If the
section exists, replaces its body in place; otherwise appends at the end.
"""
function _append_results_md(audit::Dict{String,Any})
    mkpath(dirname(P32R_RESULTS_PATH))
    lines = String[]
    push!(lines, "")
    push!(lines, "## Experiment 0 — Richardson applicability audit")
    push!(lines, "")
    push!(lines, "_populated by scripts/phase32_richardson_audit.jl_")
    push!(lines, "")
    push!(lines, "- Source phi_opt: `$(audit["source"])`")
    push!(lines, "- Fiber: SMF-28, L = $(P32R_L_FIBER) m, P = $(P32R_P_CONT) W, β_order = $(P32R_BETA_ORDER)")
    push!(lines, "- Time window: $(P32R_TIME_WINDOW) ps (fixed across Nt; zero-pad-in-frequency upsampling)")
    push!(lines, "")
    push!(lines, "| Nt   | J(phi_opt)  |")
    push!(lines, "|------|-------------|")
    for (Nt, J) in zip(audit["Nt_values"], audit["J_values"])
        push!(lines, @sprintf("| %d | %.6e |", Nt, J))
    end
    push!(lines, "")
    push!(lines, @sprintf("Fit `J(Nt) = C + A * Nt^{-p}`: **p = %.3f, R² = %.4f, C = %.3e, A = %.3e**",
        audit["p_fit"], audit["R2"], audit["C_fit"], audit["A_fit"]))
    push!(lines, "")
    push!(lines, @sprintf("**Verdict: `%s`**", audit["verdict"]))
    push!(lines, "")
    if audit["verdict"] == "APPLICABLE"
        push!(lines, "Richardson extrapolation is trustworthy on this problem. Keep the")
        push!(lines, "candidate but defer to the Experiment 1 / 2 classifier for the final")
        push!(lines, "WORTH_IT / NOT_WORTH_IT call.")
    else
        push!(lines, "Richardson extrapolation is NOT trustworthy on this problem (R² < $(P32R_R2_MIN)")
        push!(lines, "or p outside [$(P32R_P_MIN), $(P32R_P_MAX)]). Abandon Richardson per RESEARCH §6")
        push!(lines, "Experiment 0 abandon criterion — DO NOT include it in Experiment 1 / 2.")
    end
    push!(lines, "")

    new_block = join(lines, "\n")

    if isfile(P32R_RESULTS_PATH)
        existing = read(P32R_RESULTS_PATH, String)
        # Replace section if it already exists; else append.
        # Simple strategy: if the exact heading is present, truncate from there
        # to the next `##` heading (non-inclusive) and splice new_block in.
        heading = "## Experiment 0 — Richardson applicability audit"
        idx = findfirst(heading, existing)
        if idx !== nothing
            before = existing[1:prevind(existing, first(idx))]
            # Find next top-level `## ` after heading
            after_start = last(idx) + 1
            next_idx = findnext(r"\n## ", existing, after_start)
            after = next_idx === nothing ? "" : existing[first(next_idx):end]
            open(P32R_RESULTS_PATH, "w") do io
                write(io, rstrip(before), "\n", new_block, after)
            end
        else
            open(P32R_RESULTS_PATH, "a") do io
                write(io, new_block)
            end
        end
    else
        open(P32R_RESULTS_PATH, "w") do io
            write(io, "# Phase 32 Results — Extrapolation and Acceleration\n", new_block)
        end
    end
    @info "Wrote Experiment 0 section" path=P32R_RESULTS_PATH verdict=audit["verdict"]
end

# ─────────────────────────────────────────────────────────────────────────────
# Main driver
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(P32R_OUTDIR)

    probe = _probe_reference_phi()
    if probe === nothing
        @warn "No cached SMF-28 phi_opt found; using 20-iter L-BFGS fallback"
        phi_ref, Nt_ref, tw_ref, source = _fallback_reference_phi()
    else
        phi_ref, Nt_ref, tw_ref, source = probe
    end

    @info "Richardson audit: forward solves at Nt ∈ $(P32R_NT_LADDER)"
    J_values = Float64[]
    for Nt in P32R_NT_LADDER
        J = _forward_J_on_grid(phi_ref, Nt_ref, tw_ref, Nt, P32R_TIME_WINDOW)
        push!(J_values, J)
        @info @sprintf("Richardson audit: Nt = %d, J = %.6e", Nt, J)
    end

    p_fit, R2, C_fit, A_fit = _fit_power_law(P32R_NT_LADDER, J_values)
    verdict = _classify_richardson(p_fit, R2)

    audit = Dict{String,Any}(
        "Nt_values" => collect(P32R_NT_LADDER),
        "J_values"  => J_values,
        "p_fit"     => p_fit,
        "R2"        => R2,
        "C_fit"     => C_fit,
        "A_fit"     => A_fit,
        "verdict"   => verdict,
        "source"    => source,
    )

    _save_audit_jld2(audit)
    _append_results_md(audit)

    @info @sprintf("Richardson audit complete: p = %.3f, R² = %.4f, verdict = %s",
        p_fit, R2, verdict)
    return audit
end

# Guarded: `include` at REPL defines functions without triggering the solves.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
