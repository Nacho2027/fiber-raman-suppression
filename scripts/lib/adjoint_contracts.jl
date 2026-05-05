"""
Explicit adjoint-oriented contracts for research exploration controls/objectives.

This file starts with the smallest useful first-class contract: a reduced-basis
spectral phase control. It uses the existing full-grid phase adjoint gradient
and pulls that gradient back to optimizer coefficients.
"""

if !(@isdefined _ADJOINT_CONTRACTS_JL_LOADED)
const _ADJOINT_CONTRACTS_JL_LOADED = true

using FFTW
using LinearAlgebra

if !isdefined(Main, :cost_and_gradient)
    include(joinpath(@__DIR__, "raman_optimization.jl"))
end

abstract type AbstractFieldObjective end

struct ReducedPhaseControlMap
    name::Symbol
    orders::Tuple{Vararg{Int}}
end

struct FieldObjective <: AbstractFieldObjective
    kind::Symbol

    function FieldObjective(kind::Symbol=:raman_band)
        kind in (:raman_band, :raman_peak, :temporal_width) || throw(ArgumentError(
            "unsupported adjoint field objective `$kind`; supported: raman_band, raman_peak, temporal_width"))
        return new(kind)
    end
end

struct CustomFieldObjective <: AbstractFieldObjective
    kind::Symbol
    cost_adjoint::Function
    description::String
end

function CustomFieldObjective(kind::Symbol, cost_adjoint::Function; description::AbstractString="")
    kind == Symbol("") && throw(ArgumentError("custom adjoint field objective kind cannot be empty"))
    return CustomFieldObjective(kind, cost_adjoint, String(description))
end

function evaluate_objective(objective::FieldObjective, uωf, context)
    if objective.kind == :raman_band
        return spectral_band_cost(uωf, _context_value(context, :band_mask))
    elseif objective.kind == :raman_peak
        return spectral_peak_band_cost(uωf, _context_value(context, :band_mask))
    elseif objective.kind == :temporal_width
        return temporal_width_cost(uωf, _context_value(context, :sim))
    end
    throw(ArgumentError("unsupported adjoint field objective `$(objective.kind)`"))
end

function evaluate_objective(objective::CustomFieldObjective, uωf, context)
    result = objective.cost_adjoint(uωf, context)
    result isa Tuple && length(result) == 2 || throw(ArgumentError(
        "custom adjoint objective `$(objective.kind)` must return `(cost, terminal_adjoint)`"))
    J, λωL = result
    isfinite(Float64(J)) || throw(ArgumentError(
        "custom adjoint objective `$(objective.kind)` returned a non-finite cost"))
    size(λωL) == size(uωf) || throw(ArgumentError(
        "custom adjoint objective `$(objective.kind)` returned terminal adjoint shape $(size(λωL)); expected $(size(uωf))"))
    all(isfinite, real.(λωL)) && all(isfinite, imag.(λωL)) || throw(ArgumentError(
        "custom adjoint objective `$(objective.kind)` returned non-finite terminal adjoint values"))
    return Float64(J), λωL
end

function terminal_adjoint(objective::AbstractFieldObjective, uωf, context)
    _, λωL = evaluate_objective(objective, uωf, context)
    return λωL
end

function ReducedPhaseControlMap(; name::Symbol=:reduced_phase, orders=(2, 3))
    parsed_orders = Tuple(Int(order) for order in orders)
    isempty(parsed_orders) && throw(ArgumentError("ReducedPhaseControlMap requires at least one basis order"))
    any(<=(0), parsed_orders) && throw(ArgumentError("ReducedPhaseControlMap basis orders must be positive"))
    return ReducedPhaseControlMap(name, parsed_orders)
end

function _context_value(context, key::Symbol)
    hasproperty(context, key) && return getproperty(context, key)
    context isa AbstractDict && haskey(context, String(key)) && return context[String(key)]
    context isa AbstractDict && haskey(context, key) && return context[key]
    throw(ArgumentError("context is missing required field `$key`"))
end

