# ═══════════════════════════════════════════════════════════════════════════════
# Phase 29 Roofline Model — arithmetic intensity, bandwidth, Amdahl/Gustafson
# ═══════════════════════════════════════════════════════════════════════════════
# READ-ONLY consumer of timing JLD2 artifacts. No simulations, no ODE calls.
# Constants use the P29M_ prefix (Phase 29 Modeling) per STATE.md convention.
#
# Public API:
#   arithmetic_intensity(flops, bytes)                 -> Float64 (FLOP/byte)
#   roofline_bound(AI, peak_flops, peak_bw)            -> NamedTuple(bound_flops_s, regime)
#   fit_amdahl(n_threads, times)                       -> NamedTuple(p, speedup_inf, rmse)
#   fit_gustafson(n_threads, times)                    -> NamedTuple(s, speedup_n)
#   kernel_regime_verdict(AI, bound_regime)            -> String
#   assemble_roofline_memo(bench_data; hw_profile)     -> String (markdown)
#
# All functions are pure (allocate outputs, no I/O, no mutation of inputs) and
# carry @assert preconditions per scripts/common.jl style. Unit tests in
# test/test_phase29_roofline.jl.
# ═══════════════════════════════════════════════════════════════════════════════

# Module-level imports must live OUTSIDE any include guard so macros (@sprintf,
# etc.) are visible at compile time. Mirrors scripts/primitives.jl.
using LinearAlgebra
using Statistics
using Printf

if !(@isdefined _PHASE29_ROOFLINE_LOADED)

const _PHASE29_ROOFLINE_LOADED = true
const P29M_VERSION = "1.0.0"

# Thresholds are conservative; documented in 29-RESEARCH.md §9.
const P29M_MEMORY_BOUND_AI_THRESHOLD  = 1.0    # FLOP/byte: below this -> MEMORY_BOUND
const P29M_COMPUTE_BOUND_AI_THRESHOLD = 10.0   # FLOP/byte: above this -> COMPUTE_BOUND
const P29M_SERIAL_FRACTION_SATURATION = 0.2    # p<0.2 => Amdahl saturates fast (SERIAL-dominated)

# Verdict ranking — higher = worse; mirrors scripts/numerical_trust.jl _TRUST_RANK.
const P29M_REGIME_RANK = Dict(
    "MEMORY_BOUND"    => 0,
    "COMPUTE_BOUND"   => 1,
    "SERIAL_BOUND"    => 2,
    "AMDAHL_SATURATED"=> 3,
    "UNKNOWN"         => 4,
)

# ─────────────────────────────────────────────────────────────────────────────
# Arithmetic intensity
# ─────────────────────────────────────────────────────────────────────────────

"""
    arithmetic_intensity(flops::Real, bytes::Real) -> Float64

FLOP per byte for a kernel. Preconditions: `flops ≥ 0`, `bytes > 0`.
This is the x-axis coordinate in the classical roofline plot.
"""
function arithmetic_intensity(flops::Real, bytes::Real)
    @assert flops >= 0 "flops must be non-negative, got $flops"
    @assert bytes > 0 "bytes must be positive, got $bytes"
    return Float64(flops) / Float64(bytes)
end

# ─────────────────────────────────────────────────────────────────────────────
# Roofline bound
# ─────────────────────────────────────────────────────────────────────────────

"""
    roofline_bound(AI::Real, peak_flops::Real, peak_bw::Real)
        -> (bound_flops_s, regime)

Classical roofline: min(peak_flops, peak_bw * AI). `regime` is `"COMPUTE_BOUND"`
if the compute ceiling dominates (AI past the ridge point), `"MEMORY_BOUND"`
otherwise. Preconditions: AI ≥ 0, peak_flops > 0, peak_bw > 0.
"""
function roofline_bound(AI::Real, peak_flops::Real, peak_bw::Real)
    @assert AI >= 0 "AI must be non-negative"
    @assert peak_flops > 0 && peak_bw > 0 "peaks must be positive"
    mem_ceiling = Float64(peak_bw) * Float64(AI)
    if mem_ceiling >= Float64(peak_flops)
        return (bound_flops_s = Float64(peak_flops), regime = "COMPUTE_BOUND")
    else
        return (bound_flops_s = mem_ceiling, regime = "MEMORY_BOUND")
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Amdahl fit
# ─────────────────────────────────────────────────────────────────────────────

"""
    fit_amdahl(n_threads::AbstractVector, times::AbstractVector)
        -> (p, speedup_inf, rmse)

Amdahl model: `T(n) = T(1) · ((1-p) + p/n)`, where `p` is the PARALLELIZABLE
fraction (so `1-p` is serial). Returns `speedup_inf = 1/(1-p)` — the asymptotic
speedup ceiling as n → ∞.

Fit in (1/n) space: let x_n = 1/n, then T_n/T_1 = (1-p) + p·x_n = 1 + p·(x_n-1),
so y_n = T_n/T_1 - 1 = p·(x_n - 1) is linear in p; closed-form least squares.

Preconditions: n_threads ≥ 1; times > 0; same length.
"""
function fit_amdahl(n_threads::AbstractVector, times::AbstractVector)
    @assert length(n_threads) == length(times) "length mismatch"
    @assert all(n_threads .>= 1) "n_threads must be ≥ 1"
    @assert all(times .> 0) "times must be positive"
    T1 = Float64(times[1])
    xs = 1.0 ./ Float64.(n_threads)
    ys = Float64.(times) ./ T1 .- 1.0
    A  = xs .- 1.0
    # Guard against degenerate single-point input (only n=1, A ≡ 0).
    denom = sum(A .* A)
    p = denom > 0 ? sum(A .* ys) / denom : 0.0
    p = clamp(p, 0.0, 1.0)
    pred = T1 .* ((1 - p) .+ p .* xs)
    rmse = sqrt(mean((Float64.(times) .- pred) .^ 2))
    speedup_inf = p < 1.0 ? 1.0 / (1.0 - p) : Inf
    return (p = p, speedup_inf = speedup_inf, rmse = rmse)
