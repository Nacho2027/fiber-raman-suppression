"""
Phase 13 Plan 01, Tasks 2–4: gauge-fix + polynomial projection across all
existing converged φ_opt results, plus diagnostic figures.

READ-ONLY consumer of:
  * scripts/phase13_primitives.jl (gauge_fix, polynomial_project, phase_similarity)
  * scripts/common.jl (input band reconstruction uses uomega0 from JLD2)
  * scripts/raman_optimization.jl (not directly imported; no re-optimisation here)

Inputs (no re-running of any optimisation):
  * results/raman/{smf28,hnlf}/<config>/opt_result.jld2  — canonical runs
  * results/raman/sweeps/{smf28,hnlf}/L*_P*/opt_result.jld2 — parameter sweeps
  * results/raman/sweeps/multistart/start_*/opt_result.jld2 — 10-start sweep

Outputs:
  * results/raman/phase13/gauge_polynomial_analysis.jld2
  * results/raman/phase13/gauge_polynomial_summary.csv
  * results/images/phase13/phase13_01_gauge_before_after.png
  * results/images/phase13/phase13_02_polynomial_residuals.png
  * results/images/phase13/phase13_03_polynomial_coefficients.png

Usage:
  julia --project=. scripts/phase13_gauge_and_polynomial.jl
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf
using Logging
using LinearAlgebra
using Statistics
using JLD2
using DelimitedFiles
using PyPlot
using FFTW

include(joinpath(@__DIR__, "phase13_primitives.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# P13_ constants
# ─────────────────────────────────────────────────────────────────────────────

const P13_RESULTS_ROOT = joinpath(@__DIR__, "..", "results")
const P13_RAMAN_DIR    = joinpath(P13_RESULTS_ROOT, "raman")
const P13_OUT_DATA     = joinpath(P13_RAMAN_DIR, "phase13")
const P13_OUT_IMG      = joinpath(P13_RESULTS_ROOT, "images", "phase13")

# Directory groups scanned on disk. Each entry is (group_label, glob_root).
const P13_SOURCE_GROUPS = [
    ("canonical_smf28",  joinpath(P13_RAMAN_DIR, "smf28")),
    ("canonical_hnlf",   joinpath(P13_RAMAN_DIR, "hnlf")),
    ("sweep_smf28",      joinpath(P13_RAMAN_DIR, "sweeps", "smf28")),
    ("sweep_hnlf",       joinpath(P13_RAMAN_DIR, "sweeps", "hnlf")),
    ("multistart",       joinpath(P13_RAMAN_DIR, "sweeps", "multistart")),
]

const P13_COLLAPSE_THRESHOLD = 0.10   # rms_after < 10% * rms_before → "collapsed"

# ─────────────────────────────────────────────────────────────────────────────
# JLD2 discovery & loading
# ─────────────────────────────────────────────────────────────────────────────

"""
    find_opt_files(root) -> Vector{String}

Recursively locate all `opt_result.jld2` files beneath `root`. Returns [] if
`root` doesn't exist (gracefully handles missing groups).
"""
function find_opt_files(root::AbstractString)
    isdir(root) || return String[]
    paths = String[]
    for (dir, _subdirs, files) in walkdir(root)
        for f in files
            if f == "opt_result.jld2"
                push!(paths, joinpath(dir, f))
            end
        end
    end
    return sort(paths)
end

"""
    load_optimum(jld2_path) -> NamedTuple

