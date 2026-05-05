"""
Device-agnostic SLM replay helpers.

This layer converts an ideal simulated spectral phase into the phase a generic
pixelated SLM profile can actually represent, then reconstructs that loaded
phase on the original simulation frequency grid. It intentionally avoids vendor
file formats; vendor adapters should consume the replay bundle produced here.
"""

if !(@isdefined _SLM_REPLAY_JL_LOADED)
const _SLM_REPLAY_JL_LOADED = true

using Dates
using JSON3
using FiberLab
using TOML

const SLM_REPLAY_SCHEMA_VERSION = "1.0"

_norm_symbol(x) = Symbol(replace(lowercase(String(x)), "-" => "_"))

function _require_finite(x::Real, label::AbstractString)
    isfinite(Float64(x)) || throw(ArgumentError("$label must be finite"))
    return Float64(x)
end

function _require_positive_int(x, label::AbstractString)
    value = Int(x)
    value > 0 || throw(ArgumentError("$label must be positive, got $value"))
    return value
end

function _phase_range_bounds(range::Symbol)
    range == :zero_to_2pi && return (0.0, 2pi)
    range == :minus_pi_to_pi && return (-pi, pi)
    throw(ArgumentError("unsupported phase range `$range`; expected zero_to_2pi or minus_pi_to_pi"))
end

function _normalize_phase_range(x)
    s = _norm_symbol(x)
    s == Symbol("0_to_2pi") && return :zero_to_2pi
    s == :zero_to_2pi && return :zero_to_2pi
    s == :minus_pi_to_pi && return :minus_pi_to_pi
    throw(ArgumentError("unsupported phase range `$x`"))
end

"""
    slm_replay_profile(; kwargs...) -> NamedTuple

Build a device-agnostic replay profile. This is useful for tests and for
programmatic callers; persisted profiles should use `load_slm_replay_profile`.
"""
function slm_replay_profile(;
    profile_id::AbstractString,
    kind::AbstractString = "spectral_phase_slm",
    vendor::AbstractString = "generic",
    device_model::AbstractString = "abstract",
    axis::AbstractString = "frequency",
    n_pixels::Integer,
    active_min_THz::Real,
    active_max_THz::Real,
    interpolation::AbstractString = "linear",
    outside_active_policy::AbstractString = "zero_phase",
    phase_units::AbstractString = "rad",
    phase_range = "0_to_2pi",
    wrap::Bool = true,
    bit_depth::Integer = 10,
    quantize::Bool = true,
    wavelength_to_pixel::AbstractString = "none",
    phase_lut::AbstractString = "none",
    wavefront_correction::AbstractString = "none",
    polarization::AbstractString = "assumed_aligned",
    smoothing_kernel_pixels::Integer = 0,
    crosstalk_kernel::AbstractString = "none",
    require_replay_simulation::Bool = true,
    max_allowed_replay_loss_dB::Real = 6.0,
)
    n = _require_positive_int(n_pixels, "n_pixels")
    bit_depth_i = _require_positive_int(bit_depth, "bit_depth")
    active_min = _require_finite(active_min_THz, "active_min_THz")
    active_max = _require_finite(active_max_THz, "active_max_THz")
    active_min < active_max || throw(ArgumentError("active_min_THz must be < active_max_THz"))
    smoothing = Int(smoothing_kernel_pixels)
    smoothing >= 0 || throw(ArgumentError("smoothing_kernel_pixels must be nonnegative"))

    interp = _norm_symbol(interpolation)
    interp in (:linear, :nearest) || throw(ArgumentError("interpolation must be `linear` or `nearest`"))
    outside = _norm_symbol(outside_active_policy)
    outside in (:zero_phase, :preserve_ideal) || throw(ArgumentError(
        "outside_active_policy must be `zero_phase` or `preserve_ideal`"))
    phase_units == "rad" || throw(ArgumentError("only phase units `rad` are supported"))

    return (
        schema_version = SLM_REPLAY_SCHEMA_VERSION,
        profile_id = String(profile_id),
        kind = String(kind),
        vendor = String(vendor),
        device_model = String(device_model),
        pixel_grid = (
            axis = _norm_symbol(axis),
            n_pixels = n,
            active_min_THz = active_min,
            active_max_THz = active_max,
            interpolation = interp,
            outside_active_policy = outside,
        ),
        phase = (
            units = String(phase_units),
            range = _normalize_phase_range(phase_range),
            wrap = Bool(wrap),
            bit_depth = bit_depth_i,
            quantize = Bool(quantize),
        ),
        calibration = (
            wavelength_to_pixel = String(wavelength_to_pixel),
            phase_lut = String(phase_lut),
            wavefront_correction = String(wavefront_correction),
            polarization = String(polarization),
        ),
        replay = (
            smoothing_kernel_pixels = smoothing,
            crosstalk_kernel = String(crosstalk_kernel),
            require_replay_simulation = Bool(require_replay_simulation),
            max_allowed_replay_loss_dB = _require_finite(max_allowed_replay_loss_dB,
                "max_allowed_replay_loss_dB"),
        ),
    )