function reduced_phase_basis(control::ReducedPhaseControlMap, sim, Nt::Int, M::Int)
    frequency = FFTW.fftfreq(Nt, 1 / sim["Δt"])
    denom = max(maximum(abs.(frequency)), eps(Float64))
    normalized = frequency ./ denom
    basis = zeros(Float64, Nt, M, length(control.orders))
    for (i, order) in enumerate(control.orders)
        column = normalized .^ order
        column .-= sum(column) / length(column)
        column ./= max(maximum(abs.(column)), eps(Float64))
        basis[:, :, i] .= repeat(reshape(column, Nt, 1), 1, M)
    end
    return basis
end

function build_control(control::ReducedPhaseControlMap, values, context)
    x = Float64.(collect(values))
    length(x) == length(control.orders) || throw(ArgumentError(
        "control map `$(control.name)` expects $(length(control.orders)) coefficients; got $(length(x))"))
    Nt = Int(_context_value(context, :Nt))
    M = Int(_context_value(context, :M))
    sim = _context_value(context, :sim)
    basis = reduced_phase_basis(control, sim, Nt, M)
    phase = zeros(Float64, Nt, M)
    scalar_controls = Dict{String,Float64}()
    for (i, value) in enumerate(x)
        phase .+= value .* view(basis, :, :, i)
        scalar_controls["$(control.name)[$i]"] = value
    end
    return (
        control = control.name,
        optimizer_values = x,
        phase = phase,
        amplitude = ones(Nt, M),
        basis = basis,
        scalar_controls = scalar_controls,
        diagnostics = Dict{Symbol,Any}(
            :basis_orders => control.orders,
            :basis_count => length(control.orders),
            :phase_max_abs => Float64(maximum(abs.(phase))),
        ),
    )
end

function pullback_control(control::ReducedPhaseControlMap, grad_phase, context)
    Nt = Int(_context_value(context, :Nt))
    M = Int(_context_value(context, :M))
    size(grad_phase) == (Nt, M) || throw(ArgumentError(
        "gradient phase shape $(size(grad_phase)) does not match expected ($Nt, $M)"))
    sim = _context_value(context, :sim)
    basis = hasproperty(context, :basis) ?
        getproperty(context, :basis) :
        reduced_phase_basis(control, sim, Nt, M)
    size(basis) == (Nt, M, length(control.orders)) || throw(ArgumentError(
        "basis shape $(size(basis)) does not match expected ($Nt, $M, $(length(control.orders)))"))
    grad_x = zeros(Float64, length(control.orders))
    for i in eachindex(grad_x)
        grad_x[i] = sum(grad_phase .* view(basis, :, :, i))
    end
    return grad_x
end

function _adjoint_relative_error(actual::Real, expected::Real)
    denom = max(abs(actual), abs(expected), eps(Float64))
    return abs(actual - expected) / denom
end

function check_terminal_adjoint(
    objective::AbstractFieldObjective,
    uωf,
    context;
    indices=nothing,
    epsilon::Real=1e-6,
    rtol::Real=1e-4,
    atol::Real=1e-7,
)
    J, λωL = evaluate_objective(objective, uωf, context)
    ε = Float64(epsilon)
    ε > 0 || throw(ArgumentError("epsilon must be positive"))
    check_indices = isnothing(indices) ?
        Tuple(CartesianIndex(i, j) for j in axes(uωf, 2), i in unique(round.(Int, range(1, size(uωf, 1), length=min(size(uωf, 1), 5))))) :
        Tuple(indices)
    rows = []
    for idx in check_indices
        idx isa CartesianIndex || (idx = CartesianIndex(idx, 1))
        for direction in (1.0 + 0.0im, 0.0 + 1.0im)
            perturb = zeros(ComplexF64, size(uωf))
            perturb[idx] = direction
            Jp, _ = evaluate_objective(objective, uωf .+ ε .* perturb, context)
            Jm, _ = evaluate_objective(objective, uωf .- ε .* perturb, context)
            fd = (Jp - Jm) / (2ε)
            adj = 2 * real(conj(λωL[idx]) * direction)
            abs_error = abs(adj - fd)
            rel_error = _adjoint_relative_error(adj, fd)
            push!(rows, (
                index=idx,
                direction=imag(direction) == 0 ? :real : :imag,
                finite_difference=fd,
                adjoint=adj,
                abs_error=abs_error,
                rel_error=rel_error,
                pass=abs_error <= Float64(atol) || rel_error <= Float64(rtol),
            ))
        end
    end
    return (
        kind=getfield(objective, :kind),
        cost=J,
        pass=all(row -> row.pass, rows),
        rows=Tuple(rows),
    )
