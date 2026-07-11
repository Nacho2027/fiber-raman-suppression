"""
    meshgrid(x, y) -> (X, Y)

Create 2D coordinate matrices from 1D vectors, analogous to MATLAB's `meshgrid`.
Returns matrices X (rows repeat x) and Y (columns repeat y), both of size
`(length(y), length(x))`.
"""
function meshgrid(x, y)
    X = repeat(reshape(x, 1, :), length(y), 1)
    Y = repeat(reshape(y, :, 1), 1, length(x))
    return X, Y
end

"""
    lin_to_dB(x) -> Float64

Convert a linear power ratio to decibels: `10 · log₁₀(x)`.
"""
function lin_to_dB(x)
    return 10 * log10(x)
end

"""
    get_disp_sim_params(λ0, M, Nt, time_window, β_order) -> Dict{String, Any}

Build the simulation parameter dictionary for dispersive pulse propagation.

# Arguments
- `λ0`: center wavelength [m]
- `M`: number of spatial modes (M=1 for single-mode)
- `Nt`: number of temporal grid points (must be power of 2)
- `time_window`: full simulation window width [ps]
- `β_order`: highest dispersion order retained in the Taylor expansion (e.g., 2 for β₂ only)

# Returns
Dict with keys:
- `"λ0"`, `"f0"` (center frequency [THz]), `"ω0"` (angular frequency [rad/ps])
- `"M"`, `"Nt"`, `"time_window"`, `"Δt"` (temporal step [ps])
- `"ts"` (time grid [s]), `"fs"` (frequency grid [THz]), `"ωs"` (angular freq grid [rad/ps])
- `"ε"` (vacuum noise photon scaling factor for quantum noise analysis)
- `"β_order"`, `"c0"` [m/s], `"h"` [J·s]

The FFT time grid is periodic. Propagation does not apply an edge absorber;
callers must choose a wide enough window and verify raw temporal containment.
"""
function get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    λ0 isa Real && isfinite(λ0) && λ0 > 0 || throw(ArgumentError(
        "λ0 must be positive and finite"))
    M isa Integer && M > 0 || throw(ArgumentError("M must be a positive integer"))
    Nt isa Integer && Nt >= 4 && ispow2(Nt) || throw(ArgumentError(
        "Nt must be a power of two ≥ 4"))
    time_window isa Real && isfinite(time_window) && time_window > 0 ||
        throw(ArgumentError("time_window must be positive and finite"))
    β_order isa Integer && β_order >= 2 || throw(ArgumentError(
        "β_order must be an integer ≥ 2"))

    λ0, M, Nt = Float64(λ0), Int(M), Int(Nt)
    time_window, β_order = Float64(time_window), Int(β_order)
    c0 = 2.99792458e8 # m/s
    h = 6.62607e-34 # Js
    f0 = c0 / λ0 / 1e12 # THz
    Δt = time_window / Nt
    ts = 1e-12 * [-time_window / 2 + i * Δt for i in 0:Nt-1] # s
    fs = f0 .+ fftshift(fftfreq(Nt, 1 / Δt)) # THz
    all(>(0), fs) || throw(ArgumentError(
        "simulation bandwidth reaches nonpositive absolute optical frequencies"))
    ω0 = 2 * π * f0 # rad / ps
    ωs = 2 * π * fs # rad / ps
    ε = 1e-12 * Δt / (h * 1e12 * f0)

    return Dict("λ0" => λ0, "f0" => f0, "M" => M, "Nt" => Nt, "time_window" => time_window, "Δt" => Δt, "ts" => ts, "fs" => fs, "ω0" => ω0,
        "ωs" => ωs, "c0" => c0, "h" => h, "ε" => ε, "β_order" => β_order)
end

const _SILICA_RAMAN_FRACTION = 0.18
const _SILICA_RAMAN_TAU1_FS = 12.2
const _SILICA_RAMAN_TAU2_FS = 32.0
const _RAMAN_RESPONSE_MODEL = "blow_wood_single_damped_oscillator_v1"
const _RAMAN_PROVENANCE_KEYS = (
    "raman_response_model",
    "raman_fraction",
    "raman_tau1_fs",
    "raman_tau2_fs",
)

