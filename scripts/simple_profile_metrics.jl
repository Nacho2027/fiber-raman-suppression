# ═══════════════════════════════════════════════════════════════════════════════
# Phase 16 Plan 01 — Simple Phase Profile Stability Study — Simplicity Metrics
# ═══════════════════════════════════════════════════════════════════════════════
#
#   julia --project=. scripts/simple_profile_metrics.jl
#
# Consumes:
#   results/raman/phase16/baseline.jld2              (required)
#   results/raman/phase13/gauge_polynomial_analysis.jld2 (reference-set fallback)
#   results/raman/sweeps/smf28/L*/opt_result.jld2    (reference-set primary, optional)
#
# Emits:
#   results/raman/phase16/simplicity.jld2
#
# Computes three simplicity metrics on each optimum:
#   1. Total variation (TV) of gauge-fixed phase over input band
#   2. Shannon entropy of |dφ/dω| histogram (32 bins)
#   3. Stationary-point count of Gaussian-smoothed dφ/dω
#
# Reports Pearson correlation between each metric and J_after_dB across the
# baseline + N≥1 reference optima, identifies the strongest predictor, and
# saves everything to `simplicity.jld2`.
# ═══════════════════════════════════════════════════════════════════════════════

ENV["MPLBACKEND"] = "Agg"

using Printf
using Logging
using Statistics
using LinearAlgebra
using FFTW
using JLD2
using Dates
using Interpolations

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "phase13_primitives.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Constants (SPM_ = Simple Profile Metrics)
# ─────────────────────────────────────────────────────────────────────────────

const SPM_VERSION = "1.0.0"
const SPM_RESULTS_DIR   = joinpath(@__DIR__, "..", "results", "raman", "phase16")
const SPM_PHASE13_DIR   = joinpath(@__DIR__, "..", "results", "raman", "phase13")
const SPM_SWEEP_DIR     = joinpath(@__DIR__, "..", "results", "raman", "sweeps", "smf28")
const SPM_SMOOTH_SIGMA_BINS = 5.0
const SPM_ENTROPY_BINS   = 32

# ─────────────────────────────────────────────────────────────────────────────
# Reference set loader
# ─────────────────────────────────────────────────────────────────────────────

"""
    _try_load_sweep(subdir, L, P)

Try to load a Phase 7 sweep result at the canonical path. Returns
`Union{NamedTuple, Nothing}`. Each NamedTuple has the fields needed by
`compute_metrics`.
"""
function _try_load_sweep(subdir::AbstractString, L::Real, P::Real)
    path = joinpath(SPM_SWEEP_DIR, subdir, "opt_result.jld2")
    if !isfile(path)
        return nothing
    end
    try
        d = JLD2.load(path)
        return (
            name = @sprintf("SMF-28 L=%.1fm P=%.2fW", L, P),
            L = L, P = P, fiber_name = "SMF-28",
            J_after_dB = d["J_final_dB"],
            phi_opt   = d["phi_opt"],
            uω0       = d["uomega0"],
            sim_omega0 = d["sim_omega0"],
            sim_Dt     = d["sim_Dt"],
            Nt         = size(d["phi_opt"], 1),
            source     = path,
        )
    catch e
        @warn "Could not parse sweep JLD2" path=path exception=e
        return nothing
    end
end