Load one optimisation result from disk and attach the derived quantities
Phase 13 needs: full input-band mask (reconstructed from |uomega0|²),
angular-frequency vector (rad/ps), and a short human-readable label.
"""
function load_optimum(jld2_path::AbstractString)
    d = JLD2.load(jld2_path)
    phi_opt = d["phi_opt"]
    uω0     = d["uomega0"]
    Nt      = Int(d["Nt"])
    Δt      = d["sim_Dt"]
    ω0      = d["sim_omega0"]
    J_after = d["J_after"]
    J_before = d["J_before"]
    delta_J_dB = d["delta_J_dB"]
    L       = d["L_m"]
    P       = d["P_cont_W"]
    fiber   = d["fiber_name"]
    converged = d["converged"]
    iterations = d["iterations"]
    # FFT-order angular-freq offset vector (rad/ps) — gauge basis.
    ω  = omega_vector(ω0, Δt, Nt)
    # Input-band mask reconstructed from the stored input spectrum
    # (the `band_mask` field in JLD2 is the OUTPUT Raman-band mask, not input)
    bmi = input_band_mask(uω0)
    # Keep the stored (output) band mask around for provenance
    bmo = BitVector(d["band_mask"])
    # Human-readable label, e.g. "smf28/L1m_P0.05W" or "multistart/start_03"
    rel = relpath(dirname(jld2_path), P13_RAMAN_DIR)
    return (
        path = jld2_path,
        label = rel,
        phi_opt = phi_opt,
        uomega0 = uω0,
        Nt = Nt,
        Δt = Δt,
        ω0 = ω0,
        omega = ω,
        band_mask_input = bmi,
        band_mask_output = bmo,
        L = L,
        P = P,
        fiber = fiber,
        J_after = J_after,
        J_before = J_before,
        J_after_dB = delta_J_dB + (J_before > 0 ? 10.0 * log10(J_before) : 0.0),
        converged = converged,
        iterations = iterations,
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Pipeline: gauge-fix + polynomial-project all optima
# ─────────────────────────────────────────────────────────────────────────────

"""
    process_all(source_groups) -> Vector{NamedTuple}

Walk each (group_label, root) pair, load every opt_result.jld2, apply the
gauge fix and polynomial projection, and return a list of per-optimum
NamedTuples ready for serialisation and plotting.
"""
function process_all(source_groups)
    records = NamedTuple[]
    for (group_label, root) in source_groups
        files = find_opt_files(root)
        isempty(files) && begin
            @warn "No opt_result.jld2 under $root — group $group_label skipped"
            continue
        end
        @info @sprintf("Group %-20s %3d files", group_label, length(files))
        for f in files
            try
                o = load_optimum(f)
                φ_gf, (C, α) = gauge_fix(o.phi_opt, o.band_mask_input, o.omega)
                proj = polynomial_project(φ_gf, o.omega, o.band_mask_input; orders=2:6)
                push!(records, (
                    group = group_label,
                    label = o.label,
                    path = o.path,
                    fiber = o.fiber,
                    L = o.L,
                    P = o.P,
                    Nt = o.Nt,
                    J_after = o.J_after,
                    J_after_dB = 10.0 * log10(max(o.J_after, 1e-20)),
                    converged = o.converged,
                    iterations = o.iterations,
                    phi_raw = o.phi_opt,
                    phi_gauge_fixed = φ_gf,
                    gauge_C = C,
                    gauge_alpha = α,
                    coeffs = proj.coeffs,
                    phi_poly = proj.phi_poly,
                    residual_fraction = proj.residual_fraction,
                    band_mask_input = o.band_mask_input,
                    band_mask_output = o.band_mask_output,
                    omega = o.omega,
                    uomega0 = o.uomega0,
                ))
            catch err
                @warn "Failed to process $f" exception=err
            end
        end
    end
    return records
end

# ─────────────────────────────────────────────────────────────────────────────
# Pairwise similarity (multi-start group)
# ─────────────────────────────────────────────────────────────────────────────

"""
    similarity_matrix(records; use_raw=false) -> (labels, rms, cos)

Compute pairwise RMS and cosine similarity across every record in `records`,
restricted to each record's OWN band_mask_input (all multi-start records
share identical band masks because they share the same (L, P, Nt)). If
band masks differ, the pair is skipped (NaN) — this keeps cross-config
comparisons safe.
"""
function similarity_matrix(records; use_raw::Bool=false)
    N = length(records)
    labels = [r.label for r in records]
    rms = fill(NaN, N, N)
    cos_ = fill(NaN, N, N)
    for i in 1:N, j in 1:N
        a = use_raw ? records[i].phi_raw : records[i].phi_gauge_fixed
        b = use_raw ? records[j].phi_raw : records[j].phi_gauge_fixed
        bm_i = records[i].band_mask_input
        bm_j = records[j].band_mask_input
        if size(a) != size(b) || length(bm_i) != length(bm_j) || any(bm_i .!= bm_j)
            continue
        end
        s = phase_similarity(a, b, bm_i)
        rms[i, j] = s.rms_diff
        cos_[i, j] = s.cosine_sim
    end
    return labels, rms, cos_
end

# ─────────────────────────────────────────────────────────────────────────────
# Collapse fraction
# ─────────────────────────────────────────────────────────────────────────────

"""
    collapse_fraction(records; threshold) -> Float64

