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

const MULTIMODE_FIBER_PRESETS = Dict(
    :GRIN_50 => (
        name = "GRIN-50 (OM4-like)",
        description = "50-μm core parabolic GRIN, NA=0.2, silica.",
        radius = 25.0,
        core_NA = 0.2,
        alpha = 2.0,
        M = 6,
        nx = 101,
        spatial_window = 80.0,
        β_order = 2,
        Δf_THz = 1.0,
        fR = 0.18,
        τ1 = 12.2,
        τ2 = 32.0,
    ),
    :STEP_9 => (
        name = "Step-9 (few-mode)",
        description = "9-μm core step-index fiber, NA=0.14, silica.",
        radius = 4.5,
        core_NA = 0.14,
        alpha = 1000.0,
        M = 4,
        nx = 81,
        spatial_window = 24.0,
        β_order = 2,
        Δf_THz = 1.0,
        fR = 0.18,
        τ1 = 12.2,
        τ2 = 32.0,
    ),
)

function _single_mode_preset(preset::Symbol)
    haskey(SINGLE_MODE_FIBER_PRESETS, preset) || throw(ArgumentError(
        "unknown single-mode fiber preset `$(preset)`"))
    return SINGLE_MODE_FIBER_PRESETS[preset]
end

function _multimode_preset(preset::Symbol)
    haskey(MULTIMODE_FIBER_PRESETS, preset) || throw(ArgumentError(
        "unknown multimode fiber preset `$(preset)`; registered presets: $(sort!(collect(keys(MULTIMODE_FIBER_PRESETS)); by=string))"))
    return MULTIMODE_FIBER_PRESETS[preset]
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

function _nt_for_window_ps(time_window_ps; max_time_step_ps=0.0105)
    nt = 1
    while nt < ceil(Int, time_window_ps / max_time_step_ps)
        nt <<= 1
    end
    return nt
end

function _minimum_positive_frequency_window_ps(wavelength_m, nt)
    f0_thz = 2.99792458e8 / wavelength_m / 1e12
    return nt / (2 * f0_thz)
end

function _minimum_carrier_margin_window_ps(wavelength_m, nt, minimum_frequency_fraction)
    return _minimum_positive_frequency_window_ps(wavelength_m, nt) /
           (1 - minimum_frequency_fraction)
end

function _safe_carrier_margin_window_ps(
    wavelength_m,
    nt,
    minimum_frequency_fraction,
    max_time_step_ps,
)
    minimum = _minimum_carrier_margin_window_ps(
        wavelength_m, nt, minimum_frequency_fraction)
    rounded = (floor(Int, minimum * 1000) + 1) / 1000
    return rounded / nt <= max_time_step_ps ? rounded : nextfloat(minimum)
end

"""
    resolve_sampling_grid(grid; wavelength_m=1550e-9,
                          minimum_time_window_ps=0,
                          max_time_step_ps=0.0105,
                          minimum_frequency_fraction=0.1)

Resolve FFT sampling constraints without building a propagation problem. Exact
grids are only validated. Auto grids expand the window and sample count to keep
the lowest absolute frequency at least `minimum_frequency_fraction` of the
carrier and the temporal step no larger than `max_time_step_ps`.
"""
function resolve_sampling_grid(
    grid::Grid;
    wavelength_m::Real=1550e-9,
    minimum_time_window_ps::Real=0.0,
    max_time_step_ps::Real=0.0105,
    minimum_frequency_fraction::Real=0.1,
)
    nt = Int(grid.nt)
    time_window_ps = Float64(grid.time_window_ps)
    nt >= 4 && ispow2(nt) || throw(ArgumentError(
        "grid nt must be a power of two ≥ 4"))
    isfinite(time_window_ps) && time_window_ps > 0 || throw(ArgumentError(
        "grid time_window_ps must be positive and finite"))
    isfinite(wavelength_m) && wavelength_m > 0 || throw(ArgumentError(
        "wavelength_m must be positive and finite"))
    isfinite(minimum_time_window_ps) && minimum_time_window_ps >= 0 ||
        throw(ArgumentError("minimum_time_window_ps must be nonnegative and finite"))
    isfinite(max_time_step_ps) && max_time_step_ps > 0 || throw(ArgumentError(
        "max_time_step_ps must be positive and finite"))
    isfinite(minimum_frequency_fraction) && 0 < minimum_frequency_fraction < 1 ||
        throw(ArgumentError("minimum_frequency_fraction must lie in (0, 1)"))

    if grid.policy in (:exact, :fixed)
        _validate_positive_frequency_grid(wavelength_m, nt, time_window_ps)
        return Grid(nt=nt, time_window_ps=time_window_ps, policy=:exact)
    elseif grid.policy != :auto_if_undersized
        throw(ArgumentError("unsupported grid policy `$(grid.policy)`"))
    end

    minimum_step_ps = _minimum_positive_frequency_window_ps(wavelength_m, 1) /
                      (1 - minimum_frequency_fraction)
    max_time_step_ps > minimum_step_ps || throw(ArgumentError(
        "auto grid constraints are incompatible at wavelength_m=$(wavelength_m): " *
        "max_time_step_ps must exceed $(minimum_step_ps) ps to preserve the declared carrier-frequency margin"))

    time_window_ps = max(time_window_ps, minimum_time_window_ps)
    nt = max(nt, _nt_for_window_ps(time_window_ps;
                                   max_time_step_ps=max_time_step_ps))
    if time_window_ps <= _minimum_carrier_margin_window_ps(
            wavelength_m, nt, minimum_frequency_fraction)
        time_window_ps = _safe_carrier_margin_window_ps(
            wavelength_m, nt, minimum_frequency_fraction, max_time_step_ps)
    end
    time_window_ps / nt <= max_time_step_ps || error(
        "internal grid resolver error: temporal step exceeds the declared maximum")
    _validate_positive_frequency_grid(wavelength_m, nt, time_window_ps)
    return Grid(nt=nt, time_window_ps=time_window_ps, policy=:exact)
