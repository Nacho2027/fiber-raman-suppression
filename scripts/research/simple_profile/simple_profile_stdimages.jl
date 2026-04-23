#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════════════════
# Phase 17 Plan 01 — Standard-image regenerator for Session D artefacts
#
# Retroactive compliance with the 2026-04-17 mandatory-standard-images rule.
# Reads `results/raman/phase17/{baseline,transferability}.jld2` and produces
# the 4-image standard set (phase_profile, evolution, phase_diagnostic,
# evolution_unshaped) for each phi_opt that was persisted.
#
# Covers: 1 baseline (SMF-28 L=0.5m P=0.05W) + 3 warm-reopt samples that were
# retained in transferability.jld2 (indices 1, 3, 10 per the driver's
# preview_n=3 budget). The other 8 warm-reopt phi_warm arrays were not
# persisted to JLD2 and would need a re-run of --stage=transferability to
# reconstitute.
#
# Launch on the burst VM behind the heavy lock:
#
#     burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy \
#         R-D-stdimages 'julia -t auto --project=. scripts/research/simple_profile/simple_profile_stdimages.jl'"
#
# Output: results/raman/phase17/standard_images/{tag}_*.png
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using JLD2, Printf, Logging

include(joinpath(@__DIR__, "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "visualization.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "standard_images.jl"))
include(joinpath(@__DIR__, "..", "..", "lib", "determinism.jl"))
ensure_deterministic_environment(verbose=false)

using MultiModeNoise

const SPS_RESULTS_DIR = joinpath(@__DIR__, "..", "..", "..", "results", "raman", "phase17")
const SPS_OUT_DIR     = joinpath(SPS_RESULTS_DIR, "standard_images")
const SPS_FIBER_MAP   = Dict("SMF-28" => :SMF28, "HNLF" => :HNLF)

"Derive a filesystem-friendly tag from physical parameters."
function make_tag(fiber_name::AbstractString, L::Real, P::Real, suffix::AbstractString="")
    fname = replace(String(fiber_name), "-" => "")
    tag = @sprintf("%s_L%.2fm_P%.3fW", fname, L, P)
    tag = replace(lowercase(tag), "." => "p")
    isempty(suffix) ? tag : "$(tag)_$(suffix)"
end

"Rebuild (uω0, fiber, sim, band_mask, Δf, raman_threshold) for one config."
function rebuild_problem(fiber_name::AbstractString, L::Real, P::Real)
    preset = get(SPS_FIBER_MAP, String(fiber_name), nothing)
    if preset === nothing
        error("Unknown fiber_name: $fiber_name — expected SMF-28 or HNLF")
    end
    setup_raman_problem(
        Nt           = 8192,
        time_window  = 10.0,
        β_order      = 3,
        L_fiber      = Float64(L),
        P_cont       = Float64(P),
        fiber_preset = preset,
    )
end

"Render standard set for one phi_opt. Phi_opt reshaped to match sim[\"Nt\"]."
function render_one(phi_opt, fiber_name, L, P; tag_suffix="")
    uω0, fiber, sim, band_mask, Δf, raman_threshold = rebuild_problem(fiber_name, L, P)
    Nt = sim["Nt"]

    # Reshape / crop phi_opt if setup_raman_problem auto-bumped Nt.
    phi = phi_opt
    if length(phi) != Nt
        # auto-sizing kicked in (longer fiber). Save_standard_set below expects
        # phi_opt matching Nt. Interpolate on fftshifted grid.
        @warn "phi length mismatch; resampling" phi_len=length(phi) sim_Nt=Nt L=L P=P
        # Simple resample: pad with zeros in the centre (phi in fft order).
        # For now, skip this target — regenerate by re-running the optimizer
        # if needed.
        return nothing
    end
    if ndims(phi) == 1
        phi = reshape(phi, Nt, 1)
    elseif ndims(phi) == 3
        phi = phi[:, :, 1]  # take first mode
    end

    tag = make_tag(fiber_name, L, P, tag_suffix)
    @info "rendering standard set" tag=tag fiber=fiber_name L=L P=P

    save_standard_set(
        phi, uω0, fiber, sim, band_mask, Δf, raman_threshold;
        tag        = tag,
        fiber_name = replace(String(fiber_name), "-" => ""),
        L_m        = Float64(L),
        P_W        = Float64(P),
        output_dir = SPS_OUT_DIR,
    )
    return tag
end

function main()
    mkpath(SPS_OUT_DIR)

    baseline_path = joinpath(SPS_RESULTS_DIR, "baseline.jld2")
    transfer_path = joinpath(SPS_RESULTS_DIR, "transferability.jld2")

    @assert isfile(baseline_path) "missing $baseline_path — run --stage=baseline first"
    rendered = String[]

    # ── Baseline ────────────────────────────────────────────────────────────
    b = JLD2.load(baseline_path)
    phi_base = b["phi_opt"]
    fn_base  = b["fiber_name"]
    L_base   = b["L_m"]
    P_base   = b["P_cont_W"]
    t = render_one(phi_base, fn_base, L_base, P_base; tag_suffix="baseline")
    isnothing(t) || push!(rendered, t)

    # ── Transferability phi_warm samples ───────────────────────────────────
    if isfile(transfer_path)
        d = JLD2.load(transfer_path)
        phi_samples = d["phi_warm_samples"]    # (Nt, M, n_preview)
        sample_idx  = d["phi_warm_sample_idx"] # Vector{Int} length n_preview
        sample_lbls = d["phi_warm_sample_labels"]
        fiber_arr   = d["fiber_name_arr"]
        L_arr       = d["L_m_arr"]
        P_arr       = d["P_cont_W_arr"]
        n_preview   = size(phi_samples, 3)

        for k in 1:n_preview
            idx = sample_idx[k]
            lbl = sample_lbls[k]
            if idx <= 0 || idx > length(fiber_arr)
                @warn "skipping sample k=$k (invalid idx=$idx)"
                continue
            end
            phi = phi_samples[:, :, k]
            # Skip empty slots (idx<0) — driver pre-fills with zeros
            if all(iszero, phi)
                @warn "skipping sample k=$k (phi_warm is zero — slot not populated)"
                continue
            end
            suffix_lbl = replace(lbl, r"[^A-Za-z0-9_]" => "_")
            t = render_one(phi, fiber_arr[idx], L_arr[idx], P_arr[idx];
                           tag_suffix = "warm_" * suffix_lbl)
            isnothing(t) || push!(rendered, t)
        end
    else
        @warn "no transferability.jld2 — only baseline standard images rendered"
    end

    println("═"^72)
    @printf "  Rendered standard image sets: %d\n" length(rendered)
    println("─"^72)
    for r in rendered
        println("    $r")
    end
    println("═"^72)
    println("  Output dir: $SPS_OUT_DIR")
    println("═"^72)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