function _single_oscillator_raman_fields(sim; fR, τ1, τ2)
    fraction, tau1_fs, tau2_fs = Float64(fR), Float64(τ1), Float64(τ2)
    isfinite(fraction) && 0 <= fraction <= 1 || throw(ArgumentError(
        "fR must be finite and lie in [0, 1]"))
    isfinite(tau1_fs) && tau1_fs > 0 || throw(ArgumentError(
        "τ1 must be positive and finite"))
    isfinite(tau2_fs) && tau2_fs > 0 || throw(ArgumentError(
        "τ2 must be positive and finite"))

    nt, delta_t = Int(sim["Nt"]), Float64(sim["Δt"])
    nt >= 4 && ispow2(nt) || throw(ArgumentError(
        "simulation Nt must be a power of two ≥ 4"))
    isfinite(delta_t) && delta_t > 0 || throw(ArgumentError(
        "simulation Δt must be positive and finite"))
    omega = 2π .* fftfreq(nt, 1 / delta_t)
    decay, resonance = 1e3 / tau2_fs, 1e3 / tau1_fs
    all(isfinite, (decay, resonance)) || throw(ArgumentError(
        "Raman time constants are outside the supported Float64 range"))
    response = fraction .* (decay^2 + resonance^2) ./
        ((decay .+ 1im .* omega) .^ 2 .+ resonance^2)
    centered = cis.(-omega .* nt .* delta_t ./ 2) .* response
    # The even-grid Nyquist bin is unpaired and must be real for a real response.
    centered[nt ÷ 2 + 1] = real(centered[nt ÷ 2 + 1])
    all(isfinite, centered) || throw(ArgumentError(
        "Raman response is not finite for the requested parameters"))
    return Dict{String,Any}(
        "hRω" => centered,
        "one_m_fR" => 1 - fraction,
        "raman_response_model" => _RAMAN_RESPONSE_MODEL,
        "raman_fraction" => fraction,
        "raman_tau1_fs" => tau1_fs,
        "raman_tau2_fs" => tau2_fs,
    )
end

function _raman_response_metadata(fiber)
    present = map(key -> haskey(fiber, key), _RAMAN_PROVENANCE_KEYS)
    any(present) || return missing
    all(present) || throw(ArgumentError(
        "Raman provenance must provide model, fraction, tau1_fs, and tau2_fs together"))
    return (
        model = String(fiber["raman_response_model"]),
        fraction = Float64(fiber["raman_fraction"]),
        tau1_fs = Float64(fiber["raman_tau1_fs"]),
        tau2_fs = Float64(fiber["raman_tau2_fs"]),
    )
end

"""
    get_disp_fiber_params(L, radius, core_NA, alpha, nx, sim, fiber_fname;
                          spatial_window=100, fR=0.18, τ1=12.2, τ2=32) -> Dict

Build fiber parameter dictionary for GRIN multimode fibers by solving the eigenvalue
problem for spatial modes (or loading cached results from an NPZ file).

# Arguments
- `L`: fiber length [m]
- `radius`: core radius [μm]
- `core_NA`: numerical aperture
- `alpha`: GRIN profile exponent (2.0 for parabolic)
- `nx`: spatial grid points per dimension
- `sim`: simulation parameter dict from `get_disp_sim_params`
- `fiber_fname`: path to NPZ cache file (loads if exists, saves after computation)

# Keyword arguments
- `spatial_window`: spatial grid extent [μm] (default 100)
- `fR`: fractional Raman contribution (default 0.18 for silica)
- `τ1`, `τ2`: Raman response time constants [fs] (default 12.2, 32 for silica)

# Returns
Dict with keys: `"ϕ"` (eigenmodes), `"Dω"` (dispersion operator), `"γ"` (nonlinearity
tensor), `"L"`, `"hRω"` (Raman response in frequency domain), `"one_m_fR"` (1-fR),
`"zsave"`, `"x"` (spatial grid), `"gain_parameters"`.

# Raman response
The time-domain Raman response h_R(t) is the damped oscillator model:
  h_R(t) = fR · (τ₁² + τ₂²)/(τ₁·τ₂²) · exp(-t/τ₂) · sin(t/τ₁) · Θ(t)
where Θ(t) is the Heaviside step function. Its analytic Fourier transform is
evaluated on the simulation frequencies to get hRω without grid-dependent
quadrature error.
"""
function get_disp_fiber_params(L, radius, core_NA, alpha, nx, sim, fiber_fname;
                               spatial_window=100,
                               fR=_SILICA_RAMAN_FRACTION,
                               τ1=_SILICA_RAMAN_TAU1_FS,
                               τ2=_SILICA_RAMAN_TAU2_FS)
    raman = _single_oscillator_raman_fields(sim; fR = fR, τ1 = τ1, τ2 = τ2)
    Δt = sim["Δt"]

    f0 = sim["f0"]
    c0 = sim["c0"]
    M = sim["M"]
    Nt = sim["Nt"]
    β_order = sim["β_order"]

    if isfile(fiber_fname)
        @debug "Load fiber params from $fiber_fname"
        fiber = npzread(fiber_fname)
        γ = fiber["gamma"]
        ϕ = fiber["phi"]
        Dω = fiber["D_w"]
        x = fiber["x"]
    else
        @debug "Computing fiber params for nx=$nx, M=$(sim["M"])"
        βn_ω, Dω, γ, ϕ, x = get_params(f0, c0, nx, spatial_window, radius, core_NA, alpha, M, Nt, Δt, β_order)
        npzwrite(fiber_fname, Dict("gamma" => γ, "phi" => ϕ, "x" => x, "D_w" => Dω, "betas" => βn_ω))
    end
    return merge(Dict{String,Any}(
        "ϕ" => ϕ, "Dω" => Dω, "γ" => γ, "L" => L, "zsave" => nothing,
        "x" => x, "gain_parameters" => 0.0,
    ), raman)
