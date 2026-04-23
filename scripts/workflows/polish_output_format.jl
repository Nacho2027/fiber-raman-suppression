# ═══════════════════════════════════════════════════════════════════════════════
# Compatibility shim for the canonical output-format helpers.
#
# The implementation now lives in `src/io/results.jl` and is loaded through the
# `MultiModeNoise` package. This file remains include-able so older scripts,
# tests, and docs examples keep working.
# ═══════════════════════════════════════════════════════════════════════════════

using MultiModeNoise: OUTPUT_FORMAT_SCHEMA_VERSION, load_run, save_run

if abspath(PROGRAM_FILE) == @__FILE__
    mktempdir() do dir
        path = joinpath(dir, "selftest.jld2")
        result = (
            phi_opt             = collect(range(0.0, stop=π, length=64)),
            uω0                 = ComplexF64[i + 0.5im for i in 1:64],
            uωf                 = ComplexF64[0.1 * i - 0.2im for i in 1:64],
            convergence_history = Float64[-3.0, -10.0, -20.0, -35.0, -47.0],
            grid                = Dict("Nt" => 64, "Δt" => 1.5e-3, "ts" => collect(1:64),
                                       "fs" => collect(1:64), "ωs" => collect(1:64)),
            fiber               = Dict("preset" => "SMF28", "L" => 2.0),
            metadata            = Dict(
                "run_id"         => "selftest",
                "git_sha"        => "0000000",
                "julia_version"  => string(VERSION),
                "timestamp_utc"  => "2026-01-01T00:00:00Z",
                "fiber_preset"   => "SMF28",
                "L_m"            => 2.0,
                "P_W"            => 0.2,
                "lambda0_nm"     => 1550.0,
                "pulse_fwhm_fs"  => 185.0,
                "Nt"             => 64,
                "time_window_ps" => 12.0,
                "J_final_dB"     => -47.0,
                "J_initial_dB"   => -3.0,
                "n_iter"         => 4,
                "converged"      => true,
                "seed"           => 0,
            ),
        )

        sidecar = save_run(path, result)
        loaded = load_run(path)
        loaded_json = load_run(sidecar)
        @assert loaded.phi_opt == result.phi_opt
        @assert loaded_json.metadata["run_id"] == "selftest"
        println("polish_output_format.jl self-test passed")
    end
end
