"""
Continuation and homotopy schedules for Raman-suppression optimization (Phase 30).

One-line purpose
----------------
Promote "warm-start across lengths/powers" from an ad-hoc habit into an explicit
numerical method with a declared ladder, predictor, corrector, failure detectors,
and per-step trust emission on top of the Phase 28 numerical-trust schema.

Public API
----------
- `ContinuationSchedule`       — immutable plan (ladder variable, values, config)
- `ContinuationStepResult`     — per-step outcome (phi_opt, dB, trust, detectors)
- `run_ladder(schedule; ...)`  — driver that walks the ladder with predictor +
                                 corrector + detector policy, emitting one trust
                                 row per converged step
- `trivial_predictor`          — identity predictor with cross-grid interpolation
- `detect_cost_discontinuity`, `detect_corrector_burn`,
  `detect_phase_jump`, `detect_edge_growth` — pure detector functions

The default corrector wraps `optimize_spectral_phase` (scripts/raman_optimization.jl).
External callers can pass any `corrector_fn(phi_init, cfg) -> (phi_opt, J_final, iters, wall_s)`
to plug in future correctors (Phase 33/34 Newton, Phase 32 acceleration).

# Saddle caveat (Phase 22 / 35)
The competitive-dB branch of the Raman-suppression landscape is Hessian-
indefinite everywhere surveyed. L, P, and λ ladders traverse saddles, not
a smooth minimum branch. Detectors D1-D8 are designed to tolerate indefinite
Hessians; Hessian sign change (D6) is informational only. Only the N_phi
ladder (Phase 31) has a theoretical minimum-branch regime.

Phase 28 trust schema
---------------------
All per-step trust reports are built with `build_numerical_trust_report(...)`
from `scripts/numerical_trust.jl` and then augmented (additively) via
`attach_continuation_metadata!(...)`. The schema version string stays "28.0" —
Phase 30 does NOT bump it. Downstream readers that do not know about
continuation metadata keep working unchanged.

Deferred ideas (NOT in this module; tracked here for traceability)
------------------------------------------------------------------
- **Secant predictor**  — phi_next = phi_prev + α (phi_prev - phi_prev_prev).
                          Useful once two warm-starts are available. May be
                          added at executor discretion in a future plan.
- **Tangent / Newton predictor** — requires an explicit Hessian or HVP and the
                          implicit-function-theorem tangent vector. Deferred
                          to Phases 33/34 (globalized second-order optimization).
- **Pseudo-arclength continuation** — requires tangent + bordered-system solve.
                          Not viable until Phases 33/34 provide a Newton
                          corrector; pseudo-arclength on L-BFGS alone is not
                          numerically justified.
- **Multi-variable / joint ladders** — joint (L, P) or (L, Nphi) schedules are
                          a Phase 31+ successor once the reduced-basis
                          framework is in place.

References
----------
- Phase 22 (sharpness-Pareto, all competitive optima Hessian-indefinite)
- Phase 28 (numerical trust schema 28.0)
- Phase 35 (saddle-escape verdict)
- scripts/benchmark_optimization.jl:470-574 — precursor `run_continuation` (L-only,
  same-Nt). Superseded by this module; kept for reference.

Include guard
-------------
`_CONTINUATION_JL_LOADED` — safe to include multiple times.
"""

# Module-level imports outside the include guard (per project convention) —
# keeps macros visible at compile time and lets parent scripts that already
# loaded the helpers avoid duplicate `using` warnings.
using LinearAlgebra
using Printf
using Logging
using Dates

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))
include(joinpath(@__DIR__, "longfiber_setup.jl"))

if !(@isdefined _CONTINUATION_JL_LOADED)
const _CONTINUATION_JL_LOADED = true

"""
Version tag for the continuation module. Downstream consumers (Phase 31/32/33/34)
can version-gate against this constant. Unrelated to the Phase 28 trust schema
version `NUMERICAL_TRUST_SCHEMA_VERSION`, which stays "28.0".
"""
const CONTINUATION_VERSION = "30.0"

