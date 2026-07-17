"""
Control layout planning for the configurable research engine.

This module does not change optimizer behavior yet. It makes the implicit
optimizer-vector contract inspectable: what physical controls are active, how
large each block is, what units/bounds apply, and what variable-specific plots
must exist before a control is considered lab-usable.
"""

if !(@isdefined _CONTROL_LAYOUT_JL_LOADED)
const _CONTROL_LAYOUT_JL_LOADED = true

include(joinpath(@__DIR__, "variable_registry.jl"))

function _control_mode_count_hint(spec)
    if spec.problem.regime == :multimode
        return "mode_count"
    end
    return "1"
end

function _control_nt_hint(grid_resolution)
    return ismissing(grid_resolution.resolved) ? missing : grid_resolution.resolved.nt
end

_control_nt_label(nt) = ismissing(nt) ? "resolved_Nt" : string(nt)

function _control_shape_hint(spec, variable::Symbol, nt)
    contract = variable_contract(variable, spec.problem.regime)
    if variable == :energy || variable == :gain_tilt || variable == :quadratic_phase ||
       contract.backend == :scalar_phase_extension
        return "scalar"
    elseif contract.backend == :spectral_reduced_phase
        orders = get(spec.controls.policy_options, :basis_orders, [2, 3])
        return string("vector[", length(orders), "]")
    elseif contract.backend in (:vector_phase_extension, :vector_control_extension)
        return string("vector[", get(contract, :dimension, "unknown"), "]")
    elseif contract.backend == :shared_spectral_phase
        return string(_control_nt_label(nt), " shared across modes")
    end
    return string(_control_nt_label(nt), " x ", _control_mode_count_hint(spec))
end

function _control_length_hint(spec, variable::Symbol, nt)
    contract = variable_contract(variable, spec.problem.regime)
    if variable == :energy || variable == :gain_tilt || variable == :quadratic_phase ||
       contract.backend == :scalar_phase_extension
        return "1"
    elseif contract.backend == :spectral_reduced_phase
        orders = get(spec.controls.policy_options, :basis_orders, [2, 3])
        return string(length(orders))
    elseif contract.backend in (:vector_phase_extension, :vector_control_extension)
        return string(get(contract, :dimension, "unknown"))
    elseif contract.backend == :shared_spectral_phase
        return _control_nt_label(nt)
    end
    mode_count = _control_mode_count_hint(spec)
    nt_label = _control_nt_label(nt)
    return mode_count == "1" ? nt_label : string(nt_label, " * ", mode_count)
end

function control_block_plan(spec, variable::Symbol, nt)
    contract = variable_contract(variable, spec.problem.regime)
    return (
        name = variable,
        regime = spec.problem.regime,
        maturity = contract.maturity,
        units = contract.units,
        bounds = contract.bounds,
        parameterization = spec.controls.parameterization,
        supported_parameterizations = contract.parameterizations,
        optimizer_representation = contract.optimizer_representation,
        shape = _control_shape_hint(spec, variable, nt),
        length = _control_length_hint(spec, variable, nt),
        artifact_hooks = contract.artifact_hooks,
        artifact_semantics = contract.artifact_semantics,
    )
end

function control_layout_plan(spec; grid_resolution=resolve_experiment_grid(spec))
    nt = _control_nt_hint(grid_resolution)
    blocks = Tuple(control_block_plan(spec, variable, nt)
                   for variable in spec.controls.variables)
    numeric_lengths = Tuple(tryparse(Int, block.length) for block in blocks)
    total_length = if any(isnothing, numeric_lengths)
        join((string(block.name, "=", block.length) for block in blocks), "; ")
    else
        string(sum(numeric_lengths))
    end
    return (
        variables = spec.controls.variables,
        parameterization = spec.controls.parameterization,
        initialization = spec.controls.initialization,
        blocks = blocks,
        total_length = total_length,
        dimension_authority = ismissing(nt) ? :runtime_modal : :preflight_resolved,
    )
end

function render_control_layout_plan(spec; io::IO=stdout)
    layout = control_layout_plan(spec)
    println(io, "Control layout:")
    println(io, "  variables=", join(string.(layout.variables), ", "))
    println(io, "  parameterization=", layout.parameterization)
    println(io, "  initialization=", layout.initialization)
    println(io, "  optimizer_length=", layout.total_length)
    for block in layout.blocks
        println(io,
            "  - ", block.name,
            ": shape=", block.shape,
            " units=", block.units,
            " bounds=", block.bounds)
        println(io, "    optimizer=", block.optimizer_representation)
        println(io, "    artifacts=", isempty(block.artifact_hooks) ? "none" : join(string.(block.artifact_hooks), ", "))
    end
    return nothing
end

end # include guard
