"""
    YDFAParams

Mutable parameter container for a Yb-doped fiber amplifier (YDFA) model.

Encapsulates all physical parameters needed to compute spectral gain via rate equations:
geometry/dopant properties, pump channel, signal channel grid, overlap factors, and
cross-section spectra.

# Overlap factor model
Uses the Marcuse approximation for the mode field radius w:
    w = a · (0.616 + 1.66/V^1.5 + 0.987/V^6)
where V = 2πa·NA/λ is the normalized frequency, and the overlap factor is:
    Γ = 1 - exp(-2a²/w²)

# Fields (key ones)
- `L`: fiber length [m]
- `core_radius`: [m], `NA`: numerical aperture
- `rho`: ion density [m⁻³], `tau21`: upper-state lifetime [s]
- `λp`, `σap`, `σep`: pump wavelength [m] and cross-sections [m²]
- `fs`, `Δt`, `Nt`: signal frequency grid [THz], temporal step [ps], grid points
- `σas`, `σes`: absorption/emission cross-sections on signal grid [m²]
- `Gamma_p`, `Gamma_s`: pump/signal overlap factors [dimensionless]
"""
Base.@kwdef mutable struct YDFAParams
    # Geometry / dopant
    L::Float64 = 2.5
    core_radius::Float64 = 2.5e-6
    NA::Float64 = 0.13
    A::Float64 = pi * core_radius^2
    rho::Float64 = 1e25
    tau21::Float64 = 1.4e-3

    # Pump channel
    λp::Float64 = 976e-9
    νp::Float64 = 2.99792458e8 / λp
    σap::Float64 = 2.5e-24
    σep::Float64 = 2.5e-24

    # Signal channel
    λs0::Float64 = 1030e-9
    νs0::Float64 = 2.99792458e8 / λs0

    # Signal channel grid
    fs::Vector{Float64}
    Δt::Float64
    Nt::Int
    νs::Vector{Float64} = fs .* 1e12
    dt::Float64 = Δt * 1e-12
    df::Float64 = 1 / (Nt * dt)
    pulse_rep_rate::Float64 = 80e6

    # Signal field in frequency domain (mutable, can be changed during solve)
    # uω::Vector{ComplexF64} = ComplexF64.(uω0[:, 1])

    # Overlap factors
    V_p::Float64 = 2 * pi * core_radius * NA / (λp)  # Normalized Frequency
    w_p::Float64 = core_radius * (0.616 + 1.66 / (V_p^1.5) + 0.987 / (V_p^6))
    Gamma_p::Float64 = 1 - exp(-2 * core_radius^2 / w_p^2)          # Overlap factor

    V_s::Float64 = 2 * pi * core_radius * NA / (λs0)  # Normalized Frequency
    w_s::Float64 = core_radius * (0.616 + 1.66 / (V_s^1.5) + 0.987 / (V_s^6))
    Gamma_s::Float64 = 1 - exp(-2 * core_radius^2 / w_s^2)

    # Cross sections on fs grid (filled from gain.jl helper)
    σas::Vector{Float64} = zeros(length(fs))
    σes::Vector{Float64} = zeros(length(fs))
end


"""
    get_ydfa_cross_sections(fs; data_dir, absorption_file, emission_file, scale) -> Dict

Load Yb³⁺ absorption and emission cross-section spectra from NPZ files and interpolate
onto the simulation frequency grid `fs` [THz].

Returns Dict with keys `"lambda"` [m], `"sigma_as"` [m²], `"sigma_es"` [m²].
The `scale` parameter converts raw data units to m² (default 1e-27).
"""
function get_ydfa_cross_sections(fs; data_dir=@__DIR__,
    absorption_file="Yb_absorption.npz",
    emission_file="Yb_emission.npz",
    scale=1e-27)

    c0 = 2.99792458e8 # m/s

    abs_path = joinpath(data_dir, absorption_file)  # look in the same directory as this script
    em_path = joinpath(data_dir, emission_file)

    absorption_values = npzread(abs_path)
    emission_values = npzread(em_path)

    λ_abs = absorption_values["wavelength"] .* 1e-9
    σ_abs = absorption_values["intensity"] .* scale

    λ_em = emission_values["wavelength"] .* 1e-9
    σ_em = emission_values["intensity"] .* scale

    itp_abs = linear_interpolation(λ_abs, σ_abs, extrapolation_bc=Flat())
    itp_em = linear_interpolation(λ_em, σ_em, extrapolation_bc=Flat())

    λ_target = c0 ./ (fs .* 1e12)  # since THz

    sigma_as = itp_abs.(λ_target)
    sigma_es = itp_em.(λ_target)

    return Dict("lambda" => λ_target, "sigma_as" => sigma_as, "sigma_es" => sigma_es)
