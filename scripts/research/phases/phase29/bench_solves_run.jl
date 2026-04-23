"""
Phase 29 subprocess worker. Prints exactly one `BENCH_JSON: {...}` line on
stdout (everything else is discarded by the parent driver). The three modes
measure DISTINCT work to defeat the "subtract forward from full recovers ≈ 0"
failure mode:

  mode == "forward" — direct forward-only solve via MultiModeNoise.solve_disp_mmf
                      (no cost, no adjoint). See 29-RESEARCH.md §7.1 and
                      src/simulation/simulate_disp_mmf.jl:178.
  mode == "adjoint" — pre-run one forward OUTSIDE the timed block to capture
                      the ODESolution ũω AND the terminal adjoint condition
                      λωL = spectral_band_cost(uωf, band_mask)[2], then time
                      only solve_adjoint_disp_mmf(λωL, ũω, fiber, sim).
                      See 29-RESEARCH.md §7.2 and
                      src/simulation/sensitivity_disp_mmf.jl:294.
  mode == "full_cg" — time one call of cost_and_gradient (forward + cost +
                      adjoint + chain rule + regularizers + log-dB). See
                      29-RESEARCH.md §7.3 and scripts/raman_optimization.jl:73.

Consistency check done by the outer driver (29-RESEARCH.md §7.4):
  residual = median(full_cg) - (median(forward) + median(adjoint))
The residual is the cost-accumulation + chain-rule + regularizer overhead
(should be ≤ 10% of full_cg). Written to solves.jld2.

Parse-check safety: if invoked with no ARGS (`julia -e 'include("...run.jl")'`),
the worker logs a message and returns without touching ARGS[1] so lint-style
include parses do not error.
"""

using Printf
using JSON3
using LinearAlgebra
using FFTW
using Random
ENV["MPLBACKEND"] = "Agg"
using MultiModeNoise
using Tullio
using Optim

include(joinpath(@__DIR__, "..", "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "raman_optimization.jl"))

# Guard so `julia -e 'include("bench_solves_run.jl")'` (parse-check)
# does not crash on missing ARGS. Without this, the verify step's
# `include(...)` linting will error on `ARGS[1]`.
if isempty(ARGS)
    @info "phase29 worker: loaded via include with no ARGS — skipping timed block (parse-check mode)"
else

mode = ARGS[1]      # "forward" | "adjoint" | "full_cg"
tag  = ARGS[2]

const W_NT      = 2^13
const W_L_FIBER = 2.0      # SMF-28 canonical [m]
const W_P_CONT  = 0.2      # SMF-28 canonical [W]
const W_SEED    = 42

Random.seed!(W_SEED)
uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
    L_fiber=W_L_FIBER, P_cont=W_P_CONT, Nt=W_NT,
    fiber_preset=:SMF28, β_order=3, time_window=10.0)
Nt = sim["Nt"]; M = sim["M"]
φ          = zeros(Nt, M)
uω0_shaped = @. uω0 * cis(φ)   # mirror cost_and_gradient's production path

# ── JIT warmup — compile every code path we will measure below. Do it for
# all three paths so no branch pays a cold-start cost inside the timed block.
_warm_fwd = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
let ũω_warm = _warm_fwd["ode_sol"]
    L_warm    = fiber["L"]
    Dω_warm   = fiber["Dω"]
    ũω_L_warm = ũω_warm(L_warm)
    uωf_warm  = @. cis(Dω_warm * L_warm) * ũω_L_warm
    _, λωL_warm = spectral_band_cost(uωf_warm, band_mask)
    _ = MultiModeNoise.solve_adjoint_disp_mmf(λωL_warm, ũω_warm, fiber, sim)
end
_ = cost_and_gradient(φ, uω0, fiber, sim, band_mask)

# ── Timed block. Each branch measures a DIFFERENT amount of work. ──
elapsed_s = NaN
J         = NaN
iters     = 0

if mode == "forward"
    # Pure forward propagation — no cost, no adjoint.
    # Source: src/simulation/simulate_disp_mmf.jl:178 (solve_disp_mmf).
    t_start = time()
    sol_fwd = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    elapsed_s = time() - t_start
    iters = length(sol_fwd["ode_sol"].t)   # accepted Tsit5 steps
    J = NaN                                # no cost measured in this mode

elseif mode == "adjoint"
    # Pre-capture forward ODE solution + terminal adjoint condition OUTSIDE
    # the timed block, then time ONLY the adjoint propagation. This isolates
    # adjoint cost without relying on post-hoc subtraction.
    # Source: src/simulation/sensitivity_disp_mmf.jl:294 (solve_adjoint_disp_mmf).
    sol_fwd_setup = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω_sol        = sol_fwd_setup["ode_sol"]
    L_fib         = fiber["L"]
    Dω            = fiber["Dω"]
    ũω_L          = ũω_sol(L_fib)
    uωf           = @. cis(Dω * L_fib) * ũω_L
    _, λωL        = spectral_band_cost(uωf, band_mask)

    t_start = time()
    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω_sol, fiber, sim)
    elapsed_s = time() - t_start
    # Touch the result to prevent DCE but OUTSIDE the timed block.
    _λ0 = sol_adj(0)
    @assert all(isfinite, _λ0) "adjoint solution contains non-finite entries"
    iters = length(sol_adj.t)
    J = NaN

elseif mode == "full_cg"
    # Full forward + cost + adjoint + chain rule (+ optional regularizers +
    # log-dB conversion). Source: scripts/raman_optimization.jl:73.
    t_start = time()
    J_val, _grad = cost_and_gradient(φ, uω0, fiber, sim, band_mask)
    elapsed_s = time() - t_start
    J = J_val
    iters = 1

else
    error("Unknown mode: $mode (expected \"forward\" | \"adjoint\" | \"full_cg\")")
end

payload = Dict(
    "mode"          => mode,
    "tag"           => tag,
    "elapsed_s"     => isfinite(elapsed_s) ? elapsed_s : nothing,
    "J"             => isfinite(J) ? J : nothing,
    "iters"         => iters,
    "Nt"            => Nt,
    "M"             => M,
    "julia_threads" => Threads.nthreads(),
    "fftw_threads"  => FFTW.get_num_threads(),
    "blas_threads"  => BLAS.get_num_threads(),
)
println("BENCH_JSON: ", JSON3.write(payload))
flush(stdout)

end # isempty(ARGS) guard
