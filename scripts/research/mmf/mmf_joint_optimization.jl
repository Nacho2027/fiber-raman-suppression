"""
Joint (spectral phase, input mode coefficients) optimization for multimode Raman
suppression — Phase 17 Plan 01 candidate, activated by the seed
`.planning/seeds/mmf-joint-phase-mode-optimization.md`.

Optimizes BOTH φ ∈ ℝ^Nt (shared-across-modes spectral phase) AND c_m ∈ ℂ^M
(input mode weights) simultaneously, subject to ‖c‖₂ = 1 (unit energy launch)
and c_1 ∈ ℝ₊ (global-phase gauge fix).

Parametrization (keeps L-BFGS happy):
    c_1 = sqrt(max(0, 1 - Σ_{m>1} |c_m|²))   — dependent, enforces unit norm
    c_m = r_m · exp(iα_m) for m=2..M          — independent real params (r_m, α_m)

Total free params: Nt + 2·(M-1) (e.g. Nt + 10 for M=6).

Gradient chain:
    uω0_shaped[ω, m] = pulse(ω) · c_m · exp(iφ(ω))
  ⇒ ∂J/∂φ(ω)   = 2·Re(conj(λ₀(ω, m)) · i · uω0_shaped(ω, m)) summed over m  (already in `cost_and_gradient_mmf`)
  ⇒ mode-coordinate block {r_m, α_m} is deliberately computed by central
     finite differences over the small 2(M-1)-parameter block.

Protected files: none modified; wraps `cost_and_gradient_mmf` from
scripts/mmf_raman_optimization.jl.

Run:  julia -t auto scripts/mmf_joint_optimization.jl
"""

ENV["MPLBACKEND"] = "Agg"

using LinearAlgebra
using FFTW
using Printf
using Logging
using Random
using JLD2