end

function _resolved_grid(grid::Grid, fiber::Fiber, pulse::Pulse, preset, wavelength_m)
    recommended = grid.policy == :auto_if_undersized ?
        _recommended_time_window_ps(
            fiber.length_m,
            pulse,
            preset.gamma,
            preset.betas[1],
            fiber.power_w,
        ) : 0.0
    resolved = resolve_sampling_grid(
        grid;
        wavelength_m=wavelength_m,
        minimum_time_window_ps=recommended,
    )
    return resolved.nt, resolved.time_window_ps
end

"""
    resolve_grid(fiber, pulse=Pulse(), grid=Grid(); wavelength_m=1550e-9)

Resolve a single-mode grid request without running propagation. The returned
grid is exact and satisfies both the declared auto-sizing policy and the
positive absolute-frequency invariant used by the numerical backend.
"""
function resolve_grid(fiber::Fiber, pulse::Pulse=Pulse(), grid::Grid=Grid();
                      wavelength_m::Real=1550e-9)
    _validate_package_inputs(fiber, pulse, wavelength_m)
    fiber.regime == :single_mode || throw(ArgumentError(
        "resolve_grid currently supports fiber.regime = :single_mode"))
    preset = _single_mode_preset(fiber.preset)
    nt, time_window_ps = _resolved_grid(
        grid, fiber, pulse, preset, Float64(wavelength_m))
    return Grid(nt=nt, time_window_ps=time_window_ps, policy=:exact)
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

    active = findall(>(0), totals)
    isempty(active) && throw(ArgumentError(
        "worst-mode cost requires a nonzero-energy mode"))
    ratio_max = maximum(@view ratios[active])
    shifted = tau .* (@view(ratios[active]) .- ratio_max)
    denominator = sum(exp.(shifted))
    cost = ratio_max + (log(denominator) - log(length(active))) / tau
    weights = exp.(shifted) ./ denominator

    terminal = zeros(ComplexF64, size(uωf))
    for (active_index, mode) in enumerate(active)
        u_mode = @view uωf[:, mode]
        terminal[:, mode] .= weights[active_index] .* u_mode .* (band_mask .- ratios[mode]) ./ totals[mode]
    end
    0 <= cost <= 1 || throw(ArgumentError(
        "worst-mode smooth proxy left the [0,1] leakage scale"))
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
    temporal = fft(uωf, 1)
    total = sum(abs2, temporal)
    total > 0 || throw(ArgumentError("field must have nonzero temporal energy"))
    half_window = max(sim["Δt"] * nt / 2, eps(Float64))
    t = ((collect(0:nt-1) .- floor(Int, nt / 2)) .* sim["Δt"]) ./ half_window
    weights = reshape(t .^ 2, nt, 1)
    cost = sum(weights .* abs2.(temporal)) / total
    terminal_t = temporal .* (weights .- cost) ./ total
    terminal = nt .* ifft(terminal_t, 1)
    return Float64(cost), terminal
end

function _maybe_log_cost(cost::Float64, terminal, log_cost::Bool)
    log_cost || return cost, terminal
    floor = 1e-15
    scaled_cost = 10.0 * log10(max(cost, floor))
    scale = cost <= floor ? 0.0 : 10.0 / (log(10.0) * cost)
    return scaled_cost, scale .* terminal
end
