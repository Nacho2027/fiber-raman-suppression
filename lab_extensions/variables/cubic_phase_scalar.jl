"""
Executable scalar phase variable scaffold for `cubic_phase_scalar`.

This default template maps one bounded scalar to a normalized quadratic
spectral phase basis. Replace the basis construction to define your own control
while keeping the returned `(phase, amplitude, scalar_controls, diagnostics)`
contract.
"""

using FFTW

function _cubic_phase_scalar_basis(sim, Nt::Int, M::Int)
    frequency = FFTW.fftfreq(Nt, 1 / sim["Δt"])
    denom = max(maximum(abs.(frequency)), eps(Float64))
    basis = (frequency ./ denom) .^ 2
    basis .-= sum(basis) / length(basis)
    basis ./= max(maximum(abs.(basis)), eps(Float64))
    return repeat(reshape(basis, Nt, 1), 1, M)
end

function build_cubic_phase_scalar_control(context)
    coeff = Float64(context.scalar_value)
    basis = _cubic_phase_scalar_basis(context.sim, context.Nt, context.M)
    return (
        phase = coeff .* basis,
        amplitude = ones(context.Nt, context.M),
        scalar_controls = Dict("cubic_phase_scalar" => coeff),
        diagnostics = Dict(
            Symbol("cubic_phase_scalar") => coeff,
            Symbol("cubic_phase_scalar_basis_max_abs") => Float64(maximum(abs.(basis))),
        ),
    )
end

function project_cubic_phase_scalar_control(value)
    return Float64(value)
end