end

function load_slm_replay_profile(path::AbstractString)
    parsed = TOML.parsefile(path)
    pixel = parsed["pixel_grid"]
    phase = parsed["phase"]
    calib = get(parsed, "calibration", Dict{String,Any}())
    replay = get(parsed, "replay", Dict{String,Any}())

    return slm_replay_profile(;
        profile_id = parsed["profile_id"],
        kind = get(parsed, "kind", "spectral_phase_slm"),
        vendor = get(parsed, "vendor", "generic"),
        device_model = get(parsed, "device_model", "abstract"),
        axis = get(pixel, "axis", "frequency"),
        n_pixels = pixel["n_pixels"],
        active_min_THz = pixel["active_min_THz"],
        active_max_THz = pixel["active_max_THz"],
        interpolation = get(pixel, "interpolation", "linear"),
        outside_active_policy = get(pixel, "outside_active_policy", "zero_phase"),
        phase_units = get(phase, "units", "rad"),
        phase_range = get(phase, "range", "0_to_2pi"),
        wrap = Bool(get(phase, "wrap", true)),
        bit_depth = get(phase, "bit_depth", 10),
        quantize = Bool(get(phase, "quantize", true)),
        wavelength_to_pixel = get(calib, "wavelength_to_pixel", "none"),
        phase_lut = get(calib, "phase_lut", "none"),
        wavefront_correction = get(calib, "wavefront_correction", "none"),
        polarization = get(calib, "polarization", "assumed_aligned"),
        smoothing_kernel_pixels = get(replay, "smoothing_kernel_pixels", 0),
        crosstalk_kernel = get(replay, "crosstalk_kernel", "none"),
        require_replay_simulation = Bool(get(replay, "require_replay_simulation", true)),
        max_allowed_replay_loss_dB = get(replay, "max_allowed_replay_loss_dB", 6.0),
    )
end

function unwrap_phase(phi::AbstractVector{<:Real})
    out = collect(Float64, phi)
    for i in 2:length(out)
        delta = out[i] - out[i - 1]
        if delta > pi
            out[i:end] .-= 2pi
        elseif delta < -pi
            out[i:end] .+= 2pi
        end
    end
    return out
end

function _interp_linear(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, xq::Real)
    length(x) == length(y) || throw(ArgumentError("x and y lengths must match"))
    isempty(x) && throw(ArgumentError("cannot interpolate empty data"))
    xq <= x[1] && return Float64(y[1])
    xq >= x[end] && return Float64(y[end])
    hi = searchsortedfirst(x, xq)
    lo = hi - 1
    t = (xq - x[lo]) / max(x[hi] - x[lo], eps(Float64))
    return (1 - t) * y[lo] + t * y[hi]
end

function _interp_nearest(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, xq::Real)
    idx = argmin(abs.(x .- xq))
    return Float64(y[idx])
end

function _interp_values(x, y, xq, mode::Symbol)
    if mode == :linear
        return [_interp_linear(x, y, xi) for xi in xq]
    elseif mode == :nearest
        return [_interp_nearest(x, y, xi) for xi in xq]
    end
    throw(ArgumentError("unsupported interpolation mode `$mode`"))
end

function _smooth_pixels(values::Vector{Float64}, width::Int)
    width <= 1 && return copy(values)
    n = length(values)
    out = similar(values)
    half = width ÷ 2
    for i in 1:n
        lo = max(1, i - half)
        hi = min(n, i + half)
        out[i] = sum(@view values[lo:hi]) / (hi - lo + 1)
    end
    return out
end

function _wrap_phase_value(x::Real, range::Symbol)
    lo, hi = _phase_range_bounds(range)
    span = hi - lo
    return mod(Float64(x) - lo, span) + lo
end

function _hardware_phase_values(values::Vector{Float64}, profile)
    out = copy(values)
    if profile.phase.wrap
        out .= _wrap_phase_value.(out, profile.phase.range)
    end
    if profile.phase.quantize
        lo, hi = _phase_range_bounds(profile.phase.range)
        span = hi - lo
        levels = 2 ^ profile.phase.bit_depth
        step = span / levels
        out .= mod.(round.((out .- lo) ./ step) .* step, span) .+ lo
    end
    return out
