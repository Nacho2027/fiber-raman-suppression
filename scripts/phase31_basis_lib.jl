# scripts/phase31_basis_lib.jl — Phase 31 basis library extension
# Adds :polynomial (Legendre, gauge-free starting at start_order=2) and
# :chirp_ladder (fixed 4 columns: ω², ω³, ω⁴, ω⁵) kinds. Reuses
# build_phase_basis from sweep_simple_param.jl for :cubic/:dct/:linear/:identity.
#
# Per Phase 31 locked decision D-01: extend existing infrastructure; do NOT
# re-implement basis construction. build_basis_dispatch is the Phase-31 entry
# point that branches on kind and delegates to the existing implementation
# whenever possible.
#
# Constants: P31_ prefix (matches script-constant convention).
# Include guard: _PHASE31_BASIS_LIB_JL_LOADED.

using LinearAlgebra
using Statistics

# Transitively pulls common.jl (setup_raman_problem) + raman_optimization.jl
# (cost_and_gradient). Its own include guard makes this cheap on re-include.
include(joinpath(@__DIR__, "sweep_simple_param.jl"))

if !(@isdefined _PHASE31_BASIS_LIB_JL_LOADED)
const _PHASE31_BASIS_LIB_JL_LOADED = true

const P31_BASIS_LIB_VERSION = "1.0.0"
const P31_POLY_START_ORDER_DEFAULT = 2           # gauge-free (skip constant + linear)
const P31_CHIRP_LADDER_ORDER = 5                 # 4 columns: ω² .. ω⁵

# ─────────────────────────────────────────────────────────────────────────────
# build_polynomial_basis — Legendre polynomials in scaled ω variable
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_polynomial_basis(Nt, order; ω_grid, ω0, Δω_band,
                           start_order=P31_POLY_START_ORDER_DEFAULT)
        -> Matrix{Float64}  (Nt × (order - start_order + 1))

Construct a Legendre-polynomial basis in the scaled variable
`x = (ω - ω0) / Δω_band`. Columns correspond to orders
`start_order, start_order+1, ..., order`. Each column is L2-normalized over
the full Nt grid.

For `start_order=2`, the basis is GAUGE-FREE by construction: it excludes
the constant (order 0) and linear (order 1) null-space modes of the Raman
cost (Phase 13). Coefficients are directly interpretable as dispersion
orders (β₂_shaper-like, β₃-like, …) when paired with the physical ω axis.

