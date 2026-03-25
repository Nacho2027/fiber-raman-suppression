"""
Physics Correctness Verification for the Raman Suppression Pipeline

Standalone research-grade verification script (NOT a CI test suite). Runs at
production grid size (Nt=2^14) to ensure boundary effects, Raman hRω wrapping,
and band_mask physical bandwidth match the real optimization environment.

Verification checks implemented in this file:
- VERIF-01: Fundamental soliton N=1 shape preserved after one soliton period
            (max intensity deviation < 2% in the pulse core)
- VERIF-04: spectral_band_cost return value matches direct E_band/E_total
            integration to machine precision (atol=1e-12)

Verification checks added by Plan 02 (placeholders present below):
- VERIF-02: Photon number conservation on all 5 production configs
- VERIF-03: Adjoint gradient Taylor remainder check (slope ≈ 2 confirms second-order)

Design decisions:
- D-01: Separate from test_optimization.jl — test_optimization.jl is a fast CI-style
        suite at loose tolerances (10%); verification.jl runs thorough physics checks.
- D-02: Nt=2^14 (production fidelity) — smaller grids change attenuator shape and
        Raman wrapping, which can mask real physics bugs.
- Output: Markdown report written to results/raman/validation/ for archival.

Usage:
    julia scripts/verification.jl
"""

try using Revise catch end
using Test
using LinearAlgebra
using FFTW
using Logging
using Printf
using Dates
using MultiModeNoise

include("common.jl")
include("raman_optimization.jl")

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════

# Production grid size per D-02. Must match the real optimization environment.
const VERIF_NT = 2^14

# Report output directory — parallel to results/raman/ for archival
const VERIF_OUTPUT_DIR = joinpath(@__DIR__, "..", "results", "raman", "validation")

# Collect results for the markdown report.
# Each entry: (name, passed, skipped, evidence)
results = NamedTuple{(:name, :passed, :skipped, :evidence), Tuple{String, Bool, Bool, String}}[]

# ═══════════════════════════════════════════════════════════════════════════════
# VERIF-01: Fundamental soliton N=1 shape preserved after one soliton period
# ═══════════════════════════════════════════════════════════════════════════════
#
# Physics: The N=1 fundamental soliton is an exact solution to the NLSE with
# anomalous dispersion and Kerr nonlinearity (no Raman). After exactly one
# soliton period z_sol = (π/2) L_D, the pulse returns to its initial shape.
# Deviation from this analytical solution measures numerical accuracy.
#
# Threshold: 2% max normalized intensity deviation in the pulse core (I_in > 5%).
# The 2% choice is tight enough to catch physics bugs but forgiving of numerical
# dispersion at Nt=2^14 with Tsit5 reltol=1e-8.

