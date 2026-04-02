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
- `"attenuator"` (super-Gaussian temporal window to suppress FFT wraparound, shape Nt×M)
- `"ε"` (vacuum noise photon scaling factor for quantum noise analysis)
- `"β_order"`, `"c0"` [m/s], `"h"` [J·s]

# Notes
The attenuator is a super-Gaussian of order 30 with half-width at 85% of the time window,
used to absorb energy approaching the FFT boundaries and prevent unphysical wraparound.
"""
function get_disp_sim_params(λ0, M, Nt, time_window, β_order)
    c0 = 2.99792458e8 # m/s
    h = 6.62607e-34 # Js
    f0 = c0 / λ0 / 1e12 # THz
    Δt = time_window / Nt
    ts = 1e-12 * [-time_window / 2 + i * Δt for i in 0:Nt-1] # s
    fs = f0 .+ fftshift(fftfreq(Nt, 1 / Δt)) # THz
    ω0 = 2 * π * f0 # rad / ps
    ωs = 2 * π * fs # rad / ps
    ε = 1e-12 * Δt / (h * 1e12 * f0)

    r_attenuation = 0.85 * time_window / 2
    n_attenuation = 30
    σ_attenuation = r_attenuation / log(2)^(1 / n_attenuation)
    r_hm = σ_attenuation * log(2)^(1 / n_attenuation)
    attenuator = exp.(-(abs.(1e12 * ts) / σ_attenuation) .^ n_attenuation) * ones(M)'

    return Dict("λ0" => λ0, "f0" => f0, "M" => M, "Nt" => Nt, "time_window" => time_window, "Δt" => Δt, "ts" => ts, "fs" => fs, "ω0" => ω0,
        "ωs" => ωs, "attenuator" => attenuator, "c0" => c0, "h" => h, "ε" => ε, "β_order" => β_order)
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
where Θ(t) is the Heaviside step function. This is Fourier-transformed to get hRω.
"""
function get_disp_fiber_params(L, radius, core_NA, alpha, nx, sim, fiber_fname; spatial_window=100, fR=0.18, τ1=12.2, τ2=32)
    Δt = sim["Δt"]
    ts = sim["ts"]
    one_m_fR = (1 - fR)
    # Causal Raman response: clamp negative t to 0 BEFORE exp() to prevent Float64 overflow
    # when time_window > 45 ps (|t| > 22710 fs causes exp(|t|/τ₂) → Inf, then Inf*0 = NaN).
    ts_pos = max.(ts, 0.0)
    hRt = fR * Δt * 1e3 * (τ1^2 + τ2^2) / (τ1 * τ2^2) .* exp.(-ts_pos * 1e15 / τ2) .* sin.(ts_pos * 1e15 / τ1) .* (sign.(ts) .+ 1) / 2
    hRω = fft(hRt)

    f0 = sim["f0"]
    c0 = sim["c0"]
    M = sim["M"]
    Nt = sim["Nt"]
    β_order = sim["β_order"]

    if isfile(fiber_fname) == true
        @debug "Load fiber params from $fiber_fname"
        fiber = npzread(fiber_fname)
        γ = fiber["gamma"]
        ϕ = fiber["phi"]
        Dω = fiber["D_w"]
        x = fiber["x"]
        βn_ω = fiber["betas"]
    else
        @debug "Computing fiber params for nx=$nx, M=$(sim["M"])"
        βn_ω, Dω, γ, ϕ, x = get_params(f0, c0, nx, spatial_window, radius, core_NA, alpha, M, Nt, Δt, β_order)
        npzwrite(fiber_fname, Dict("gamma" => γ, "phi" => ϕ, "x" => x, "D_w" => Dω, "betas" => βn_ω))
    end
    return Dict("ϕ" => ϕ, "Dω" => Dω, "γ" => γ, "L" => L, "hRω" => hRω, "one_m_fR" => one_m_fR, "zsave" => nothing, "x" => x, "gain_parameters" => 0.0)
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
function get_disp_fiber_params_user_defined(L, sim; fR=0.18, τ1=12.2, τ2=32, gamma_user=nothing, betas_user=nothing)

    @debug "User defined fiber params"

    Δt = sim["Δt"]
    ts = sim["ts"]
    Nt = sim["Nt"]
    β_order = sim["β_order"]

    if isnothing(gamma_user) || isnothing(betas_user)
        throw(ArgumentError("gamma_user and betas_user must both be provided"))
    end

    if length(betas_user) > β_order - 1
        throw(ArgumentError("betas_user length must be ≤ β_order-1 ($(β_order - 1)); got $(length(betas_user))"))
    end

    one_m_fR = (1 - fR)
    # Causal Raman response: clamp negative t to 0 BEFORE exp() to prevent Float64 overflow
    # when time_window > 45 ps (|t| > 22710 fs causes exp(|t|/τ₂) → Inf, then Inf*0 = NaN).
    ts_pos = max.(ts, 0.0)
    hRt = fR * Δt * 1e3 * (τ1^2 + τ2^2) / (τ1 * τ2^2) .* exp.(-ts_pos * 1e15 / τ2) .* sin.(ts_pos * 1e15 / τ1) .* (sign.(ts) .+ 1) / 2
    hRω = fft(hRt)

    β_tail = vcat(collect(betas_user), zeros(β_order - 1 - length(betas_user)))
    βn_ω = reshape(vcat([0.0, 0.0], β_tail), :, 1)
    Dω = hcat([(2 * π * fftfreq(Nt, 1 / Δt) * 1e12) .^ n / factorial(n) for n in 0:β_order]...) * βn_ω
    γ = fill(float(gamma_user), 1, 1, 1, 1)

    @debug "βn_ω" βn_ω

    return Dict("ϕ" => nothing, "Dω" => Dω, "γ" => γ, "L" => L, "hRω" => hRω, "one_m_fR" => one_m_fR, "zsave" => nothing, "x" => nothing, "gain_parameters" => 0.0)
end