Among all records that share the SAME (Nt, L, P, fiber) configuration AND
belong to group "multistart" (or any group with >1 member per config),
compute the fraction of pairs for which the gauge-fixed RMS difference
is less than `threshold` times the raw RMS difference.

Returns 0 if no multi-start pairs exist.
"""
function collapse_fraction(records; threshold::Real=P13_COLLAPSE_THRESHOLD)
    # Group records by (fiber, L, P, Nt)
    key_of(r) = (r.fiber, r.L, r.P, r.Nt)
    groups = Dict{Any, Vector{Int}}()
    for (i, r) in enumerate(records)
        push!(get!(groups, key_of(r), Int[]), i)
    end
    n_pairs = 0
    n_collapsed = 0
    for (_key, idxs) in groups
        length(idxs) < 2 && continue
        for i in idxs, j in idxs
            i >= j && continue
            a_raw = records[i].phi_raw
            b_raw = records[j].phi_raw
            a_gf  = records[i].phi_gauge_fixed
            b_gf  = records[j].phi_gauge_fixed
            bm    = records[i].band_mask_input
            size(a_raw) != size(b_raw) && continue
            s_raw = phase_similarity(a_raw, b_raw, bm)
            s_gf  = phase_similarity(a_gf, b_gf, bm)
            # Guard against zero baseline
            s_raw.rms_diff < eps() && continue
            n_pairs += 1
            if s_gf.rms_diff < threshold * s_raw.rms_diff
                n_collapsed += 1
            end
        end
    end
    return n_pairs == 0 ? 0.0 : n_collapsed / n_pairs, n_pairs, n_collapsed
end

# ─────────────────────────────────────────────────────────────────────────────
# Serialization — JLD2 + CSV
# ─────────────────────────────────────────────────────────────────────────────

"""
    write_jld2(records, pairwise_labels, rms_raw, rms_gf, cos_raw, cos_gf, path)

Serialise every per-optimum record into a single JLD2 for Plan 02 to reuse.
"""
function write_jld2(records, pairwise; path)
    mkpath(dirname(path))
    n = length(records)
    # Stack scalar fields into arrays
    groups     = String[r.group      for r in records]
    labels     = String[r.label      for r in records]
    fibers     = String[r.fiber      for r in records]
    Ls         = Float64[r.L         for r in records]
    Ps         = Float64[r.P         for r in records]
    Nts        = Int[r.Nt            for r in records]
    J_afters   = Float64[r.J_after   for r in records]
    J_afters_dB = Float64[r.J_after_dB for r in records]
    residuals  = Float64[r.residual_fraction for r in records]
    gauge_Cs   = Float64[r.gauge_C   for r in records]
    gauge_αs   = Float64[r.gauge_alpha for r in records]
    converged  = Bool[r.converged    for r in records]
    iterations = Int[r.iterations    for r in records]
    # Polynomial coefficients a2..a6 (always present)
    a2 = Float64[r.coeffs.a2 for r in records]
    a3 = Float64[r.coeffs.a3 for r in records]
    a4 = Float64[r.coeffs.a4 for r in records]
    a5 = Float64[r.coeffs.a5 for r in records]
    a6 = Float64[r.coeffs.a6 for r in records]
    ω_means  = Float64[r.coeffs.omega_mean for r in records]
    ω_ranges = Float64[r.coeffs.omega_range for r in records]
    # Phase arrays — Nt varies per record, so store as Vector{Vector}
    phi_raw_list = [vec(r.phi_raw) for r in records]
    phi_gf_list  = [vec(r.phi_gauge_fixed) for r in records]
    phi_poly_list = [r.phi_poly for r in records]
    bm_input_list = [collect(r.band_mask_input) for r in records]
    omega_list    = [r.omega for r in records]

    jldsave(path;
        # Provenance
        P13_VERSION = P13_VERSION,
        n_records = n,
        group = groups,
        label = labels,
        path_list = String[r.path for r in records],
        # Config
        fiber = fibers,
        L = Ls, P = Ps, Nt = Nts,
        converged = converged,
        iterations = iterations,
        # Cost
        J_after = J_afters,
        J_after_dB = J_afters_dB,
        # Gauge
        gauge_C = gauge_Cs,
        gauge_alpha = gauge_αs,
        # Polynomial
        a2 = a2, a3 = a3, a4 = a4, a5 = a5, a6 = a6,
        omega_mean = ω_means, omega_range = ω_ranges,
        residual_fraction = residuals,
        # Phase profiles (gauge-fixed; raw kept for provenance)
        phi_raw = phi_raw_list,
        phi_gauge_fixed = phi_gf_list,
        phi_poly = phi_poly_list,
        band_mask_input = bm_input_list,
        omega = omega_list,
        # Pairwise similarity (full N×N where comparable; NaN otherwise)
        pairwise_rms_raw = pairwise.rms_raw,
        pairwise_rms_gf  = pairwise.rms_gf,
        pairwise_cos_raw = pairwise.cos_raw,
        pairwise_cos_gf  = pairwise.cos_gf,
    )
    @info "Wrote $path"
end

"""
    write_csv(records, path)