end

function check_control_pullback(
    control::ReducedPhaseControlMap,
    values,
    context;
    epsilon::Real=1e-6,
    rtol::Real=1e-5,
    atol::Real=1e-7,
)
    x = Float64.(collect(values))
    ε = Float64(epsilon)
    ε > 0 || throw(ArgumentError("epsilon must be positive"))

    objective(vals) = begin
        built = build_control(control, vals, context)
        0.5 * sum(abs2, built.phase)
    end

    built = build_control(control, x, context)
    grad_x = pullback_control(control, built.phase, (; context..., basis=built.basis))
    rows = []
    for i in eachindex(x)
        xp = copy(x); xm = copy(x)
        xp[i] += ε; xm[i] -= ε
        fd = (objective(xp) - objective(xm)) / (2ε)
        adj = grad_x[i]
        abs_error = abs(adj - fd)
        rel_error = _adjoint_relative_error(adj, fd)
        push!(rows, (
            index=i,
            finite_difference=fd,
            pullback=adj,
            abs_error=abs_error,
            rel_error=rel_error,
            pass=abs_error <= Float64(atol) || rel_error <= Float64(rtol),
        ))
    end
    return (
        control=control.name,
        pass=all(row -> row.pass, rows),
        rows=Tuple(rows),
    )
end

function render_adjoint_contract_check_report(report; io::IO=stdout)
    label = haskey(report, :kind) ? "Objective $(report.kind)" :
        haskey(report, :control) ? "Control $(report.control)" :
        "Adjoint contract"
    println(io, "# ", label, " Check")
    println(io)
    println(io, "- Status: `", report.pass ? "PASS" : "FAIL", "`")
    haskey(report, :cost) && println(io, "- Cost: `", report.cost, "`")
    println(io)
    if haskey(report, :kind)
        println(io, "| Index | Direction | Finite difference | Adjoint | Abs error | Rel error | Pass |")
        println(io, "|---|---|---:|---:|---:|---:|---|")
        for row in report.rows
            println(io, "| ", row.index, " | ", row.direction, " | ", row.finite_difference,
                " | ", row.adjoint, " | ", row.abs_error, " | ", row.rel_error, " | ", row.pass, " |")
        end
    else
        println(io, "| Index | Finite difference | Pullback | Abs error | Rel error | Pass |")
        println(io, "|---|---:|---:|---:|---:|---|")
        for row in report.rows
            println(io, "| ", row.index, " | ", row.finite_difference,
                " | ", row.pullback, " | ", row.abs_error, " | ", row.rel_error, " | ", row.pass, " |")
        end
    end
    return nothing
end

function reduced_phase_adjoint_cost_gradient(
    values,
    uω0,
    fiber,
    sim,
    band_mask;
    control::ReducedPhaseControlMap=ReducedPhaseControlMap(),
    objective::Union{Nothing,FieldObjective}=nothing,
    objective_kind::Symbol=:raman_band,
    λ_gdd=0.0,
    λ_boundary=0.0,
    log_cost::Bool=true,
)
    if objective !== nothing
        objective_kind = objective.kind
    end
    Nt, M = sim["Nt"], sim["M"]
    context = (sim=sim, Nt=Nt, M=M)
    built = build_control(control, values, context)
    J, grad_phase = cost_and_gradient(
        built.phase,
        uω0,
        fiber,
        sim,
        band_mask;
        objective_kind=objective_kind,
        λ_gdd=λ_gdd,
        λ_boundary=λ_boundary,
        log_cost=log_cost,
    )
    grad_x = pullback_control(control, grad_phase, (; context..., basis=built.basis))
    return Float64(J), grad_x
end

