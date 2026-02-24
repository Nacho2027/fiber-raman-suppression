function meshgrid(x, y)
    X = repeat(reshape(x, 1, :), length(y), 1)
    Y = repeat(reshape(y, :, 1), 1, length(x))
    return X, Y
end

function lin_to_dB(x)
    return 10 * log10(x)
end

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

function get_disp_fiber_params(L, radius, core_NA, alpha, nx, sim, fiber_fname; spatial_window=100, fR=0.18, τ1=12.2, τ2=32)
    Δt = sim["Δt"]
    ts = sim["ts"]
    one_m_fR = (1 - fR)
    hRt = fR * Δt * 1e3 * (τ1^2 + τ2^2) / (τ1 * τ2^2) * exp.(-ts * 1e15 / τ2) .* sin.(ts * 1e15 / τ1) .* (sign.(ts) .+ 1) / 2
    hRω = fft(hRt)

    f0 = sim["f0"]
    c0 = sim["c0"]
    M = sim["M"]
    Nt = sim["Nt"]
    β_order = sim["β_order"]

    if isfile(fiber_fname) == true
        println("Load fiber params")
        flush(stdout)
        fiber = npzread(fiber_fname)
        γ = fiber["gamma"]
        ϕ = fiber["phi"]
        Dω = fiber["D_w"]
        x = fiber["x"]
        βn_ω = fiber["betas"]
    else
        println("Compute fiber params")
        flush(stdout)
        βn_ω, Dω, γ, ϕ, x = get_params(f0, c0, nx, spatial_window, radius, core_NA, alpha, M, Nt, Δt, β_order)
        npzwrite(fiber_fname, Dict("gamma" => γ, "phi" => ϕ, "x" => x, "D_w" => Dω, "betas" => βn_ω))
    end
    println()
    return Dict("ϕ" => ϕ, "Dω" => Dω, "γ" => γ, "L" => L, "hRω" => hRω, "one_m_fR" => one_m_fR, "zsave" => nothing, "x" => x, "gain_parameters" => 0.0)
end


function get_disp_fiber_params_user_defined(L, sim; fR=0.18, τ1=12.2, τ2=32, gamma_user=nothing, betas_user=nothing)

    println("User defined fiber params")

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
    hRt = fR * Δt * 1e3 * (τ1^2 + τ2^2) / (τ1 * τ2^2) * exp.(-ts * 1e15 / τ2) .* sin.(ts * 1e15 / τ1) .* (sign.(ts) .+ 1) / 2
    hRω = fft(hRt)

    β_tail = vcat(collect(betas_user), zeros(β_order - 1 - length(betas_user)))
    βn_ω = reshape(vcat([0.0, 0.0], β_tail), :, 1)
    Dω = hcat([(2 * π * fftfreq(Nt, 1 / Δt) * 1e12) .^ n / factorial(n) for n in 0:β_order]...) * βn_ω
    γ = fill(float(gamma_user), 1, 1, 1, 1)

    println(βn_ω)

    return Dict("ϕ" => nothing, "Dω" => Dω, "γ" => γ, "L" => L, "hRω" => hRω, "one_m_fR" => one_m_fR, "zsave" => nothing, "x" => nothing, "gain_parameters" => 0.0)
end