Recurrence used (Bonnet's, numerically stable):
    P₀(x) = 1
    P₁(x) = x
    (n+1)·P_{n+1}(x) = (2n+1)·x·P_n(x) - n·P_{n-1}(x)

# Arguments
- `Nt::Int`                 — FFT grid size
- `order::Int`              — highest polynomial order included (inclusive)

# Keyword arguments
- `ω_grid::AbstractVector`  — angular-frequency grid (length Nt). Typically
                              `sim["ωs"]` in rad/ps.
- `ω0::Real`                — carrier angular frequency (rad/ps).
- `Δω_band::Real`           — bandwidth half-width used to scale x into
                              roughly [-1, 1] on the pulse support.
- `start_order::Int`        — lowest polynomial order included. Default 2.

# Returns
`Matrix{Float64}` of shape `(Nt, order - start_order + 1)`.

# PRECONDITIONS
- `Nt > 0`; `order ≥ start_order ≥ 0`; `length(ω_grid) == Nt`; `Δω_band > 0`.
- `maximum(abs.(x)) ≤ 2.0` after scaling (so the Legendre recurrence stays
  numerically reasonable off-band).
"""
function build_polynomial_basis(Nt::Int, order::Int;
                                ω_grid::AbstractVector{<:Real},
                                ω0::Real,
                                Δω_band::Real,
                                start_order::Int = P31_POLY_START_ORDER_DEFAULT)
    # PRECONDITIONS
    @assert Nt > 0 "Nt must be positive, got $Nt"
    @assert order ≥ start_order "order=$order must be ≥ start_order=$start_order"
    @assert start_order ≥ 0 "start_order must be non-negative, got $start_order"
    @assert length(ω_grid) == Nt "ω_grid length $(length(ω_grid)) ≠ Nt $Nt"
    @assert Δω_band > 0 "Δω_band must be positive, got $Δω_band"

    # Scaled variable — roughly in [-1, 1] on the bandwidth
    x = (collect(ω_grid) .- ω0) ./ Δω_band
    @assert maximum(abs.(x)) ≤ 2.0 "scaled ω range max|x|=$(maximum(abs.(x))) exceeds 2.0; widen Δω_band or check ω_grid"

    ncols = order - start_order + 1
    B = zeros(Float64, Nt, ncols)

    # Build Legendre polynomials P_0 .. P_order using Bonnet recurrence,
    # keeping only columns from start_order to order.
    P_prev2 = ones(Float64, Nt)   # P_0(x)
    P_prev1 = copy(x)             # P_1(x)

    function _set_col(n::Int, vals::Vector{Float64})
        if n ≥ start_order && n ≤ order
            B[:, n - start_order + 1] .= vals
        end
    end

    _set_col(0, P_prev2)
    if order ≥ 1
        _set_col(1, P_prev1)
    end

    for n in 1:(order - 1)
        P_next = @. ((2n + 1) * x * P_prev1 - n * P_prev2) / (n + 1)
        _set_col(n + 1, P_next)
        P_prev2 = P_prev1
        P_prev1 = P_next
    end

    # L2-normalize each column on the full Nt grid
    for j in 1:ncols
        nrm = norm(B[:, j])
        @assert nrm > 0 "polynomial column $j is zero — degenerate ω_grid?"
        B[:, j] ./= nrm
    end

    # POSTCONDITIONS
    @assert size(B) == (Nt, ncols) "unexpected size $(size(B))"
    @assert all(isfinite, B) "polynomial basis contains NaN/Inf"

    _sanity_check_basis(B)
    return B
end

# ─────────────────────────────────────────────────────────────────────────────
# build_chirp_ladder_basis — fixed 4-column gauge-free polynomial basis
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_chirp_ladder_basis(Nt; ω_grid, ω0, Δω_band) -> Matrix{Float64}

Thin wrapper: returns `build_polynomial_basis(Nt, 5; ω_grid, ω0, Δω_band,
start_order=2)`. Produces exactly 4 columns corresponding to polynomial
orders {2, 3, 4, 5} — the "minimum-description-length" chirp ansatz Phase 35
found to be the only minimum-like branch.
"""
function build_chirp_ladder_basis(Nt::Int;
                                  ω_grid::AbstractVector{<:Real},
                                  ω0::Real,
                                  Δω_band::Real)
    return build_polynomial_basis(Nt, P31_CHIRP_LADDER_ORDER;
                                  ω_grid=ω_grid, ω0=ω0, Δω_band=Δω_band,
                                  start_order=2)
end

# ─────────────────────────────────────────────────────────────────────────────
# build_basis_dispatch — Phase 31 one-stop basis builder
# ─────────────────────────────────────────────────────────────────────────────

"""
    build_basis_dispatch(kind, Nt, N_phi, bw_mask, sim) -> Matrix{Float64}

Phase 31 unified basis entry point.

For `kind ∈ (:polynomial, :chirp_ladder)`: builds via `build_polynomial_basis`
using `sim["ωs"]` / `sim["ω0"]` and a bandwidth half-width computed from
`bw_mask` applied to `sim["ωs"]`.

  - `:polynomial`: expects `N_phi = order - start_order + 1 = order - 1` (we
    use `start_order=2`). Recovered order = `N_phi + 1`. Example: `N_phi=5`
    → orders {2,3,4,5,6}.
  - `:chirp_ladder`: expects `N_phi == 4` (asserted); always 4 columns.

For `kind ∈ (:cubic, :dct, :linear, :identity)`: delegates to
`build_phase_basis(Nt, N_phi; kind, bandwidth_mask=bw_mask)` — reuses the
existing Session E implementation verbatim.

# PRECONDITIONS
- `sim` has keys `"ωs"`, `"ω0"`, `"Nt"`; `sim["Nt"] == Nt`.
- `length(bw_mask) == Nt`; `sum(bw_mask) ≥ 2` for polynomial/chirp_ladder.
"""
function build_basis_dispatch(kind::Symbol, Nt::Int, N_phi::Int,
                              bw_mask::AbstractVector{Bool},
                              sim::Dict)
    # PRECONDITIONS
    @assert haskey(sim, "ωs") "sim missing 'ωs'"
    @assert haskey(sim, "ω0") "sim missing 'ω0'"
    @assert length(bw_mask) == Nt "bw_mask length $(length(bw_mask)) ≠ Nt $Nt"

    if kind === :polynomial || kind === :chirp_ladder
        @assert sum(bw_mask) ≥ 2 "bandwidth support < 2 bins — cannot define Δω_band"
        ωs = sim["ωs"]
        ω0 = sim["ω0"]
        ω_in_bw = ωs[bw_mask]
        Δω_band = (maximum(ω_in_bw) - minimum(ω_in_bw)) / 2
        @assert Δω_band > 0 "Δω_band computed as zero from bw_mask"

        if kind === :chirp_ladder
            @assert N_phi == 4 ":chirp_ladder requires N_phi == 4 (got $N_phi)"
            return build_chirp_ladder_basis(Nt; ω_grid=ωs, ω0=ω0, Δω_band=Δω_band)
        else
            # N_phi = order - start_order + 1, with start_order=2 → order = N_phi + 1
            order = N_phi + 1
            return build_polynomial_basis(Nt, order;
                                          ω_grid=ωs, ω0=ω0, Δω_band=Δω_band,
                                          start_order=P31_POLY_START_ORDER_DEFAULT)
        end
    else
        # Delegate to existing Session E implementation
        return build_phase_basis(Nt, N_phi; kind=kind, bandwidth_mask=bw_mask)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# basis_conditioning — Gram matrix conditioning, recordable diagnostic
# ─────────────────────────────────────────────────────────────────────────────

"""
    basis_conditioning(B, bw_mask) -> NamedTuple(kappa_B, kappa_warning)

Compute the condition number of `B' * B`. Skipped (returns NaN) for
`size(B, 2) > 512` where the Nt × Nt intermediate is too big to form.
A flag `kappa_warning` is set when `kappa_B > LR_COND_LIMIT` (1e12).

`bw_mask` is accepted for a future variant that would restrict to the
bandwidth support; the current implementation uses the full-grid Gram
(consistent with `_sanity_check_basis` behavior).
"""
function basis_conditioning(B::AbstractMatrix{<:Real},
                            bw_mask::AbstractVector{Bool})
    Nt, N_phi = size(B)
    if N_phi > 512
        return (kappa_B = NaN, kappa_warning = false)
    end
    G = Symmetric(B' * B)
    λs = eigvals(G)
    λmax = maximum(λs); λmin = minimum(λs)
    if λmin ≤ 0
        return (kappa_B = Inf, kappa_warning = true)
    end
    κ = λmax / λmin
    return (kappa_B = κ, kappa_warning = κ > LR_COND_LIMIT)
end

end  # _PHASE31_BASIS_LIB_JL_LOADED