@testset "VERIF-01: Fundamental soliton N=1 shape preserved (<2% max deviation)" begin
    # Fiber parameters for soliton condition (anomalous dispersion, no Raman)
    beta2 = -2.6e-26      # s²/m  (anomalous dispersion for soliton)
    gamma_val = 0.0013     # W⁻¹m⁻¹

    # Pulse parameters matching the standard optimization setup
    pulse_fwhm = 185e-15   # s
    pulse_rep_rate = 80.5e6  # Hz

    # Soliton pulse parameter T₀ (sech half-width at 1/e intensity)
    # Relation: FWHM = 2 * acosh(√2) * T₀ ≈ 1.7627 * T₀
    T0 = pulse_fwhm / (2 * acosh(sqrt(2)))

    # Soliton peak power: P_peak = |β₂| / (γ × T₀²)
    P_peak = abs(beta2) / (gamma_val * T0^2)

    # Convert peak power to average-power convention used by setup_raman_problem.
    # In setup_raman_problem, P_peak = 0.881374 * P_cont / (pulse_fwhm * pulse_rep_rate)
    # => P_cont = P_peak * pulse_fwhm * pulse_rep_rate / 0.881374
    P_cont = P_peak * pulse_fwhm * pulse_rep_rate / 0.881374

    # Dispersion length L_D = T₀² / |β₂|
    L_D = T0^2 / abs(beta2)

    # One soliton period — exact return point for N=1 soliton
    z_soliton = (pi / 2) * L_D

    @info @sprintf(
        "VERIF-01 setup: P_peak=%.2f W, T0=%.2f fs, L_D=%.4f m, z_sol=%.4f m, Nt=%d",
        P_peak, T0 * 1e15, L_D, z_soliton, VERIF_NT
    )

    # Set up the propagation problem.
    # fR=1e-15 effectively disables Raman so we test the pure Kerr+dispersion soliton.
    uomega0, fiber, sim, _, _, _ = setup_raman_problem(
        Nt=VERIF_NT, L_fiber=z_soliton, P_cont=P_cont, time_window=10.0,
        β_order=2, gamma_user=gamma_val, betas_user=[beta2], fR=1e-15
    )

    # Deepcopy required — setup_raman_problem leaves fiber["zsave"]=nothing, and
    # solve_disp_mmf requires fiber["zsave"] set to a position vector to return
    # field snapshots. Modifying the returned dict directly would be a bug.
    fiber_prop = deepcopy(fiber)
    fiber_prop["zsave"] = [0.0, z_soliton]

    sol = MultiModeNoise.solve_disp_mmf(uomega0, fiber_prop, sim)

    # Extract temporal intensity profiles at z=0 and z=z_sol (mode 1 only, M=1)
    I_in  = abs2.(sol["ut_z"][1,   :, 1])
    I_out = abs2.(sol["ut_z"][end, :, 1])

    # Normalize to peak=1 for shape comparison (global phase/scaling is irrelevant)
    I_in_norm  = I_in  ./ maximum(I_in)
    I_out_norm = I_out ./ maximum(I_out)

    # Restrict comparison to the pulse core where the soliton has significant energy.
    # Points below 5% of peak are noise-dominated and would inflate the error metric.
    center_mask = I_in_norm .> 0.05

    max_dev = maximum(abs.(I_out_norm[center_mask] .- I_in_norm[center_mask]))

    @info @sprintf(
        "VERIF-01 result: max_deviation=%.6f (threshold=0.02), pulse_core_points=%d",
        max_dev, sum(center_mask)
    )

    @test max_dev < 0.02

    push!(results, (
        name    = "VERIF-01: Soliton shape preservation",
        passed  = max_dev < 0.02,
        skipped = false,
        evidence = @sprintf(
            "max_dev=%.6f < 0.02, Nt=2^14, z_sol=%.4f m, P_peak=%.2f W, core_points=%d",
            max_dev, z_soliton, P_peak, sum(center_mask)
        )
    ))
end

# ═══════════════════════════════════════════════════════════════════════════════
# VERIF-02 placeholder — Plan 02 implements photon number conservation
# ═══════════════════════════════════════════════════════════════════════════════
#
# TODO: Plan 02 adds VERIF-02 here.
#
# Physics: Photon number N_ph = ∫|U(ω)|²/(ℏω) dω is conserved by the lossless
# NLSE (no gain/loss, only Kerr+Raman). Conservation tests all 5 production
# configs from FIBER_PRESETS. The photon number integral requires ω+ω₀ (carrier
# offset) to avoid division by zero near DC.

@testset "VERIF-02: Photon number conservation (all production configs)" begin
    @info "VERIF-02: SKIPPED — not yet implemented (Plan 02)"
    push!(results, (
        name    = "VERIF-02: Photon number conservation",
        passed  = false,
        skipped = true,
        evidence = "Not yet implemented — Plan 02 adds this check"
    ))
end

# ═══════════════════════════════════════════════════════════════════════════════
# VERIF-03 placeholder — Plan 02 implements adjoint gradient Taylor remainder
# ═══════════════════════════════════════════════════════════════════════════════
#
# TODO: Plan 02 adds VERIF-03 here.
#
# Physics: For a correct adjoint gradient ∂J/∂φ, the Taylor remainder
# |J(φ + ε δ) - J(φ) - ε ∇J·δ| should converge as O(ε²). A log-log plot of
# remainder vs ε should have slope ≈ 2. Slope outside [1.4, 2.6] signals a bug.

@testset "VERIF-03: Adjoint gradient Taylor remainder (slope ≈ 2)" begin
    @info "VERIF-03: SKIPPED — not yet implemented (Plan 02)"
    push!(results, (
        name    = "VERIF-03: Adjoint gradient Taylor remainder",
        passed  = false,
        skipped = true,
        evidence = "Not yet implemented — Plan 02 adds this check"
    ))
end

# ═══════════════════════════════════════════════════════════════════════════════
# VERIF-04: spectral_band_cost matches direct E_band/E_total integration
# ═══════════════════════════════════════════════════════════════════════════════
#
# Physics: spectral_band_cost computes J = E_band/E_total and its gradient dJ.
# This test cross-checks J against a direct five-line computation to confirm the
# function is internally consistent and free of indexing or normalization bugs.
# The tolerance is machine precision (atol=1e-12) since both paths use the same
# floating-point arithmetic — any deviation would signal a logic error.