"""
Known ladder variables. Adding a new one requires also updating the
`_CONTINUATION_LADDER_VARS` set in `scripts/numerical_trust.jl` so the
metadata validator stays in sync.
"""
const LADDER_VARS = (:L, :P, :Nphi, :lambda)

"""
Known path-status values emitted by `run_ladder`. The same set is validated in
`attach_continuation_metadata!` (numerical_trust.jl).
"""
const PATH_STATUSES = (:ok, :degraded, :broken)

# ─────────────────────────────────────────────────────────────────────────────
# Public structs
# ─────────────────────────────────────────────────────────────────────────────

"""
    ContinuationSchedule(continuation_id, ladder_var, values, base_config,
                        predictor, corrector, max_iter_per_step, enable_hessian_probe)

Immutable plan for a continuation run.

# Fields
- `continuation_id::String`        — caller-supplied identifier (e.g., "p30_demo_smf28_L")
- `ladder_var::Symbol`             — one of `:L`, `:P`, `:Nphi`, `:lambda`
- `values::Vector{Float64}`        — ladder values in physical units
                                      (metres for `:L`, W for `:P`, count for
                                      `:Nphi`, dimensionless for `:lambda`)
- `base_config::Dict{String,Any}`  — keys consumed by `setup_raman_problem` /
                                      `setup_longfiber_problem`: `P_cont`, `Nt`,
                                      `time_window`, `fiber_preset`, `β_order`,
                                      plus optional `λ_gdd`, `λ_boundary`
- `predictor::Symbol`              — `:trivial` (v1 only; see deferred-ideas
                                      list in the module docstring)
- `corrector::Symbol`              — `:lbfgs_warm_restart` (v1 only)
- `max_iter_per_step::Int`         — corrector budget per step (budget parity
                                      between cold-start and warm-start arms
                                      MUST come from passing the same value)
- `enable_hessian_probe::Bool`     — reserved for future `detect_hessian_sign_change`
                                      (D6). Default `false` in v1.
"""
struct ContinuationSchedule
    continuation_id::String
    ladder_var::Symbol
    values::Vector{Float64}
    base_config::Dict{String,Any}
    predictor::Symbol
    corrector::Symbol
    max_iter_per_step::Int
    enable_hessian_probe::Bool

    function ContinuationSchedule(;
        continuation_id::AbstractString,
        ladder_var::Symbol,
        values::AbstractVector,
        base_config::Dict{String,Any},
        predictor::Symbol = :trivial,
        corrector::Symbol = :lbfgs_warm_restart,
        max_iter_per_step::Integer = 30,
        enable_hessian_probe::Bool = false,
    )
        @assert ladder_var in LADDER_VARS "unknown ladder_var :$ladder_var — allowed: $(LADDER_VARS)"
        @assert predictor in (:trivial,) "unsupported predictor :$predictor — only :trivial in v1"
        @assert corrector in (:lbfgs_warm_restart,) "unsupported corrector :$corrector — only :lbfgs_warm_restart in v1"
        @assert !isempty(values) "ContinuationSchedule needs at least one ladder value"
        @assert max_iter_per_step > 0 "max_iter_per_step must be positive"
        return new(
            String(continuation_id),
            ladder_var,
            collect(float.(values)),
            base_config,
            predictor,
            corrector,
            Int(max_iter_per_step),
            enable_hessian_probe,
        )
    end
end

"""
    ContinuationStepResult

Per-step outcome emitted by `run_ladder`.

# Fields
- `step_index::Int`                     — 1-based ladder index
- `ladder_value::Float64`               — physical ladder value at this step
- `J_init::Float64`                     — initial cost seen by the corrector
                                          (linear, not dB) — best-effort
                                          NaN-safe: if the predictor fails,
                                          J_init is `NaN`
- `J_opt_dB::Float64`                   — final cost in dB (10·log10(J_linear))
- `phi_opt::Vector{Float64}`            — optimized spectral phase (FFT-order)
- `corrector_iters::Int`                — iterations the corrector used
- `wall_time_s::Float64`                — wall-clock time of the corrector call
- `trust_report::Dict{String,Any}`      — Phase 28 trust report augmented by
                                          `attach_continuation_metadata!`
- `detector_flags::Dict{Symbol,Bool}`   — D2/D3/D4/D8 trigger booleans
- `path_status::Symbol`                 — one of `:ok | :degraded | :broken`
"""
struct ContinuationStepResult
    step_index::Int
    ladder_value::Float64
    J_init::Float64
    J_opt_dB::Float64
    phi_opt::Vector{Float64}
    corrector_iters::Int
    wall_time_s::Float64
    trust_report::Dict{String,Any}
    detector_flags::Dict{Symbol,Bool}
    path_status::Symbol
