#!/usr/bin/env julia
"""
Phase 21 — inspect and honestly validate Session F's 100m result schema.
"""

ENV["MPLBACKEND"] = "Agg"

using JLD2
using Printf
using Logging

include(joinpath(@__DIR__, "recovery_common.jl"))

const LONG100_SOURCE = joinpath(@__DIR__, "..", "results", "raman", "phase16", "100m_validate_fixed.jld2")
const LONG100_RESULTS_DIR = recovery_result_path("longfiber100m")

function main()
    mkpath(LONG100_RESULTS_DIR)
    d = JLD2.load(LONG100_SOURCE)
    keys_sorted = sort!(collect(keys(d)))

    phi = recovery_key_or_nothing(d, ["phi_opt", "phi", "x"])
    phi === nothing && error("could not find phi_opt-like key in $(LONG100_SOURCE); keys=$(keys_sorted)")

    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_longfiber_problem(;
        fiber_preset=:SMF28,
        L_fiber=100.0,
        P_cont=0.05,
        Nt=32768,
        time_window=160.0,
        β_order=2,
    )
    phi_opt = recovery_scalarize_phi(phi, sim["Nt"])
    phi_opt = recovery_remove_linear_phase(phi_opt, uω0, sim)
    metrics = recovery_forward_metrics(uω0, phi_opt, deepcopy(fiber), sim, band_mask)

    tag = "phase21_sessionf_100m_smf28_l100m_p0p05w"
    images = recovery_save_standard_set(phi_opt, uω0, deepcopy(fiber), sim, band_mask, Δf, raman_threshold;
        tag=tag, fiber_name="SMF-28", L_m=100.0, P_W=0.05)

    out_jld2 = joinpath(LONG100_RESULTS_DIR, "sessionf_100m_normalized.jld2")
    JLD2.jldsave(out_jld2;
        source=LONG100_SOURCE,
        source_keys=keys_sorted,
        phi_opt=phi_opt,
        J_honest_lin=metrics.J_lin,
        J_honest_dB=metrics.J_dB,
        edge_frac=metrics.edge_frac,
        energy_drift=metrics.energy_drift,
        stored_converged=recovery_key_or_nothing(d, ["converged"]),
        stored_J_opt_dB=recovery_key_or_nothing(d, ["J_opt_dB", "J_lin_dB"]),
        stored_J_warm_dB=recovery_key_or_nothing(d, ["J_warm_dB"]),
        stored_J_flat_dB=recovery_key_or_nothing(d, ["J_flat_dB"]),
    )

    report = String[
        "# Session F 100m schema validation",
        "",
        @sprintf("Source: `%s`", LONG100_SOURCE),
        "",
        "## Schema keys",
        "",
        join(["- `$k`" for k in keys_sorted], "\n"),
        "",
        "## Honest validation",
        "",
        @sprintf("- Honest J: %.2f dB", metrics.J_dB),
        @sprintf("- Edge fraction: %.3e", metrics.edge_frac),
        @sprintf("- Energy drift: %.3e", metrics.energy_drift),
        @sprintf("- Stored converged flag: %s", string(recovery_key_or_nothing(d, ["converged"]))),
        @sprintf("- Stored J_opt_dB: %s", string(recovery_key_or_nothing(d, ["J_opt_dB", "J_lin_dB"]))),
        "",
        "Verdict note: if `converged=false`, this remains a best-achieved lower bound rather than a certified optimum, even though the pulse-containment gate passes.",
    ]
    recovery_write_markdown(joinpath(LONG100_RESULTS_DIR, "sessionf_100m_validation.md"), report)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
