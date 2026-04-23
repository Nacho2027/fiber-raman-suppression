"""
Phase 13 Plan 02 Task 3 — Hessian Eigenspectrum at a Converged L-BFGS Optimum.

READ-ONLY consumer of:
  * scripts/hvp.jl      — fd_hvp, build_oracle, ensure_deterministic_fftw
  * scripts/primitives.jl — input_band_mask, omega_vector, gauge_fix
  * scripts/common.jl            — setup_raman_problem (not modified)
  * scripts/raman_optimization.jl — cost_and_gradient (not modified, loaded lazily)
  * results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2 (SMF-28 canonical)
  * results/raman/sweeps/hnlf/L0.5m_P0.01W/opt_result.jld2 (HNLF canonical)
  * results/raman/phase13/gauge_polynomial_analysis.jld2 (Plan 01 output)

Outputs:
  * results/raman/phase13/hessian_{config}.jld2
  * results/images/phase13/phase13_04_hessian_eigvals_stem.png  (combined when both configs run)
  * results/images/phase13/phase13_05_top_eigenvectors.png      (combined)
  * results/images/phase13/phase13_06_bottom_eigenvectors.png   (combined)

Usage:
  julia --project=. --threads=auto scripts/hessian_eigspec.jl --config smf28_canonical
  julia --project=. --threads=auto scripts/hessian_eigspec.jl --config hnlf_canonical
  julia --project=. --threads=auto scripts/hessian_eigspec.jl --figures   # produces the 3 combined figures after both JLD2 exist

Key design decisions:
  - Arpack.eigs is the matrix-free Lanczos wrapper (already a project dependency).
  - :LR extracts top-K algebraic eigenvalues (largest real); :SR extracts
    bottom-K algebraic (smallest real, i.e., most-negative if indefinite, or
    smallest-positive if PSD). At a converged optimum of a physical cost,
    the Hessian is PSD-ish, so :SR should include the gauge null modes.
  - Matrix-free shift-invert is IMPOSSIBLE with Arpack (needs factorization);
    the plan's "shift-invert" fallback is therefore not usable here. Instead,
    we extract both wings wide enough (K=20 each) so near-zero modes surface
    as the "smallest :SR" values.
  - FFTW pinned to ESTIMATE + single-threaded at startup (Plan 01 found
    MEASURE causes 1 rad / 1.8 dB drift between supposedly identical runs).
"""

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf
using Logging
using LinearAlgebra
using Statistics
using Random
using FFTW
using JLD2
using Arpack
using Dates

include(joinpath(@__DIR__, "hvp.jl"))   # brings phase13_primitives too

# ─────────────────────────────────────────────────────────────────────────────
# P13_ constants (Phase 13 naming convention)
# ─────────────────────────────────────────────────────────────────────────────

const P13_HES_RESULTS_DIR = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "phase13")
const P13_HES_IMG_DIR     = joinpath(@__DIR__, "..", "..", "..", "..", "results", "images", "phase13")
const P13_HES_TOP_K = 20
const P13_HES_BOT_K = 20
const P13_HES_EPS_DEFAULT = 1e-4     # HVP finite-difference step
const P13_HES_MAXITER = 500          # Arpack Lanczos max iterations
const P13_HES_TOL = 1e-7             # Arpack relative tolerance
const P13_HES_NEAR_ZERO_REL = 1e-6   # |λ| < threshold · λ_max defines "near-zero"

# Canonical configuration registry. Config name -> (jld2_path, setup_kwargs).
# jld2_path is where the converged phi_opt lives; setup_kwargs reconstructs
# the (uω0, fiber, sim, band_mask) via setup_raman_problem so we don't
# need to persist those alongside phi_opt.
const P13_HES_CONFIGS = Dict(
    "smf28_canonical" => (
        jld2_path = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "sweeps", "smf28", "L2m_P0.2W", "opt_result.jld2"),
        setup_kwargs = (fiber_preset = :SMF28,
                        L_fiber = 2.0,
                        P_cont = 0.2,
                        Nt = 2^13,
                        time_window = 40.0,
                        β_order = 3),
        label = "SMF-28 canonical (L=2m, P=0.2W)",
    ),
    "hnlf_canonical" => (
        # Chosen per Plan 01 SUMMARY: the HNLF converged optimum with the LOWEST
        # polynomial residual (0.723) + deepest J (-74.4 dB).
        jld2_path = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "sweeps", "hnlf", "L0.5m_P0.01W", "opt_result.jld2"),
        setup_kwargs = (fiber_preset = :HNLF,
                        L_fiber = 0.5,
                        P_cont = 0.01,
                        Nt = 2^13,
                        time_window = 5.0,
                        β_order = 3),
        label = "HNLF canonical (L=0.5m, P=0.01W)",
    ),
)

