"""
    get_ydfa_cross_sections(fs; data_dir=".", absorption_file="Yb_absorption.npz", emission_file="Yb_emission.npz", scale=1e-27)

Load YDFA absorption/emission spectra from NPZ files and interpolate them onto a
frequency grid `fs` (THz).

# Arguments
- `fs`: Frequency grid in THz (for example `sim["fs"]`).

# Keyword Arguments
- `data_dir`: Directory where NPZ files are stored (default: current directory).
- `absorption_file`: NPZ filename for absorption data.
- `emission_file`: NPZ filename for emission data.
- `scale`: Scale factor applied to `"intensity"` values before interpolation.

# Returns
A dictionary with:
- `"lambda"`: wavelength grid in meters used for interpolation.
- `"sigma_as"`: absorption cross section on the `fs` grid.
- `"sigma_es"`: emission cross section on the `fs` grid.
"""
function get_ydfa_cross_sections(fs; data_dir=@__DIR__,
    absorption_file="Yb_absorption.npz",
    emission_file="Yb_emission.npz",
    scale=1e-27)

    c0 = 2.99792458e8 # m/s

    abs_path = joinpath(data_dir, absorption_file)  # look in the same directory as this script
    em_path = joinpath(data_dir, emission_file)

    absorption_values = npzread(abs_path)
    emission_values = npzread(em_path)

    λ_abs = absorption_values["wavelength"] .* 1e-9
    σ_abs = absorption_values["intensity"] .* scale

    λ_em = emission_values["wavelength"] .* 1e-9
    σ_em = emission_values["intensity"] .* scale

    itp_abs = linear_interpolation(λ_abs, σ_abs, extrapolation_bc=Flat())
    itp_em = linear_interpolation(λ_em, σ_em, extrapolation_bc=Flat())

    λ_target = c0 ./ (fs .* 1e12)  # since THz

    sigma_as = itp_abs.(λ_target)
    sigma_es = itp_em.(λ_target)

    return Dict("lambda" => λ_target, "sigma_as" => sigma_as, "sigma_es" => sigma_es)
end