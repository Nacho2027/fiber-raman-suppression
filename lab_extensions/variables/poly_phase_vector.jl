"""
Executable vector phase variable scaffold for `poly_phase_vector`.

This default template maps a bounded coefficient vector to low-order normalized
spectral phase bases. Replace `_poly_phase_vector_basis` or the basis orders to
define your own multi-parameter control.
"""

using FFTW

function _poly_phase_vector_basis(sim, Nt::Int, M::Int, order::Int)
    frequency = FFTW.fftfreq(Nt, 1 / sim["Δt"])
    denom = max(maximum(abs.(frequency)), eps(Float64))
    basis = (frequency ./ denom) .^ order
    basis .-= sum(basis) / length(basis)
    basis ./= max(maximum(abs.(basis)), eps(Float64))
    return repeat(reshape(basis, Nt, 1), 1, M)
end

function build_poly_phase_vector_control(context)
    values = Float64.(context.control_values)
    length(values) == 2 || throw(ArgumentError("poly_phase_vector expects 2 coefficients"))
    phase = zeros(context.Nt, context.M)
    controls = Dict{String,Float64}()
    labels = ("quadratic", "cubic")
    for (i, value) in enumerate(values)
        phase .+= value .* _poly_phase_vector_basis(context.sim, context.Nt, context.M, i + 1)
        controls["poly_phase_vector_$(labels[i])"] = value
    end
    return (
        phase = phase,
        amplitude = ones(context.Nt, context.M),
        scalar_controls = controls,
        diagnostics = Dict(
            Symbol("poly_phase_vector") => maximum(abs.(phase)),
            Symbol("poly_phase_vector_dimension") => 2,
        ),
    )
end

function project_poly_phase_vector_control(values)
    return Float64.(values)
end
