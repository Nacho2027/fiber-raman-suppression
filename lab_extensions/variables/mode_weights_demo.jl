"""
Planning-only optimization variable stub for multimode launch/modal weights.

This file documents the intended extension point. It is deliberately not wired
to execution until units, bounds, gradients, artifacts, and validation are
promoted.
"""

function build_mode_weights_demo_control(args...)
    throw(ArgumentError(
        "mode_weights_demo is a planning-only variable contract; implement and promote it before execution"))
end

function project_mode_weights_demo_control(args...)
    throw(ArgumentError(
        "mode_weights_demo is a planning-only variable contract; implement simplex projection before execution"))
end