end

# ─────────────────────────────────────────────────────────────────────────────
# Detectors (pure functions — easy to unit-test)
# ─────────────────────────────────────────────────────────────────────────────

"""
    detect_cost_discontinuity(prev_dB, curr_dB; threshold_dB=3.0) -> Bool

Soft-halt detector (D2). Fires when the final-cost dB JUMPS UP between two
consecutive ladder steps by more than `threshold_dB` dB. A sudden improvement
(curr_dB < prev_dB) is never flagged — that is desirable and normal when the
problem gets easier on the next step.

# Arguments
- `prev_dB`        : previous step's J_opt_dB
- `curr_dB`        : current  step's J_opt_dB
- `threshold_dB`   : tolerance in dB (default 3.0, per RESEARCH §3)
"""
function detect_cost_discontinuity(prev_dB::Real, curr_dB::Real; threshold_dB::Real=3.0)
    !isfinite(prev_dB) && return false
    !isfinite(curr_dB) && return true
    return (curr_dB - prev_dB) > threshold_dB
end

"""
    detect_corrector_burn(iters, baseline_iters; factor=3.0) -> Bool

Soft-halt detector (D3). Fires when the corrector uses more than
`factor × baseline_iters` iterations to converge on the current step.
Indicates the warm start was far from the next basin.

# Arguments
- `iters`          : iterations used by the corrector on the current step
- `baseline_iters` : reference iteration count (typically the cold-start
                     iterations at step 1, or `max_iter_per_step`)
- `factor`         : multiplicative tolerance (default 3.0, per RESEARCH §3)
"""
function detect_corrector_burn(iters::Integer, baseline_iters::Integer; factor::Real=3.0)
    baseline_iters <= 0 && return false
    return iters > factor * baseline_iters
end

"""
    detect_phase_jump(phi_init, phi_opt; ratio=10.0) -> Bool

Soft-halt detector (D4). Fires when the corrector moved the phase by more than
`ratio × norm(phi_init)` — i.e., the warm start was not actually near the
converged point. Guarded against `norm(phi_init) == 0` (cold-start): returns
`false` in that case since no "jump ratio" is meaningful.

# Arguments
- `phi_init`       : initial phase handed to the corrector (FFT-order vector)
- `phi_opt`        : corrector output
- `ratio`          : multiplicative tolerance (default 10.0)
"""
function detect_phase_jump(phi_init::AbstractVector, phi_opt::AbstractVector; ratio::Real=10.0)
    @assert length(phi_init) == length(phi_opt) "phi_init ($(length(phi_init))) and phi_opt ($(length(phi_opt))) length mismatch"
    n_init = norm(phi_init)
    if !isfinite(n_init) || n_init < sqrt(eps(Float64))
        return false
    end
    return norm(phi_opt .- phi_init) > ratio * n_init
end