end

function _pixel_centers(active_min::Real, active_max::Real, n_pixels::Int)
    n_pixels == 1 && return [0.5 * (active_min + active_max)]
    return collect(range(active_min, active_max; length=n_pixels))
end

"""
    replay_slm_phase(phi, rel_f_THz, profile) -> NamedTuple

Replay `phi` through the generic SLM profile and reconstruct the loaded phase on
the original simulation frequency axis. `rel_f_THz` must be the frequency-offset
axis in the same storage order as `phi`.
"""
function replay_slm_phase(phi::AbstractVector{<:Real},
                          rel_f_THz::AbstractVector{<:Real},
                          profile)
    length(phi) == length(rel_f_THz) || throw(ArgumentError(
        "phi length $(length(phi)) must match frequency axis length $(length(rel_f_THz))"))
    profile.pixel_grid.axis == :frequency || throw(ArgumentError(
        "only frequency-axis SLM replay is currently supported"))

    active = findall(f -> profile.pixel_grid.active_min_THz <= f <= profile.pixel_grid.active_max_THz,
        rel_f_THz)
    isempty(active) && throw(ArgumentError("SLM active band does not overlap the simulation frequency axis"))

    sorted_active = sort(active; by=i -> rel_f_THz[i])
    x_active = Float64[rel_f_THz[i] for i in sorted_active]
    phi_active = unwrap_phase(Float64[phi[i] for i in sorted_active])
    centers = _pixel_centers(profile.pixel_grid.active_min_THz,
        profile.pixel_grid.active_max_THz, profile.pixel_grid.n_pixels)

    sampled = _interp_values(x_active, phi_active, centers, profile.pixel_grid.interpolation)
    sampled = _smooth_pixels(sampled, profile.replay.smoothing_kernel_pixels)
    pixel_phase = _hardware_phase_values(sampled, profile)

    replay_sorted = _interp_values(centers, pixel_phase, x_active, profile.pixel_grid.interpolation)
    phi_replayed = if profile.pixel_grid.outside_active_policy == :preserve_ideal
        collect(Float64, phi)
    else
        zeros(Float64, length(phi))
    end
    for (dst, value) in zip(sorted_active, replay_sorted)
        phi_replayed[dst] = value
    end

    return (
        schema_version = SLM_REPLAY_SCHEMA_VERSION,
        profile_id = profile.profile_id,
        profile = profile,
        phi_ideal = collect(Float64, phi),
        rel_f_THz = collect(Float64, rel_f_THz),
        phi_replayed = phi_replayed,
        active_indices = active,
        sorted_active_indices = sorted_active,
        pixel_centers_THz = centers,
        pixel_phase_rad = pixel_phase,
        pixel_phase_sampled_rad = sampled,
    )
end

function slm_replay_survival_status(ideal_J_dB::Real, replayed_J_dB::Real, profile)
    loss = Float64(replayed_J_dB) - Float64(ideal_J_dB)
    threshold = profile.replay.max_allowed_replay_loss_dB
    return (
        pass = isfinite(loss) && loss <= threshold,
        ideal_J_dB = Float64(ideal_J_dB),
        replayed_J_dB = Float64(replayed_J_dB),
        replay_loss_dB = loss,
        max_allowed_replay_loss_dB = threshold,
    )
end

function _csv_value(x)
    return x isa Bool ? (x ? "true" : "false") : string(Float64(x))
end

function _write_replayed_phase_csv(path::AbstractString, replay)
    open(path, "w") do io
        println(io, "index,frequency_offset_THz,phase_ideal_rad,phase_replayed_rad,active")
        active_set = Set(replay.active_indices)
        for i in eachindex(replay.phi_ideal)
            println(io, join((
                string(i),
                _csv_value(replay.rel_f_THz[i]),
                _csv_value(replay.phi_ideal[i]),
                _csv_value(replay.phi_replayed[i]),
                i in active_set ? "true" : "false",
            ), ","))
        end
    end
    return path
end

function _write_pixel_phase_csv(path::AbstractString, replay)
    open(path, "w") do io
        println(io, "pixel_index,frequency_center_THz,phase_sampled_rad,phase_loaded_rad")
        for i in eachindex(replay.pixel_centers_THz)
            println(io, join((
                string(i),
                _csv_value(replay.pixel_centers_THz[i]),
                _csv_value(replay.pixel_phase_sampled_rad[i]),
                _csv_value(replay.pixel_phase_rad[i]),
            ), ","))
        end
    end
    return path
end