"""
    _try_load_phase13_row(L, P)

Fallback loader: use the Phase 13 `gauge_polynomial_analysis.jld2` to
extract the `phi_raw` entry for the (L, P) canonical SMF-28 saddle when
the sweep JLD2 is unavailable.
"""
function _try_load_phase13_row(L::Real, P::Real)
    path = joinpath(SPM_PHASE13_DIR, "gauge_polynomial_analysis.jld2")
    if !isfile(path)
        return nothing
    end
    try
        d = JLD2.load(path)
        # The Phase 13 file stores per-optimum `phi_raw`, `J_final_dB`,
        # `L_m`, `P_cont_W` arrays. Find the row matching (L, P).
        if !(haskey(d, "L_m") && haskey(d, "P_cont_W") && haskey(d, "phi_raw"))
            return nothing
        end
        Ls = d["L_m"]; Ps = d["P_cont_W"]; phis = d["phi_raw"]
        Jafter = haskey(d, "J_final_dB") ? d["J_final_dB"] : fill(NaN, length(Ls))
        idx = findfirst(i -> isapprox(Ls[i], L; atol=1e-6) &&
                             isapprox(Ps[i], P; atol=1e-6), 1:length(Ls))
        if isnothing(idx)
            return nothing
        end
        # Phase 13 uses Nt=2^13 with time_window=40 ps typically — use those.
        # If the file stores explicit Nt / Δt we use them; else compute from phi length.
        phi = phis[idx]
        Nt = size(phi, 1)
        # Best-effort: read sim_omega0 / sim_Dt if stored, else use SMF-28 defaults.
        sim_omega0 = haskey(d, "sim_omega0") ? d["sim_omega0"] : 2π * 2.9979e8 / 1550e-9 / 1e12
        sim_Dt     = haskey(d, "sim_Dt")     ? d["sim_Dt"]     : 40.0 / Nt
        uω0        = haskey(d, "uomega0")    ? d["uomega0"]    : nothing
        return (
            name = @sprintf("SMF-28 L=%.1fm P=%.2fW (phase13)", L, P),
            L = L, P = P, fiber_name = "SMF-28",
            J_after_dB = Jafter[idx],
            phi_opt   = phi,
            uω0       = uω0,
            sim_omega0 = sim_omega0,
            sim_Dt     = sim_Dt,
            Nt         = Nt,
            source     = path,
        )
    catch e
        @warn "Phase 13 fallback failed" path=path exception=e
        return nothing
    end
end

"""
    load_reference_optima() -> Vector{NamedTuple}

Collect the reference optima defined in decisions §4:
  • SMF-28 (L=2m, P=0.2W) — Phase 13 canonical saddle
  • SMF-28 (L=1m, P=0.1W) — mid-regime
  • SMF-28 (L=5m, P=0.2W) — near suppression horizon

For each, try the canonical sweep path first, then the Phase 13 fallback.
Missing entries are logged and skipped (synthesizer handles low-N gracefully).
"""
function load_reference_optima()
    wanted = [
        ("L2m_P0.2W", 2.0, 0.2),
        ("L1m_P0.1W", 1.0, 0.1),
        ("L5m_P0.2W", 5.0, 0.2),
    ]
    refs = NamedTuple[]
    for (sub, L, P) in wanted
        entry = _try_load_sweep(sub, L, P)
        if isnothing(entry)
            entry = _try_load_phase13_row(L, P)
        end
        if isnothing(entry)
            @warn @sprintf("Reference optimum unavailable: L=%.1fm P=%.2fW — skipped", L, P)
            continue
        end
        # Require phi_opt and uω0; if uω0 is missing we cannot build the
        # input-band mask so we skip.
        if isnothing(entry.uω0)
            @warn @sprintf("Reference optimum has no uω0 — skipped (%s)", entry.name)
            continue
        end
        push!(refs, entry)
    end
    @info @sprintf("Loaded %d reference optima (out of 3 attempted)", length(refs))
    return refs
end

# ─────────────────────────────────────────────────────────────────────────────
# Metric primitives
# ─────────────────────────────────────────────────────────────────────────────

"""
    _gaussian_smooth(y, sigma) -> Vector{Float64}

1D Gaussian smoothing with reflective boundary handling. `sigma` is in
samples; radius is 4σ.
"""
function _gaussian_smooth(y::AbstractVector{<:Real}, sigma::Real)
    @assert sigma > 0 "sigma must be positive"
    n = length(y)
    r = max(1, round(Int, 4 * sigma))
    ks = -r:r
    kernel = @. exp(-(ks^2) / (2 * sigma^2))
    kernel ./= sum(kernel)
    out = zeros(n)
    for i in 1:n
        s = 0.0
        for (jj, k) in enumerate(ks)
            idx = i + k
            if idx < 1
                idx = 2 - idx            # reflect at left edge
            elseif idx > n
                idx = 2 * n - idx        # reflect at right edge
            end
            idx = clamp(idx, 1, n)
            s += kernel[jj] * y[idx]
        end
        out[i] = s
    end
    return out
end

