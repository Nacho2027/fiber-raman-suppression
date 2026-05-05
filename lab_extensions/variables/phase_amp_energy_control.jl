"""
Executable vector control scaffold for `phase_amp_energy_control`.

This broader control-extension template maps a bounded coefficient vector into
phase, amplitude, and an optional energy scale. It is the first-class pattern
for non-phase-only exploratory controls: edit the basis construction and
control mapping, not optimizer internals.
"""

using FFTW

function _phase_amp_energy_control_normalized_frequency(sim, Nt::Int)
    frequency = FFTW.fftfreq(Nt, 1 / sim["Δt"])
    denom = max(maximum(abs.(frequency)), eps(Float64))
    return frequency ./ denom
end

function build_phase_amp_energy_control_control(context)
    values = Float64.(context.control_values)
    length(values) == 3 || throw(ArgumentError("phase_amp_energy_control expects 3 coefficients"))
    normalized_frequency = _phase_amp_energy_control_normalized_frequency(context.sim, context.Nt)
    phase_basis = normalized_frequency .^ 2
    phase_basis .-= sum(phase_basis) / length(phase_basis)
    phase_basis ./= max(maximum(abs.(phase_basis)), eps(Float64))

    phase_coeff = values[1]
    amplitude_tilt = length(values) >= 2 ? values[2] : 0.0
    energy_log_scale = length(values) >= 3 ? values[3] : 0.0

    phase = phase_coeff .* repeat(reshape(phase_basis, context.Nt, 1), 1, context.M)
    amplitude_1d = clamp.(1 .+ 0.05 .* tanh(amplitude_tilt) .* normalized_frequency, 0.05, 2.0)
    amplitude = repeat(reshape(amplitude_1d, context.Nt, 1), 1, context.M)
    energy_scale = exp(clamp(energy_log_scale, -2.0, 2.0))

    controls = Dict{String,Float64}(
        "phase_amp_energy_control_phase_coeff" => phase_coeff,
        "phase_amp_energy_control_amplitude_tilt" => amplitude_tilt,
        "phase_amp_energy_control_energy_log_scale" => energy_log_scale,
        "phase_amp_energy_control_energy_scale" => energy_scale,
    )

    return (
        phase = phase,
        amplitude = amplitude .* sqrt(energy_scale),
        energy_scale = energy_scale,
        scalar_controls = controls,
        diagnostics = Dict(
            Symbol("phase_amp_energy_control") => maximum(abs.(phase)),
            Symbol("phase_amp_energy_control_amplitude_min") => Float64(minimum(amplitude)),
            Symbol("phase_amp_energy_control_amplitude_max") => Float64(maximum(amplitude)),
            Symbol("phase_amp_energy_control_energy_scale") => energy_scale,
            Symbol("phase_amp_energy_control_dimension") => 3,
        ),
    )
end

function project_phase_amp_energy_control_control(values)
    return Float64.(values)
end