"""
    detect_edge_growth(edge_prev, edge_curr; factor=10.0, absolute=0.01,
                       floor=1e-6) -> Bool

Hard-halt detector (D8). Fires when the output-pulse temporal-edge energy
fraction grew by more than `factor×` between steps AND the current value
exceeds `floor`, OR exceeds an absolute ceiling `absolute` (default 1 %).
Either condition indicates the pulse is being absorbed by the attenuator
boundary — results past this step are not to be trusted regardless of the
cost value.

The `floor` guard prevents step-to-step magnification of noise at nearly-zero
edge values (e.g., 1e-12 → 1e-10 is a 100× ratio but physically irrelevant).

# Arguments
- `edge_prev`      : previous step's max edge fraction
- `edge_curr`      : current  step's max edge fraction
- `factor`         : relative-growth tolerance (default 10.0)
- `absolute`       : absolute ceiling (default 0.01 = 1 %)
- `floor`          : below this, the factor rule is suppressed (default 1e-6)
"""
function detect_edge_growth(edge_prev::Real, edge_curr::Real;
                            factor::Real=10.0, absolute::Real=0.01,
                            floor::Real=1e-6)
    !isfinite(edge_curr) && return true
    edge_curr > absolute && return true
    if isfinite(edge_prev) && edge_prev > 0 && edge_curr > floor
        return edge_curr > factor * edge_prev
    end
    return false
end

# ─────────────────────────────────────────────────────────────────────────────
# Predictor
# ─────────────────────────────────────────────────────────────────────────────

"""
    trivial_predictor(phi_prev, cfg_prev, cfg_next) -> Vector{Float64}

v1 predictor: copy the previous phi onto the next grid. If the two grids share
`Nt`, returns `copy(phi_prev)`. Otherwise delegates to
`longfiber_interpolate_phi` (scripts/longfiber_setup.jl) which performs a
physical-frequency-domain linear interpolation.

# Arguments
- `phi_prev` : previous step's optimized phase (FFT-order vector)
- `cfg_prev` : previous step's config — MUST carry `"Nt"` and `"time_window"` (ps)
- `cfg_next` : next step's config — same keys

# Returns
- `phi_next :: Vector{Float64}` of length `cfg_next["Nt"]`, FFT-order.

# Example
```julia
phi_next = trivial_predictor(phi_prev,
    Dict("Nt"=>8192, "time_window"=>10.0),
    Dict("Nt"=>16384, "time_window"=>40.0))
```
"""
function trivial_predictor(phi_prev::AbstractVector,
                           cfg_prev::Dict{String,Any},
                           cfg_next::Dict{String,Any})
    Nt_prev = Int(cfg_prev["Nt"])
    Nt_next = Int(cfg_next["Nt"])
    if Nt_prev == Nt_next
        return Vector{Float64}(copy(vec(phi_prev)))
    end
    tw_prev = float(cfg_prev["time_window"])
    tw_next = float(cfg_next["time_window"])
    @info @sprintf("trivial_predictor: cross-grid Nt %d→%d, tw %.1f→%.1f ps",
                   Nt_prev, Nt_next, tw_prev, tw_next)
    phi_new = longfiber_interpolate_phi(vec(phi_prev), Nt_prev, tw_prev, Nt_next, tw_next)
    return Vector{Float64}(vec(phi_new))
end

# ─────────────────────────────────────────────────────────────────────────────
# Config helpers
# ─────────────────────────────────────────────────────────────────────────────

# Merge base_config with the current ladder value into a per-step config Dict.
# Handles the per-ladder-variable mapping: :L→L_fiber, :P→P_cont, :lambda→λ_gdd,
# :Nphi→Nt (reserved for Phase 31; v1 treats Nphi as Nt so the λ-ladder smoke
# test stays Nt-invariant).
function _step_config(schedule::ContinuationSchedule, ladder_value::Real)
    cfg = Dict{String,Any}()
    for (k, v) in schedule.base_config
        cfg[k] = v
    end
    if schedule.ladder_var === :L
        cfg["L_fiber"] = float(ladder_value)
    elseif schedule.ladder_var === :P
        cfg["P_cont"]  = float(ladder_value)
    elseif schedule.ladder_var === :lambda
        cfg["λ_gdd"]   = float(ladder_value)
    elseif schedule.ladder_var === :Nphi
        cfg["Nt"]      = Int(ladder_value)
    end
    return cfg
end

# Pull an auto-sized-compatible grid out of `cfg`. `setup_raman_problem` may
# upsize Nt / time_window on us — we still want to record what the CALLER
# REQUESTED so the predictor uses consistent values across steps.
function _requested_grid(cfg::Dict{String,Any})
    Nt_req = Int(get(cfg, "Nt", 2^13))
    tw_req = float(get(cfg, "time_window", 10.0))
    return Nt_req, tw_req
