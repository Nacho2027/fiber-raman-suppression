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

function _control_shape_hint(spec, variable::Symbol)
    if variable == :energy || variable == :gain_tilt
        return "scalar"
    elseif variable == :mode_weights || variable == :mode_coeffs
        return "mode_count"
    end
    return string(spec.problem.Nt, " x ", _control_mode_count_hint(spec))
end

function _control_length_hint(spec, variable::Symbol)
    if variable == :energy || variable == :gain_tilt
        return "1"
    elseif variable == :mode_weights || variable == :mode_coeffs
        return "mode_count"
    end
    mode_count = _control_mode_count_hint(spec)
    return mode_count == "1" ? string(spec.problem.Nt) : string(spec.problem.Nt, " * ", mode_count)
end

function control_block_plan(spec, variable::Symbol)
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
        shape = _control_shape_hint(spec, variable),
        length = _control_length_hint(spec, variable),
        artifact_hooks = contract.artifact_hooks,
        artifact_semantics = contract.artifact_semantics,
    )
end

function control_layout_plan(spec)
    blocks = Tuple(control_block_plan(spec, variable) for variable in spec.controls.variables)
    total_length = if any(block -> occursin("mode_count", block.length), blocks)
        join((string(block.name, "=", block.length) for block in blocks), "; ")
    else
        string(sum(parse(Int, block.length) for block in blocks))
    end
    return (
        variables = spec.controls.variables,
        parameterization = spec.controls.parameterization,
        initialization = spec.controls.initialization,
        blocks = blocks,
        total_length = total_length,
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