Tabular summary — one row per optimum — for quick human inspection.
"""
function write_csv(records, path)
    mkpath(dirname(path))
    header = ["group", "label", "fiber", "L_m", "P_W", "Nt",
              "J_after", "J_after_dB", "converged", "iterations",
              "gauge_C", "gauge_alpha",
              "a2", "a3", "a4", "a5", "a6",
              "omega_mean", "omega_range", "residual_fraction"]
    rows = Vector{Any}[]
    for r in records
        push!(rows, [
            r.group, r.label, r.fiber, r.L, r.P, r.Nt,
            r.J_after, r.J_after_dB, r.converged, r.iterations,
            r.gauge_C, r.gauge_alpha,
            r.coeffs.a2, r.coeffs.a3, r.coeffs.a4, r.coeffs.a5, r.coeffs.a6,
            r.coeffs.omega_mean, r.coeffs.omega_range, r.residual_fraction,
        ])
    end
    open(path, "w") do io
        writedlm(io, vcat([header], rows), ',')
    end
    @info "Wrote $path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Figures
# ─────────────────────────────────────────────────────────────────────────────

"""
    figure_01_gauge_before_after(records; out_path)

Multi-start (or per-config clustered) overlay of φ_raw vs φ_gauge_fixed, to
make the "collapse under gauge fix" visually unmistakable. If a multistart
group exists it is preferred; otherwise falls back to the densest config.
"""
function figure_01_gauge_before_after(records; out_path)
    mkpath(dirname(out_path))
    # Prefer the multistart group; if absent, pick the (fiber, L, P, Nt)
    # group with the most members.
    multistart = filter(r -> r.group == "multistart", records)
    if !isempty(multistart)
        group_label = "multistart (10 random starts, SMF-28 P=0.2W L=2m)"
        sel = multistart
    else
        counts = Dict{Any, Int}()
        for r in records
            k = (r.fiber, r.L, r.P, r.Nt)
            counts[k] = get(counts, k, 0) + 1
        end
        key_max, n_max = argmax_with_val(counts)
        if n_max < 2
            @warn "No group with ≥2 members; Figure 1 will show a single curve"
            sel = records[1:1]
            group_label = string(records[1].label)
        else
            sel = filter(r -> (r.fiber, r.L, r.P, r.Nt) == key_max, records)
            group_label = @sprintf("%s L=%.2fm P=%.3fW (%d runs)",
                                    key_max[1], key_max[2], key_max[3], n_max)
        end
    end

    ω  = sel[1].omega
    bm = sel[1].band_mask_input
    # fftshift for display so low-to-high frequency reads left-to-right.
    ωs = fftshift(ω)
    bms = fftshift(bm)
    # All panels zoom to the input band (out-of-band phase is physically
    # meaningless because |uω0|² → 0 there; linear-in-ω extrapolation would
    # dominate the plot without adding information).
    ω_in = ωs[bms]
    xlim_zoom = isempty(ω_in) ? (-1.0, 1.0) :
                (1.3 * minimum(ω_in), 1.3 * maximum(ω_in))

    fig, axes = PyPlot.subplots(2, 2, figsize=(11, 7))

    # Row 1: raw φ
    ax = axes[1, 1]
    for r in sel
        ax.plot(ωs, fftshift(vec(r.phi_raw)), linewidth=1.0, alpha=0.75)
    end
    ax.set_title("Raw φ_opt (all members)")
    ax.set_xlabel("ω − ω₀ [rad/ps]")
    ax.set_ylabel("φ [rad]")
    ax.set_xlim(xlim_zoom)
    _shade_band!(ax, ωs, bms)

    ax = axes[1, 2]
    for r in sel
        φ = vec(r.phi_raw)
        φ = φ .- mean(φ[r.band_mask_input])
        ax.plot(ωs, fftshift(φ), linewidth=1.0, alpha=0.75)
    end
    ax.set_title("Raw φ_opt − mean (constant removed only)")
    ax.set_xlabel("ω − ω₀ [rad/ps]")
    ax.set_ylabel("φ − mean [rad]")
    ax.set_xlim(xlim_zoom)
    _shade_band!(ax, ωs, bms)

    # Row 2: gauge-fixed φ — zoomed so the linear extrapolation outside the
    # band doesn't visually dominate (it is not physically relevant, the
    # input pulse has zero energy out there).
    ax = axes[2, 1]
    for r in sel
        ax.plot(ωs, fftshift(vec(r.phi_gauge_fixed)), linewidth=1.0, alpha=0.75)
    end
    ax.set_title("Gauge-fixed φ  (C + α·ω removed over input band)")
    ax.set_xlabel("ω − ω₀ [rad/ps]")
    ax.set_ylabel("φ [rad]")
    ax.set_xlim(xlim_zoom)
    _shade_band!(ax, ωs, bms)

    # Overlay only the INPUT-BAND bins on the last panel, so the collapse
    # question can be read directly off the figure.
    ax = axes[2, 2]
    for r in sel
        φ = fftshift(vec(r.phi_gauge_fixed))
        φ_masked = copy(φ); φ_masked[.!bms] .= NaN
        ax.plot(ωs, φ_masked, linewidth=1.2, alpha=0.85)
    end
    ax.set_title("Gauge-fixed φ  (input-band only)")
    ax.set_xlabel("ω − ω₀ [rad/ps]")
    ax.set_ylabel("φ [rad]")
    if !isempty(ω_in)
        ax.set_xlim(minimum(ω_in), maximum(ω_in))
    end
    _shade_band!(ax, ωs, bms)

    fig.suptitle("Phase 13 Fig 1 — Gauge fix collapse check: " * group_label,
                 fontsize=12)
    fig.tight_layout()
    fig.savefig(out_path, dpi=300)
    PyPlot.close(fig)
    @info "Wrote $out_path"
end

"""
    figure_02_polynomial_residuals(records; out_path)

