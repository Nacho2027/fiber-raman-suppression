"""
Planning-only optimization variable stub for a smooth spectral gain/attenuation tilt.

This is a non-standard single-mode control contract. It is deliberately not
wired to execution until the lab defines the projection, throughput limits,
gradient behavior, artifacts, and hardware-safety checks.
"""

function build_gain_tilt_demo_control(args...)
    throw(ArgumentError(
        "gain_tilt_demo is a planning-only variable contract; implement and promote it before execution"))
end

function project_gain_tilt_demo_control(args...)
    throw(ArgumentError(
        "gain_tilt_demo is a planning-only variable contract; implement bounded gain projection before execution"))
end
