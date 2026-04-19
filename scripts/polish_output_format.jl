# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 — Output Format Reference (save_run / load_run)
# ═══════════════════════════════════════════════════════════════════════════════
# Canonical saver + loader for a Raman-suppression optimization run.
#
# One run = one JLD2 payload + one JSON sidecar. The sidecar is cat-able,
# grep-able, and cross-language; the JLD2 holds the large numerical arrays.
#
# See docs/output-format.md (in this repo) for the full schema reference.
#
# Usage:
#   include(joinpath(@__DIR__, "polish_output_format.jl"))
#   result = (
#       phi_opt              = phi_opt,              # Vector{Float64}
#       uω0                  = uω0,                  # Vector{ComplexF64}
#       uωf                  = uωf,                  # Vector{ComplexF64}
#       convergence_history  = conv_history_dB,      # Vector{Float64} (dB)
#       grid                 = Dict("Nt"=>8192, "Δt"=>..., "ts"=>..., "fs"=>..., "ωs"=>...),
#       fiber                = fiber_dict,
#       metadata             = metadata_dict,        # matches sidecar scalars
#   )
#   save_run("results/raman/myrun.jld2", result)
#   loaded = load_run("results/raman/myrun.jld2")       # or "...json"
#
# This file is include-guarded: safe to include any number of times.
# ═══════════════════════════════════════════════════════════════════════════════

using JLD2
using JSON3
using Dates

if !(@isdefined _POLISH_OUTPUT_FORMAT_JL_LOADED)
const _POLISH_OUTPUT_FORMAT_JL_LOADED = true

"Current output-format schema version. Bump on any breaking change."
const OUTPUT_FORMAT_SCHEMA_VERSION = "1.0"

"Threshold above which `phi_opt_rad` is omitted from the JSON sidecar."
const PHI_OPT_INLINE_LIMIT = 8192

const _JLD2_REQUIRED_KEYS = (
    :phi_opt, :uω0, :uωf, :convergence_history, :grid, :fiber, :metadata,
)

const _SIDECAR_REQUIRED_SCALARS = (
    :schema_version, :payload_file, :run_id, :git_sha, :julia_version,
    :timestamp_utc, :fiber_preset, :L_m, :P_W, :lambda0_nm, :pulse_fwhm_fs,
    :Nt, :time_window_ps, :J_final_dB, :J_initial_dB, :n_iter, :converged,
    :seed,
)

"""
    save_run(path, result; schema_version=OUTPUT_FORMAT_SCHEMA_VERSION)

Write a Raman-suppression optimization run to the canonical two-file format:

- `<path>`              — JLD2 payload (large arrays, grid, fiber dict).
- `<basename>.json`     — sidecar with scalar metadata.

Arguments:
- `path`   — output JLD2 path. May end in `.jld2` (recommended) or anything
             else; the sidecar is always named `<strip_extension(path)>.json`.
- `result` — a NamedTuple with keys `phi_opt`, `uω0`, `uωf`,
             `convergence_history`, `grid`, `fiber`, `metadata`.

Keywords:
- `schema_version` — string written to the sidecar. Defaults to the current
  constant `OUTPUT_FORMAT_SCHEMA_VERSION`.

Does not mutate `result`. Returns the path to the JSON sidecar as a String.

The sidecar's `metadata` is taken verbatim from `result.metadata` (assumed to
contain the scalars listed in `_SIDECAR_REQUIRED_SCALARS` minus
`schema_version` and `payload_file`, which `save_run` fills in).

See also: `load_run`, `docs/output-format.md`.
"""
function save_run(path::AbstractString, result; schema_version::AbstractString=OUTPUT_FORMAT_SCHEMA_VERSION)
    # Validate required fields are present
    for k in _JLD2_REQUIRED_KEYS
        hasproperty(result, k) || throw(ArgumentError("save_run: result missing required field :$k"))
    end

    # 1. Write JLD2 payload
    jld2_path = String(path)
    mkpath(dirname(jld2_path) == "" ? "." : dirname(jld2_path))
    JLD2.jldopen(jld2_path, "w") do f
        f["phi_opt"]             = collect(result.phi_opt)
        f["uω0"]                 = collect(result.uω0)
        f["uωf"]                 = collect(result.uωf)
        f["convergence_history"] = collect(result.convergence_history)
        f["grid"]                = result.grid
        f["fiber"]               = result.fiber
        f["metadata"]            = result.metadata
    end

    # 2. Assemble JSON sidecar
    sidecar_path = _sidecar_path_for(jld2_path)
    meta = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in result.metadata)
    meta[:schema_version] = schema_version
    meta[:payload_file]   = basename(jld2_path)

    # Defensive: ensure all required scalar keys exist so the sidecar is complete.
    for k in _SIDECAR_REQUIRED_SCALARS
        haskey(meta, k) || @warn "save_run: sidecar field :$k missing from result.metadata (writing anyway)"
    end

    # phi_opt_rad inline-vs-omit
    n = length(result.phi_opt)
    if n < PHI_OPT_INLINE_LIMIT
        meta[:phi_opt_rad] = collect(Float64, result.phi_opt)
    else
        meta[:phi_opt_rad_note] = "omitted: length ≥ $PHI_OPT_INLINE_LIMIT; read from payload_file"
    end

    open(sidecar_path, "w") do io
        JSON3.pretty(io, meta)
    end

    return sidecar_path