Residual fraction per optimum, grouped by source group. Log y-axis so
sub-1% residuals are still visible.
"""
function figure_02_polynomial_residuals(records; out_path)
    mkpath(dirname(out_path))
    # Sort records by group, then residual
    groups = unique([r.group for r in records])
    fig, ax = PyPlot.subplots(1, 1, figsize=(10, 5))
    cmap = PyPlot.get_cmap("tab10")
    colors = Dict(g => cmap((i - 1) / max(1, length(groups)))
                   for (i, g) in enumerate(groups))
    x_cursor = 1
    tick_positions = Float64[]
    tick_labels = String[]
    for g in groups
        members = filter(r -> r.group == g, records)
        if isempty(members); continue; end
        xs = x_cursor:(x_cursor + length(members) - 1)
        residuals = [max(r.residual_fraction, 1e-12) for r in members]
        ax.bar(xs, residuals, color=colors[g], label=g, alpha=0.85)
        push!(tick_positions, mean(xs))
        push!(tick_labels, g)
        x_cursor += length(members) + 1
    end
    ax.set_yscale("log")
    ax.set_ylabel("Residual fraction  ‖φ − poly(φ)‖² / ‖φ‖²   (input band)")
    ax.set_xlabel("optimum index (grouped)")
    ax.set_xticks(tick_positions)
    ax.set_xticklabels(tick_labels, rotation=20, ha="right")
    ax.axhline(0.10, linestyle="--", linewidth=1.0, color="gray", label="10% residual")
    ax.axhline(0.01, linestyle=":",  linewidth=1.0, color="gray", label="1% residual")
    ax.legend(loc="best", fontsize=8)
    ax.set_title("Phase 13 Fig 2 — Polynomial (orders 2..6) residual fraction per optimum")
    fig.tight_layout()
    fig.savefig(out_path, dpi=300)
    PyPlot.close(fig)
    @info "Wrote $out_path"
end

"""
    figure_03_polynomial_coefficients(records; out_path)

