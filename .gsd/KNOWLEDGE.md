# Knowledge

## JSON3.read returns immutable objects — must convert before mutation

`JSON3.read(text, Vector{Dict{String,Any}})` returns objects that cannot be mutated in-place.
To add/update fields (e.g., `soliton_number_N`), convert each entry: `Dict{String,Any}(entry)`.
Discovered in S03/T02 when updating manifest.json with computed soliton numbers.

## JLD2 sim_Dt is in picoseconds — convert to seconds for frequency-domain functions

`sim["Δt"]` (saved as `sim_Dt` in JLD2) is in picoseconds (time_window_ps / Nt).
Functions like `decompose_phase_polynomial` that call `fftfreq(Nt, 1.0/Δt)` expect seconds
so the FFT grid comes out in Hz (not THz). Multiply by `1e-12` before passing.

## compute_soliton_number expects peak power, not average/continuum power

The soliton number formula N = sqrt(gamma * P0 * T0^2 / |beta2|) requires instantaneous peak power.
JLD2 stores `P_cont_W` (average continuum power). Convert via:
`P_peak = 0.881374 * P_cont_W / (fwhm_s * rep_rate)` where 0.881374 is the sech^2 energy integral factor
(confirmed in `src/simulation/simulate_disp_mmf.jl:113`).

## RC_ prefix convention for script-local fiber constants

Scripts that define fiber constants (`SMF28_GAMMA`, etc.) should use a unique prefix (`RC_` for run_comparison)
to avoid `const` redefinition errors when the script is `include()`d in a REPL session where
`raman_optimization.jl` or `common.jl` has already defined the same names.
