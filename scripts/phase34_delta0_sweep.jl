# scripts/phase34_delta0_sweep.jl — Phase 34 Plan 01: Δ₀-sweep diagnostic.
#
# Runs bench-01-smf28-canonical/cold for 4 Δ₀ values in DELTA0_SWEEP_VALUES
# using the frozen SteihaugSolver. Answers Phase 33 open question 5 before
# Plans 02-04 commit to preconditioning.
#
# Invoke ONLY via burst-run-heavy (CLAUDE.md Rule 1 + Rule P5):
#
#     burst-ssh "cd fiber-raman-suppression && git pull && \
#                ~/bin/burst-run-heavy Q-phase34-delta0 \
#                'julia -t auto --project=. scripts/phase34_delta0_sweep.jl'"
#
# Do NOT launch bare `julia` (CLAUDE.md Rule 1 — all sim work runs on burst).

try using Revise catch end
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using LinearAlgebra
using Random
using Dates
using Printf
using JLD2
using MultiModeNoise

# ── pin deterministic numerical environment BEFORE any simulation call ────────
include(joinpath(@__DIR__, "determinism.jl"));    ensure_deterministic_environment()
include(joinpath(@__DIR__, "phase13_hvp.jl"));    ensure_deterministic_fftw()

# ── core libraries (read-only consumers) ──────────────────────────────────────
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "numerical_trust.jl"))
include(joinpath(@__DIR__, "trust_region_core.jl"))
include(joinpath(@__DIR__, "trust_region_telemetry.jl"))
include(joinpath(@__DIR__, "trust_region_optimize.jl"))

# ── benchmark config (single source of truth, shared with synthesis) ─────────
include(joinpath(@__DIR__, "phase33_benchmark_common.jl"))

# ══════════════════════════════════════════════════════════════════════════════
# Edge-fraction pre-flight (Phase 28 trust gate, pitfall P8)
#
# Before running the TR optimizer on φ0, do ONE forward solve and measure the
# temporal edge fraction of the input pulse. If it exceeds edge_frac_pass the
# attenuator is already eating the pulse → any optimization result is contaminated.
# Skip the config cleanly and emit an abort-stub trust_report.md.
# ══════════════════════════════════════════════════════════════════════════════

"""
    _pulse_edge_fraction(uω, sim) -> Float64

Fraction of temporal energy in the outer 5% of the time window (both tails
combined). Matches the convention used by Phase 21's edge_frac measurements.
"""
function _pulse_edge_fraction_delta0(uω::AbstractMatrix{<:Complex}, sim::Dict)
    Nt = sim["Nt"]
    # Time-domain field: IFFT of fftshift-ordered uω (same convention as solver).
    ut = MultiModeNoise.ifft(uω, 1)
    energy = sum(abs2, ut)
    energy > 0 || return NaN
    edge_n = max(1, round(Int, 0.05 * Nt))
    edge_energy = sum(abs2, @view ut[1:edge_n, :]) +
                  sum(abs2, @view ut[(end - edge_n + 1):end, :])
    return Float64(edge_energy / energy)
end

# ══════════════════════════════════════════════════════════════════════════════
# Per-run execution — Δ₀-sweep variant
# ══════════════════════════════════════════════════════════════════════════════

