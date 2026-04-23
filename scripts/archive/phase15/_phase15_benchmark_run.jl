# ═══════════════════════════════════════════════════════════════════════════════
# Phase 15 Plan 01 — Benchmark Worker (ONE run, ONE fresh process)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Invoked by scripts/benchmark.jl as:
#   julia --project=. scripts/benchmark_run.jl (measure|estimate) <tag>
#
# Runs ONE SMF-28 canonical optimization and prints a single JSON line to stdout:
#   BENCH_JSON: {"mode":"...","tag":"...","elapsed_s":X.XX,"J":X.X,"iters":N,"Nt":N,"M":N}
#
# Timing scope: ONLY the Optim.optimize call — not Julia startup, not data setup,
# not precompilation. The driver runs a discarded warm-up subprocess first to pay
# the precompile cost, so the 3 timed runs reflect steady-state wall time.
#
# The `measure`/`estimate` mode arg is informational (logging + JSON tag only).
# The actual FFTW plan choice is controlled by whatever `flags=FFTW.X` is encoded
# in the src/simulation/*.jl files at the moment this process is spawned. The
# driver swaps those files between legs — see scripts/benchmark.jl.
# ═══════════════════════════════════════════════════════════════════════════════

using Printf
using FFTW
using LinearAlgebra
using Random
using JSON3
using Optim

# Thread pins are identical across legs (the ONLY variable we want to measure
# is the FFTW planner flag). These match what `ensure_deterministic_environment()`
# sets.
FFTW.set_num_threads(1)
BLAS.set_num_threads(1)

# Config — SMF-28 canonical, production-grade
const BM_SEED     = 42
const BM_MAX_ITER = 30
const BM_NT       = 8192      # 2^13
const BM_L_FIBER  = 2.0
const BM_P_CONT   = 0.2
const BM_TW_PS    = 20.0
const BM_PRESET   = :SMF28
const BM_BETA_ORD = 3
const BM_LOG_COST = true

# Parse CLI args
mode = length(ARGS) ≥ 1 ? ARGS[1] : "estimate"
tag  = length(ARGS) ≥ 2 ? ARGS[2] : "run"
@assert mode in ("measure", "estimate") "mode must be 'measure' or 'estimate', got $mode"

# Load the pipeline (triggers precompilation; the driver discards the first
# subprocess per leg to absorb this cost).
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))

# Set up the problem (NOT timed — we measure the optimizer loop only)
Random.seed!(BM_SEED)
uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
    fiber_preset = BM_PRESET,
    Nt           = BM_NT,
    time_window  = BM_TW_PS,
    L_fiber      = BM_L_FIBER,
    P_cont       = BM_P_CONT,
    β_order      = BM_BETA_ORD,
)
Nt_actual = sim["Nt"]
M_actual  = sim["M"]
φ0 = zeros(Nt_actual, M_actual)

# ─── The one timed region: the full L-BFGS optimization ─────────────────────
t0 = time()
result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
    φ0         = φ0,
    max_iter   = BM_MAX_ITER,
    λ_gdd      = 0.0,
    λ_boundary = 0.0,
    store_trace = false,
    log_cost   = BM_LOG_COST,
)
elapsed = time() - t0
# ─────────────────────────────────────────────────────────────────────────────

phi_opt = reshape(Optim.minimizer(result), Nt_actual, M_actual)
J, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask; log_cost=false)
iters = Optim.iterations(result)

# Emit machine-parseable JSON on a single line, with a sentinel prefix so the
# driver can robustly extract it from interleaved stderr/info logs.
payload = Dict(
    "mode"      => mode,
    "tag"       => tag,
    "elapsed_s" => elapsed,
    "J"         => J,
    "iters"     => iters,
    "Nt"        => Nt_actual,
    "M"         => M_actual,
)
println("BENCH_JSON: ", JSON3.write(payload))
flush(stdout)
