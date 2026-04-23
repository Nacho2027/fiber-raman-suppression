"""
Multimode cost-function variants for Session C.

Three variants on the Raman-band spectral cost:
- `mmf_cost_sum`         — J = Σ_m E_band_m / Σ_m E_total_m    (baseline, = integrating detector)
- `mmf_cost_fundamental` — J = E_band_1  / E_total_1           (fundamental-only)
- `mmf_cost_worst_mode`  — J = max_m (E_band_m / E_total_m)    (robustness; smoothed via log-sum-exp)

Each function returns `(J, dJ)` with
- `J::Float64`                                 scalar cost
- `dJ::Matrix{ComplexF64}`  shape (Nt, M)      adjoint terminal condition ∂J/∂conj(uωf)

The sign/normalization matches `scripts/common.jl::spectral_band_cost` so that
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

Mathematically equivalent to `scripts/common.jl::spectral_band_cost` — kept
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

Smooth approximation to `max_m (E_band_m / E_total_m)` via log-sum-exp:

    J_τ = (1/τ) · log(Σ_m exp(τ · r_m)),    r_m = E_band_m / E_total_m

As τ → ∞, J_τ → max_m r_m.  The default τ=50 gives approximation error
|J_τ - max_m r_m| < log(M)/τ ≈ 0.04 at M=6, which is tighter than optimization
stopping tolerances (1e-3).

Rationale: a true `max_m` has a gradient only on the argmax mode, which breaks
L-BFGS quasi-Newton updates when the argmax switches. LSE is smooth everywhere.

Gradient:
    ∂J/∂conj(uωf[ω,m]) = w_m · uωf[ω,m] · (1_{band}(ω) - r_m) / E_total_m
where w_m = softmax_τ(r)_m = exp(τ·r_m) / Σ_k exp(τ·r_k).
"""
function mmf_cost_worst_mode(uωf, band_mask; τ::Real = 50.0)
    @assert size(uωf, 1) == length(band_mask)
    @assert any(band_mask)
    @assert τ > 0

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

    # Stable log-sum-exp: J_τ = r_max + (1/τ)·log(Σ_m exp(τ·(r_m - r_max)))
    r_max   = maximum(r)
    shifted = τ .* (r .- r_max)
    denom   = sum(exp.(shifted))
    J       = r_max + log(denom) / τ

    # Softmax weights (gradient chain rule)
    w = exp.(shifted) ./ denom

    dJ = zeros(ComplexF64, size(uωf))
    for m in 1:M
        if E_total[m] > 0
            u_m = @view uωf[:, m]
            @. @views dJ[:, m] = w[m] * u_m * (band_mask - r[m]) / E_total[m]
        end
    end

    @assert isfinite(J) "J non-finite: $J"
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

Modes with zero total energy are reported as 0.0.
"""
function mmf_mode_band_fractions(uωf, band_mask)
    @assert size(uωf, 1) == length(band_mask)
    M = size(uωf, 2)
    r = zeros(Float64, M)
    for m in 1:M
        u_m = @view uωf[:, m]
        E_total = sum(abs2, u_m)
        if E_total > 0
            r[m] = sum(abs2.(u_m[band_mask])) / E_total
        end
    end
    @assert all(isfinite, r)
    return r
end

"""
    mmf_cost_report(uωf, band_mask; τ=50.0) -> NamedTuple

Evaluate all multimode Raman cost views on the same output field:
- `:sum` — integrating-detector baseline
- `:fundamental` — LP01-only
- `:worst_mode` — smooth robust worst-mode proxy

Also returns the true per-mode fractions.
"""
function mmf_cost_report(uωf, band_mask; τ::Real = 50.0)
    per_mode_lin = mmf_mode_band_fractions(uωf, band_mask)
    J_sum, _ = mmf_cost_sum(uωf, band_mask)
    J_fund, _ = mmf_cost_fundamental(uωf, band_mask)
    J_worst, _ = mmf_cost_worst_mode(uωf, band_mask; τ = τ)

    to_dB(x) = 10.0 * log10(max(x, 1e-15))
    return (
        sum_lin = J_sum,
        sum_dB = to_dB(J_sum),
        fundamental_lin = J_fund,
        fundamental_dB = to_dB(J_fund),
        worst_mode_lin = J_worst,
        worst_mode_dB = to_dB(J_worst),
        worst_mode_true_lin = maximum(per_mode_lin),
        worst_mode_true_dB = to_dB(maximum(per_mode_lin)),
        per_mode_lin = per_mode_lin,
        per_mode_dB = to_dB.(per_mode_lin),
        τ = Float64(τ),
    )
end

end # include guard