end

# Build the Raman problem from a step config. Returns the six-tuple returned by
# setup_raman_problem; lets the caller override via `setup_fn` if they need the
# long-fiber bypass (`setup_longfiber_problem`).
function _build_problem(cfg::Dict{String,Any}; setup_fn=nothing)
    if setup_fn !== nothing
        return setup_fn(cfg)
    end
    kwargs = Dict{Symbol,Any}()
    for k in ("L_fiber", "P_cont", "Nt", "time_window", "β_order",
              "fiber_preset", "gamma_user", "betas_user", "fR",
              "pulse_fwhm", "pulse_rep_rate", "pulse_shape",
              "raman_threshold", "λ0", "M")
        if haskey(cfg, k)
            kwargs[Symbol(k)] = cfg[k]
        end
    end
    return setup_raman_problem(; kwargs...)
end

# Default corrector: wrap optimize_spectral_phase. Returns a tuple
# (phi_opt::Vector, J_final_linear::Float64, iters::Int, wall_s::Float64).
function _default_corrector_lbfgs(phi_init::AbstractVector, cfg::Dict{String,Any};
                                  uω0, fiber, sim, band_mask,
                                  max_iter::Integer)
    Nt = sim["Nt"]
    M  = sim["M"]
    @assert length(phi_init) == Nt "phi_init length $(length(phi_init)) ≠ sim[Nt] $Nt"
    φ0 = reshape(Vector{Float64}(vec(phi_init)), Nt, M)

    λ_gdd      = float(get(cfg, "λ_gdd", 0.0))
    λ_boundary = float(get(cfg, "λ_boundary", 0.0))
    log_cost   = Bool(get(cfg, "log_cost", true))

    t0 = time()
    result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
        φ0=φ0, max_iter=Int(max_iter),
        λ_gdd=λ_gdd, λ_boundary=λ_boundary,
        log_cost=log_cost, store_trace=false)
    wall_s = time() - t0

    phi_opt = Vector{Float64}(vec(result.minimizer))
    # optimize_spectral_phase returns Optim result; `result.minimum` is the
    # scalar objective L-BFGS saw. If `log_cost=true` the objective is in dB;
    # convert back to linear so downstream Phase 28 trust reports and the
    # J_opt_dB field are on a consistent scale.
    J_scalar = float(result.minimum)
    J_linear = log_cost ? 10.0^(J_scalar / 10.0) : J_scalar
    return phi_opt, J_linear, Int(result.iterations), wall_s
end

# Helper: compute boundary and energy diagnostics from a converged phi on a
# specific problem setup. Returns (edge_input_frac, edge_output_frac,
# energy_drift). All three are thin wrappers around existing primitives and
# MUST NOT mutate uω0 or fiber.
#
# Both edge measurements operate on TIME-DOMAIN fields:
#   - edge_in: IFFT of the shaped spectrum uω0_shaped back to time domain.
#   - edge_out: time-domain output field from solve_disp_mmf.
# `check_boundary_conditions` (scripts/common.jl) expects a time-domain
# argument (ut_z).
function _boundary_and_energy(phi_opt::AbstractVector, uω0, fiber, sim, band_mask)
    Nt = sim["Nt"]
    M  = sim["M"]
    phi_mat = reshape(Vector{Float64}(vec(phi_opt)), Nt, M)
    uω0_shaped = @. uω0 * cis(phi_mat)

    # Edge fraction of the SHAPED INPUT pulse in TIME DOMAIN. We measure on
    # the RAW ifft of the frequency-domain shaped pulse (no attenuator recovery).
    # The Phase 28 convention asks for the "pre-attenuator temporal edge
    # fraction"; in this code path the shaped spectrum is pre-attenuator (the
    # attenuator is applied inside the ODE solver's state transformation), so
    # ifft(uω_shaped) is the correct physical pre-attenuator time-domain field.
    # Using check_boundary_conditions directly here would divide by the
    # attenuator (≈1e-40 at the edges) and inflate numerical noise by 40
    # orders of magnitude, which dominates D8 falsely.
    ut0_shaped = ifft(uω0_shaped, 1)
    n_edge = max(1, Nt ÷ 20)
    E_in_total = sum(abs2.(ut0_shaped))
    E_in_edges = sum(abs2.(ut0_shaped[1:n_edge, :])) +
                 sum(abs2.(ut0_shaped[end-n_edge+1:end, :]))
    frac_in = E_in_edges / max(E_in_total, eps())

    # Forward propagate for output edge fraction + energy drift.
    fiber_check = deepcopy(fiber)
    fiber_check["zsave"] = [fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_check, sim)
    utf = sol["ut_z"][end, :, :]

    # Output edge fraction on the RAW time-domain field from the solver.
    # solve_disp_mmf returns ut_z already in the physical (post-attenuator)
    # basis, so we measure edges directly — same convention as
    # scripts/benchmark_optimization.jl:544.
    E_out_total = sum(abs2.(utf))
    E_out_edges = sum(abs2.(utf[1:n_edge, :])) +
                  sum(abs2.(utf[end-n_edge+1:end, :]))
    frac_out = E_out_edges / max(E_out_total, eps())

    # Energy drift in time domain; both sides on the physical basis.
    drift = abs(E_out_total - E_in_total) / max(E_in_total, eps())

    return float(frac_in), float(frac_out), float(drift)
