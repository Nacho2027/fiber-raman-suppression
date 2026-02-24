# --- Single modular parameter container ---
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


# --- Modular helpers ---
function psd_from_uω(uω, p::YDFAParams)
    # Convert MultiModeNoise FFT convention to physical ESD/PSD
    uω_s = uω .* p.Nt .* p.dt
    ESD = abs2.(uω_s)
    return fftshift(ESD) .* p.pulse_rep_rate # W/Hz
end

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


function get_YDFAParams(sim)
    pYDFA = YDFAParams(fs=sim["fs"], Δt=sim["Δt"], Nt=sim["Nt"])
    xs = MultiModeNoise.get_ydfa_cross_sections(pYDFA.fs)
    pYDFA.σas .= xs["sigma_as"]
    pYDFA.σes .= xs["sigma_es"]
    return pYDFA

end