@testset "VERIF-04: spectral_band_cost matches direct E_band/E_total integration" begin
    # Use the default SMF-28 preset at production grid size.
    # SMF28 has both β₂ and β₃, so β_order=3 is required (betas_user length ≤ β_order-1).
    uomega0, fiber, sim, band_mask, _, _ = setup_raman_problem(
        Nt=VERIF_NT, L_fiber=1.0, P_cont=0.05, time_window=10.0,
        β_order=3, fiber_preset=:SMF28
    )

    # Propagate to z=L to get a realistic output field with Raman-shifted content
    fiber_prop = deepcopy(fiber)
    fiber_prop["zsave"] = [fiber["L"]]

    sol = MultiModeNoise.solve_disp_mmf(uomega0, fiber_prop, sim)

    # Frequency-domain output field: shape (1, Nt, M) → extract the single save point
    uomegaf = sol["uω_z"][end, :, :]

    # Cost from the library function
    J_func, _ = spectral_band_cost(uomegaf, band_mask)

    # Direct five-line cross-check — same arithmetic, independent of the function body
    E_band   = sum(abs2.(uomegaf[band_mask, :]))
    E_total  = sum(abs2.(uomegaf))
    J_direct = E_band / E_total
    diff = abs(J_func - J_direct)

    @info @sprintf(
        "VERIF-04 result: J_func=%.10e, J_direct=%.10e, |diff|=%.2e (threshold=1e-12)",
        J_func, J_direct, diff
    )

    @test J_func ≈ J_direct atol=1e-12

    push!(results, (
        name    = "VERIF-04: Cost cross-check (machine precision)",
        passed  = diff < 1e-12,
        skipped = false,
        evidence = @sprintf(
            "J_func=%.10e, J_direct=%.10e, |diff|=%.2e < 1e-12, Nt=2^14, fiber=SMF-28",
            J_func, J_direct, diff
        )
    ))
end

# ═══════════════════════════════════════════════════════════════════════════════
# Report writer
# ═══════════════════════════════════════════════════════════════════════════════

"""
    write_verification_report(results, output_dir)

Write a markdown verification report to `output_dir`. Creates the directory if
it does not exist. The report includes a results table (name, status, evidence)
and a final PASS/FAIL summary.

# Arguments
- `results`: Vector of NamedTuples with fields (:name, :passed, :skipped, :evidence)
- `output_dir`: Directory path for the output file
"""
function write_verification_report(results, output_dir)
    mkpath(output_dir)

    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    filename  = "verification_$(timestamp).md"
    path      = joinpath(output_dir, filename)

    n_passed  = count(r -> r.passed && !r.skipped, results)
    n_failed  = count(r -> !r.passed && !r.skipped, results)
    n_skipped = count(r -> r.skipped, results)

    open(path, "w") do io
        println(io, "# Correctness Verification Report")
        println(io)
        println(io, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
        println(io, "**Grid size:** Nt = VERIF_NT = 2^14 = $(VERIF_NT)")
        println(io, "**Julia version:** $(VERSION)")
        println(io)
        println(io, "## Results")
        println(io)
        println(io, "| Check | Status | Evidence |")
        println(io, "|-------|--------|----------|")
        for r in results
            if r.skipped
                status = "SKIPPED"
            elseif r.passed
                status = "PASS"
            else
                status = "FAIL"
            end
            println(io, "| $(r.name) | **$(status)** | $(r.evidence) |")
        end
        println(io)
        println(io, "## Summary")
        println(io)
        println(io, "- Passed:  $(n_passed)")
        println(io, "- Failed:  $(n_failed)")
        println(io, "- Skipped: $(n_skipped)")
        println(io)
        if n_failed == 0
            println(io, "**Overall: PASS** ($(n_passed) checks passed, $(n_skipped) skipped)")
        else
            println(io, "**Overall: FAIL** ($(n_failed) checks failed)")
        end
    end

    @info "Verification report written to $path"
    return path
end

# ═══════════════════════════════════════════════════════════════════════════════
# Main execution
# ═══════════════════════════════════════════════════════════════════════════════

n_passed  = count(r -> r.passed && !r.skipped, results)
n_failed  = count(r -> !r.passed && !r.skipped, results)
n_skipped = count(r -> r.skipped, results)

@info @sprintf(
    "Verification complete: %d passed, %d failed, %d skipped",
    n_passed, n_failed, n_skipped
)

write_verification_report(results, VERIF_OUTPUT_DIR)
