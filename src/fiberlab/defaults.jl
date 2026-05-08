"""
Default and resolved-choice auditing for FiberLab experiments.

Defaults are part of the scientific contract. This layer records choices that
are conventional, automatically resolved, or worth explicit researcher review.
It does not try to infer whether the user typed a value explicitly.
"""

struct DefaultAssumption
    key::Symbol
    value
    level::Symbol
    message::String
end

function _assumption!(items::Vector{DefaultAssumption}, key::Symbol, value,
                      level::Symbol, message::AbstractString)
    push!(items, DefaultAssumption(key, value, level, String(message)))
    return items
end

_control_map_label(control::AbstractControlMap) = control.name
_control_map_label(control::ControlSpace) = Tuple(block.name for block in control.blocks)

"""
    default_assumptions(experiment) -> Tuple{Vararg{DefaultAssumption}}

Return the resolved choices that FiberLab treats as conventional defaults,
automatic policies, or scientific choices worth review. The audit is intentionally
conservative: it records default-like choices even if the user explicitly typed
the same value in a notebook.
"""
function default_assumptions(experiment::Experiment)
    items = DefaultAssumption[]

    experiment.fiber.regime == :single_mode && _assumption!(
        items,
        :fiber_regime,
        experiment.fiber.regime,
        :conventional,
        "single-mode propagation is selected; set `regime` explicitly for multimode or long-fiber studies.",
    )
    experiment.fiber.preset == :SMF28 && _assumption!(
        items,
        :fiber_preset,
        experiment.fiber.preset,
        :conventional,
        "SMF-28 is selected as the fiber preset.",
    )
    experiment.fiber.beta_order == 3 && _assumption!(
        items,
        :fiber_beta_order,
        experiment.fiber.beta_order,
        :conventional,
        "third-order dispersion is included by default.",
    )

    if experiment.pulse == Pulse()
        _assumption!(
            items,
            :pulse,
            experiment.pulse,
            :conventional,
            "pulse parameters match FiberLab's built-in source defaults.",
        )
    end

    experiment.grid.policy == :auto_if_undersized && _assumption!(
        items,
        :grid_policy,
        experiment.grid.policy,
        :auto,
        "grid policy may increase the time window or sample count before execution; inspect result metadata for resolved grid values.",
    )

    if experiment.control isa Control
        experiment.control.variables == (:phase,) && _assumption!(
            items,
            :control_variables,
            experiment.control.variables,
            :review,
            "symbolic phase control is selected; confirm this is the intended design variable.",
        )
        experiment.control.parameterization == :full_grid && _assumption!(
            items,
            :control_parameterization,
            experiment.control.parameterization,
            :review,
            "full-grid control is selected; consider a basis map when the scientific question is low-dimensional.",
        )
    elseif experiment.control isa AbstractControlMap
        _assumption!(
            items,
            :control_map,
            _control_map_label(experiment.control),
            :explicit,
            "custom control map supplied; FiberLab will use its declared decode and pullback contract.",
        )
    end

    if experiment.objective isa Objective
        experiment.objective.kind == :raman_band && _assumption!(
            items,
            :objective_kind,
            experiment.objective.kind,
            :scientific_target,
            "Raman-band objective is selected; treat this as a benchmark target, not a universal default.",
        )
    elseif experiment.objective isa AbstractFiberObjective
        _assumption!(
            items,
            :objective_map,
            experiment.objective.name,
            :explicit,
            "custom objective supplied; FiberLab will use its declared cost and terminal-adjoint contract.",
        )
    end

    experiment.solver.kind == :lbfgs && _assumption!(
        items,
        :solver_kind,
        experiment.solver.kind,
        :conventional,
        "LBFGS is selected for adjoint-gradient optimization.",
    )
    !experiment.solver.validate_gradient && _assumption!(
        items,
        :gradient_validation,
        experiment.solver.validate_gradient,
        :review,
        "gradient validation is disabled for routine speed; enable it for new controls, objectives, or adjoint changes.",
    )

    experiment.artifacts.standard_images && _assumption!(
        items,
        :standard_images,
        experiment.artifacts.standard_images,
        :evidence,
        "standard figures are enabled and should be inspected for completed optimization runs.",
    )

    return Tuple(items)
end