# ─────────────────────────────────────────────────────────────────────────────
# Matrix-free HVP operator (Arpack.eigs-compatible)
# ─────────────────────────────────────────────────────────────────────────────
#
# Arpack.eigs accepts any object A that implements:
#     size(A), size(A, d), eltype(A), issymmetric(A), ishermitian(A),
#     LinearAlgebra.mul!(y, A, x)
# The matrix-free contract lets us plug fd_hvp in without building any
# explicit matrix.

struct HVPOperator{F, V}
    n::Int
    oracle::F
    phi::V
    eps::Float64
end

Base.size(H::HVPOperator) = (H.n, H.n)
Base.size(H::HVPOperator, d::Integer) = H.n
Base.eltype(::HVPOperator{F, V}) where {F, V} = Float64
LinearAlgebra.issymmetric(::HVPOperator) = true
LinearAlgebra.ishermitian(::HVPOperator) = true

function LinearAlgebra.mul!(y::AbstractVector, H::HVPOperator, x::AbstractVector)
    # Arpack feeds unit-norm vectors; fd_hvp rescales internally.
    y .= fd_hvp(H.phi, collect(x), H.oracle; eps=H.eps)
    return y
end

# Matrix multiplication (A*x) for display/debug; Arpack uses mul!
Base.:*(H::HVPOperator, x::AbstractVector) = fd_hvp(H.phi, collect(x), H.oracle; eps=H.eps)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    load_phi_opt(jld2_path) -> (phi_opt::Matrix{Float64}, metadata::NamedTuple)

Load a converged φ_opt from a Phase 7 / Plan 01 result file and extract
metadata needed to reconstruct the setup (λ0, L_m, P_cont_W, etc.).
"""
function load_phi_opt(jld2_path::AbstractString)
    @assert isfile(jld2_path) "JLD2 not found: $jld2_path"
    d = JLD2.load(jld2_path)
    phi_opt = d["phi_opt"]
    meta = (
        jld2_path = jld2_path,
        fiber_name = d["fiber_name"],
        L_m = d["L_m"],
        P_cont_W = d["P_cont_W"],
        lambda0_nm = d["lambda0_nm"],
        fwhm_fs = d["fwhm_fs"],
        gamma = d["gamma"],
        Nt = Int(d["Nt"]),
        time_window_ps = d["time_window_ps"],
        J_after = d["J_after"],
        delta_J_dB = d["delta_J_dB"],
        grad_norm = d["grad_norm"],
        converged = d["converged"],
        iterations = Int(d["iterations"]),
        sim_Dt = d["sim_Dt"],
        sim_omega0 = d["sim_omega0"],
    )
    return phi_opt, meta
end

"""
    run_eigendecomposition(config_name; eps, top_k, bot_k)

The main work function: load φ_opt, build oracle, wrap HVP operator, run
Arpack.eigs twice, save JLD2.