using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "mmf_setup.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "src", "mmf_cost.jl"))
include(joinpath(@__DIR__, "mmf_raman_optimization.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Parameter vector ↔ (φ, c_m) conversion
# ─────────────────────────────────────────────────────────────────────────────

"""
    _unpack_joint(x, Nt, M) -> (φ, c_m)

x layout: [ φ::Nt , r_2, α_2, r_3, α_3, ..., r_M, α_M ]
c_1 = sqrt(max(0, 1 - Σ_{m>1} r_m²)) · 1 + 0·i   (positive real, gauge-fixed)
c_m = r_m · cis(α_m)  for m=2..M
"""
function _unpack_joint(x::AbstractVector{<:Real}, Nt::Int, M::Int)
    @assert length(x) == Nt + 2 * (M - 1)
    φ = @view x[1:Nt]
    c_m = Vector{ComplexF64}(undef, M)
    sumsq = 0.0
    for m in 2:M
        r  = x[Nt + 2 * (m - 2) + 1]
        α  = x[Nt + 2 * (m - 2) + 2]
        c_m[m] = ComplexF64(r * cos(α), r * sin(α))
        sumsq += r^2
    end
    c_m[1] = ComplexF64(sqrt(max(0.0, 1 - sumsq)), 0.0)
    return φ, c_m
end

"""
    _pack_joint!(x, φ, c_m)

Inverse: fills x from (φ, c_m). Uses (r, α) = (|c_m|, angle(c_m)).
"""
function _pack_joint!(x::AbstractVector{<:Real}, φ::AbstractVector{<:Real},
                     c_m::AbstractVector{<:Complex})
    Nt = length(φ)
    M  = length(c_m)
    @assert length(x) == Nt + 2 * (M - 1)
    x[1:Nt] .= φ
    for m in 2:M
        r = abs(c_m[m])
        α = angle(c_m[m])
        x[Nt + 2 * (m - 2) + 1] = r
        x[Nt + 2 * (m - 2) + 2] = α
    end
    return x
end

# ─────────────────────────────────────────────────────────────────────────────
# Joint cost + gradient
# ─────────────────────────────────────────────────────────────────────────────

function _joint_forward_cost(
    x::AbstractVector{<:Real},
    uω0_pulse::AbstractMatrix,
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool};
    variant::Symbol = :sum,
    log_cost::Bool = true,
)
    Nt = size(uω0_pulse, 1)
    M  = size(uω0_pulse, 2)
    φ, c_m = _unpack_joint(x, Nt, M)
    phase_factor = cis.(φ)
    uω0_base = uω0_pulse .* reshape(c_m, 1, M)
    uω0_shaped = uω0_base .* phase_factor

    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω = sol["ode_sol"]
    L = fiber["L"]
    uωf = cis.(fiber["Dω"] .* L) .* ũω(L)

    J, _ = if variant === :sum
        mmf_cost_sum(uωf, band_mask)
    elseif variant === :fundamental
        mmf_cost_fundamental(uωf, band_mask)
    elseif variant === :worst_mode
        mmf_cost_worst_mode(uωf, band_mask)
    else
        throw(ArgumentError("unknown variant :$variant"))
    end
    return log_cost ? 10.0 * log10(max(J, 1e-15)) : J
end

"""
    cost_and_gradient_joint(x, uω0_pulse, fiber, sim, band_mask; kwargs...)

Joint cost/gradient in terms of the packed parameter vector `x`. Here
`uω0_pulse` is the pulse factor WITHOUT the mode weights — shape (Nt, 1) or
(Nt,). Internally `uω0_base = uω0_pulse .* c_m'` is reconstructed per call.

The existing `cost_and_gradient_mmf` returns φ-gradient directly but NOT the
c_m gradient. The mode-coordinate block is intentionally central-FD rather
than analytic because it is small and the previous hand-derived complex chain
failed the dedicated preflight check.

Keyword arguments:
- `variant::Symbol = :sum`
- `log_cost::Bool = true`
- `λ_gdd::Real = 0.0`
- `λ_boundary::Real = 0.0`
"""
function cost_and_gradient_joint(
    x::AbstractVector{<:Real},
    uω0_pulse::AbstractMatrix,
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool};
    variant::Symbol = :sum,
    log_cost::Bool = true,
    λ_gdd::Real = 0.0,
    λ_boundary::Real = 0.0,
    mode_fd_eps::Real = 1e-5,
)
    Nt = size(uω0_pulse, 1)
    M  = size(uω0_pulse, 2)
    @assert M ≥ 1
    @assert length(x) == Nt + 2 * (M - 1)
    @assert λ_gdd == 0.0 "joint MMF mode-coordinate FD currently supports λ_gdd=0 only"
    @assert λ_boundary == 0.0 "joint MMF mode-coordinate FD currently supports λ_boundary=0 only"

    φ, c_m = _unpack_joint(x, Nt, M)
    # Build shaped input (broadcast c_m across columns)
    phase_factor = cis.(φ)                              # (Nt,)
    uω0_base     = uω0_pulse .* reshape(c_m, 1, M)      # (Nt, M)
    uω0_shaped   = uω0_base .* phase_factor             # (Nt, M)

    # Forward
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω  = sol["ode_sol"]
    L   = fiber["L"]
    Dω  = fiber["Dω"]
    ũω_L  = ũω(L)
    uωf   = cis.(Dω .* L) .* ũω_L

    # Cost + adjoint terminal
    J, λωL = if variant === :sum
        mmf_cost_sum(uωf, band_mask)
    elseif variant === :fundamental
        mmf_cost_fundamental(uωf, band_mask)
    elseif variant === :worst_mode
        mmf_cost_worst_mode(uωf, band_mask)
    else
        throw(ArgumentError("unknown variant :$variant"))
    end

    sol_adj = MultiModeNoise.solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)
    λ0      = sol_adj(0)                                # (Nt, M)

    # φ gradient (shared across modes → sum over m)
    ∂J_∂φ_expanded = 2.0 .* real.(conj.(λ0) .* (1im .* uω0_shaped))  # (Nt, M)
    ∂J_∂φ          = vec(sum(∂J_∂φ_expanded, dims = 2))              # (Nt,)

    # Mode-coefficient gradients: use central finite differences for the small
    # packed mode block. The custom complex adjoint chain for {r_m, α_m} is easy
    # to get wrong; this block has only 2(M-1) parameters, so FD is a defensible
    # preflight-safe default for advisor-facing mode-launch studies.
    grad_r_alpha = zeros(Float64, 2 * (M - 1))
    for (j, idx) in enumerate((Nt + 1):(Nt + 2 * (M - 1)))
        xp = copy(x)
        xm = copy(x)
        xp[idx] += mode_fd_eps
        xm[idx] -= mode_fd_eps
        Jp = _joint_forward_cost(
            xp, uω0_pulse, fiber, sim, band_mask;
            variant = variant,
            log_cost = log_cost,
        )
        Jm = _joint_forward_cost(
            xm, uω0_pulse, fiber, sim, band_mask;
            variant = variant,
            log_cost = log_cost,
        )
        grad_r_alpha[j] = (Jp - Jm) / (2mode_fd_eps)
    end

    # Combine into packed gradient
    grad_x = vcat(∂J_∂φ, grad_r_alpha)

    # Log-scaling for the adjoint phase block. The mode-coefficient block was
    # already finite-differenced on the returned scalar surface above.
    if log_cost
        J_clamped   = max(J, 1e-15)
        J_phys      = 10.0 * log10(J_clamped)
        scale       = 10.0 / (J_clamped * log(10.0))
        grad_x[1:Nt] .*= scale
        # (GDD/boundary penalties left for future expansion; baseline doesn't use here)
    else
        J_phys = J
    end

    @assert isfinite(J_phys)
    @assert all(isfinite, grad_x)
    return J_phys, grad_x
