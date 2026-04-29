"""
Executable scalar objective extension for playground smoke testing.

This objective maximizes the normalized temporal peak power at the fiber output
by minimizing `1 - peak_fraction`. It is intentionally limited to
derivative-free bounded scalar search over `gain_tilt`; no full-grid gradient is
claimed here.
"""

using FFTW

function temporal_peak_scalar_cost(context)
    uωf = context.uωf
    ut = ifft(uωf, 1)
    power = vec(sum(abs2.(ut), dims = 2))
    total = sum(power)
    total > 0 || throw(ArgumentError("temporal_peak_scalar requires nonzero output energy"))
    peak_fraction = maximum(power) / total
    return 1.0 - Float64(peak_fraction)
end

function temporal_peak_scalar_gradient(args...)
    throw(ArgumentError(
        "temporal_peak_scalar is executable only with derivative-free bounded_scalar search"))
end