(a_2, a_3, a_4) scatter across parameter sweeps. Each point is one
sweep optimum; marker colour keyed to P, marker size to L. Separated
by fiber type.
"""
function figure_03_polynomial_coefficients(records; out_path)
    mkpath(dirname(out_path))
    sweeps = filter(r -> startswith(r.group, "sweep_"), records)
    if isempty(sweeps)
        @warn "No sweep records available for Fig 3 — falling back to all records"
        sweeps = records
    end

    # Drop residual-dominated records (residual > 0.95) since their polynomial
    # coefficients are effectively noise — fitting a 5-parameter polynomial to
    # a high-entropy signal produces meaningless coefficient values. These
    # records are precisely the ones that a future phase would reformulate
    # with a richer basis; they are not the target of Fig 3's smoothness check.
    usable = filter(r -> r.residual_fraction < 0.95, sweeps)
    n_dropped = length(sweeps) - length(usable)
    if n_dropped > 0
        @info "Fig 3: dropped $n_dropped records with residual_fraction >= 0.95"
    end
    if isempty(usable)
        @warn "Fig 3: all records have residual > 0.95; plotting all anyway"
        usable = sweeps
    end

    fig, axes = PyPlot.subplots(1, 3, figsize=(15, 4.8))

    fibers = unique([r.fiber for r in usable])
    marker_for = Dict(f => m for (f, m) in zip(fibers, ["o", "s", "D", "^"]))

    # Choose a symlog linear-threshold from the data itself so small clusters
    # (most optima) stay readable while the large-magnitude outliers (HNLF
    # high-L low-P points where polynomial fit saturates) remain visible.
    all_coeffs = vcat([[getfield(r.coeffs, c) for r in usable] for c in (:a2, :a3, :a4)]...)
    linthresh = max(10.0, quantile(abs.(all_coeffs), 0.5))

    scat_handles = Dict{String, Any}()  # one mappable per fiber for colorbar
    for (ax, (label, ai, bi)) in zip(
            axes,
            [("(a2, a3)", :a2, :a3), ("(a2, a4)", :a2, :a4), ("(a3, a4)", :a3, :a4)])
        for f in fibers
            members = filter(r -> r.fiber == f, usable)
            if isempty(members); continue; end
            xs = [getfield(r.coeffs, ai) for r in members]
            ys = [getfield(r.coeffs, bi) for r in members]
            P = [r.P for r in members]
            L = [r.L for r in members]
            sizes = @. 40 + 60 * L / max(maximum(L), 1)
            sc = ax.scatter(xs, ys, c=P, s=sizes, marker=marker_for[f],
                            alpha=0.85, cmap="viridis", edgecolor="k", linewidth=0.4,
                            label=f)
            scat_handles[f] = sc
        end
        ax.set_xscale("symlog"; linthresh=linthresh)
        ax.set_yscale("symlog"; linthresh=linthresh)
        ax.set_xlabel(String(ai) * " [rad]  (symlog)")
        ax.set_ylabel(String(bi) * " [rad]  (symlog)")
        ax.set_title(label)
        ax.axhline(0, color="gray", linewidth=0.5)
        ax.axvline(0, color="gray", linewidth=0.5)
        ax.legend(loc="best", fontsize=8, title="fiber / marker size ∝ L")
    end

    # Colorbar for P — placed to the right of the rightmost axis, not over the axes
    if !isempty(scat_handles)
        cbar = fig.colorbar(first(values(scat_handles)), ax=axes, orientation="vertical",
                             fraction=0.025, pad=0.03)
        cbar.set_label("P_cont [W]")
    end

    subtitle = n_dropped > 0 ?
        @sprintf(" — %d of %d sweep optima; %d dropped (residual ≥ 0.95)",
                 length(usable), length(sweeps), n_dropped) : ""
    fig.suptitle("Phase 13 Fig 3 — Polynomial coefficients (orders 2..4) across sweeps" * subtitle,
                 fontsize=11)
    fig.savefig(out_path, dpi=300, bbox_inches="tight")
    PyPlot.close(fig)
    @info "Wrote $out_path"
end

# ─────────────────────────────────────────────────────────────────────────────
# Small helpers
# ─────────────────────────────────────────────────────────────────────────────

function _shade_band!(ax, ωs, bms)
    if !any(bms); return; end
    # Shade a transparent band on the mask. Works even if the mask is
    # disconnected (e.g., FFT wrap); we shade a single extent since after
    # fftshift the mask is contiguous around ω=0 for typical centered pulses.
    ω_in = ωs[bms]
    ax.axvspan(minimum(ω_in), maximum(ω_in), alpha=0.08, color="C1",
               label="input band")
end

function argmax_with_val(d::Dict)
    best_k, best_v = nothing, typemin(valtype(d))
    for (k, v) in d
        if v > best_v
            best_k, best_v = k, v
        end
    end
    return best_k, best_v
end

# ─────────────────────────────────────────────────────────────────────────────
# Determinism check (Task 3 of plan)
# ─────────────────────────────────────────────────────────────────────────────

"""
    run_determinism_check(; out_md_path)