function optimize_reduced_phase_coefficients(
    uω0,
    fiber,
    sim,
    band_mask;
    basis_orders=(2, 3),
    coefficient_initial=nothing,
    max_iter::Int=20,
    objective_kind::Symbol=:raman_band,
    λ_gdd=0.0,
    λ_boundary=0.0,
    log_cost::Bool=true,
    store_trace::Bool=true,
    solver_f_abstol=:auto,
    solver_g_abstol=:auto,
)
    control = ReducedPhaseControlMap(orders=basis_orders)
    x0 = isnothing(coefficient_initial) ?
        zeros(length(control.orders)) :
        Float64.(collect(coefficient_initial))
    length(x0) == length(control.orders) || throw(ArgumentError(
        "coefficient_initial length $(length(x0)) does not match basis order count $(length(control.orders))"))

    fiber["zsave"] = nothing
    default_f_tol = log_cost ? 0.01 : 1e-10
    f_tol = solver_f_abstol === :auto ? default_f_tol : Float64(solver_f_abstol)
    options = if solver_g_abstol === :auto
        Optim.Options(iterations=max_iter, f_abstol=f_tol, store_trace=store_trace)
    else
        Optim.Options(iterations=max_iter, f_abstol=f_tol, g_abstol=Float64(solver_g_abstol), store_trace=store_trace)
    end

    result = Optim.optimize(
        Optim.only_fg!() do F, G, x
            J, grad_x = reduced_phase_adjoint_cost_gradient(
                x, uω0, fiber, sim, band_mask;
                control=control,
                objective_kind=objective_kind,
                λ_gdd=λ_gdd,
                λ_boundary=λ_boundary,
                log_cost=log_cost,
            )
            if G !== nothing
                G .= grad_x
            end
            if F !== nothing
                return J
            end
        end,
        x0,
        Optim.LBFGS(),
        options,
    )
    return result, control
end