end

"""
    load_run(path) -> NamedTuple

Load a run saved by `save_run`. The path may point to either the JLD2 payload
or the JSON sidecar — both resolve to the same pair of files.

Returns a NamedTuple with fields:
`phi_opt`, `uω0`, `uωf`, `convergence_history`, `grid`, `fiber`, `metadata`,
`sidecar` (the parsed JSON).

Verifies `schema_version` against the current `OUTPUT_FORMAT_SCHEMA_VERSION` and
emits an `@warn` on mismatch; the load still succeeds so older runs remain
readable.
"""
function load_run(path::AbstractString)
    path = String(path)
    jld2_path, sidecar_path = _resolve_pair(path)

    sidecar = JSON3.read(read(sidecar_path, String))

    if !haskey(sidecar, :schema_version)
        @warn "load_run: sidecar has no schema_version field (pre-Phase-16 run?)"
    elseif String(sidecar.schema_version) != OUTPUT_FORMAT_SCHEMA_VERSION
        @warn "load_run: schema_version mismatch" found=sidecar.schema_version expected=OUTPUT_FORMAT_SCHEMA_VERSION
    end

    payload = JLD2.jldopen(jld2_path, "r") do f
        (
            phi_opt             = read(f, "phi_opt"),
            uω0                 = read(f, "uω0"),
            uωf                 = read(f, "uωf"),
            convergence_history = read(f, "convergence_history"),
            grid                = read(f, "grid"),
            fiber               = read(f, "fiber"),
            metadata            = read(f, "metadata"),
        )
    end

    return (
        phi_opt             = payload.phi_opt,
        uω0                 = payload.uω0,
        uωf                 = payload.uωf,
        convergence_history = payload.convergence_history,
        grid                = payload.grid,
        fiber               = payload.fiber,
        metadata            = payload.metadata,
        sidecar             = sidecar,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Private helpers
# ─────────────────────────────────────────────────────────────────────────────

function _sidecar_path_for(jld2_path::String)::String
    stem, _ = splitext(jld2_path)
    return string(stem, ".json")
end

function _resolve_pair(path::String)::Tuple{String, String}
    stem, ext = splitext(path)
    if lowercase(ext) == ".json"
        sidecar = path
        sidecar_data = JSON3.read(read(sidecar, String))
        # Prefer the sidecar's declared payload_file if present; else assume <stem>.jld2
        jld2 = if haskey(sidecar_data, :payload_file)
            joinpath(dirname(path), String(sidecar_data.payload_file))
        else
            string(stem, ".jld2")
        end
    else
        jld2    = path
        sidecar = string(stem, ".json")
    end
    isfile(jld2)    || throw(ArgumentError("load_run: JLD2 payload not found: $jld2"))
    isfile(sidecar) || throw(ArgumentError("load_run: JSON sidecar not found: $sidecar"))
    return (jld2, sidecar)
end

end  # include guard

# ═══════════════════════════════════════════════════════════════════════════════
# Self-test — runs only when this file is executed directly as a script.
# Keeps the test close to the code it verifies; the fast-tier test in
# test/tier_fast.jl reuses save_run/load_run with the same pattern.
# ═══════════════════════════════════════════════════════════════════════════════

if abspath(PROGRAM_FILE) == @__FILE__
    using Printf
    mktempdir() do dir
        path = joinpath(dir, "selftest.jld2")
        result = (
            phi_opt             = collect(range(0.0, stop=π, length=64)),
            uω0                 = ComplexF64[i + 0.5im for i in 1:64],
            uωf                 = ComplexF64[0.1*i - 0.2im for i in 1:64],
            convergence_history = Float64[-3.0, -10.0, -20.0, -35.0, -47.0],
            grid                = Dict("Nt"=>64, "Δt"=>1.5e-3, "ts"=>collect(1:64),
                                       "fs"=>collect(1:64), "ωs"=>collect(1:64)),
            fiber               = Dict("preset"=>"SMF28", "L"=>2.0),
            metadata            = Dict(
                "run_id"         => "selftest",
                "git_sha"        => "deadbeef",
                "julia_version"  => string(VERSION),
                "timestamp_utc"  => Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
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
                "seed"           => 42,
            ),
        )
        save_run(path, result)
        loaded = load_run(path)
        @assert loaded.phi_opt == result.phi_opt
        @assert loaded.uω0     == result.uω0
        @assert loaded.uωf     == result.uωf
        @assert loaded.convergence_history == result.convergence_history
        @assert loaded.metadata["run_id"] == "selftest"
        # Also verify the JSON-path form of load_run:
        loaded_via_json = load_run(joinpath(dir, "selftest.json"))
        @assert loaded_via_json.phi_opt == result.phi_opt
        println("PASS: output format round trip (schema $OUTPUT_FORMAT_SCHEMA_VERSION)")
    end
end