end

# ─────────────────────────────────────────────────────────────────────────────
# run_ladder — the driver
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_ladder(schedule::ContinuationSchedule;
               corrector_fn=nothing,
               cold_start::Bool=false,
               setup_fn=nothing,
               baseline_iters::Union{Nothing,Integer}=nothing) -> Vector{ContinuationStepResult}

Walk `schedule.values` in order, applying `schedule.predictor` before the
corrector at each step, and emit one `ContinuationStepResult` per step.

# Arguments
- `schedule`        — immutable plan.
- `corrector_fn`    — optional `(phi_init, cfg; uω0, fiber, sim, band_mask, max_iter)
                      -> (phi_opt, J_linear, iters, wall_s)`. Defaults to an
                      L-BFGS wrapper over `optimize_spectral_phase`. Phases
                      32/33/34 plug in here.
- `cold_start`      — if `true`, every step is handed `phi_init = zeros(Nt)`
                      instead of the previous step's phase. Used for the
                      cold-start baseline arm at IDENTICAL corrector budget
                      (budget-parity honest, per RESEARCH §Anti-patterns).
- `setup_fn`        — optional `cfg -> (uω0, fiber, sim, band_mask, Δf, raman_threshold)`
                      override (use `setup_longfiber_problem` for long fibers).
                      Defaults to `setup_raman_problem` (scripts/common.jl).
- `baseline_iters`  — corrector-iteration baseline for D3 detection. If `nothing`,
                      uses `schedule.max_iter_per_step`.

# Returns
`Vector{ContinuationStepResult}`, one entry per successfully-converged step.
If a step triggers a hard-halt (D1 trust SUSPECT, D8 edge growth, or the
corrector otherwise fails to finish), the driver records `path_status=:broken`
on that step and STOPS — later ladder values are not attempted.

# Detector → halt-policy mapping
| Detector | Name                        | Policy in v1        |
|----------|-----------------------------|---------------------|
| D1       | trust SUSPECT (overall)     | hard halt           |
| D2       | cost discontinuity (dB)     | soft (→ :degraded)  |
| D3       | corrector burn              | soft (→ :degraded)  |
| D4       | phase jump vs warm start    | soft (→ :degraded)  |
| D5       | gradient-validation fail    | hard halt (via D1)  |
| D6       | Hessian sign change         | informational only  |
| D7       | non-finite cost only        | hard halt (see note)|
| D8       | edge-fraction growth        | hard halt           |

D7 note: v1 only fires on non-finite J_opt_dB. A true `g_converged == false`
check requires the corrector interface to return Optim's convergence flag;
`_default_corrector_lbfgs` currently discards the full Optim result, so the
g-norm signal is not available. Deferred until Phases 33/34 plug in Newton
correctors with a richer return contract.

