"""
Multimode cost-function variants for Session C.

Three variants on the Raman-band spectral cost:
- `mmf_cost_sum`         — J = Σ_m E_band_m / Σ_m E_total_m    (baseline, = integrating detector)
- `mmf_cost_fundamental` — J = E_band_1  / E_total_1           (fundamental-only)
- `mmf_cost_worst_mode`  — bounded smooth proxy for max_m (E_band_m / E_total_m)

Each function returns `(J, dJ)` with
- `J::Float64`                                 scalar cost
- `dJ::Matrix{ComplexF64}`  shape (Nt, M)      adjoint terminal condition ∂J/∂conj(uωf)

The sign/normalization matches `scripts/lib/common.jl::spectral_band_cost` so that
the existing adjoint solver `solve_adjoint_disp_mmf(λωL, ũω, fiber, sim)`
accepts `λωL = dJ` directly.

Include guard: safe to include multiple times.
"""

if !(@isdefined _MMF_COST_JL_LOADED)
const _MMF_COST_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# Baseline: sum-over-modes
# ─────────────────────────────────────────────────────────────────────────────

"""
    mmf_cost_sum(uωf, band_mask) -> (J, dJ)

Sum-over-modes Raman-band fraction:
    J = Σ_m E_band_m / Σ_m E_total_m,   E_x_m = Σ_ω |uωf[ω,m]|² 1_{band or total}.

This is the spectrum seen by a broadband integrating detector placed at the
fiber output: all modes add up incoherently in power.

Mathematically equivalent to `scripts/lib/common.jl::spectral_band_cost` — kept
here with an MMF-specific name so the optimizer code reads cleanly and the
three variants live in one file.

Preconditions:
- `size(uωf, 1) == length(band_mask)`
- `any(band_mask)`
- `sum(abs2, uωf) > 0`

Postconditions:
- `0 ≤ J ≤ 1`
- `all(isfinite, dJ)`
"""
function mmf_cost_sum(uωf, band_mask)
    @assert size(uωf, 1) == length(band_mask)
    @assert any(band_mask)
    @assert sum(abs2, uωf) > 0

    E_band  = sum(abs2.(uωf[band_mask, :]))
    E_total = sum(abs2.(uωf))
    J  = E_band / E_total
    dJ = uωf .* (band_mask .- J) ./ E_total

    @assert 0 ≤ J ≤ 1 "J=$J out of [0,1]"
    @assert all(isfinite, dJ)
    return J, dJ
end

# ─────────────────────────────────────────────────────────────────────────────
# Fundamental-only
# ─────────────────────────────────────────────────────────────────────────────

"""
    mmf_cost_fundamental(uωf, band_mask) -> (J, dJ)

Raman-band fraction measured ON THE FUNDAMENTAL MODE ONLY:
    J = Σ_ω∈band |uωf[ω,1]|² / Σ_ω |uωf[ω,1]|².

Physically, this is what a mode-selective detector (e.g. a fiber-coupled
single-mode output after a mode stripper) would measure. It is generically
HIGHER than `mmf_cost_sum` in GRIN fibers because Kerr self-cleaning and
Raman preferentially populate the fundamental with Raman-shifted energy.

Gradient is nonzero only on the mode-1 column.
"""
function mmf_cost_fundamental(uωf, band_mask)
    @assert size(uωf, 1) == length(band_mask)
    @assert any(band_mask)

    M = size(uωf, 2)
    u1 = @view uωf[:, 1]
    E_band_1  = sum(abs2.(u1[band_mask]))
    E_total_1 = sum(abs2.(u1))
    @assert E_total_1 > 0 "fundamental mode has zero energy"

    J = E_band_1 / E_total_1
    dJ = zeros(ComplexF64, size(uωf))
    @. @views dJ[:, 1] = u1 * (band_mask - J) / E_total_1

    @assert 0 ≤ J ≤ 1 "J=$J out of [0,1]"
    @assert all(isfinite, dJ)
    return J, dJ
end

# ─────────────────────────────────────────────────────────────────────────────
# Worst-mode (smooth-max via log-sum-exp)
# ─────────────────────────────────────────────────────────────────────────────