function run_reduced_phase_optimization(;
    max_iter=20,
    validate=true,
    save_prefix="reduced_phase_opt",
    basis_orders=(2, 3),
    coefficient_initial=nothing,
    λ_gdd=:auto,
    λ_boundary=1.0,
    fiber_name="Custom",
    do_plots=true,
    log_cost::Bool=true,
    objective_kind::Symbol=:raman_band,
    solver_reltol=1e-8,
    solver_f_abstol=:auto,
    solver_g_abstol=:auto,
    problem_setup=setup_raman_problem,
    kwargs...,
)
    _ = validate
    t_start = time()
    uω0, fiber, sim, band_mask, Δf, raman_threshold = problem_setup(; kwargs...)
    fiber["reltol"] = Float64(solver_reltol)
    Nt = sim["Nt"]
    M = sim["M"]

    λ_gdd_val = λ_gdd === :auto ? 1e-4 : Float64(λ_gdd)
    result, control = optimize_reduced_phase_coefficients(
        uω0, fiber, sim, band_mask;
        basis_orders=basis_orders,
        coefficient_initial=coefficient_initial,
        max_iter=max_iter,
        objective_kind=objective_kind,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        log_cost=log_cost,
        store_trace=true,
        solver_f_abstol=solver_f_abstol,
        solver_g_abstol=solver_g_abstol,
    )

    context = (sim=sim, Nt=Nt, M=M)
    built_after = build_control(control, Optim.minimizer(result), context)
    φ_before = zeros(Nt, M)
    φ_after = built_after.phase
    J_before, _ = cost_and_gradient(φ_before, uω0, fiber, sim, band_mask;
        objective_kind=objective_kind, log_cost=false)
    J_after, grad_after = reduced_phase_adjoint_cost_gradient(
        Optim.minimizer(result), uω0, fiber, sim, band_mask;
        control=control,
        objective_kind=objective_kind,
        λ_gdd=0.0,
        λ_boundary=0.0,
        log_cost=false,
    )
    ΔJ_dB = FiberLab.lin_to_dB(J_after) - FiberLab.lin_to_dB(J_before)

    uω0_opt = @. uω0 * cis(φ_after)
    ut0_opt = ifft(uω0_opt, 1)
    bc_input_ok, bc_input_frac = check_raw_temporal_edges(ut0_opt;
        threshold=TRUST_THRESHOLDS.edge_frac_pass)

    fiber_bc = deepcopy(fiber)
    fiber_bc["zsave"] = [fiber["L"]]
    sol_bc = FiberLab.solve_disp_mmf(uω0_opt, fiber_bc, sim)
    bc_output_ok, bc_output_frac = check_raw_temporal_edges(sol_bc["ut_z"][end, :, :];
        threshold=TRUST_THRESHOLDS.edge_frac_pass)
    uωf = sol_bc["uω_z"][end, :, :]
    photon_drift = photon_number_drift(uω0_opt, uωf, sim)

    elapsed = time() - t_start
    tw_ps = Nt * sim["Δt"]
    _λ0 = get(kwargs, :λ0, 1550e-9)
    _P_cont = get(kwargs, :P_cont, 0.05)
    _pulse_fwhm = get(kwargs, :pulse_fwhm, 185e-15)
    _L_fiber = get(kwargs, :L_fiber, 1.0)
    run_meta = (
        fiber_name = fiber_name,
        L_m = _L_fiber,
        P_cont_W = _P_cont,
        lambda0_nm = _λ0 * 1e9,
        fwhm_fs = _pulse_fwhm * 1e15,
    )

    objective_spec = raman_cost_surface_spec(
        log_cost=log_cost,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        objective_kind=objective_kind,
        objective_label=string("reduced-basis ", _single_mode_objective_label(objective_kind)),
    )
    trust_report = build_numerical_trust_report(
        det_status=deterministic_environment_status(),
        edge_input_frac=bc_input_frac,
        edge_output_frac=bc_output_frac,
        energy_drift=photon_drift,
        gradient_validation=nothing,
        log_cost=log_cost,
        λ_gdd=λ_gdd_val,
        λ_boundary=λ_boundary,
        objective_spec=objective_spec,
        objective_label=string("reduced-basis ", _single_mode_objective_label(objective_kind)),
    )
    trust_md_path = write_numerical_trust_report("$(save_prefix)_trust.md", trust_report)

    convergence_history = log_cost ?
        collect(Optim.f_trace(result)) :
        FiberLab.lin_to_dB.(Optim.f_trace(result))
    result_payload = build_raman_result_payload(;
        run_meta = run_meta,
        run_tag = (@isdefined(RUN_TAG) ? RUN_TAG : "interactive"),
        fiber = fiber,
        sim = sim,
        Nt = Nt,
        time_window_ps = tw_ps,
        J_before = J_before,
        J_after = J_after,
        delta_J_dB = ΔJ_dB,
        grad_norm = norm(grad_after),
        converged = Optim.converged(result),
        iterations = Optim.iterations(result),
        wall_time_s = elapsed,
        convergence_history = convergence_history,
        phi_opt = φ_after,
        uω0 = uω0,
        E_conservation = photon_drift,
        photon_number_drift = photon_drift,
        bc_input_frac = bc_input_frac,
        bc_output_frac = bc_output_frac,
        bc_input_ok = bc_input_ok,
        bc_output_ok = bc_output_ok,
        trust_report = trust_report,
        trust_report_md = trust_md_path,
        band_mask = band_mask,
    )
    jld2_path = "$(save_prefix)_result.jld2"
    sidecar_path = FiberLab.save_run(jld2_path, result_payload)
    manifest_path = joinpath("results", "raman", "manifest.json")
    update_manifest_entry(manifest_path, build_raman_manifest_entry(result_payload, jld2_path))

    if do_plots
        plot_optimization_result_v2(φ_before, φ_after, uω0, fiber, sim,
            band_mask, Δf, raman_threshold;
            save_path="$(save_prefix).png", metadata=run_meta,
            objective_kind=objective_kind)
        close("all")
    end
    save_standard_set(φ_after, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag = basename(save_prefix),
        fiber_name = run_meta.fiber_name,
        L_m = run_meta.L_m,
        P_W = run_meta.P_cont_W,
        output_dir = dirname(save_prefix) == "" ? "." : dirname(save_prefix),
        lambda0_nm = run_meta.lambda0_nm,
        fwhm_fs = run_meta.fwhm_fs,
        objective_kind = objective_kind)

    return result, uω0, fiber, sim, band_mask, Δf
end

end # include guard