Run the canonical determinism config (SMF-28, P=0.2W, L=2m, Nt=8192,
max_iter=30) twice with identical Random.seed!(42) and single-threaded
FFTW/BLAS. Append verdict to `out_md_path`.

This function is deliberately separate from the main pipeline because it
re-runs an optimisation (the ONLY re-optimisation in Phase 13 Plan 01) —
at ~30 iterations it costs roughly 1 minute per run on the 2-vCPU host.
"""
function run_determinism_check(; out_md_path::AbstractString, max_iter::Integer=30)
    mkpath(dirname(out_md_path))
    cfg = (fiber_preset=:SMF28, P_cont=0.2, L_fiber=2.0, Nt=2^13,
           time_window=40.0, β_order=3)
    @info "Determinism check starting (config: $cfg)"
    res = determinism_check(; config=cfg, seed=42, max_iter=max_iter)
    verdict = res.identical ? "PASS (bit-identical phi_opt)" :
              (res.max_abs_diff < 1e-10 ? "PASS within 1e-10" :
               (res.max_abs_diff < 1e-6  ? "PASS within 1e-6"  : "FAIL"))

    md = """
    # Phase 13 Determinism Check

    Generated: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))

    ## Config
    - Fiber preset: :SMF28
    - P_cont: 0.2 W
    - L_fiber: 2.0 m
    - Nt: 8192
    - time_window: 40 ps
    - β_order: 3
    - Optimiser: L-BFGS (log-cost) with f_abstol = 0.01 dB
    - max_iter: $max_iter

    ## Environment
    - Random.seed!(42) set before each run
    - FFTW.set_num_threads(1), BLAS.set_num_threads(1)
    - $(res.notes)

    ## Result

    - Identical (==): **$(res.identical)**
    - max(|phi_a - phi_b|): **$(res.max_abs_diff)**
    - J_a: $(res.J_a)
    - J_b: $(res.J_b)

    ## Verdict

    determinism: $verdict
    """
    open(out_md_path, "w") do io
        write(io, md)
    end
    @info "Wrote $out_md_path — $verdict"
    return res, verdict
end

# Dates is needed by run_determinism_check
using Dates

# ─────────────────────────────────────────────────────────────────────────────
# Main entry point
# ─────────────────────────────────────────────────────────────────────────────

function main(; include_determinism::Bool=true)
    @info "Phase 13 Plan 01 — gauge_and_polynomial pipeline starting"
    mkpath(P13_OUT_DATA)
    mkpath(P13_OUT_IMG)

    # ── Load and process all optima ────────────────────────────────────────
    records = process_all(P13_SOURCE_GROUPS)
    @info @sprintf("Loaded %d optima across %d groups",
                   length(records), length(unique([r.group for r in records])))
    if isempty(records)
        @error "Zero JLD2 optima found — blocker, see plan Blockers section."
        return nothing
    end

    # ── Pairwise similarity (raw + gauge-fixed) ────────────────────────────
    labels, rms_raw, cos_raw = similarity_matrix(records; use_raw=true)
    _,      rms_gf,  cos_gf  = similarity_matrix(records; use_raw=false)
    pairwise = (labels=labels, rms_raw=rms_raw, rms_gf=rms_gf,
                cos_raw=cos_raw, cos_gf=cos_gf)

    # ── Collapse fraction (multi-start + same-config groups) ──────────────
    cf, n_pairs, n_collapsed = collapse_fraction(records)
    @info @sprintf("Collapse fraction (gauge fix): %.2f  (%d/%d pairs, thr=%.2f)",
                   cf, n_collapsed, n_pairs, P13_COLLAPSE_THRESHOLD)

    # ── Serialise ──────────────────────────────────────────────────────────
    write_jld2(records, pairwise;
               path=joinpath(P13_OUT_DATA, "gauge_polynomial_analysis.jld2"))
    write_csv(records, joinpath(P13_OUT_DATA, "gauge_polynomial_summary.csv"))

    # ── Figures ────────────────────────────────────────────────────────────
    figure_01_gauge_before_after(records;
        out_path=joinpath(P13_OUT_IMG, "phase13_01_gauge_before_after.png"))
    figure_02_polynomial_residuals(records;
        out_path=joinpath(P13_OUT_IMG, "phase13_02_polynomial_residuals.png"))
    figure_03_polynomial_coefficients(records;
        out_path=joinpath(P13_OUT_IMG, "phase13_03_polynomial_coefficients.png"))

    # ── Summary to stdout ──────────────────────────────────────────────────
    residuals = [r.residual_fraction for r in records]
    @info @sprintf("""
    ┌─ Phase 13 Plan 01 — gauge_and_polynomial summary ─┐
    │  records processed       : %d
    │  groups                  : %s
    │  median residual fraction: %.4f
    │  p90    residual fraction: %.4f
    │  max    residual fraction: %.4f
    │  pairs (same-config)     : %d
    │  collapsed (rms_gf < 10%% rms_raw): %d  (fraction %.2f)
    └───────────────────────────────────────────────────┘""",
        length(records),
        join(unique([r.group for r in records]), ", "),
        median(residuals), quantile(residuals, 0.90), maximum(residuals),
        n_pairs, n_collapsed, cf)

    # ── Determinism check (optional; this is the ONLY re-optimisation) ────
    determinism_verdict = "NOT RUN"
    if include_determinism
        try
            _res, determinism_verdict = run_determinism_check(;
                out_md_path=joinpath(P13_OUT_DATA, "determinism.md"), max_iter=30)
        catch err
            @warn "Determinism check failed" exception=err
            determinism_verdict = "ERROR: $(err)"
        end
    end

    return (records=records,
            pairwise=pairwise,
            collapse_fraction=cf,
            n_pairs=n_pairs,
            n_collapsed=n_collapsed,
            residuals=residuals,
            determinism_verdict=determinism_verdict)
end

# Only run when executed as a script, not when included.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
