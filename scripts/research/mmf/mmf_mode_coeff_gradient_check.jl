"""
Finite-difference preflight for MMF mode-coefficient optimization.

The advisor-facing MMF mode-launch question should not run as a large science
campaign until the custom complex mode-coefficient gradient is checked. This
script validates the packed joint gradient from `mmf_joint_optimization.jl` on
small, cheap GRIN-50 problems.

Run on burst or a small ephemeral:

    julia -t auto --project=. scripts/research/mmf/mmf_mode_coeff_gradient_check.jl

Useful environment overrides:

    MMF_MODE_FD_NT=1024
    MMF_MODE_FD_L=0.2
    MMF_MODE_FD_P=0.05
    MMF_MODE_FD_TW=8
    MMF_MODE_FD_EPS=1e-5
"""

using Dates
using LinearAlgebra
using Printf
using Random

include(joinpath(@__DIR__, "mmf_joint_optimization.jl"))

const OUT_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "mmf_mode_coeff_preflight")
const SEED = 20260426

function _env_int(name::AbstractString, default::Int)
    return parse(Int, get(ENV, name, string(default)))
end

function _env_float(name::AbstractString, default::Float64)
    return parse(Float64, get(ENV, name, string(default)))
end

function _relative_error(a::Real, b::Real)
    return abs(a - b) / max(abs(a), abs(b), 1e-12)
end

function run_mmf_mode_coeff_gradient_check()
    mkpath(OUT_DIR)
    Nt_req = _env_int("MMF_MODE_FD_NT", 1024)
    L = _env_float("MMF_MODE_FD_L", 0.2)
    P = _env_float("MMF_MODE_FD_P", 0.05)
    tw = _env_float("MMF_MODE_FD_TW", 8.0)
    eps_fd = _env_float("MMF_MODE_FD_EPS", 1e-5)
    max_rel_allowed = _env_float("MMF_MODE_FD_MAX_REL", 5e-2)

    setup = setup_mmf_raman_problem(;
        preset = :GRIN_50,
        L_fiber = L,
        P_cont = P,
        Nt = Nt_req,
        time_window = tw,
        auto_time_window = true,
    )
    Nt, M = size(setup.uω0)
    c_init = setup.mode_weights
    @assert abs(c_init[1]) > 1e-8 "LP01 coefficient too small to recover pulse"

    pulse_1d = setup.uω0[:, 1] ./ c_init[1]
    uω0_pulse = repeat(pulse_1d, 1, M)

    rng = MersenneTwister(SEED)
    φ = 0.01 .* randn(rng, Nt)
    x = zeros(Float64, Nt + 2 * (M - 1))
    _pack_joint!(x, φ, c_init)

    J0, g0 = cost_and_gradient_joint(
        x, uω0_pulse, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum,
        log_cost = false,
    )

    mode_idxs = collect((Nt + 1):min(length(x), Nt + 2 * min(M - 1, 3)))
    rows = NamedTuple[]
    max_rel = 0.0
    for idx in mode_idxs
        xp = copy(x); xm = copy(x)
        xp[idx] += eps_fd
        xm[idx] -= eps_fd
        Jp, _ = cost_and_gradient_joint(
            xp, uω0_pulse, setup.fiber, setup.sim, setup.band_mask;
            variant = :sum,
            log_cost = false,
        )
        Jm, _ = cost_and_gradient_joint(
            xm, uω0_pulse, setup.fiber, setup.sim, setup.band_mask;
            variant = :sum,
            log_cost = false,
        )
        g_fd = (Jp - Jm) / (2eps_fd)
        rel = _relative_error(g0[idx], g_fd)
        max_rel = max(max_rel, rel)
        push!(rows, (
            index = idx,
            analytic = g0[idx],
            finite_difference = g_fd,
            rel_error = rel,
        ))
    end

    passed = isfinite(J0) && all(isfinite, g0) && max_rel <= max_rel_allowed
    summary_path = joinpath(OUT_DIR, "mode_coeff_gradient_check_summary.md")
    open(summary_path, "w") do io
        println(io, "# MMF Mode-Coefficient Gradient Check")
        println(io)
        println(io, @sprintf("Generated %s UTC.", Dates.format(now(UTC), dateformat"yyyy-mm-dd HH:MM:SS")))
        println(io)
        println(io, "- Preset: `GRIN_50`")
        println(io, @sprintf("- L=%.3f m, P=%.3f W, Nt=%d, time_window=%.1f ps", L, P, Nt, setup.sim["time_window"]))
        println(io, @sprintf("- J0=%.6e", J0))
        println(io, @sprintf("- Max relative error: %.3e", max_rel))
        println(io, @sprintf("- Threshold: %.3e", max_rel_allowed))
        println(io, "- Verdict: " * (passed ? "PASS" : "FAIL"))
        println(io)
        println(io, "| packed index | analytic | finite difference | rel error |")
        println(io, "|---:|---:|---:|---:|")
        for r in rows
            println(io, @sprintf("| %d | %.8e | %.8e | %.3e |",
                r.index, r.analytic, r.finite_difference, r.rel_error))
        end
    end

    @info "mode-coefficient gradient check summary: $summary_path"
    if !passed
        error(@sprintf("MMF mode-coefficient gradient check failed: max_rel=%.3e", max_rel))
    end
    return (; passed, max_rel, rows, summary_path)
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_mmf_mode_coeff_gradient_check()
end
