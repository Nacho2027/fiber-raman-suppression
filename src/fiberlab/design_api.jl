"""
    initial_coordinates(control)

Return the neutral optimizer coordinates for a control map. For built-in maps
this decodes to zero phase, unit amplitude, and unit positive scalars.
"""
initial_coordinates(control::AbstractControlMap) = zeros(dimension(control))

"""
    controls(map...)

Build a `ControlSpace` from named control maps without repeating each name at
the call site.
"""
function controls(maps::AbstractControlMap...)
    isempty(maps) && throw(ArgumentError("controls requires at least one control map"))
    return ControlSpace((map.name => map for map in maps)...)
end

"""
    polynomial_basis(problem, powers=0:3)

Create normalized polynomial basis columns over the simulation frequency grid.
The rows are in solver order, so the basis can be passed directly to phase or
amplitude controls.
"""
function polynomial_basis(problem::FiberFieldProblem, powers=0:3)
    p = Tuple(Int(power) for power in powers)
    isempty(p) && throw(ArgumentError("polynomial_basis requires at least one power"))
    nt = sample_count(problem)
    f = FFTW.fftfreq(nt, 1 / problem.sim["Δt"])
    scale = maximum(abs.(f))
    scale > 0 || throw(ArgumentError("polynomial_basis requires a nonzero frequency grid"))
    s = f ./ scale
    basis = Matrix{Float64}(undef, nt, length(p))
    for (j, power) in enumerate(p)
        power >= 0 || throw(ArgumentError("polynomial powers must be non-negative"))
        column = power == 0 ? ones(nt) : s .^ power
        power > 0 && (column .-= sum(column) / length(column))
        norm_inf = maximum(abs.(column))
        norm_inf > 0 && (column ./= norm_inf)
        basis[:, j] .= column
    end
    return basis
end

"""
    fourier_basis(problem, harmonics=8)

Create a smooth real Fourier basis over the simulation frequency grid. The
first column is a constant offset, followed by sine/cosine pairs for each
harmonic. Columns are normalized so bounded profile controls have predictable
coordinate scales.
"""
function fourier_basis(problem::FiberFieldProblem, harmonics::Integer=8)
    h = Int(harmonics)
    h >= 0 || throw(ArgumentError("fourier_basis harmonics must be non-negative"))
    nt = sample_count(problem)
    f = FFTW.fftfreq(nt, 1 / problem.sim["Δt"])
    scale = maximum(abs.(f))
    scale > 0 || throw(ArgumentError("fourier_basis requires a nonzero frequency grid"))
    s = f ./ scale
    basis = Matrix{Float64}(undef, nt, 1 + 2h)
    basis[:, 1] .= 1.0
    col = 2
    for k in 1:h
        for values in (sinpi.(k .* s), cospi.(k .* s))
            centered = values .- sum(values) / length(values)
            norm_inf = maximum(abs.(centered))
            norm_inf > 0 && (centered ./= norm_inf)
            basis[:, col] .= centered
            col += 1
        end
    end
    return basis
end

"""
    phase_control(problem; basis=nothing, bounds=nothing)

Construct a phase control. With no basis this is a full-grid phase. With a
basis matrix this is a reduced phase control. With `bounds=(lo, hi)` the phase
profile is bounded smoothly through a tanh parameterization.
"""
function phase_control(problem::FiberFieldProblem;
                       basis=nothing,
                       bounds=nothing,
                       name::Symbol=:phase)
    if basis === nothing
        return bounds === nothing ?
            FullGridPhase(problem; name = name) :
            bounded_full_grid_control(
                name,
                sample_count(problem);
                lower = first(bounds),
                upper = last(bounds),
                units = "rad",
                figure_hooks = control_contract(:phase).figure_hooks,
            )
    end
    basis_matrix = Matrix{Float64}(basis)
    return bounds === nothing ?
        PhaseBasis(basis_matrix; name = name) :
        bounded_profile_control(
            name,
            basis_matrix;
            lower = first(bounds),
            upper = last(bounds),
            units = "rad",
            figure_hooks = control_contract(:phase).figure_hooks,
        )
end

function bounded_full_grid_control(name::Symbol,
                                   n::Integer;
                                   lower::Real,
                                   upper::Real,
                                   units::AbstractString="",
                                   figure_hooks=())
    nt = Int(n)
    nt > 0 || throw(ArgumentError("bounded_full_grid_control requires a positive dimension"))
    lo = Float64(lower)
    hi = Float64(upper)
    isfinite(lo) && isfinite(hi) && lo < hi || throw(ArgumentError(
        "bounded_full_grid_control requires finite lower < upper bounds"))
    midpoint = (lo + hi) / 2
    radius = (hi - lo) / 2
    return ControlMap(
        name;
        dimension = nt,
        decode = (x, context) -> midpoint .+ radius .* tanh.(Float64.(collect(x))),
        pullback = (physical_gradient, context) ->
            radius .* Float64.(collect(physical_gradient)) .* (1 .- tanh.(context.coordinates).^2),
        figure_hooks = figure_hooks,
        units = units,
    )
end

"""
    amplitude_control(problem; basis=polynomial_basis(problem, 0:2), bounds=(0.8, 1.2))

Construct a bounded relative-amplitude profile control. The default is a small,
smooth, positive profile family; pass any basis matrix or explicit bounds for a
different physical parameterization.
"""
function amplitude_control(problem::FiberFieldProblem;
                           basis=polynomial_basis(problem, 0:2),
                           bounds=(0.8, 1.2),
                           name::Symbol=:amplitude)
    return bounded_profile_control(
        name,
        Matrix{Float64}(basis);
        lower = first(bounds),
        upper = last(bounds),
        units = "relative field amplitude",
        figure_hooks = control_contract(:amplitude).figure_hooks,
    )
end

"""
    energy_control(; name=:energy)

Construct a positive scalar control for relative pulse energy.
"""
energy_control(; name::Symbol=:energy) =
    PositiveScalar(
        name;
        units = "relative pulse energy",
        figure_hooks = control_contract(:energy).figure_hooks,
    )

"""
    bounded_profile_control(name, basis; lower, upper)

Generic smooth bounded profile map. The decoded profile is the midpoint plus a
tanh-limited excursion, and the pullback applies the exact local derivative.
"""
function bounded_profile_control(name::Symbol,
                                 basis::AbstractMatrix{<:Real};
                                 lower::Real,
                                 upper::Real,
                                 units::AbstractString="",
                                 figure_hooks=())
    lo = Float64(lower)
    hi = Float64(upper)
    isfinite(lo) && isfinite(hi) && lo < hi || throw(ArgumentError(
        "bounded_profile_control requires finite lower < upper bounds"))
    B = Matrix{Float64}(basis)
    rows, cols = size(B)
    rows > 0 && cols > 0 || throw(ArgumentError(
        "bounded_profile_control requires a non-empty basis matrix"))
    midpoint = (lo + hi) / 2
    radius = (hi - lo) / 2
    return ControlMap(
        name;
        dimension = cols,
        decode = (x, context) -> midpoint .+ radius .* tanh.(B * x),
        pullback = (physical_gradient, context) -> begin
            z = B * context.coordinates
            radius .* (transpose(B) * (Float64.(collect(physical_gradient)) .* (1 .- tanh.(z).^2)))
        end,
        figure_hooks = figure_hooks,
        units = units,
    )
end