end

# ─────────────────────────────────────────────────────────────────────────────
# Gustafson fit (scaled speedup — included for completeness)
# ─────────────────────────────────────────────────────────────────────────────

"""
    fit_gustafson(n_threads, times) -> (s, speedup_n)

Scaled-speedup fit: Gustafson's law `S(n) = n - s·(n-1)`. Returns serial
fraction `s` and observed max speedup at the largest n. Fixed-total-work
timings (as measured by Phase 29) are NOT strictly Gustafson — the caller is
responsible for interpretation. Exported for completeness; the Phase 29 memo
reports Amdahl primarily.
"""
function fit_gustafson(n_threads::AbstractVector, times::AbstractVector)
    @assert length(n_threads) == length(times) "length mismatch"
    @assert all(n_threads .>= 1) "n_threads must be ≥ 1"
    @assert all(times .> 0) "times must be positive"
    ns = Float64.(n_threads); ts = Float64.(times)
    T1 = ts[1]
    S  = T1 ./ ts .* ns           # naive speedup·n
    A  = 1.0 .- ns
    y  = S .- ns
    denom = sum(A .* A)
    s = denom > 0 ? sum(A .* y) / denom : 0.0
    s = clamp(s, 0.0, 1.0)
    speedup_n = maximum(S)
    return (s = s, speedup_n = speedup_n)
end

# ─────────────────────────────────────────────────────────────────────────────
# Kernel regime verdict (roofline + AI thresholds combined)
# ─────────────────────────────────────────────────────────────────────────────

"""
    kernel_regime_verdict(AI::Real, bound_regime::AbstractString) -> String

Returns one of `"MEMORY_BOUND"`, `"COMPUTE_BOUND"`, `"SERIAL_BOUND"`,
`"AMDAHL_SATURATED"`, `"UNKNOWN"`. Preconditions: AI ≥ 0; `bound_regime` ∈
{"MEMORY_BOUND", "COMPUTE_BOUND", "UNKNOWN"}.

Decision rule:
  AI < P29M_MEMORY_BOUND_AI_THRESHOLD   → "MEMORY_BOUND" (forced, regardless of roofline)
  AI > P29M_COMPUTE_BOUND_AI_THRESHOLD  → "COMPUTE_BOUND" (forced)
  otherwise                             → trust the roofline caller's bound_regime
"""
function kernel_regime_verdict(AI::Real, bound_regime::AbstractString)
    @assert AI >= 0 "AI non-negative"
    bound_regime in ("MEMORY_BOUND", "COMPUTE_BOUND", "UNKNOWN") ||
        throw(ArgumentError("unsupported bound_regime=$bound_regime"))
    AI < P29M_MEMORY_BOUND_AI_THRESHOLD  && return "MEMORY_BOUND"
    AI > P29M_COMPUTE_BOUND_AI_THRESHOLD && return "COMPUTE_BOUND"
    return bound_regime
end

# ─────────────────────────────────────────────────────────────────────────────
# Memo assembler
# ─────────────────────────────────────────────────────────────────────────────

"""
    assemble_roofline_memo(bench_data::Dict; hw_profile::Dict) -> String

Render the full markdown memo used by scripts/report.jl. MUST include
the headings:
  "# Phase 29 Report", "## Executive Verdict", "## Kernel Timings",
  "## Amdahl Fits", "## Roofline Regimes", "## Recommendations".
Returns the markdown string (no I/O). Missing sub-sections render as "TODO" so
the scope-lock memo remains valid before numeric results exist.
"""
function assemble_roofline_memo(bench_data::Dict; hw_profile::Dict)
    io = IOBuffer()
    println(io, "# Phase 29 Report — Performance Modeling and Roofline Audit")
    println(io)
    println(io, "**Generated:** ", get(bench_data, "timestamp", "UNKNOWN"))
    println(io, "**Host:** ", get(hw_profile, "hostname", "UNKNOWN"),
                "  |  CPU: ", get(hw_profile, "cpu_info", "UNKNOWN"),
                "  |  Julia threads launched: ", get(hw_profile, "julia_threads", "?"),
                "  |  git: ", get(hw_profile, "git_commit", "unknown"))
    println(io)
    println(io, "## Executive Verdict")
    println(io)
    println(io, get(bench_data, "executive_verdict", "TODO"))
    println(io)
    println(io, "## Kernel Timings")
    println(io)
    println(io, get(bench_data, "kernels_md", "TODO"))
    println(io)
    println(io, "## Amdahl Fits")
    println(io)
    println(io, get(bench_data, "amdahl_md", "TODO"))
    println(io)
    println(io, "## Roofline Regimes")
    println(io)
    println(io, get(bench_data, "roofline_md", "TODO"))
    println(io)
    println(io, "## Recommendations")
    println(io)
    println(io, get(bench_data, "recommendations_md", "TODO"))
    return String(take!(io))
end

end # include guard _PHASE29_ROOFLINE_LOADED
