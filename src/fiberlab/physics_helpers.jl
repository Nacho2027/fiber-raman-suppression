const SINGLE_MODE_FIBER_PRESETS = Dict(
    :SMF28 => (
        name = "SMF-28",
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        fR = 0.18,
    ),
    :SMF28_beta2_only => (
        name = "SMF-28 beta2 only",
        gamma = 1.1e-3,
        betas = [-2.17e-26],
        fR = 0.18,
    ),
    :HNLF => (
        name = "HNLF",
        gamma = 10.0e-3,
        betas = [-0.5e-26, 1.0e-40],
        fR = 0.18,
    ),
    :HNLF_zero_disp => (
        name = "HNLF zero dispersion",
        gamma = 10.0e-3,
        betas = [-0.1e-26, 3.0e-40],
        fR = 0.18,
    ),
)

function _single_mode_preset(preset::Symbol)
    haskey(SINGLE_MODE_FIBER_PRESETS, preset) || throw(ArgumentError(
        "unknown single-mode fiber preset `$(preset)`"))
    return SINGLE_MODE_FIBER_PRESETS[preset]
end

function _pulse_shape_string(shape::Symbol)
    shape == :sech_sq && return "sech_sq"
    shape in (:gauss, :gaussian) && return "gauss"
    throw(ArgumentError("unsupported pulse shape `$(shape)`"))
end

function _peak_power_from_average(power_w, fwhm_s, rep_rate_hz, shape::Symbol)
    factor = shape == :sech_sq ? 0.881374 :
        shape in (:gauss, :gaussian) ? 0.939437 :
        throw(ArgumentError("unsupported pulse shape `$(shape)`"))
    return factor * power_w / (fwhm_s * rep_rate_hz)
end

function _recommended_time_window_ps(length_m, pulse::Pulse, gamma, beta2, power_w)
    p_peak = _peak_power_from_average(power_w, pulse.fwhm_s, pulse.rep_rate_hz, pulse.shape)
    Δω_raman = 2π * 13e12
    walkoff_ps = abs(beta2) * length_m * Δω_raman * 1e12
    t0 = pulse.fwhm_s / 1.763
    nonlinear_phase = gamma * p_peak * length_m
    spm_angular_width = 0.86 * nonlinear_phase / t0
    spm_ps = abs(beta2) * length_m * spm_angular_width * 1e12
    return max(5.0, ceil(2.0 * (walkoff_ps + spm_ps + 0.5)))
end

function _nt_for_window_ps(time_window_ps; dt_min_ps=0.0105)
    nt = 1
    while nt < ceil(Int, time_window_ps / dt_min_ps)
        nt <<= 1
    end
    return nt
end

function _resolved_grid(grid::Grid, fiber::Fiber, pulse::Pulse, preset)
    nt = Int(grid.nt)
    time_window_ps = Float64(grid.time_window_ps)
    nt > 0 && ispow2(nt) || throw(ArgumentError("grid nt must be a positive power of 2"))
    time_window_ps > 0 || throw(ArgumentError("grid time_window_ps must be positive"))
    if grid.policy == :auto_if_undersized
        recommended = _recommended_time_window_ps(
            fiber.length_m,
            pulse,
            preset.gamma,
            preset.betas[1],
            fiber.power_w,
        )
        if time_window_ps < recommended
            time_window_ps = recommended
            nt = max(nt, _nt_for_window_ps(time_window_ps))
        end
    elseif grid.policy in (:exact, :fixed)
        return nt, time_window_ps
    else
        throw(ArgumentError("unsupported grid policy `$(grid.policy)`"))
    end
    return nt, time_window_ps
end

function _field_spectral_band_cost(uωf, band_mask)
    size(uωf, 1) == length(band_mask) || throw(ArgumentError(
        "field rows $(size(uωf, 1)) do not match band mask length $(length(band_mask))"))
    any(band_mask) || throw(ArgumentError("band mask must contain at least one bin"))
    total = sum(abs2, uωf)
    total > 0 || throw(ArgumentError("field must have nonzero spectral energy"))
    band = sum(abs2, uωf[band_mask, :])
    cost = band / total
    terminal = uωf .* (band_mask .- cost) ./ total
    return Float64(cost), terminal
end