"""
    mmf_cost_worst_mode(uωf, band_mask; τ=50.0) -> (J, dJ)

Bounded smooth approximation to `max_m (E_band_m / E_total_m)` over
nonzero-energy modes via normalized log-sum-exp:

    J_τ = (1/τ) · log(mean_m exp(τ · r_m)),    r_m = E_band_m / E_total_m

For `K` active modes, `max(r) - log(K)/τ ≤ J_τ ≤ max(r)`, so the
proxy remains in `[0, 1]`. The default τ=50 has a worst-case gap below
`log(K)/50`. Reporting uses the true maximum; this proxy exists only to give
the optimizer a smooth gradient.

Rationale: a true `max_m` has a gradient only on the argmax mode, which breaks
L-BFGS quasi-Newton updates when the argmax switches. LSE is smooth everywhere.

Gradient:
    ∂J/∂conj(uωf[ω,m]) = w_m · uωf[ω,m] · (1_{band}(ω) - r_m) / E_total_m
where w_m = softmax_τ(r)_m = exp(τ·r_m) / Σ_k exp(τ·r_k).
"""
function mmf_cost_worst_mode(uωf, band_mask; τ::Real = 50.0)
    @assert size(uωf, 1) == length(band_mask)
    @assert any(band_mask)
    @assert isfinite(τ) && τ > 0

    M = size(uωf, 2)
    r       = zeros(Float64, M)
    E_total = zeros(Float64, M)
    for m in 1:M
        u_m        = @view uωf[:, m]
        Et         = sum(abs2, u_m)
        E_total[m] = Et
        if Et > 0
            r[m] = sum(abs2.(u_m[band_mask])) / Et
        else
            r[m] = 0.0
        end
    end

    active = findall(>(0), E_total)
    isempty(active) && throw(ArgumentError("worst-mode cost requires a nonzero-energy mode"))

    # Normalization by K keeps the smooth proxy on the same [0,1] fraction
    # scale as the true worst-mode leakage.
    r_max   = maximum(@view r[active])
    shifted = τ .* (@view(r[active]) .- r_max)
    denom   = sum(exp.(shifted))
    J       = r_max + (log(denom) - log(length(active))) / τ

    # Softmax weights (gradient chain rule)
    w = exp.(shifted) ./ denom

    dJ = zeros(ComplexF64, size(uωf))
    for (active_index, m) in enumerate(active)
        u_m = @view uωf[:, m]
        @. @views dJ[:, m] = w[active_index] * u_m * (band_mask - r[m]) / E_total[m]
    end

    @assert isfinite(J) "J non-finite: $J"
    @assert 0 ≤ J ≤ 1 "smooth worst-mode proxy J=$J out of [0,1]"
    @assert all(isfinite, dJ)
    return J, dJ
end

# ─────────────────────────────────────────────────────────────────────────────
# Reporting helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    mmf_mode_band_fractions(uωf, band_mask) -> Vector{Float64}

Per-mode Raman-band fractions:
    r_m = E_band_m / E_total_m.

Modes with zero total energy are reported as `NaN`, because they have no
defined leakage fraction.
"""
function mmf_mode_band_fractions(uωf, band_mask)
    @assert size(uωf, 1) == length(band_mask)
    M = size(uωf, 2)
    r = fill(NaN, M)
    for m in 1:M
        u_m = @view uωf[:, m]
        E_total = sum(abs2, u_m)
        if E_total > 0
            r[m] = sum(abs2.(u_m[band_mask])) / E_total
        end
    end
    return r
end

"""
    mmf_cost_report(uωf, band_mask; τ=50.0) -> NamedTuple

Evaluate all multimode Raman cost views on the same output field:
- `:sum` — integrating-detector baseline
- `:fundamental` — LP01-only
- `:worst_mode` — true maximum leakage across nonzero-energy modes

The separately labelled smooth proxy is the value differentiated during
optimization. Its distance below the true maximum is bounded by
`log(active_mode_count) / τ`.
"""
function mmf_cost_report(uωf, band_mask; τ::Real = 50.0)
    per_mode_lin = mmf_mode_band_fractions(uωf, band_mask)
    J_sum, _ = mmf_cost_sum(uωf, band_mask)
    J_worst_proxy, _ = mmf_cost_worst_mode(uωf, band_mask; τ = τ)
    mode_totals = [sum(abs2, @view uωf[:, mode]) for mode in axes(uωf, 2)]
    active_modes = findall(>(0), mode_totals)
    active_mode_count = length(active_modes)
    active_mode_count > 0 || throw(ArgumentError(
        "MMF cost report requires a nonzero-energy mode"))
    true_worst = maximum(@view per_mode_lin[active_modes])
    fundamental = 1 in active_modes ? per_mode_lin[1] : NaN

    to_dB(x) = 10.0 * log10(max(x, 1e-15))
    return (
        sum_lin = J_sum,
        sum_dB = to_dB(J_sum),
        fundamental_lin = fundamental,
        fundamental_dB = isfinite(fundamental) ? to_dB(fundamental) : NaN,
        worst_mode_lin = true_worst,
        worst_mode_dB = to_dB(true_worst),
        worst_mode_smooth_proxy_lin = J_worst_proxy,
        worst_mode_smooth_proxy_dB = to_dB(J_worst_proxy),
        worst_mode_smooth_proxy_error_bound = log(active_mode_count) / Float64(τ),
        active_mode_count = active_mode_count,
        per_mode_lin = per_mode_lin,
        per_mode_dB = [isfinite(value) ? to_dB(value) : NaN for value in per_mode_lin],
        τ = Float64(τ),
    )
end

end # include guard
