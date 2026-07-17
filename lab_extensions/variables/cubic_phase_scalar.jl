"""
Executable scalar phase variable scaffold for `cubic_phase_scalar`.

Maps one scalar to a normalized cubic spectral-phase basis. The unpaired
Nyquist bin is set to zero so opposite represented frequencies remain odd.
"""

using FFTW

function _cubic_phase_scalar_basis(sim, Nt::Int, M::Int)
    frequency = FFTW.fftfreq(Nt, 1 / sim["Δt"])
    denom = max(maximum(abs.(frequency)), eps(Float64))
    basis = (frequency ./ denom) .^ 3
    iseven(Nt) && (basis[Nt ÷ 2 + 1] = 0.0)
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
