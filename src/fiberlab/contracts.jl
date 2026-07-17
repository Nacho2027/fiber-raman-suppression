"""
Small package-level contracts for FiberLab controls and objectives.

These contracts are intentionally about public API semantics only: whether a
named control/objective has the adjoint pieces needed by `solve` preflight, and
which figure hooks it asks result tooling to expose. Execution-specific
validation still lives behind backend adapters until it is promoted.
"""

struct ControlContract
    kind::Symbol
    has_pullback::Bool
    units::String
    figure_hooks::Tuple{Vararg{Symbol}}
end

struct ObjectiveContract
    kind::Symbol
    has_terminal_adjoint::Bool
    figure_hooks::Tuple{Vararg{Symbol}}
end

const CONTROL_CONTRACTS = Dict{Symbol,ControlContract}(
    :phase => ControlContract(:phase, true, "rad", (:phase_profile, :group_delay)),
    :reduced_phase => ControlContract(:reduced_phase, true, "rad", (:phase_profile, :group_delay)),
    :amplitude => ControlContract(:amplitude, true, "dimensionless transmission", (:amplitude_mask, :shaped_input_spectrum, :energy_throughput)),
    :energy => ControlContract(:energy, true, "relative pulse energy", (:energy_scale, :peak_power)),
    :gain_tilt => ControlContract(:gain_tilt, true, "dimensionless bounded transmission slope", (:gain_tilt_profile, :energy_throughput)),
)

const OBJECTIVE_CONTRACTS = Dict{Symbol,ObjectiveContract}(
    :raman_band => ObjectiveContract(:raman_band, true, (:spectrum_before_after, :raman_band_overlay, :convergence_trace)),
    :raman_peak => ObjectiveContract(:raman_peak, true, (:spectrum_before_after, :raman_peak_marker, :convergence_trace)),
    :temporal_width => ObjectiveContract(:temporal_width, true, (:spectrum_before_after, :convergence_trace)),
    :mmf_sum => ObjectiveContract(:mmf_sum, true, (:mode_resolved_spectra, :per_mode_leakage_table, :convergence_trace)),
    :mmf_fundamental => ObjectiveContract(:mmf_fundamental, true, (:mode_resolved_spectra, :convergence_trace)),
    :mmf_worst_mode => ObjectiveContract(:mmf_worst_mode, true, (:mode_resolved_spectra, :per_mode_leakage_table, :convergence_trace)),
)

control_contract(kind::Symbol) = get(CONTROL_CONTRACTS, kind, nothing)
objective_contract(kind::Symbol) = get(OBJECTIVE_CONTRACTS, kind, nothing)

registered_control_kinds() = Tuple(sort!(collect(keys(CONTROL_CONTRACTS)); by=string))
registered_objective_kinds() = Tuple(sort!(collect(keys(OBJECTIVE_CONTRACTS)); by=string))

function _contract_hooks(hooks)
    return Tuple(Symbol(hook) for hook in hooks)
end

"""
    register_control!(kind; has_pullback=true, units="", figure_hooks=())

Register a package-level control contract for preflight and result planning.
This is the notebook/API path for promoting a custom continuous control without
editing FiberLab's built-in contract table.
"""
function register_control!(kind::Symbol; has_pullback::Bool=true,
                           units::AbstractString="",
                           figure_hooks=())
    kind == Symbol("") && throw(ArgumentError("control kind cannot be empty"))
    contract = ControlContract(kind, has_pullback, String(units), _contract_hooks(figure_hooks))
    CONTROL_CONTRACTS[kind] = contract
    return contract
end

"""
    register_objective!(kind; has_terminal_adjoint=true, figure_hooks=())

Register a package-level objective contract for adjoint preflight and result
planning. Gradient solvers only pass preflight when the objective contract
declares a terminal adjoint.
"""
function register_objective!(kind::Symbol; has_terminal_adjoint::Bool=true,
                             figure_hooks=())
    kind == Symbol("") && throw(ArgumentError("objective kind cannot be empty"))
    contract = ObjectiveContract(kind, has_terminal_adjoint, _contract_hooks(figure_hooks))
    OBJECTIVE_CONTRACTS[kind] = contract
    return contract
end

has_control_pullback(kind::Symbol) = begin
    contract = control_contract(kind)
    contract !== nothing && contract.has_pullback
end

has_objective_terminal_adjoint(kind::Symbol) = begin
    contract = objective_contract(kind)
    contract !== nothing && contract.has_terminal_adjoint
end

function figure_hooks(control_kinds::Tuple{Vararg{Symbol}}, objective_kind::Symbol)
    hooks = Symbol[]
    objective = objective_contract(objective_kind)
    objective !== nothing && append!(hooks, objective.figure_hooks)
    for kind in control_kinds
        control = control_contract(kind)
        control !== nothing && append!(hooks, control.figure_hooks)
    end
    return Tuple(unique(hooks))
end
