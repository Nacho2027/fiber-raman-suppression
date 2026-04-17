#!/usr/bin/env julia
# scripts/regenerate_standard_images.jl
# ─────────────────────────────────────────────────────────────────────────────
# Post-hoc standard-image generator. Walks a results directory, finds every
# JLD2 that carries a phi_opt and its config, rebuilds the fiber/sim, runs the
# forward propagation, and writes the canonical image set via save_standard_set.
#
# Useful for:
#   - Regenerating standard images after an optimizer driver changes format
#   - Producing the standard set for old runs that were saved before the
#     "every driver must call save_standard_set" rule was in place.
#
# Usage (on the burst VM, behind the heavy-lock):
#   ~/bin/burst-run-heavy R-stdimages \
#       'julia -t auto --project=. scripts/regenerate_standard_images.jl'
#
# By default, scans results/raman/ recursively. Override via REGEN_ROOT env.

ENV["MPLBACKEND"] = "Agg"

using JLD2, Printf, Logging

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))

using MultiModeNoise

const ROOT = get(ENV, "REGEN_ROOT", joinpath(@__DIR__, "..", "results", "raman"))
const OUTPUT_SUBDIR = "standard_images"    # sibling folder next to each JLD2

function find_candidates(root)
    found = String[]
    for (dir, _, files) in walkdir(root)
        for f in files
            if endswith(f, ".jld2")
                push!(found, joinpath(dir, f))
            end
        end
    end
    return found
end

"""
Try to extract (phi_opt, config-dict, tag) from an arbitrary JLD2 payload.
Returns nothing if the file doesn't look like an optimizer run.
"""
function try_extract(path)
    local d
    try
        d = JLD2.load(path)
    catch e
        @warn "skip (JLD2 load failed)" path error=e
        return nothing
    end

    # Case A: sweep2_LP_fiber.jld2 style — array of results with phi_opt inside
    if haskey(d, "results") && d["results"] isa AbstractVector &&
       !isempty(d["results"]) && d["results"][1] isa AbstractDict
        return (kind=:sweep_array, results=d["results"], source=path)
    end

    # Case B: single-run JLD2 with phi_opt at top level
    if haskey(d, "phi_opt") && haskey(d, "fiber_preset") &&
       haskey(d, "L_fiber") && haskey(d, "P_cont")
        return (kind=:single, data=d, source=path)
    end

    # Case C: looks like an opt_result.jld2 — try common keys
    if haskey(d, "phi_opt")
        fiber = get(d, "fiber_preset", nothing)
        L = get(d, "L_fiber", get(d, "L", nothing))
        P = get(d, "P_cont", get(d, "P", nothing))
        if fiber !== nothing && L !== nothing && P !== nothing
            return (kind=:single, data=d, source=path)
        end
    end

    return nothing
end

function render_one(; phi_opt, fiber_preset, L, P, N_phi=nothing, label, out_dir)
    fiber_preset_sym = fiber_preset isa Symbol ? fiber_preset : Symbol(fiber_preset)

    # Setup: β_order must be >=3 for SMF28/HNLF presets (2 beta coeffs)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        Nt          = 2^14,
        time_window = 10.0,
        β_order     = 3,
        L_fiber     = Float64(L),
        P_cont      = Float64(P),
        fiber_preset = fiber_preset_sym,
    )

    # Sanity: phi_opt length must match sim["Nt"] (auto-sizing may have bumped it)
    if length(phi_opt) != sim["Nt"]
        @warn "phi length != sim Nt; skipping" label phi=length(phi_opt) Nt=sim["Nt"]
        return
    end

    fname = String(fiber_preset_sym)
    tag = lowercase(@sprintf("%s_L%.2fm_P%.3fW%s",
        fname, L, P, N_phi === nothing ? "" : "_Nphi$(N_phi)"))
    tag = replace(tag, "." => "p")   # file-system-friendly

    @info "regenerating" label tag out_dir
    save_standard_set(phi_opt, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag = tag,
        fiber_name = fname,
        L_m = L,
        P_W = P,
        output_dir = out_dir,
    )
end

# ─── main ────────────────────────────────────────────────────────────────

@info "scanning for optimizer runs" root=ROOT
candidates = find_candidates(ROOT)
@info "found JLD2 files" count=length(candidates)

n_rendered = 0
for path in candidates
    ex = try_extract(path)
    ex === nothing && continue

    parent = dirname(path)
    out_dir = joinpath(parent, OUTPUT_SUBDIR)

    if ex.kind == :sweep_array
        for (i, r) in enumerate(ex.results)
            cfg = get(r, "config", nothing)
            cfg === nothing && continue
            fp = get(cfg, :fiber_preset, get(cfg, "fiber_preset", nothing))
            L  = get(cfg, :L_fiber,      get(cfg, "L_fiber",      nothing))
            P  = get(cfg, :P_cont,       get(cfg, "P_cont",       nothing))
            φ  = get(r,   "phi_opt",     nothing)
            Nφ = get(r,   "N_phi",       get(cfg, :N_phi, nothing))
            if fp === nothing || L === nothing || P === nothing || φ === nothing
                continue
            end
            try
                render_one(phi_opt=φ, fiber_preset=fp, L=L, P=P, N_phi=Nφ,
                           label="$(basename(path))#$i", out_dir=out_dir)
                n_rendered += 1
            catch e
                @warn "render failed" file=path i=i error=e
            end
        end

    elseif ex.kind == :single
        d = ex.data
        try
            render_one(
                phi_opt = d["phi_opt"],
                fiber_preset = d["fiber_preset"],
                L = d["L_fiber"],
                P = d["P_cont"],
                N_phi = get(d, "N_phi", nothing),
                label = basename(path),
                out_dir = out_dir,
            )
            n_rendered += 1
        catch e
            @warn "render failed" file=path error=e
        end
    end
end

@info "done" rendered=n_rendered
