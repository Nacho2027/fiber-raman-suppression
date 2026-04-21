# scripts/phase33_benchmark_common.jl — shared config for Phase 33 benchmark.
#
# NO side effects on include: no Pkg.activate, no ensure_deterministic_*. Safe to
# include from both the Plan 02 driver and any downstream synthesis / analysis.
#
# Source of truth for BENCHMARK_CONFIGS + START_TYPES. The driver `include`s this
# file — do NOT duplicate the config list anywhere else.
#
# Substitution rationale (2026-04-21): the original RESEARCH.md §Benchmark Set
# named 4 canonical warm-starts. The Phase 21 audit invalidated 2 of them
# (bc_input_ok=false), and the Pareto-57 JLD2 was never synced from Mac to burst.
# Three configs remain; they cover (SMF-28 canonical, HNLF Phase-21 honest,
# SMF-28 Phase-21 honest). Result: 3 configs × 3 start types = 9 TR runs.
#
# Grid discipline: each config's `Nt` and `time_window_ps` are PINNED to its
# warm-start JLD2's grid. `setup_raman_problem` is a 1-arg ps interface
# (`time_window=cfg.time_window_ps`, NOT * 1e-12), so loading phi_opt with a
# mismatched Nt will fail with a length assertion at gauge projection.

if !@isdefined(_PHASE33_BENCHMARK_COMMON_JL_LOADED)
    const _PHASE33_BENCHMARK_COMMON_JL_LOADED = true

    const BENCHMARK_CONFIGS = [
        (tag = "bench-01-smf28-canonical",
         fiber = :SMF28, L = 2.0, P = 0.2,
         Nt = 2^13, time_window_ps = 40.0, Nφ = nothing,
         warm_jld2 = "results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2",
         warm_note = "pre-audit canonical (bc_input_ok=false — baseline contrast)"),
        (tag = "bench-02-hnlf-phase21",
         fiber = :HNLF,  L = 0.5, P = 0.01,
         Nt = 2^16, time_window_ps = 320.0, Nφ = nothing,
         warm_jld2 = "results/raman/phase21/phase13/hnlf_reanchor.jld2",
         warm_note = "Phase 21 honest HNLF, J=-86.68 dB, edge_frac=2.2e-4"),
        (tag = "bench-03-smf28-phase21",
         fiber = :SMF28, L = 2.0, P = 0.2,
         Nt = 2^14, time_window_ps = 54.0, Nφ = nothing,
         warm_jld2 = "results/raman/phase21/phase13/smf28_reanchor.jld2",
         warm_note = "Phase 21 honest SMF-28, J=-66.61 dB, edge_frac=8.1e-4"),
        # bench-04 (Pareto-57 @ Nφ=57) DROPPED 2026-04-21 — per-row optimum not
        # synced locally. Can be restored if results/raman/phase22/... is rebuilt.
    ]

    const START_TYPES = [:cold, :warm, :perturbed]
    # :cold      -> φ0 = zeros(Nt)
    # :warm      -> φ0 = vec(load(warm_jld2)["phi_opt"])
    # :perturbed -> warm + 0.05 .* randn(Xoshiro(42 + config_index), Nt)
end