"""
    compute_total_variation(phi_gf, band_mask) -> Float64

TV of the gauge-fixed phase over the input band. Contiguous-index order.
"""
function compute_total_variation(phi_gf::AbstractArray{<:Real}, band_mask::AbstractVector{Bool})
    v = vec(phi_gf)[band_mask]
    length(v) < 2 && return 0.0
    return sum(abs.(diff(v)))
end

"""
    compute_spectral_entropy(phi_gf, band_mask; n_bins=32) -> Float64

Shannon entropy of the histogram of |dφ/dω| restricted to the input band.
Uses natural log; zeros are handled via the 0·log(0)=0 convention.
"""
function compute_spectral_entropy(phi_gf::AbstractArray{<:Real},
                                  band_mask::AbstractVector{Bool};
                                  n_bins::Integer=SPM_ENTROPY_BINS)
    v = vec(phi_gf)[band_mask]
    length(v) < 3 && return 0.0
    dphi = abs.(diff(v))
    mn, mx = extrema(dphi)
    if mx <= mn
        return 0.0
    end
    edges = range(mn, mx; length=n_bins + 1)
    counts = zeros(Int, n_bins)
    for x in dphi
        b = searchsortedlast(edges, x)
        b = clamp(b, 1, n_bins)
        counts[b] += 1
    end
    total = sum(counts)
    total == 0 && return 0.0
    H = 0.0
    for c in counts
        if c > 0
            p = c / total
            H -= p * log(p)
        end
    end
    return H
end

"""
    compute_stationary_points(phi_gf, band_mask; sigma_bins=5.0) -> Int

Count zero-crossings of the Gaussian-smoothed finite-difference derivative
of phi_gf over the input band. The band is treated as a contiguous slice
via `findall(band_mask)` + its min…max range (discontiguities are rare in
practice; we take the first contiguous block).
"""
function compute_stationary_points(phi_gf::AbstractArray{<:Real},
                                   band_mask::AbstractVector{Bool};
                                   sigma_bins::Real=SPM_SMOOTH_SIGMA_BINS)
    idx = findall(band_mask)
    length(idx) < 4 && return 0
    # Take the contiguous block covered by the band_mask (simple robust choice).
    i0, i1 = minimum(idx), maximum(idx)
    v = vec(phi_gf)[i0:i1]
    dphi = diff(v)
    dphi_s = _gaussian_smooth(dphi, sigma_bins)
    cnt = 0
    for i in 2:length(dphi_s)
        if sign(dphi_s[i]) != sign(dphi_s[i-1]) && dphi_s[i] != 0 && dphi_s[i-1] != 0
            cnt += 1
        end
    end
    return cnt
end

"""
    compute_metrics(phi_opt, uω0, sim_omega0, sim_Dt, Nt)

Apply gauge fix + compute (TV, entropy, stationary_pts, band_size).
Returns a NamedTuple.
"""
function compute_metrics(phi_opt::AbstractArray{<:Real}, uω0, sim_omega0::Real, sim_Dt::Real, Nt::Integer)
    @assert size(phi_opt, 1) == Nt "phi_opt/Nt mismatch"
    omega = omega_vector(sim_omega0, sim_Dt, Nt)
    mask  = input_band_mask(uω0)
    phi_col = size(phi_opt, 2) == 1 ? vec(phi_opt) : vec(phi_opt[:, 1])
    phi_gf, _ = gauge_fix(phi_col, mask, omega)

    tv      = compute_total_variation(phi_gf, mask)
    entropy = compute_spectral_entropy(phi_gf, mask)
    statpts = compute_stationary_points(phi_gf, mask)
    band_sz = sum(mask)
    return (tv=tv, entropy=entropy, stationary=statpts, band_size=band_sz, phi_gf=Vector{Float64}(phi_gf))
end

