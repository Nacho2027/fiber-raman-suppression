# scripts/phase33_benchmark_run.jl — Phase 33 trust-region benchmark driver.
#
# Runs 3 configs × 3 start types = 9 TR runs via optimize_spectral_phase_tr.
# Each run emits: telemetry.csv + _result.jld2 + trust_report.md section +
# the MANDATORY 4-panel standard image set (per CLAUDE.md §Standard output).
#
# Invoke ONLY via burst-run-heavy with session tag P-phase33-tr (CLAUDE.md
# Rule 1 + Rule P5):
#
#     burst-ssh "cd fiber-raman-suppression && git pull && \
#                ~/bin/burst-run-heavy P-phase33-tr \
#                'julia -t auto --project=. scripts/phase33_benchmark_run.jl'"
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
# Pre-flight: hard-abort if any warm-start JLD2 is missing.
#
# Without this, a `:warm` or `:perturbed` start would silently fall back to cold,
# collapsing the NxM matrix and making the warm-start robustness claim
# unverifiable. Per the plan's <interfaces>, hard-fail is the intended contract.
# ══════════════════════════════════════════════════════════════════════════════

function _assert_warm_paths_present()
    missing_paths = String[]
    for cfg in BENCHMARK_CONFIGS
        if !isfile(cfg.warm_jld2)
            push!(missing_paths, "$(cfg.tag): $(cfg.warm_jld2)")
        end
    end
    if !isempty(missing_paths)
        error("Phase 33 benchmark ABORT — warm_jld2 paths not found:\n  " *
              join(missing_paths, "\n  ") *
              "\nFix BENCHMARK_CONFIGS in scripts/phase33_benchmark_common.jl, " *
              "or explicitly drop :warm/:perturbed from START_TYPES for affected " *
              "configs (edit the common file, not the driver).")
    end
    @info "warm_jld2 pre-flight passed" n_configs=length(BENCHMARK_CONFIGS)
    return nothing
end

_assert_warm_paths_present()

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
function _pulse_edge_fraction(uω::AbstractMatrix{<:Complex}, sim::Dict)
    Nt = sim["Nt"]
    # Time-domain field: IFFT of fftshift-ordered uω (same convention as solver).
    ut = MultiModeNoise.ifft(uω; dims = 1)
    energy = sum(abs2, ut)
    energy > 0 || return NaN
    edge_n = max(1, round(Int, 0.05 * Nt))
    edge_energy = sum(abs2, @view ut[1:edge_n, :]) +
                  sum(abs2, @view ut[(end - edge_n + 1):end, :])
    return Float64(edge_energy / energy)
end

# ══════════════════════════════════════════════════════════════════════════════
# Per-run execution
# ══════════════════════════════════════════════════════════════════════════════

