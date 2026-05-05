"""
Create a device-agnostic SLM replay bundle from a saved run.

Usage:
    julia -t auto --project=. scripts/canonical/replay_slm_mask.jl RUN PROFILE [OUTPUT_DIR]
    julia -t auto --project=. scripts/canonical/replay_slm_mask.jl RUN PROFILE --evaluate [OUTPUT_DIR]

`PROFILE` may be a path to a TOML file or an id under `configs/slm_profiles/`.
The default command writes the replayed mask bundle only. `--evaluate` performs
a forward propagation with the replayed mask and records the replayed Raman
objective; use it only when the run size is appropriate for the current host.
"""

using FFTW
using JLD2
using FiberLab
using Printf

include(joinpath(@__DIR__, "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "lib", "run_artifacts.jl"))
include(joinpath(@__DIR__, "..", "lib", "slm_replay.jl"))

const SLM_PROFILE_DIR = normpath(joinpath(@__DIR__, "..", "..", "configs", "slm_profiles"))

function _replay_usage()
    return """
Usage:
    julia -t auto --project=. scripts/canonical/replay_slm_mask.jl RUN PROFILE [OUTPUT_DIR]
    julia -t auto --project=. scripts/canonical/replay_slm_mask.jl RUN PROFILE --evaluate [OUTPUT_DIR]

PROFILE may be a TOML path or an id under configs/slm_profiles/.
"""
end

function parse_slm_replay_args(args)
    isempty(args) && error(_replay_usage())
    any(arg -> arg in ("--help", "-h"), args) && return (help = true,)

    evaluate = false
    positional = String[]
    for arg in args
        if arg == "--evaluate"
            evaluate = true
        else
            push!(positional, String(arg))
        end
    end

    length(positional) in (2, 3) || error(_replay_usage())
    return (
        help = false,
        run = positional[1],
        profile = positional[2],
        output_dir = length(positional) == 3 ? positional[3] : "",
        evaluate = evaluate,
    )
end

function resolve_slm_profile_path(spec::AbstractString)
    isfile(spec) && return abspath(spec)
    filename = endswith(spec, ".toml") ? spec : string(spec, ".toml")
    candidate = joinpath(SLM_PROFILE_DIR, filename)
    isfile(candidate) && return abspath(candidate)
    available = isdir(SLM_PROFILE_DIR) ?
        sort!(replace.(filter(name -> endswith(name, ".toml"), readdir(SLM_PROFILE_DIR)), ".toml" => "")) :
        String[]
    throw(ArgumentError("could not resolve SLM profile `$spec`; available profiles: $(join(available, ", "))"))
end

function _load_replay_artifact(path::AbstractString)
    artifact = resolve_run_artifact_path(path)
    loaded = try
        FiberLab.load_run(artifact)
    catch
        JLD2.load(artifact)
    end
    return artifact, loaded
end

function _loaded_matrix_field(loaded, field::Symbol)
    value = _artifact_loaded_field(loaded, field, nothing)
    value === nothing && throw(ArgumentError("artifact missing required field `$field`"))
    return value
end

function _loaded_vector_field(loaded, field::Symbol)
    return vec(Float64.(_loaded_matrix_field(loaded, field)))
end

function _relative_frequency_axis(loaded)
    Nt = Int(_artifact_loaded_field(loaded, :Nt, 0))
    dt = Float64(_artifact_loaded_field(loaded, :sim_Dt, NaN))
    Nt > 0 || throw(ArgumentError("artifact missing positive Nt"))
    isfinite(dt) && dt > 0 || throw(ArgumentError("artifact missing positive sim_Dt"))
    return collect(FFTW.fftfreq(Nt, 1 / dt))
end

function _default_replay_output_dir(artifact::AbstractString, profile)
    return joinpath(dirname(artifact), string("slm_replay_", profile.profile_id))
end

function _ideal_objective_dB(loaded)
    J_after = Float64(_artifact_loaded_field(loaded, :J_after, NaN))
    return isfinite(J_after) && J_after > 0 ? FiberLab.lin_to_dB(J_after) : NaN
end

function _evaluate_replayed_linear_cost(loaded, replay)
    Nt = Int(_artifact_loaded_field(loaded, :Nt, 0))
    M = size(_loaded_matrix_field(loaded, :uomega0), 2)
    M == 1 || throw(ArgumentError("forward replay evaluation currently supports single-mode artifacts only"))

    gamma = Float64(_artifact_loaded_field(loaded, :gamma, NaN))
    betas = Float64.(collect(_artifact_loaded_field(loaded, :betas, Float64[])))
    isfinite(gamma) && gamma > 0 || throw(ArgumentError("artifact missing positive gamma"))
    !isempty(betas) || throw(ArgumentError("artifact missing betas"))

    lambda0_nm = Float64(_artifact_loaded_field(loaded, :lambda0_nm, 1550.0))
    L_m = Float64(_artifact_loaded_field(loaded, :L_m, NaN))
    P_cont_W = Float64(_artifact_loaded_field(loaded, :P_cont_W, NaN))
    fwhm_fs = Float64(_artifact_loaded_field(loaded, :fwhm_fs, 185.0))
    time_window_ps = Float64(_artifact_loaded_field(loaded, :time_window_ps, NaN))
    band_mask = Bool.(collect(_artifact_loaded_field(loaded, :band_mask, Bool[])))
    raman_threshold = -5.0

    setup = setup_raman_problem_exact(;
        λ0 = lambda0_nm * 1e-9,
        M = 1,
        Nt = Nt,
        time_window = time_window_ps,
        β_order = max(2, length(betas) + 1),
        L_fiber = L_m,
        P_cont = P_cont_W,
        pulse_fwhm = fwhm_fs * 1e-15,
        gamma_user = gamma,
        betas_user = betas,
        raman_threshold = raman_threshold,
    )
    _, fiber, sim, setup_band_mask, _, _ = setup
    if length(band_mask) != Nt || !any(band_mask)
        band_mask = setup_band_mask
    end

    uomega0 = Matrix{ComplexF64}(_loaded_matrix_field(loaded, :uomega0))
    phi = reshape(replay.phi_replayed, Nt, 1)
    uomega_shaped = @. uomega0 * cis(phi)
    sol = FiberLab.solve_disp_mmf(uomega_shaped, fiber, sim)
    utilde = sol["ode_sol"]
    uomegaf = @. cis(fiber["Dω"] * fiber["L"]) * utilde(fiber["L"])
    J, _ = spectral_band_cost(uomegaf, band_mask)
    return J, FiberLab.lin_to_dB(J)
end

function run_slm_replay_bundle(run_path::AbstractString,
                               profile_path::AbstractString,
                               output_dir::AbstractString = "";
                               evaluate::Bool = false)
    artifact, loaded = _load_replay_artifact(run_path)
    profile = load_slm_replay_profile(resolve_slm_profile_path(profile_path))
    rel_f = _relative_frequency_axis(loaded)
    phi = _loaded_vector_field(loaded, :phi_opt)
    replay = replay_slm_phase(phi, rel_f, profile)

    ideal_dB = _ideal_objective_dB(loaded)
    replayed_dB = NaN
    replayed_linear = NaN
    if evaluate
        replayed_linear, replayed_dB = _evaluate_replayed_linear_cost(loaded, replay)
    end

    out_dir = isempty(output_dir) ? _default_replay_output_dir(artifact, profile) : output_dir
    bundle = write_slm_replay_bundle(out_dir, replay;
        source_artifact = artifact,
        ideal_J_dB = ideal_dB,
        replayed_J_dB = replayed_dB,
    )

    return (;
        bundle...,
        source_artifact = artifact,
        profile_path = resolve_slm_profile_path(profile_path),
        evaluated = evaluate,
        replayed_J = replayed_linear,
        replayed_J_dB = replayed_dB,
    )
end

function replay_slm_mask_main(args = ARGS)
    parsed = parse_slm_replay_args(String.(args))
    if parsed.help
        println(_replay_usage())
        return nothing
    end
    result = run_slm_replay_bundle(parsed.run, parsed.profile, parsed.output_dir;
        evaluate = parsed.evaluate)
    println("SLM replay bundle: ", result.output_dir)
    println("Replayed phase CSV: ", result.replayed_phase_csv)
    println("Pixel phase CSV: ", result.pixel_phase_csv)
    println("Metadata JSON: ", result.metadata_json)
    if result.evaluated
        println("Replayed J dB: ", result.replayed_J_dB)
        println("Replay survival pass: ", result.survival.pass)
    else
        println("Forward replay evaluation: not run")
    end
    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    replay_slm_mask_main(ARGS)
end