Returns the output path for downstream logging.
"""
function run_eigendecomposition(config_name::AbstractString;
                                eps::Real = P13_HES_EPS_DEFAULT,
                                top_k::Integer = P13_HES_TOP_K,
                                bot_k::Integer = P13_HES_BOT_K,
                                maxiter::Integer = P13_HES_MAXITER,
                                tol::Real = P13_HES_TOL)
    @assert haskey(P13_HES_CONFIGS, config_name) "unknown config: $config_name. Available: $(collect(keys(P13_HES_CONFIGS)))"
    cfg = P13_HES_CONFIGS[config_name]
    @info "═══════════════════════════════════════════════════════════════════"
    @info "  Phase 13 Plan 02 — Hessian eigenspectrum"
    @info "  Config: $config_name ($(cfg.label))"
    @info "═══════════════════════════════════════════════════════════════════"
    @info @sprintf("  JULIA_NUM_THREADS = %d (Threads.nthreads = %d)",
                   parse(Int, get(ENV, "JULIA_NUM_THREADS", "1")),
                   Threads.nthreads())

    # Pin FFTW: Plan 01 determinism.md showed MEASURE causes drift; ESTIMATE
    # is bitwise-deterministic across identical inputs.
    ensure_deterministic_fftw()
    @info @sprintf("  FFTW threads: %d, BLAS threads: %d",
                   FFTW.get_num_threads(), BLAS.get_num_threads())

    # 1. Load the converged optimum
    phi_opt_mat, opt_meta = load_phi_opt(cfg.jld2_path)
    @info "  Loaded φ_opt from $(cfg.jld2_path)"
    @info @sprintf("    L=%.2f m, P=%.3f W, Nt=%d, J_after=%.3e (%.1f dB), converged=%s, iters=%d",
                   opt_meta.L_m, opt_meta.P_cont_W, opt_meta.Nt,
                   opt_meta.J_after, opt_meta.delta_J_dB,
                   string(opt_meta.converged), opt_meta.iterations)
    @assert opt_meta.Nt == cfg.setup_kwargs.Nt "Nt mismatch: JLD2 says $(opt_meta.Nt), config says $(cfg.setup_kwargs.Nt)"

    # 2. Build the HVP oracle (reconstructs sim/fiber/band_mask deterministically)
    @info "  Building HVP oracle..."
    t_oracle = time()
    oracle, meta = build_oracle(cfg.setup_kwargs)
    @info @sprintf("  Oracle built in %.1f s; N = Nt·M = %d", time() - t_oracle, meta.Nt * meta.M)
    @info "  HVP objective surface: $(meta.objective_spec.scalar_surface)"
    @assert meta.Nt == opt_meta.Nt "oracle Nt $(meta.Nt) ≠ JLD2 Nt $(opt_meta.Nt)"

    # 3. Sanity check: gradient at phi_opt should be small (it's an optimum)
    phi_opt_flat = vec(copy(phi_opt_mat))
    g_check = oracle(phi_opt_flat)
    @info @sprintf("  ‖∇J(phi_opt)‖ = %.3e (JLD2 reports %.3e)",
                   norm(g_check), opt_meta.grad_norm)

    # 4. Wrap as HVP operator
    H_op = HVPOperator(length(phi_opt_flat), oracle, phi_opt_flat, eps)

    # 5. Arpack :LR (top-K algebraic eigenvalues)
    @info "  Running Arpack.eigs :LR for top $top_k eigenvalues..."
    t_top = time()
    local λ_top, V_top, n_iter_top
    try
        λ_top, V_top, n_iter_top = Arpack.eigs(H_op;
            nev = top_k, which = :LR, maxiter = maxiter, tol = tol)
    catch e
        @warn "Arpack :LR failed" exception=e
        rethrow(e)
    end
    t_top_el = time() - t_top
    @info @sprintf("  :LR done in %.1f s (nconv=%d, niter=%d)",
                   t_top_el, length(λ_top), n_iter_top)
    @info @sprintf("    λ_top[1..5] = %s", string(λ_top[1:min(5, end)]))

    # 6. Arpack :SR (bottom-K algebraic eigenvalues — most-negative or smallest-positive)
    @info "  Running Arpack.eigs :SR for bottom $bot_k eigenvalues..."
    t_bot = time()
    local λ_bot, V_bot, n_iter_bot
    try
        λ_bot, V_bot, n_iter_bot = Arpack.eigs(H_op;
            nev = bot_k, which = :SR, maxiter = maxiter, tol = tol)
    catch e
        @warn "Arpack :SR failed; retrying with increased maxiter and looser tol" exception=e
        λ_bot, V_bot, n_iter_bot = Arpack.eigs(H_op;
            nev = bot_k, which = :SR, maxiter = 2 * maxiter, tol = 10 * tol)
    end
    t_bot_el = time() - t_bot
    @info @sprintf("  :SR done in %.1f s (nconv=%d, niter=%d)",
                   t_bot_el, length(λ_bot), n_iter_bot)
    @info @sprintf("    λ_bot[end-4..end] = %s", string(λ_bot[end-min(4, length(λ_bot)-1):end]))

    # 7. Near-zero mode count: |λ| < 1e-6 · λ_max
    λ_max = maximum(λ_top)
    near_zero_thr = P13_HES_NEAR_ZERO_REL * abs(λ_max)
    # Union of both wings (most-negative and most-positive)
    all_λ = vcat(collect(λ_top), collect(λ_bot))
    near_zero_count = count(x -> abs(x) < near_zero_thr, all_λ)
    @info @sprintf("  λ_max = %.3e, near-zero threshold = %.3e (1e-6 · λ_max)",
                   λ_max, near_zero_thr)
    @info @sprintf("  Near-zero modes in reported 2K eigenvalues: %d", near_zero_count)

    # 8. Serialize
    mkpath(P13_HES_RESULTS_DIR)
    out_path = joinpath(P13_HES_RESULTS_DIR, "hessian_$(config_name).jld2")
    @info "  Saving eigendecomposition to $out_path"

    # ensure eigenvalues/eigenvectors are real-typed (Arpack returns Complex{Float64} for generic ops)
    λ_top_real = real.(λ_top)
    λ_bot_real = real.(λ_bot)
    V_top_real = real.(V_top)
    V_bot_real = real.(V_bot)
    jldsave(out_path;
        # Eigendata
        lambda_top = λ_top_real,
        eigenvectors_top = V_top_real,
        lambda_bottom = λ_bot_real,
        eigenvectors_bottom = V_bot_real,
        # Base point
        phi_opt = vec(phi_opt_flat),
        grad_at_phi_opt = g_check,
        # Arpack metadata
        n_iter_top = n_iter_top,
        n_iter_bottom = n_iter_bot,
        wall_time_top_s = t_top_el,
        wall_time_bottom_s = t_bot_el,
        hvp_eps = eps,
        arpack_tol = tol,
        arpack_maxiter = maxiter,
        top_k = top_k,
        bot_k = bot_k,
        near_zero_threshold = near_zero_thr,
        near_zero_count_reported = near_zero_count,
        # Grid + frequency info
        Nt = meta.Nt,
        M = meta.M,
        sim_Dt = meta.sim["Δt"],
        sim_omega0 = meta.sim["ω0"],
        omega = meta.omega,
        input_band_mask = meta.input_band_mask,
        output_band_mask = meta.band_mask,
        objective_surface = meta.objective_spec.scalar_surface,
        objective_scale = meta.objective_spec.scale,
        objective_log_cost = meta.objective_spec.log_cost,
        lambda_gdd = meta.objective_spec.lambda_gdd,
        lambda_boundary = meta.objective_spec.lambda_boundary,
        # Config provenance
        config_name = config_name,
        config_label = cfg.label,
        jld2_path = cfg.jld2_path,
        J_after = opt_meta.J_after,
        delta_J_dB = opt_meta.delta_J_dB,
        L_m = opt_meta.L_m,
        P_cont_W = opt_meta.P_cont_W,
        fiber_name = opt_meta.fiber_name,
        converged = opt_meta.converged,
        iterations = opt_meta.iterations,
        # Threading metadata (for reproducibility records)
        julia_nthreads = Threads.nthreads(),
        fftw_nthreads = FFTW.get_num_threads(),
        blas_nthreads = BLAS.get_num_threads(),
        completed_at = string(now()),
        phase13_hvp_version = P13_HVP_VERSION,
    )
    @info "  JLD2 save complete."
    return out_path
end

# ─────────────────────────────────────────────────────────────────────────────
# Figure production (runs after both JLD2 files exist)
# ─────────────────────────────────────────────────────────────────────────────

"""
    make_figures()