end


"""
    psd_from_uω(uω, p::YDFAParams) -> Vector{Float64}

Convert FFT-convention field amplitudes to physical power spectral density [W/Hz].

The FFT field uω has units √(J/bin). To get physical PSD:
1. Scale by Nt·dt to convert to √(J·s) = √(W/Hz) per bin
2. Take |·|² to get energy spectral density [J·s]
3. fftshift to physical frequency order
4. Multiply by pulse_rep_rate to convert from single-pulse ESD to average PSD [W/Hz]
"""
function psd_from_uω(uω, p::YDFAParams)
    # Convert FiberLab FFT convention to physical ESD/PSD
    uω_s = uω .* p.Nt .* p.dt
    ESD = abs2.(uω_s)
    return fftshift(ESD) .* p.pulse_rep_rate # W/Hz
end

"""
    calculate_gain_YDFA(Pp, Ps_vec, p::YDFAParams) -> (gν_signal, gP)

Compute YDFA spectral gain from steady-state rate equations.

The population inversion n₂ is solved from the balance equation:
    n₂ = (R₁₂ + W₁₂) / (R₁₂ + R₂₁ + W₁₂ + W₂₁ + 1/τ₂₁)

where R₁₂, R₂₁ are pump transition rates and W₁₂, W₂₁ are signal transition rates.
The spectral gain is then:
    g(ν) = Γ_s · (σ_es·n₂ - σ_as·n₁) · ρ  [1/m]

# Arguments
- `Pp`: pump power [W] (can be complex from ODE state)
- `Ps_vec`: signal PSD [W/Hz] on frequency grid, shape (Nt, 1)
- `p`: YDFAParams struct

# Returns
- `gν_signal`: spectral gain [1/m] on signal frequency grid
- `gP`: pump gain [1/m] (negative means pump is absorbed)
"""
function calculate_gain_YDFA(Pp::ComplexF64, Ps_vec::Matrix{Float64}, p::YDFAParams)
    h = 6.62607015e-34
    R12 = (p.Gamma_p * p.σap * Pp) / (h * p.νp * p.A)
    R21 = (p.Gamma_p * p.σep * Pp) / (h * p.νp * p.A)

    W12 = sum((p.Gamma_s .* p.σas .* Ps_vec .* p.df) ./ (h .* p.νs .* p.A))
    W21 = sum((p.Gamma_s .* p.σes .* Ps_vec .* p.df) ./ (h .* p.νs .* p.A))

    n2 = (R12 + W12) / (R12 + R21 + W12 + W21 + 1 / p.tau21)
    n1 = 1 - n2

    gν_signal = p.Gamma_s .* (p.σes .* n2 .- p.σas .* n1) .* p.rho

    gP = p.Gamma_p * (p.σep * n2 - p.σap * n1) * p.rho

    return gν_signal, gP
end


"""
    get_YDFAParams(sim) -> YDFAParams

Instantiate a YDFAParams struct from a simulation parameter dictionary and populate
the Yb cross-section spectra by loading from NPZ data files.
"""
function get_YDFAParams(sim)
    pYDFA = YDFAParams(fs=sim["fs"], Δt=sim["Δt"], Nt=sim["Nt"])
    xs = FiberLab.get_ydfa_cross_sections(pYDFA.fs)
    pYDFA.σas .= xs["sigma_as"]
    pYDFA.σes .= xs["sigma_es"]
    return pYDFA

end