"""
    run_single_benchmark_delta0(cfg, Δ0; out_root)

Run one cold-start TR optimization on `cfg` with the given initial trust radius Δ0.
Δ₀-sweep is cold-start only — no warm_jld2 required. Per CLAUDE.md discipline we
`deepcopy(fiber)` before handing to the optimizer even in serial — defends
against future parallel callers and against the optimizer mutating
`fiber["zsave"]`.
"""
function run_single_benchmark_delta0(cfg, Δ0::Float64; out_root::AbstractString)
    # Output subdirectory named by Δ₀ value, e.g. delta0_0p5, delta0_0p01
    delta0_label = "delta0_" * replace(string(Δ0), "." => "p")
    out_dir = joinpath(out_root, cfg.tag, delta0_label)
    mkpath(out_dir)

    @info "─── $(cfg.tag) / cold / Δ₀=$(Δ0) ─────────────────────────────────"

    # ── build problem on the config grid (Nt, time_window_ps) ────────────────
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = cfg.fiber,
        L_fiber      = cfg.L,
        P_cont       = cfg.P,
        Nt           = cfg.Nt,
        time_window  = cfg.time_window_ps,
        β_order      = 3,
    )
    n = length(uω0)

    # ── initial phase: cold start only ───────────────────────────────────────
    # Δ₀-sweep is cold-start only — no warm_jld2 required. Pre-flight skipped.
    φ0 = zeros(Float64, n)

    # ── pre-flight edge-fraction trust gate (pitfall P8) ─────────────────────
    uω0_shaped = uω0 .* cis.(reshape(φ0, size(uω0)))
    edge_frac = _pulse_edge_fraction_delta0(uω0_shaped, sim)
    if isfinite(edge_frac) && edge_frac > TRUST_THRESHOLDS.edge_frac_pass
        @warn "pre-flight EDGE_FRAC_SUSPECT — skipping config" tag=cfg.tag Δ0=Δ0 edge_frac threshold=TRUST_THRESHOLDS.edge_frac_pass
        open(joinpath(out_dir, "trust_report.md"), "w") do io
            println(io, "# Trust Report — ", cfg.tag, " / cold / Δ₀=", Δ0)
            println(io)
            println(io, "- **Aborted pre-flight**: `EDGE_FRAC_SUSPECT`")
            println(io, @sprintf("- Input-shaped edge fraction: `%.3e`", edge_frac))
            println(io, @sprintf("- Threshold (edge_frac_pass): `%.3e`",
                                 TRUST_THRESHOLDS.edge_frac_pass))
            println(io, "- No TR run was executed.")
        end
        return nothing
    end
    @info "pre-flight edge_frac PASS" edge_frac

    # ── run the optimizer (deepcopy(fiber) per CLAUDE.md discipline) ─────────
    t0 = time()
    result = optimize_spectral_phase_tr(
        uω0, deepcopy(fiber), sim, band_mask;
        φ0                     = zeros(Float64, n),
        solver                 = SteihaugSolver(),      # explicit for clarity
        max_iter               = 50,
        Δ0                     = Δ0,                    # ← varies per sweep point
        Δ_max                  = 10.0,
        Δ_min                  = 1e-6,
        η1                     = 0.25,
        η2                     = 0.75,
        γ_shrink               = 0.25,
        γ_grow                 = 2.0,
        g_tol                  = 1e-5,
        H_tol                  = -1e-6,
        λ_gdd                  = 0.0,
        λ_boundary             = 0.0,
        log_cost               = false,
        lambda_probe_cadence   = 10,
        stall_window           = 10,
        telemetry_path         = joinpath(out_dir, "telemetry.csv"),
    )
    wall_s = time() - t0

    # ── MANDATORY standard images (CLAUDE.md §Standard output) ──────────────
    save_standard_set(
        result.minimizer, uω0, fiber, sim,
        band_mask, Δf, raman_threshold;
        tag        = "$(cfg.tag)_cold_$(delta0_label)",
        fiber_name = string(cfg.fiber),
        L_m        = cfg.L,
        P_W        = cfg.P,
        output_dir = out_dir,
    )

    # ── per-run result bundle ────────────────────────────────────────────────
    jsave = joinpath(out_dir, "_result.jld2")
    jldsave(jsave;
        phi_opt           = result.minimizer,
        J_final           = result.J_final,
        exit_code         = string(result.exit_code),
        iterations        = result.iterations,
        hvps_total        = result.hvps_total,
        grad_calls_total  = result.grad_calls_total,
        forward_only_total = result.forward_only_calls_total,
        lambda_min_final  = result.lambda_min_final,
        lambda_max_final  = result.lambda_max_final,
        wall_s            = wall_s,
        benchmark_tag     = cfg.tag,
        start_type        = "cold",
        Nt                = cfg.Nt,
        time_window_ps    = cfg.time_window_ps,
        fiber_name        = string(cfg.fiber),
        L_m               = cfg.L,
        P_W               = cfg.P,
        edge_frac_preflight = edge_frac,
        delta0            = Δ0,
        solver_type       = "SteihaugSolver",
    )

    # ── trust-report section (Phase 28 additive) ─────────────────────────────
    trust_md = joinpath(out_dir, "trust_report.md")
    # Seed a minimal header so append_trust_report_section has context.
    if !isfile(trust_md)
        open(trust_md, "w") do io
            println(io, "# Trust Report — ", cfg.tag, " / cold / Δ₀=", Δ0)
            println(io)
            println(io, @sprintf("- Pre-flight edge fraction: `%.3e` (PASS)", edge_frac))
            println(io, @sprintf("- Δ₀ swept: `%.4g`", Δ0))
            println(io, @sprintf("- Start type: cold (φ₀ = 0)"))
            println(io, @sprintf("- Warm-start source: N/A (cold-only sweep)"))
            println(io, @sprintf("- Warm-start note: %s", cfg.warm_note))
        end
    end
    append_trust_report_section(
        trust_md,
        Dict{String,Any}(
            "exit_code"                => string(result.exit_code),
            "iterations"               => result.iterations,
            "J_final"                  => result.J_final,
            "hvps_total"               => result.hvps_total,
            "grad_calls_total"         => result.grad_calls_total,
            "forward_only_calls_total" => result.forward_only_calls_total,
            "wall_time_s"              => wall_s,
            "lambda_min_final"         => result.lambda_min_final,
            "lambda_max_final"         => result.lambda_max_final,
        ),
        result.telemetry,
    )

    @info @sprintf("%s/cold/Δ₀=%.4g: exit=%s J=%.3e iter=%d hvps=%d wall=%.1fs",
                   cfg.tag, Δ0, string(result.exit_code),
                   result.J_final, result.iterations, result.hvps_total, wall_s)
    return nothing
end

# ══════════════════════════════════════════════════════════════════════════════
# Main entry — skipped when the file is `include`d (tests, REPL)
# ══════════════════════════════════════════════════════════════════════════════

if abspath(PROGRAM_FILE) == @__FILE__
    @info "phase34 delta0 sweep starting" threads=Threads.nthreads() julia_version=VERSION
    out_root = get(ENV, "PHASE34_DELTA0_OUT", "results/raman/phase34/delta0_sweep")
    mkpath(out_root)

    cfg = BENCHMARK_CONFIGS[1]  # bench-01-smf28-canonical
    @assert cfg.tag == "bench-01-smf28-canonical"

    @info "delta0 sweep plan" config=cfg.tag start_type=:cold n_delta0=length(DELTA0_SWEEP_VALUES) delta0_values=DELTA0_SWEEP_VALUES

    for Δ0 in DELTA0_SWEEP_VALUES
        try
            run_single_benchmark_delta0(cfg, Δ0; out_root = out_root)
        catch e
            @error "delta0 sweep Δ0=$(Δ0) crashed — logging and continuing" exception = (e, catch_backtrace())
        end
    end

    @info "phase34 delta0 sweep done"
end