end

# ─────────────────────────────────────────────────────────────────────────────
# Joint optimizer
# ─────────────────────────────────────────────────────────────────────────────

"""
    optimize_mmf_joint(uω0_pulse, fiber, sim, band_mask; kwargs...) -> NamedTuple

L-BFGS on the joint (φ, c_m) vector. Warm-start with a φ_init and c_m_init.
"""
function optimize_mmf_joint(
    uω0_pulse::AbstractMatrix,
    fiber::Dict,
    sim::Dict,
    band_mask::AbstractVector{Bool};
    φ_init::Union{Nothing, AbstractVector{<:Real}} = nothing,
    c_m_init::Union{Nothing, AbstractVector{<:Complex}} = nothing,
    max_iter::Int = 30,
    variant::Symbol = :sum,
    log_cost::Bool = true,
    verbose::Bool = true,
)
    Nt = size(uω0_pulse, 1)
    M  = size(uω0_pulse, 2)
    n_params = Nt + 2 * (M - 1)

    φ0 = isnothing(φ_init)  ? zeros(Nt) : copy(φ_init)
    c0 = isnothing(c_m_init) ? default_mode_weights(M) : ComplexF64.(c_m_init)
    c0 = c0 ./ norm(c0)

    x0 = zeros(Float64, n_params)
    _pack_joint!(x0, φ0, c0)

    J_history = Float64[]

    function fg!(F, G, x)
        J, g = cost_and_gradient_joint(
            x, uω0_pulse, fiber, sim, band_mask;
            variant = variant, log_cost = log_cost,
        )
        if G !== nothing
            G .= g
        end
        push!(J_history, J)
        if verbose
            @info @sprintf("  joint iter %3d: J = %.4e", length(J_history), J)
        end
        return J
    end

    result = Optim.optimize(
        Optim.only_fg!(fg!),
        x0,
        Optim.LBFGS(),
        Optim.Options(iterations = max_iter, allow_f_increases = true, show_trace = false),
    )
    x_opt = Optim.minimizer(result)
    φ_opt, c_opt = _unpack_joint(x_opt, Nt, M)
    φ_opt = collect(φ_opt)

    return (
        φ_opt     = φ_opt,
        c_opt     = c_opt,
        x_opt     = x_opt,
        J_final   = Optim.minimum(result),
        J_history = J_history,
        result    = result,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Entry point — Phase 17 Plan 01 baseline
# ─────────────────────────────────────────────────────────────────────────────

function run_joint_baseline(;
    preset::Symbol = :GRIN_50,
    L_fiber::Real = 1.0,
    P_cont::Real = 0.05,
    Nt::Int = 2^13,
    time_window::Real = 10.0,
    max_iter::Int = 30,
    warm_start_phase_only::Bool = true,
    save_dir::String = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase17"),
    seed::Int = 42,
)
    mkpath(save_dir)
    setup = setup_mmf_raman_problem(;
        preset = preset, L_fiber = L_fiber, P_cont = P_cont,
        Nt = Nt, time_window = time_window,
    )
    M = size(setup.uω0, 2)

    # The setup's uω0 has c_m already baked in. For the joint optimizer we need
    # the PULSE alone (before c_m weighting) — reconstruct by dividing out c_m
    # from column 1 and re-broadcasting 1 × M.
    c_init = setup.mode_weights
    @assert abs(c_init[1]) > 1e-6 "LP01 amplitude too small to recover pulse"
    pulse_1d = setup.uω0[:, 1] ./ c_init[1]       # pulse at column 1 = pulse × c[1]
    uω0_pulse = repeat(pulse_1d, 1, M)            # (Nt, M) with identical pulse per column

    # Warm-start: run phase-only first so L-BFGS has a good starting point
    φ_init = zeros(Float64, Nt)
    if warm_start_phase_only
        @info "Warm-starting with 20 phase-only iterations..."
        warm = optimize_mmf_phase(
            setup.uω0, c_init, setup.fiber, setup.sim, setup.band_mask;
            max_iter = 20, log_cost = true, seed = seed, verbose = false,
        )
        φ_init = warm.φ_opt
        @info @sprintf("Warm-start done: J = %.4e", warm.J_final)
    end

    @info "Joint optimization: (φ ∈ ℝ^$Nt, c ∈ ℂ^$M with unit-norm gauge)"
    t0 = time()
    joint = optimize_mmf_joint(
        uω0_pulse, setup.fiber, setup.sim, setup.band_mask;
        φ_init = φ_init, c_m_init = c_init,
        max_iter = max_iter, log_cost = true,
    )
    wall = time() - t0

    # Linear-scale J at φ_opt, c_opt
    x_final = zeros(Float64, Nt + 2 * (M - 1))
    _pack_joint!(x_final, joint.φ_opt, joint.c_opt)
    J_lin, _ = cost_and_gradient_joint(
        x_final, uω0_pulse, setup.fiber, setup.sim, setup.band_mask;
        variant = :sum, log_cost = false,
    )
    J_lin_dB = 10 * log10(max(J_lin, 1e-15))

    @info @sprintf("Joint done: J_lin = %.3e (%.2f dB), wall = %.1f s", J_lin, J_lin_dB, wall)

    fname = joinpath(save_dir, @sprintf("joint_baseline_%s_L%g_P%g_seed%d.jld2",
        String(preset), L_fiber, P_cont, seed))
    jldopen(fname, "w") do f
        f["preset"]    = String(preset)
        f["L_fiber"]   = L_fiber
        f["P_cont"]    = P_cont
        f["seed"]      = seed
        f["phi_opt"]   = joint.φ_opt
        f["c_opt"]     = joint.c_opt
        f["J_lin"]     = J_lin
        f["J_lin_dB"]  = J_lin_dB
        f["J_history"] = joint.J_history
        f["wall"]      = wall
    end
    @info "Saved $fname"

    # ── MANDATORY standard image set (CLAUDE.md rule, 2026-04-17) ─────────
    # Reconstruct the shaped-field uω0_base with the OPTIMIZED c_m so the
    # "unshaped" comparison plot reflects the realizable experimental launch.
    uω0_base_opt = uω0_pulse .* reshape(joint.c_opt, 1, M)
    save_standard_set(
        joint.φ_opt, uω0_base_opt, setup.fiber, setup.sim,
        setup.band_mask, setup.Δf, setup.raman_threshold;
        tag         = lowercase(replace(@sprintf("joint_%s_l%gm_p%gw_seed%d",
                                                 String(preset), L_fiber, P_cont, seed),
                                        "." => "p")),
        fiber_name  = String(preset),
        L_m         = L_fiber,
        P_W         = P_cont,
        output_dir  = save_dir,
    )

    return (; setup, joint, J_lin_dB, wall, fname)
end

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Phase 17 (seed) — joint (φ, c_m) optimization on GRIN-50, L=1m, P=0.05W"
    @info "Threads: $(Threads.nthreads())"
    run_joint_baseline()
end