function _field_fundamental_band_cost(uωf, band_mask)
    size(uωf, 1) == length(band_mask) || throw(ArgumentError(
        "field rows $(size(uωf, 1)) do not match band mask length $(length(band_mask))"))
    any(band_mask) || throw(ArgumentError("band mask must contain at least one bin"))
    size(uωf, 2) >= 1 || throw(ArgumentError("field must contain at least one mode"))
    u1 = @view uωf[:, 1]
    total = sum(abs2, u1)
    total > 0 || throw(ArgumentError("fundamental mode must have nonzero spectral energy"))
    band = sum(abs2, u1[band_mask])
    cost = band / total
    terminal = zeros(ComplexF64, size(uωf))
    terminal[:, 1] .= u1 .* (band_mask .- cost) ./ total
    return Float64(cost), terminal
end

function _field_worst_mode_band_cost(uωf, band_mask; τ::Real=50.0)
    size(uωf, 1) == length(band_mask) || throw(ArgumentError(
        "field rows $(size(uωf, 1)) do not match band mask length $(length(band_mask))"))
    any(band_mask) || throw(ArgumentError("band mask must contain at least one bin"))
    tau = Float64(τ)
    isfinite(tau) && tau > 0 || throw(ArgumentError("worst-mode smoothness τ must be positive and finite"))
    m = size(uωf, 2)
    m >= 1 || throw(ArgumentError("field must contain at least one mode"))

    ratios = zeros(Float64, m)
    totals = zeros(Float64, m)
    for mode in 1:m
        u_mode = @view uωf[:, mode]
        total = sum(abs2, u_mode)
        totals[mode] = total
        if total > 0
            ratios[mode] = sum(abs2, u_mode[band_mask]) / total
        end
    end

    ratio_max = maximum(ratios)
    shifted = tau .* (ratios .- ratio_max)
    denominator = sum(exp.(shifted))
    cost = ratio_max + log(denominator) / tau
    weights = exp.(shifted) ./ denominator

    terminal = zeros(ComplexF64, size(uωf))
    for mode in 1:m
        totals[mode] <= 0 && continue
        u_mode = @view uωf[:, mode]
        terminal[:, mode] .= weights[mode] .* u_mode .* (band_mask .- ratios[mode]) ./ totals[mode]
    end
    return Float64(cost), terminal
end

function _field_spectral_peak_cost(uωf, band_mask)
    size(uωf, 1) == length(band_mask) || throw(ArgumentError(
        "field rows $(size(uωf, 1)) do not match band mask length $(length(band_mask))"))
    any(band_mask) || throw(ArgumentError("band mask must contain at least one bin"))
    total = sum(abs2, uωf)
    total > 0 || throw(ArgumentError("field must have nonzero spectral energy"))
    band_indices = findall(band_mask)
    bin_energy = vec(sum(abs2, uωf; dims=2))
    peak_index = band_indices[argmax(bin_energy[band_indices])]
    cost = bin_energy[peak_index] / total
    peak_mask = falses(length(band_mask))
    peak_mask[peak_index] = true
    terminal = uωf .* (peak_mask .- cost) ./ total
    return Float64(cost), terminal
end

function _field_temporal_width_cost(uωf, sim)
    nt = Int(sim["Nt"])
    size(uωf, 1) == nt || throw(ArgumentError(
        "field rows $(size(uωf, 1)) do not match Nt=$nt"))
    ut = ifft(uωf, 1)
    centered = fftshift(ut, 1)
    total = sum(abs2, centered)
    total > 0 || throw(ArgumentError("field must have nonzero temporal energy"))
    half_window = max(sim["Δt"] * nt / 2, eps(Float64))
    t = ((collect(0:nt-1) .- floor(Int, nt / 2)) .* sim["Δt"]) ./ half_window
    weights = reshape(t .^ 2, nt, 1)
    cost = sum(weights .* abs2.(centered)) / total
    terminal_t = centered .* (weights .- cost) ./ total
    terminal = fft(ifftshift(terminal_t, 1), 1) ./ nt
    return Float64(cost), terminal
end

function _maybe_log_cost(cost::Float64, terminal, log_cost::Bool)
    log_cost || return cost, terminal
    floor = 1e-15
    scaled_cost = 10.0 * log10(max(cost, floor))
    scale = cost <= floor ? 0.0 : 10.0 / (log(10.0) * cost)
    return scaled_cost, scale .* terminal
end