end


"""
    get_disp_fiber_params_user_defined(L, sim; fR=0.18, τ1=12.2, τ2=32,
                                       gamma_user=nothing, betas_user=nothing) -> Dict

Build fiber parameter dictionary from user-specified γ and β coefficients, bypassing
the GRIN eigenvalue solver. Used for single-mode (M=1) fibers like SMF-28 and HNLF.

# Arguments
- `L`: fiber length [m]
- `sim`: simulation parameter dict from `get_disp_sim_params`

# Keyword arguments
- `fR`: fractional Raman contribution (default 0.18)
- `τ1`, `τ2`: Raman response time constants [fs] (default 12.2, 32)
- `gamma_user`: nonlinear coefficient γ [W⁻¹m⁻¹] (required)
- `betas_user`: vector of dispersion coefficients [β₂, β₃, ...] in SI units (required)

# Dispersion operator construction
The dispersion operator Dω is built from the Taylor expansion:
  D(ω) = Σₙ βₙ/n! · (2π·Δf)ⁿ
where Δf is the FFT frequency grid. β₀ and β₁ are set to zero (reference frame
co-moving with pulse group velocity). Higher-order βₙ beyond those provided are
zero-padded up to `β_order` from the simulation parameters.

# Returns
Same Dict structure as `get_disp_fiber_params`, with `"ϕ"` and `"x"` set to `nothing`
(no spatial modes for user-defined single-mode fibers), and `"γ"` as a 1×1×1×1 tensor.
"""
function get_disp_fiber_params_user_defined(
    L,
    sim;
    fR=_SILICA_RAMAN_FRACTION,
    τ1=_SILICA_RAMAN_TAU1_FS,
    τ2=_SILICA_RAMAN_TAU2_FS,
    gamma_user=nothing,
    betas_user=nothing,
)

    @debug "User defined fiber params"

    Nt = sim["Nt"]
    Δt = sim["Δt"]
    β_order = sim["β_order"]

    if isnothing(gamma_user) || isnothing(betas_user)
        throw(ArgumentError("gamma_user and betas_user must both be provided"))
    end

    if length(betas_user) > β_order - 1
        throw(ArgumentError("betas_user length must be ≤ β_order-1 ($(β_order - 1)); got $(length(betas_user))"))
    end

    raman = _single_oscillator_raman_fields(sim; fR = fR, τ1 = τ1, τ2 = τ2)

    β_tail = vcat(collect(betas_user), zeros(β_order - 1 - length(betas_user)))
    βn_ω = reshape(vcat([0.0, 0.0], β_tail), :, 1)
    Dω = hcat([(2 * π * fftfreq(Nt, 1 / Δt) * 1e12) .^ n / factorial(n) for n in 0:β_order]...) * βn_ω
    γ = fill(float(gamma_user), 1, 1, 1, 1)

    @debug "βn_ω" βn_ω

    return merge(Dict{String,Any}(
        "ϕ" => nothing, "Dω" => Dω, "γ" => γ, "L" => L, "zsave" => nothing,
        "x" => nothing, "gain_parameters" => 0.0,
    ), raman)
end