Generate the 3 Phase 13 Plan 02 figures once eigendecompositions for both
configs exist. Files are side-by-side panels (SMF-28 | HNLF).
"""
function make_figures()
    using_pyplot = try
        @eval using PyPlot
        true
    catch
        false
    end
    @assert using_pyplot "PyPlot not available — cannot render figures"
    smf_path = joinpath(P13_HES_RESULTS_DIR, "hessian_smf28_canonical.jld2")
    hnlf_path = joinpath(P13_HES_RESULTS_DIR, "hessian_hnlf_canonical.jld2")
    @assert isfile(smf_path) "missing: $smf_path"
    @assert isfile(hnlf_path) "missing: $hnlf_path"

    smf = JLD2.load(smf_path)
    hnlf = JLD2.load(hnlf_path)
    mkpath(P13_HES_IMG_DIR)

    _make_eigvals_stem(smf, hnlf)
    _make_top_eigvecs(smf, hnlf)
    _make_bot_eigvecs(smf, hnlf)
    @info "All 3 figures written to $P13_HES_IMG_DIR"
    return nothing
end

# Signed-log helper: f(x) = sign(x) · log10(1 + |x|·10^k) for a scale k
function _signed_log(x::AbstractVector, linthresh::Real)
    # matches matplotlib's SymLog: |x| < linthresh -> linear, else log
    return sign.(x) .* (log10.(1.0 .+ abs.(x) ./ linthresh))
end

function _collect_eigvals(d)
    λ = vcat(collect(d["lambda_top"]), collect(d["lambda_bottom"]))
    # Unique + sort by magnitude, preserving sign
    # Actually just sort algebraically for plotting
    return sort(λ)
end

function _make_eigvals_stem(smf, hnlf)
    fig, axs = subplots(1, 2, figsize=(14, 6))
    for (ax, d, title) in zip(axs, (smf, hnlf),
                               ("SMF-28 canonical (L=2m, P=0.2W)",
                                "HNLF canonical (L=0.5m, P=0.01W)"))
        λ_top = collect(d["lambda_top"])
        λ_bot = collect(d["lambda_bottom"])
        thr = d["near_zero_threshold"]
        λ_max = maximum(λ_top)
        # Symmetric-log y-axis scaled by the near-zero threshold
        # x positions: bot_k on the left (negative x), top_k on the right
        n_top = length(λ_top); n_bot = length(λ_bot)
        x_top = collect(1:n_top)
        x_bot = -collect(1:n_bot)
        # sort top descending, bottom ascending so the extremes are at the outside
        order_top = sortperm(λ_top; rev=true)
        order_bot = sortperm(λ_bot)
        λ_top_sorted = λ_top[order_top]
        λ_bot_sorted = λ_bot[order_bot]

        ax.stem(x_top, λ_top_sorted,
            linefmt="b-", markerfmt="bo", basefmt=" ",
            label=@sprintf("top-%d (algebraic)", n_top))
        ax.stem(x_bot, λ_bot_sorted,
            linefmt="r-", markerfmt="rs", basefmt=" ",
            label=@sprintf("bottom-%d (algebraic)", n_bot))

        # Near-zero threshold band
        ax.axhspan(-thr, thr, alpha=0.15, color="gray",
            label=@sprintf("|λ| < 10⁻⁶ · λ_max = %.1e", thr))

        ax.axhline(0, color="k", lw=0.5)
        ax.set_xlabel("Rank (negative = bottom, positive = top)")
        ax.set_ylabel("Eigenvalue λ (linear)")
        ax.set_title(title)
        ax.legend(loc="upper left", fontsize=9)
        ax.grid(alpha=0.3)
        # Annotate near-zero mode count
        near_zero = d["near_zero_count_reported"]
        ax.text(0.98, 0.02,
            @sprintf("near-zero modes in reported 2K: %d\nλ_max = %.2e", near_zero, λ_max),
            transform=ax.transAxes, ha="right", va="bottom", fontsize=9,
            bbox=Dict("facecolor" => "white", "alpha" => 0.8, "edgecolor" => "none"))
    end
    fig.suptitle("Phase 13 Fig 4: Hessian top-20 + bottom-20 eigenvalues at converged L-BFGS optima",
        fontsize=13)
    fig.tight_layout()
    out = joinpath(P13_HES_IMG_DIR, "phase13_04_hessian_eigvals_stem.png")
    fig.savefig(out, dpi=300, bbox_inches="tight")
    @info "  Saved $out"
    close(fig)
end

function _make_top_eigvecs(smf, hnlf)
    K_plot = 5
    fig, axs = subplots(2, 2, figsize=(14, 9),
        sharex=false, sharey=false,
        gridspec_kw=Dict("width_ratios" => [1.0, 1.0]))
    for (col, d, title) in zip(1:2, (smf, hnlf),
                               ("SMF-28 canonical",
                                "HNLF canonical"))
        λ_top = collect(d["lambda_top"])
        V_top = collect(d["eigenvectors_top"])   # (N, K_returned)
        omega = collect(d["omega"])              # rad/ps, FFT order
        in_mask = collect(d["input_band_mask"])

        # Rank top eigenvectors descending by |λ|
        order = sortperm(abs.(λ_top); rev=true)
        λ_sorted = λ_top[order]
        V_sorted = V_top[:, order]

        # Frequency axis: use THz and fftshift for plotting
        Δf = omega ./ (2π)
        shift_idx = sortperm(Δf)
        Δf_shift = Δf[shift_idx]

        # Top panel: eigenvalues
        ax_top = axs[1, col]
        ax_top.bar(1:min(K_plot, length(λ_sorted)), λ_sorted[1:min(K_plot, end)],
            color="steelblue", alpha=0.8)
        ax_top.set_xticks(1:min(K_plot, length(λ_sorted)))
        ax_top.set_xlabel("Rank k")
        ax_top.set_ylabel("λ_k")
        ax_top.set_title("$title — top-$K_plot eigenvalues")
        ax_top.grid(axis="y", alpha=0.3)

        # Bottom panel: eigenvectors as φ(ω)
        ax_bot = axs[2, col]
        colors = get_cmap("viridis").(range(0, 0.9, length=K_plot))
        # Shade the input band
        Δf_band = Δf[in_mask]
        if !isempty(Δf_band)
            ax_bot.axvspan(minimum(Δf_band), maximum(Δf_band),
                alpha=0.1, color="gold", label="input band")
        end
        for k in 1:min(K_plot, size(V_sorted, 2))
            v = V_sorted[:, k][shift_idx]
            # Normalize sign: choose sign so max |v| is positive
            imax = argmax(abs.(v))
            v = v .* sign(v[imax])
            ax_bot.plot(Δf_shift, v, color=colors[k], lw=1.2,
                label=@sprintf("k=%d, λ=%.2e", k, λ_sorted[k]))
        end
        ax_bot.set_xlabel("Δf (THz)")
        ax_bot.set_ylabel("eigenvector component")
        ax_bot.set_title("$title — top-$K_plot eigenvectors")
        ax_bot.legend(loc="best", fontsize=8)
        ax_bot.grid(alpha=0.3)
        # Zoom x-axis around the input band (±1.5× its extent)
        if !isempty(Δf_band)
            extent = maximum(Δf_band) - minimum(Δf_band)
            center = 0.5 * (maximum(Δf_band) + minimum(Δf_band))
            ax_bot.set_xlim(center - 0.75 * extent, center + 0.75 * extent)
        end
    end
    fig.suptitle("Phase 13 Fig 5: Top-5 Hessian eigenvectors — stiff directions at the optimum",
        fontsize=13)
    fig.tight_layout()
    out = joinpath(P13_HES_IMG_DIR, "phase13_05_top_eigenvectors.png")
    fig.savefig(out, dpi=300, bbox_inches="tight")
    @info "  Saved $out"
    close(fig)
end

function _make_bot_eigvecs(smf, hnlf)
    K_plot = 5
    fig, axs = subplots(2, 2, figsize=(14, 9),
        sharex=false, sharey=false)
    for (col, d, title) in zip(1:2, (smf, hnlf),
                               ("SMF-28 canonical",
                                "HNLF canonical"))
        λ_bot = collect(d["lambda_bottom"])
        V_bot = collect(d["eigenvectors_bottom"])
        omega = collect(d["omega"])
        in_mask = collect(d["input_band_mask"])

        # Rank by |λ| ascending (smallest-magnitude first) — these should be gauge + soft modes
        order = sortperm(abs.(λ_bot))
        λ_sorted = λ_bot[order]
        V_sorted = V_bot[:, order]

        Δf = omega ./ (2π)
        shift_idx = sortperm(Δf)
        Δf_shift = Δf[shift_idx]

        # Top: eigenvalues (signed)
        ax_top = axs[1, col]
        signed_colors = [λ >= 0 ? "steelblue" : "firebrick" for λ in λ_sorted[1:min(K_plot, end)]]
        ax_top.bar(1:min(K_plot, length(λ_sorted)), λ_sorted[1:min(K_plot, end)],
            color=signed_colors, alpha=0.8)
        ax_top.set_xticks(1:min(K_plot, length(λ_sorted)))
        ax_top.set_xlabel("Rank k (by |λ| ascending)")
        ax_top.set_ylabel("λ_k")
        ax_top.set_title("$title — bottom-$K_plot by |λ|")
        ax_top.grid(axis="y", alpha=0.3)
        ax_top.axhline(0, color="k", lw=0.5)

        # Bottom: eigenvectors
        ax_bot = axs[2, col]
        colors = get_cmap("plasma").(range(0, 0.9, length=K_plot))
        Δf_band = Δf[in_mask]
        if !isempty(Δf_band)
            ax_bot.axvspan(minimum(Δf_band), maximum(Δf_band),
                alpha=0.1, color="gold", label="input band")
        end
        # Reference curves for visual gauge-mode comparison
        # constant = 1 (normalised); linear = ω - mean(ω_band)
        ω_band = omega[in_mask]
        ω_mean = isempty(ω_band) ? 0.0 : mean(ω_band)
        # Normalise constant and linear over the full grid
        const_ref = ones(length(omega))
        const_ref ./= norm(const_ref)
        lin_ref = omega .- ω_mean
        lin_ref ./= norm(lin_ref)

        for k in 1:min(K_plot, size(V_sorted, 2))
            v = V_sorted[:, k][shift_idx]
            # Sign-normalise for display
            imax = argmax(abs.(v))
            v = v .* sign(v[imax])
            # Cosine similarity with constant and linear gauge modes
            cos_const = abs(dot(V_sorted[:, k], const_ref))
            cos_lin = abs(dot(V_sorted[:, k], lin_ref))
            marker = cos_const > 0.95 ? "  [gauge: C]" : (cos_lin > 0.95 ? "  [gauge: ω]" : "")
            ax_bot.plot(Δf_shift, v, color=colors[k], lw=1.2,
                label=@sprintf("k=%d, λ=%.2e%s", k, λ_sorted[k], marker))
        end
        # Overlay reference gauge modes (dashed)
        ax_bot.plot(Δf_shift, const_ref[shift_idx], "k--", alpha=0.5, lw=0.8, label="ref: constant")
        ax_bot.plot(Δf_shift, lin_ref[shift_idx], "k:", alpha=0.5, lw=0.8, label="ref: linear(ω−ω̄)")
        ax_bot.set_xlabel("Δf (THz)")
        ax_bot.set_ylabel("eigenvector component")
        ax_bot.set_title("$title — bottom-$K_plot eigenvectors (ranked by |λ|)")
        ax_bot.legend(loc="best", fontsize=7)
        ax_bot.grid(alpha=0.3)
        if !isempty(Δf_band)
            extent = maximum(Δf_band) - minimum(Δf_band)
            center = 0.5 * (maximum(Δf_band) + minimum(Δf_band))
            ax_bot.set_xlim(center - 0.75 * extent, center + 0.75 * extent)
        end
    end
    fig.suptitle("Phase 13 Fig 6: Bottom-5 Hessian eigenvectors — soft directions (gauge + genuine flatness)",
        fontsize=13)
    fig.tight_layout()
    out = joinpath(P13_HES_IMG_DIR, "phase13_06_bottom_eigenvectors.png")
    fig.savefig(out, dpi=300, bbox_inches="tight")
    @info "  Saved $out"
    close(fig)
end

# ─────────────────────────────────────────────────────────────────────────────
# CLI dispatch
# ─────────────────────────────────────────────────────────────────────────────

function _parse_args(args::AbstractVector{<:AbstractString})
    config = nothing
    do_figures = false
    eps = P13_HES_EPS_DEFAULT
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--config" && i < length(args)
            config = args[i+1]
            i += 2
        elseif a == "--figures"
            do_figures = true
            i += 1
        elseif a == "--eps" && i < length(args)
            eps = parse(Float64, args[i+1])
            i += 2
        elseif a == "--help" || a == "-h"
            println("Usage: julia --project=. --threads=auto $(@__FILE__) --config {smf28_canonical|hnlf_canonical}")
            println("       julia --project=. --threads=auto $(@__FILE__) --figures")
            println("Options:")
            println("  --config NAME   run eigendecomposition for the named config")
            println("  --figures       produce the 3 phase13 figures (requires both JLD2 to exist)")
            println("  --eps VAL       HVP finite-difference step (default $(P13_HES_EPS_DEFAULT))")
            exit(0)
        else
            @warn "unrecognised argument: $a"
            i += 1
        end
    end
    return (config = config, figures = do_figures, eps = eps)
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed = _parse_args(ARGS)
    if parsed.figures
        make_figures()
    elseif parsed.config !== nothing
        run_eigendecomposition(parsed.config; eps = parsed.eps)
    else
        @error "Specify --config NAME or --figures. Try --help."
        exit(2)
    end
end