"""
    run_single_benchmark(cfg, start_type, config_index; out_root)

Run one (config, start_type) TR optimization. Per CLAUDE.md discipline we
`deepcopy(fiber)` before handing to the optimizer even in serial — defends
against future parallel callers and against the optimizer mutating
`fiber["zsave"]`.
"""
function run_single_benchmark(cfg, start_type::Symbol, config_index::Int;
                              out_root::AbstractString)
    out_dir = joinpath(out_root, cfg.tag, string(start_type))
    mkpath(out_dir)

    @info "─── $(cfg.tag) / $(start_type) ───────────────────────────────────"

    # ── build problem on the WARM grid (Nt, time_window_ps) ──────────────────
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(
        fiber_preset = cfg.fiber,
        L_fiber      = cfg.L,
        P_cont       = cfg.P,
        Nt           = cfg.Nt,
        time_window  = cfg.time_window_ps,
        β_order      = 3,
    )
    n = length(uω0)

    # ── initial phase ────────────────────────────────────────────────────────
    φ0 = if start_type === :cold
        zeros(Float64, n)
    elseif start_type === :warm
        @assert isfile(cfg.warm_jld2)   # belt-and-suspenders; startup check is authoritative
        phi_mat = load(cfg.warm_jld2, "phi_opt")
        vphi = vec(Float64.(phi_mat))
        @assert length(vphi) == n "warm phi_opt length $(length(vphi)) ≠ Nt·M = $n for $(cfg.tag)"
        vphi
    elseif start_type === :perturbed
        phi_mat = load(cfg.warm_jld2, "phi_opt")
        vphi = vec(Float64.(phi_mat))
        @assert length(vphi) == n "perturbed phi_opt length $(length(vphi)) ≠ Nt·M = $n for $(cfg.tag)"
        rng = Xoshiro(42 + config_index)
        vphi .+ 0.05 .* randn(rng, n)
    else
        error("unknown start_type $start_type; expected :cold | :warm | :perturbed")
    end

    # ── pre-flight edge-fraction trust gate (pitfall P8) ─────────────────────
    uω0_shaped = @. uω0 * cis(reshape(φ0, size(uω0)))
    edge_frac = _pulse_edge_fraction(uω0_shaped, sim)
    if isfinite(edge_frac) && edge_frac > TRUST_THRESHOLDS.edge_frac_pass
        @warn "pre-flight EDGE_FRAC_SUSPECT — skipping config" tag=cfg.tag start_type edge_frac threshold=TRUST_THRESHOLDS.edge_frac_pass
        open(joinpath(out_dir, "trust_report.md"), "w") do io
            println(io, "# Trust Report — ", cfg.tag, " / ", start_type)
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
        φ0                     = φ0,
        max_iter               = 50,
        Δ0                     = 0.5,
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
        tag        = "$(cfg.tag)_$(start_type)",
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
        start_type        = string(start_type),
        Nt                = cfg.Nt,
        time_window_ps    = cfg.time_window_ps,
        fiber_name        = string(cfg.fiber),
        L_m               = cfg.L,
        P_W               = cfg.P,
        edge_frac_preflight = edge_frac,
    )

    # ── trust-report section (Phase 28 additive) ─────────────────────────────
    trust_md = joinpath(out_dir, "trust_report.md")
    # Seed a minimal header so append_trust_report_section has context.
    if !isfile(trust_md)
        open(trust_md, "w") do io
            println(io, "# Trust Report — ", cfg.tag, " / ", start_type)
            println(io)
            println(io, @sprintf("- Pre-flight edge fraction: `%.3e` (PASS)", edge_frac))
            println(io, @sprintf("- Warm-start source: `%s`", cfg.warm_jld2))
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

    @info @sprintf("%s/%s: exit=%s J=%.3e iter=%d hvps=%d wall=%.1fs",
                   cfg.tag, start_type, string(result.exit_code),
                   result.J_final, result.iterations, result.hvps_total, wall_s)
    return nothing
end

# ══════════════════════════════════════════════════════════════════════════════
# Main entry — skipped when the file is `include`d (tests, REPL, Plan 03)
# ══════════════════════════════════════════════════════════════════════════════

if abspath(PROGRAM_FILE) == @__FILE__
    @info "phase33 benchmark starting" threads=Threads.nthreads() julia_version=VERSION
    out_root = get(ENV, "PHASE33_OUT", "results/raman/phase33")
    mkpath(out_root)

    n_total = length(BENCHMARK_CONFIGS) * length(START_TYPES)
    @info "sweep plan" configs=length(BENCHMARK_CONFIGS) starts=length(START_TYPES) total=n_total out_root

    for (i, cfg) in enumerate(BENCHMARK_CONFIGS)
        for st in START_TYPES
            try
                run_single_benchmark(cfg, st, i; out_root = out_root)
            catch e
                @error "benchmark $(cfg.tag)/$(st) crashed — logging and continuing" exception = (e, catch_backtrace())
                # Never let one config kill the sweep. The missing artifacts will
                # be visible in the post-sweep smell tests.
            end
        end
    end

    @info "phase33 benchmark done"
end
