"""
Demo objective extension file for pulse-compression planning.

This file is intentionally not wired into execution yet. It documents the
function names declared by `pulse_compression_demo.toml` so researchers can see
where lab-owned objective code would live before promotion.
"""

function pulse_compression_cost(args...)
    throw(ArgumentError(
        "pulse_compression_demo is a planning-only objective contract; implement and promote this objective before execution"))
end

function pulse_compression_gradient(args...)
    throw(ArgumentError(
        "pulse_compression_demo is a planning-only objective contract; implement and promote this gradient before execution"))
end