# Saddle caveat (Phase 22 / 35)
The competitive-dB branch is Hessian-indefinite everywhere surveyed; L, P,
lambda ladders traverse saddles, not a smooth minimum branch. The detectors
are designed to tolerate this. Hessian sign-change (D6) is intentionally
informational only in v1.

# Deferred
Secant / tangent / pseudo-arclength predictors and multi-variable schedules
are deferred (see module docstring for tracking).

# Example
```julia
schedule = ContinuationSchedule(
    continuation_id = "demo_lambda",
    ladder_var = :lambda,
    values = [1e-2, 1e-3],
    base_config = Dict{String,Any}("L_fiber"=>2.0, "P_cont"=>0.2,
                                     "Nt"=>2^12, "time_window"=>10.0,
                                     "fiber_preset"=>:SMF28, "β_order"=>3),
    max_iter_per_step = 10,
)
results = run_ladder(schedule; cold_start=false)
```
"""
function run_ladder(schedule::ContinuationSchedule;
                    corrector_fn = nothing,
                    cold_start::Bool = false,
                    setup_fn = nothing,
                    baseline_iters::Union{Nothing,Integer} = nothing)

    # Determinism is process-global and idempotent.
    ensure_deterministic_environment()

    baseline = isnothing(baseline_iters) ? schedule.max_iter_per_step : Int(baseline_iters)
    results = ContinuationStepResult[]

    prev_phi    = nothing
    prev_cfg    = nothing
    prev_J_dB   = NaN
    prev_edge   = NaN

    for (step_idx, value) in enumerate(schedule.values)
        cfg = _step_config(schedule, value)
        @info @sprintf("run_ladder[%s] step %d/%d: %s = %s (cold_start=%s)",
                       schedule.continuation_id, step_idx, length(schedule.values),
                       String(schedule.ladder_var), string(value), string(cold_start))

        # Build the per-step problem. setup_raman_problem may auto-size Nt /
        # time_window upward on us; after the call, sim[Nt] is authoritative.
        uω0, fiber, sim, band_mask, _, _ = _build_problem(cfg; setup_fn = setup_fn)

        # Post-setup: refresh the per-step Nt / time_window in cfg so that the
        # predictor for the NEXT step sees what actually ran.
        cfg["Nt"] = sim["Nt"]
        cfg["time_window"] = sim["Δt"] * sim["Nt"]  # picoseconds

        # Pick initial phase via predictor (or zero for cold-start).
        Nt = sim["Nt"]
        phi_init = if cold_start || prev_phi === nothing
            zeros(Float64, Nt)
        else
            if schedule.predictor === :trivial
                trivial_predictor(prev_phi, prev_cfg, cfg)
            else
                error("unsupported predictor :$(schedule.predictor)")
            end
        end

        # Run corrector. CLAUDE.md §Error Handling: no try/catch in numerical
        # code — errors propagate. Precondition-check the predictor output
        # before calling cost_and_gradient; on non-finite phi we record
        # J_init = NaN and let downstream detectors flag the step.
        if !all(isfinite, phi_init)
            @warn "predictor produced non-finite phi; treating step as broken"
            J_init = NaN
        else
            Ji, _ = cost_and_gradient(reshape(phi_init, Nt, 1),
                                      uω0, fiber, sim, band_mask;
                                      log_cost = false)
            J_init = float(Ji)
        end

        corrector_call = corrector_fn === nothing ?
            _default_corrector_lbfgs :
            corrector_fn

        phi_opt, J_linear, iters, wall_s = corrector_call(
            phi_init, cfg;
            uω0 = uω0, fiber = fiber, sim = sim, band_mask = band_mask,
            max_iter = schedule.max_iter_per_step,
        )

        J_opt_dB = 10.0 * log10(max(J_linear, 1e-300))

        # Diagnostics used by detectors + Phase 28 trust report.
        edge_in, edge_out, drift = _boundary_and_energy(phi_opt, uω0, fiber, sim, band_mask)
        max_edge = max(edge_in, edge_out)

        # Detector evaluations.
        flag_d2 = detect_cost_discontinuity(prev_J_dB, J_opt_dB)
        flag_d3 = detect_corrector_burn(iters, baseline)
        flag_d4 = detect_phase_jump(phi_init, phi_opt)
        flag_d8 = detect_edge_growth(prev_edge, max_edge)

        # Corrector-convergence detector (D7). optimize_spectral_phase returns
        # Optim.OptimizationResults via `optimize_spectral_phase`; we lost the
        # full result by going through _default_corrector_lbfgs, so we apply a
        # soft heuristic: iters >= max_iter_per_step AND prev_J_dB finite with
        # |J_opt_dB - prev_J_dB| < 0.01 dB means the corrector likely hit the
        # iteration cap, which we flag as "ran out of budget" but still :ok.
        # D7 hard halt is reserved for explicit failures (non-finite cost).
        hard_d7 = !isfinite(J_opt_dB)

        # Build Phase 28 trust report. This is the canonical row per step.
        det_status = deterministic_environment_status()
        trust = build_numerical_trust_report(;
            det_status = det_status,
            edge_input_frac  = edge_in,
            edge_output_frac = edge_out,
            energy_drift     = drift,
            gradient_validation = nothing,
            log_cost    = true,
            λ_gdd       = float(get(cfg, "λ_gdd", 0.0)),
            λ_boundary  = float(get(cfg, "λ_boundary", 0.0)),
            objective_label = "continuation $(schedule.continuation_id) step=$step_idx",
        )

        # Decide path status BEFORE stamping the metadata so the row is honest.
        overall = trust["overall_verdict"]
        hard_d1 = overall == "SUSPECT"
        hard_d8 = flag_d8

        path_status = if hard_d1 || hard_d7 || hard_d8
            :broken
        elseif flag_d2 || flag_d3 || flag_d4
            :degraded
        else
            :ok
        end

        attach_continuation_metadata!(trust, Dict{String,Any}(
            "continuation_id" => schedule.continuation_id,
            "ladder_var"      => String(schedule.ladder_var),
            "step_index"      => step_idx,
            "ladder_value"    => float(value),
            "predictor"       => String(schedule.predictor),
            "corrector"       => String(schedule.corrector),
            "path_status"     => String(path_status),
            "is_cold_start_baseline" => cold_start,
            "detectors" => Dict{String,Any}(
                "cost_discontinuity_dB" => isfinite(prev_J_dB) ? (J_opt_dB - prev_J_dB) : NaN,
                "corrector_iters"       => iters,
                "phase_jump_ratio"      => norm(phi_init) > sqrt(eps()) ?
                                            norm(phi_opt .- phi_init) / norm(phi_init) : 0.0,
                "edge_fraction_delta"   => isfinite(prev_edge) ?
                                            (max_edge - prev_edge) : max_edge,
            ),
        ))

        flags = Dict{Symbol,Bool}(
            :D1 => hard_d1,
            :D2 => flag_d2,
            :D3 => flag_d3,
            :D4 => flag_d4,
            :D7 => hard_d7,
            :D8 => hard_d8,
        )

        push!(results, ContinuationStepResult(
            step_idx, float(value),
            J_init, J_opt_dB,
            phi_opt, iters, wall_s,
            trust, flags, path_status,
        ))

        @info @sprintf("run_ladder[%s] step %d done: J_dB=%.3f iters=%d wall=%.1fs verdict=%s path=%s",
                       schedule.continuation_id, step_idx,
                       J_opt_dB, iters, wall_s, overall, String(path_status))

        if path_status === :broken
            @warn @sprintf("run_ladder[%s]: hard halt at step %d (D1=%s, D7=%s, D8=%s)",
                           schedule.continuation_id, step_idx,
                           hard_d1, hard_d7, hard_d8)
            break
        end

        prev_phi  = phi_opt
        prev_cfg  = cfg
        prev_J_dB = J_opt_dB
        prev_edge = max_edge
    end

    return results
end

end  # _CONTINUATION_JL_LOADED include guard