function _profile_metadata(profile)
    return Dict{String,Any}(
        "schema_version" => profile.schema_version,
        "profile_id" => profile.profile_id,
        "kind" => profile.kind,
        "vendor" => profile.vendor,
        "device_model" => profile.device_model,
        "pixel_grid" => Dict{String,Any}(
            "axis" => String(profile.pixel_grid.axis),
            "n_pixels" => profile.pixel_grid.n_pixels,
            "active_min_THz" => profile.pixel_grid.active_min_THz,
            "active_max_THz" => profile.pixel_grid.active_max_THz,
            "interpolation" => String(profile.pixel_grid.interpolation),
            "outside_active_policy" => String(profile.pixel_grid.outside_active_policy),
        ),
        "phase" => Dict{String,Any}(
            "units" => profile.phase.units,
            "range" => String(profile.phase.range),
            "wrap" => profile.phase.wrap,
            "bit_depth" => profile.phase.bit_depth,
            "quantize" => profile.phase.quantize,
        ),
        "calibration" => Dict{String,Any}(
            "wavelength_to_pixel" => profile.calibration.wavelength_to_pixel,
            "phase_lut" => profile.calibration.phase_lut,
            "wavefront_correction" => profile.calibration.wavefront_correction,
            "polarization" => profile.calibration.polarization,
        ),
        "replay" => Dict{String,Any}(
            "smoothing_kernel_pixels" => profile.replay.smoothing_kernel_pixels,
            "crosstalk_kernel" => profile.replay.crosstalk_kernel,
            "require_replay_simulation" => profile.replay.require_replay_simulation,
            "max_allowed_replay_loss_dB" => profile.replay.max_allowed_replay_loss_dB,
        ),
    )
end

_json_number_or_nothing(x::Real) = isfinite(Float64(x)) ? Float64(x) : nothing

"""
    write_slm_replay_bundle(output_dir, replay; kwargs...) -> NamedTuple

Write a replay bundle containing the reconstructed simulation-axis phase, the
pixel-axis phase, and JSON metadata. This is still device-agnostic; vendor
adapters should consume this bundle rather than the optimizer artifact directly.
"""
function write_slm_replay_bundle(output_dir::AbstractString,
                                 replay;
                                 source_artifact::AbstractString = "",
                                 ideal_J_dB::Real = NaN,
                                 replayed_J_dB::Real = NaN)
    mkpath(output_dir)
    replay_csv = joinpath(output_dir, "phase_profile_replayed.csv")
    pixel_csv = joinpath(output_dir, "pixel_phase_profile.csv")
    metadata_json = joinpath(output_dir, "slm_replay_metadata.json")

    _write_replayed_phase_csv(replay_csv, replay)
    _write_pixel_phase_csv(pixel_csv, replay)

    survival = if isfinite(Float64(ideal_J_dB)) && isfinite(Float64(replayed_J_dB))
        slm_replay_survival_status(ideal_J_dB, replayed_J_dB, replay.profile)
    else
        (
            pass = false,
            ideal_J_dB = Float64(ideal_J_dB),
            replayed_J_dB = Float64(replayed_J_dB),
            replay_loss_dB = NaN,
            max_allowed_replay_loss_dB = replay.profile.replay.max_allowed_replay_loss_dB,
        )
    end

    metadata = Dict{String,Any}(
        "schema_version" => SLM_REPLAY_SCHEMA_VERSION,
        "generated_utc" => Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SSZ"),
        "profile_id" => replay.profile_id,
        "source_artifact" => String(source_artifact),
        "replayed_phase_csv" => basename(replay_csv),
        "pixel_phase_csv" => basename(pixel_csv),
        "n_simulation_points" => length(replay.phi_replayed),
        "n_active_simulation_points" => length(replay.active_indices),
        "n_pixels" => length(replay.pixel_phase_rad),
        "survival" => Dict{String,Any}(
            "pass" => survival.pass,
            "ideal_J_dB" => _json_number_or_nothing(survival.ideal_J_dB),
            "replayed_J_dB" => _json_number_or_nothing(survival.replayed_J_dB),
            "replay_loss_dB" => _json_number_or_nothing(survival.replay_loss_dB),
            "max_allowed_replay_loss_dB" => survival.max_allowed_replay_loss_dB,
        ),
        "profile" => _profile_metadata(replay.profile),
    )
    write_json_file(metadata_json, metadata)

    return (
        output_dir = output_dir,
        replayed_phase_csv = replay_csv,
        pixel_phase_csv = pixel_csv,
        metadata_json = metadata_json,
        survival = survival,
    )
end

end # include guard