"""
    pearson(x, y) -> Float64

Pearson correlation; NaN if either has zero variance.
"""
function pearson(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    @assert length(x) == length(y) "length mismatch"
    length(x) < 2 && return NaN
    mx, my = mean(x), mean(y)
    dx, dy = x .- mx, y .- my
    denom = sqrt(sum(dx .^ 2) * sum(dy .^ 2))
    denom == 0 && return NaN
    return sum(dx .* dy) / denom
end

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

function main()
    mkpath(SPM_RESULTS_DIR)
    baseline_path = joinpath(SPM_RESULTS_DIR, "baseline.jld2")
    out_path      = joinpath(SPM_RESULTS_DIR, "simplicity.jld2")
    @assert isfile(baseline_path) "baseline.jld2 missing — run simple_profile_driver.jl --stage=baseline first"

    base = JLD2.load(baseline_path)
    base_entry = (
        name       = @sprintf("SMF-28 L=%.2fm P=%.3fW (baseline)", base["L_m"], base["P_cont_W"]),
        L          = base["L_m"]::Float64,
        P          = base["P_cont_W"]::Float64,
        fiber_name = base["fiber_name"]::String,
        J_after_dB = base["J_final_dB"]::Float64,
        phi_opt    = base["phi_opt"],
        uω0        = base["uomega0"],
        sim_omega0 = base["sim_omega0"]::Float64,
        sim_Dt     = base["sim_Dt"]::Float64,
        Nt         = base["Nt"]::Int,
        source     = baseline_path,
    )

    refs = load_reference_optima()

    all_entries = NamedTuple[base_entry]
    append!(all_entries, refs)
    n = length(all_entries)

    names   = [e.name for e in all_entries]
    J_arr   = [e.J_after_dB for e in all_entries]
    tv_arr  = fill(NaN, n); ent_arr = fill(NaN, n); st_arr = fill(NaN, n)
    band_sz_arr = fill(0, n)
    phi_gf_collection = Vector{Vector{Float64}}(undef, n)

    for (i, e) in enumerate(all_entries)
        m = compute_metrics(e.phi_opt, e.uω0, e.sim_omega0, e.sim_Dt, e.Nt)
        tv_arr[i]      = m.tv
        ent_arr[i]     = m.entropy
        st_arr[i]      = m.stationary
        band_sz_arr[i] = m.band_size
        phi_gf_collection[i] = m.phi_gf
    end

    # Correlations (across n points, if n ≥ 2)
    r_tv  = pearson(tv_arr,  J_arr)
    r_ent = pearson(ent_arr, J_arr)
    r_st  = pearson(Float64.(st_arr), J_arr)

    # Winner = largest |r|. If n == 1 or all NaN → inconclusive.
    winner = "INCONCLUSIVE_NREFS=$(n-1)"
    best_r = NaN
    if n >= 2
        candidates = [(abs(r_tv), "TV", r_tv),
                      (abs(r_ent), "entropy", r_ent),
                      (abs(r_st), "stationary", r_st)]
        # Ignore NaN entries
        candidates = [c for c in candidates if !isnan(c[1])]
        if !isempty(candidates)
            sort!(candidates; by=x -> -x[1])
            winner = candidates[1][2]
            best_r = candidates[1][3]
        end
    end

    # ── Print summary table ──
    println(repeat("═", 88))
    @printf("  %-44s  %10s  %10s  %10s  %10s\n",
        "optimum", "J_dB", "TV", "entropy", "stat_pts")
    println(repeat("─", 88))
    for i in 1:n
        @printf("  %-44s  %10.3f  %10.2f  %10.3f  %10d\n",
            names[i], J_arr[i], tv_arr[i], ent_arr[i], st_arr[i])
    end
    println(repeat("─", 88))
    @printf("  Pearson r vs J_dB:           TV=%.3f   entropy=%.3f   stationary=%.3f\n",
        r_tv, r_ent, r_st)
    @printf("  Winner (largest |r|): %s   (r=%.3f)\n", winner, best_r)
    println(repeat("═", 88))

    jldsave(out_path;
        phase = "16", plan = "01", script = "simple_profile_metrics",
        version = SPM_VERSION,
        created_at = string(Dates.now()),
        n_optima = n,
        names  = names,
        J_after_dB  = J_arr,
        TV_arr      = tv_arr,
        entropy_arr = ent_arr,
        stationary_arr = st_arr,
        band_size_arr = band_sz_arr,
        phi_gf_collection = phi_gf_collection,
        r_TV = r_tv,
        r_entropy = r_ent,
        r_stationary = r_st,
        winner = winner,
        best_r = best_r,
        sources = [e.source for e in all_entries],
    )
    @info "simplicity.jld2 written" path=out_path winner=winner best_r=best_r
    return out_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
