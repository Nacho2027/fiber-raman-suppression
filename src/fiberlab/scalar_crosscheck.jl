"""
Validation-only scalar RK4 interaction-picture propagation.

This deliberately does not call the production RHS or ODE setup. It reuses the
resolved physical inputs, grid, launch, scalar model form, and FFTW, so it checks
the propagation implementation but not input construction or model form.
"""
function _scalar_rk4_output(problem::FiberFieldProblem; steps)
    steps isa Integer && !(steps isa Bool) && steps > 0 || throw(ArgumentError(
        "steps must be a positive integer"))
    _validate_package_problem_snapshot(problem)
    mode_count(problem) == 1 || throw(ArgumentError(
        "the fixed-step propagation cross-check supports scalar problems only"))

    nt = sample_count(problem)
    size(problem.fiber["Dω"]) == (nt, 1) || throw(ArgumentError(
        "scalar dispersion must have size ($nt, 1)"))
    size(problem.fiber["γ"]) == (1, 1, 1, 1) || throw(ArgumentError(
        "scalar nonlinearity must have size (1, 1, 1, 1)"))
    length(problem.fiber["hRω"]) == nt || throw(ArgumentError(
        "Raman response must contain one value per frequency sample"))
    get(problem.fiber, "gain_parameters", 0.0) == 0.0 || throw(ArgumentError(
        "the fixed-step propagation cross-check does not support gain"))

    context = (
        dispersion = vec(Float64.(problem.fiber["Dω"])),
        gamma = Float64(only(problem.fiber["γ"])),
        raman = ComplexF64.(problem.fiber["hRω"]),
        kerr_fraction = Float64(problem.fiber["one_m_fR"]),
        shock = FFTW.fftshift(Float64.(problem.sim["ωs"])) ./
                Float64(problem.sim["ω0"]),
    )
    all(isfinite, context.dispersion) && isfinite(context.gamma) &&
        all(isfinite, context.raman) && isfinite(context.kerr_fraction) &&
        all(isfinite, context.shock) || throw(ArgumentError(
            "resolved scalar propagation inputs must be finite"))

    rhs(z, interaction_field) = begin
        lab_spectrum = cis.(context.dispersion .* z) .* interaction_field
        time_field = FFTW.fft(lab_spectrum)
        nonlinear_intensity = context.gamma .* abs2.(time_field)
        delayed_intensity = real.(FFTW.fftshift(FFTW.ifft(
            context.raman .* FFTW.fft(complex.(nonlinear_intensity)))))
        nonlinear_time = (context.kerr_fraction .* nonlinear_intensity .+
                          delayed_intensity) .* time_field
        nonlinear_spectrum = context.shock .* FFTW.ifft(nonlinear_time)
        1im .* cis.(-context.dispersion .* z) .* nonlinear_spectrum
    end

    length_m = Float64(problem.fiber["L"])
    step_m = length_m / steps
    interaction_field = vec(copy(problem.uω0))
    for index in 0:steps-1
        z = index * step_m
        k1 = rhs(z, interaction_field)
        k2 = rhs(z + step_m / 2, interaction_field .+ step_m / 2 .* k1)
        k3 = rhs(z + step_m / 2, interaction_field .+ step_m / 2 .* k2)
        k4 = rhs(z + step_m, interaction_field .+ step_m .* k3)
        interaction_field .+= step_m / 6 .* (k1 .+ 2k2 .+ 2k3 .+ k4)
    end
    output = reshape(
        cis.(context.dispersion .* length_m) .* interaction_field,
        nt,
        1,
    )
    all(isfinite, output) || error("fixed-step propagation produced non-finite fields")
    return output
end

"""Validate a positive, exactly doubling fixed-step refinement schedule."""
function _doubling_step_schedule(steps)
    schedule = collect(steps)
    length(schedule) >= 3 || throw(ArgumentError(
        "a convergence schedule requires at least three step counts"))
    all(step -> step isa Integer && !(step isa Bool) && step > 0, schedule) ||
        throw(ArgumentError("cross-check step counts must be positive integers"))
    all(schedule[index] == 2 * schedule[index - 1] for index in 2:length(schedule)) ||
        throw(ArgumentError("cross-check step counts must exactly double"))
    return Tuple(Int(step) for step in schedule)
end

"""
Return the energy-weighted frequency centroid in THz.

The field must use the problem's raw FFT frequency order. The grid spacing is
stored in ps, so `fftfreq` returns cycles/ps, numerically equal to THz.
"""
function _scalar_reference_centroid_thz(spectrum, problem::FiberFieldProblem)
    field = Matrix{ComplexF64}(spectrum)
    size(field) == (sample_count(problem), 1) || throw(ArgumentError(
        "reference centroid requires a scalar field on the problem grid"))
    all(isfinite, field) || throw(ArgumentError("reference field must be finite"))
    frequency = FFTW.fftfreq(sample_count(problem), 1 / Float64(problem.sim["Δt"]))
    bin_energy = vec(sum(abs2, field; dims = 2))
    total_energy = sum(bin_energy)
    total_energy > 0 || throw(ArgumentError("reference field must be nonzero"))
    return Float64(sum(frequency .* bin_energy) / total_energy)
end
