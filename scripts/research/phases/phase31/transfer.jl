# scripts/transfer.jl — Phase 31 Plan 02 Task 2
#
# Transferability + robustness probe. For every optimum in Branch A and
# Branch B, evaluate phi_opt (forward-only, no re-optimization) on:
#   (a) HNLF canonical — different fiber material
#   (b) +5% FWHM canonical — perturbed pulse duration
#   (c) +10% P canonical — perturbed input power
#   (d) +5% β₂ canonical — perturbed dispersion
# and measure
#   sigma_3dB — 1D Gaussian perturbation of phi_opt at which J degrades by 3 dB
#
# Output: results/raman/phase31/transfer_results.jld2
#   rows::Vector{Dict{String,Any}} — one per (source_branch, source_index)
#
# Invocation: julia -t auto --project=. scripts/transfer.jl

ENV["MPLBACKEND"] = "Agg"
try using Revise catch end

using Printf
using LinearAlgebra
using Random
using Statistics
using JLD2
using Dates
using JSON3

include(joinpath(@__DIR__, "..", "..", "..", "lib", "common.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "raman_optimization.jl"))
include(joinpath(@__DIR__, "..", "..", "..", "lib", "determinism.jl"))

using MultiModeNoise
ensure_deterministic_environment()

const P31T_RESULTS_DIR = joinpath(@__DIR__, "..", "..", "..", "..", "results", "raman", "phase31")
const P31T_RUN_TAG     = Dates.format(now(), "yyyymmdd_HHMMSS")
const P31T_NT          = 2^14
const P31T_TIME_WINDOW = 10.0
const P31T_SIGMA_TRIALS = 10          # draws for sigma_3dB estimate (was 20 — reduced for wall-time budget)
const P31T_SIGMA_LADDER = [0.0, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0]  # rad (was 9 pts; trimmed to 7)

# Canonical SMF-28 configuration (identical to Branch A/B)
const P31T_CANONICAL = (fiber_preset = :SMF28, L_fiber = 2.0, P_cont = 0.2,
                         pulse_fwhm = 185e-15)

# Perturbation configurations (applied one at a time relative to canonical)
const P31T_PERTURB_CONFIGS = Dict(
    "fwhm_5pct"  => (pulse_fwhm = P31T_CANONICAL.pulse_fwhm * 1.05,),
    "P_10pct"    => (P_cont = P31T_CANONICAL.P_cont * 1.10,),
    "beta2_5pct" => (beta2_scale = 1.05,),  # handled via betas_user override
)

# Transfer target: HNLF canonical point. L=0.5m, P=0.01W is a typical
# HNLF operating regime that is well-separated from SMF-28 parameters.
const P31T_HNLF = (fiber_preset = :HNLF, L_fiber = 0.5, P_cont = 0.01)

mkpath(P31T_RESULTS_DIR)

"""
Evaluate `J_raman_linear` for a given phase vector on a given problem setup.
Forward-only: no adjoint solve. Reproduces the forward portion of
cost_and_gradient by applying cis(φ), running solve_disp_mmf, rotating
into the lab frame with cis(Dω·L), and calling spectral_band_cost.

Roughly 2× cheaper than cost_and_gradient — the adjoint solve is skipped.
"""
function evaluate_J_linear(phi_vec::AbstractVector{<:Real},
                            uω0::AbstractMatrix,
                            fiber::Dict,
                            sim::Dict,
                            band_mask::AbstractVector{Bool})
    Nt = sim["Nt"]
    @assert length(phi_vec) == Nt "phi length $(length(phi_vec)) != Nt $Nt"
    φ = reshape(phi_vec, Nt, 1)
    uω0_shaped = @. uω0 * cis(φ)
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)
    ũω = sol["ode_sol"]
    L = fiber["L"]
    Dω = fiber["Dω"]
    ũω_L = ũω(L)
    uωf = @. cis(Dω * L) * ũω_L
    J, _ = spectral_band_cost(uωf, band_mask)
    return J
end

"""
Build a perturbed problem setup from `perturb_label`. Returns the same
tuple as `setup_raman_problem` plus a status dict recording whether the
perturbation was applied and why.
"""
function setup_raman_problem_perturbed(label::AbstractString)
    # Baseline from canonical
    base = P31T_CANONICAL

    status = Dict{String,Any}(
        "label"          => label,
        "fwhm_applied"   => false,
        "P_applied"      => false,
        "beta2_applied"  => false,
        "note"           => "",
    )

    if label == "fwhm_5pct"
        status["fwhm_applied"] = true
        out = setup_raman_problem(;
            fiber_preset = base.fiber_preset,
            β_order      = 3,
            L_fiber      = base.L_fiber,
            P_cont       = base.P_cont,
            pulse_fwhm   = base.pulse_fwhm * 1.05,
            Nt           = P31T_NT,
            time_window  = P31T_TIME_WINDOW,
        )
        return out, status
    elseif label == "P_10pct"
        status["P_applied"] = true
        out = setup_raman_problem(;
            fiber_preset = base.fiber_preset,
            β_order      = 3,
            L_fiber      = base.L_fiber,
            P_cont       = base.P_cont * 1.10,
            pulse_fwhm   = base.pulse_fwhm,
            Nt           = P31T_NT,
            time_window  = P31T_TIME_WINDOW,
        )
        return out, status
    elseif label == "beta2_5pct"
        # β₂ perturbation via betas_user kwarg with fiber_preset = nothing.
        # Read SMF-28 preset values and scale β₂.
        preset = get_fiber_preset(:SMF28)
        betas_scaled = collect(preset.betas)
        betas_scaled[1] *= 1.05
        status["beta2_applied"] = true
        out = setup_raman_problem(;
            fiber_preset = nothing,
            gamma_user   = preset.gamma,
            betas_user   = betas_scaled,
            fR           = preset.fR,
            β_order      = 3,
            L_fiber      = base.L_fiber,
            P_cont       = base.P_cont,
            pulse_fwhm   = base.pulse_fwhm,
            Nt           = P31T_NT,
            time_window  = P31T_TIME_WINDOW,
        )
        return out, status
    else
        error("unknown perturb label: $label")
    end
end

"""
Build the HNLF transfer setup.
"""
function setup_raman_problem_hnlf()
    return setup_raman_problem(;
        fiber_preset = P31T_HNLF.fiber_preset,
        β_order      = 3,
        L_fiber      = P31T_HNLF.L_fiber,
        P_cont       = P31T_HNLF.P_cont,
        Nt           = P31T_NT,
        time_window  = P31T_TIME_WINDOW,
    )
end

"""
Estimate sigma_3dB: find the Gaussian perturbation scale at which the
mean J (in dB) over `n_trials` draws degrades by 3 dB relative to the
unperturbed J.

Uses **early-exit**: iterate σ ladder in ascending order and stop the
ladder scan the moment mean(J_dB) > J_base + 3 dB. Cuts typical
evaluation count from 9·n_trials to ~3·n_trials per source row since
most optima cross the 3 dB threshold between σ ∈ [0.02, 0.1].

Returns the sigma in radians at the 3 dB crossover, or `NaN` if no
crossover is found before the end of the ladder.
"""
function estimate_sigma_3dB(phi_opt::AbstractVector{<:Real},
                             J_base_dB::Real,
                             uω0::AbstractMatrix,
                             fiber::Dict,
                             sim::Dict,
                             band_mask::AbstractVector{Bool};
                             rng_seed::Int = 12345,
                             n_trials::Int = P31T_SIGMA_TRIALS,
                             sigma_ladder = P31T_SIGMA_LADDER)
    rng = MersenneTwister(rng_seed)
    Nt = length(phi_opt)
    target = J_base_dB + 3.0

    J_dB_per_sigma = Float64[J_base_dB]  # σ=0 baseline
    σ_scanned = Float64[0.0]

    for σ in sigma_ladder
        σ == 0.0 && continue
        Js = Float64[]
        for _ in 1:n_trials
            z = randn(rng, Nt)
            phi_pert = phi_opt .+ σ .* z
            J_lin = evaluate_J_linear(phi_pert, uω0, fiber, sim, band_mask)
            push!(Js, 10.0 * log10(max(J_lin, 1e-15)))
        end
        J_mean = mean(Js)
        push!(J_dB_per_sigma, J_mean)
        push!(σ_scanned, σ)
        if J_mean > target
            # Crossover found — interpolate between prev and current
            J_lo = J_dB_per_sigma[end - 1]
            J_hi = J_dB_per_sigma[end]
            σ_lo = σ_scanned[end - 1]
            σ_hi = σ_scanned[end]
            (J_hi == J_lo) && return σ_hi
            frac = (target - J_lo) / (J_hi - J_lo)
            return σ_lo + frac * (σ_hi - σ_lo)
        end
    end

    # Reached end of ladder without crossing — extremely robust optimum
    return NaN
end

"""
Core transfer probe: given one source row from sweep_A or sweep_B, evaluate
phi_opt on HNLF, three perturbed canonicals, and compute sigma_3dB at the
canonical fiber.

Inputs:
- `source_row`: Dict loaded from sweep_A_basis.jld2 or sweep_B_penalty.jld2.
- cached setups keyed by configuration label.

Output: Dict{String,Any} with J_transfer_HNLF, J_transfer_perturb, perturb_flags,
sigma_3dB, plus provenance (source_branch, source_index, source_kind,
source_N_phi, source_J_final).
"""
function transfer_probe(source_row::Dict{String,Any},
                         source_index::Int,
                         canonical_setup::Tuple,
                         hnlf_setup::Tuple,
                         perturb_setups::Dict{String,<:Any})
    phi_vec = Float64.(source_row["phi_opt"])
    (uω0_can, fiber_can, sim_can, bm_can, _, _) = canonical_setup
    (uω0_hn, fiber_hn, sim_hn, bm_hn, _, _) = hnlf_setup

    # Source-branch J on canonical (from the row itself)
    J_canonical_dB = Float64(source_row["J_final"])

    # HNLF transfer
    fiber_hn_local = deepcopy(fiber_hn)
    fiber_hn_local["zsave"] = nothing
    J_hnlf_linear = try
        evaluate_J_linear(phi_vec, uω0_hn, fiber_hn_local, sim_hn, bm_hn)
    catch e
        @warn "HNLF transfer failed" idx=source_index error=sprint(showerror, e)
        NaN
    end
    J_hnlf_dB = J_hnlf_linear |> x -> (isnan(x) ? NaN : 10.0 * log10(max(x, 1e-15)))

    # Perturbed canonicals
    J_perturb = Dict{String,Float64}()
    perturb_flags = Dict{String,Any}()
    for (label, (setup_tup, status)) in perturb_setups
        (uω0_p, fiber_p, sim_p, bm_p, _, _) = setup_tup
        fiber_p_local = deepcopy(fiber_p)
        fiber_p_local["zsave"] = nothing
        J_lin = try
            evaluate_J_linear(phi_vec, uω0_p, fiber_p_local, sim_p, bm_p)
        catch e
            @warn "perturbed transfer failed" idx=source_index label=label error=sprint(showerror, e)
            NaN
        end
        J_perturb[label] = isnan(J_lin) ? NaN : 10.0 * log10(max(J_lin, 1e-15))
        perturb_flags[label] = status
    end

    # sigma_3dB at the canonical
    fiber_can_local = deepcopy(fiber_can)
    fiber_can_local["zsave"] = nothing
    sigma_3dB = try
        estimate_sigma_3dB(phi_vec, J_canonical_dB,
                            uω0_can, fiber_can_local, sim_can, bm_can)
    catch e
        @warn "sigma_3dB failed" idx=source_index error=sprint(showerror, e)
        NaN
    end

    return Dict{String,Any}(
        "source_branch" => String(source_row["branch"]),
        "source_index"  => source_index,
        "source_kind"   => String(source_row["kind"]),
        "source_N_phi"  => Int(source_row["N_phi"]),
        "source_penalty_name" => get(source_row, "penalty_name", ""),
        "source_lambda"       => get(source_row, "lambda", 0.0),
        "source_J_final"       => J_canonical_dB,
        "J_transfer_HNLF"      => J_hnlf_dB,
        "J_transfer_perturb"   => J_perturb,
        "perturb_flags"        => perturb_flags,
        "sigma_3dB"            => sigma_3dB,
    )
end

function run_transfer_probe(; dry_run::Bool = false)
    t_start = time()
    @info "Phase 31 Plan 02 Task 2 — transfer probe" canonical=P31T_CANONICAL threads=Threads.nthreads()

    # Load Branch A + Branch B rows
    sweep_A_path = joinpath(P31T_RESULTS_DIR, "sweep_A_basis.jld2")
    sweep_B_path = joinpath(P31T_RESULTS_DIR, "sweep_B_penalty.jld2")

    rows_A = isfile(sweep_A_path) ? JLD2.load(sweep_A_path, "rows") : Dict{String,Any}[]
    rows_B = isfile(sweep_B_path) ? JLD2.load(sweep_B_path, "rows") : Dict{String,Any}[]
    @info @sprintf("  Loaded %d Branch A rows from %s", length(rows_A), sweep_A_path)
    @info @sprintf("  Loaded %d Branch B rows from %s", length(rows_B), sweep_B_path)

    source_rows = Tuple{String,Int,Dict{String,Any}}[]
    for (i, r) in enumerate(rows_A); push!(source_rows, ("A", i, r)); end
    for (i, r) in enumerate(rows_B); push!(source_rows, ("B", i, r)); end
    @info "Total source rows: $(length(source_rows))"

    if isempty(source_rows)
        @warn "No source rows to probe — run Branch A and/or Branch B first."
        return Dict{String,Any}[]
    end

    if dry_run
        @info "dry-run: setting up canonical/HNLF/perturbations only (skipping per-row evaluation)"
    end

    # Setup canonical, HNLF, and the 3 perturbation setups ONCE — they are
    # thread-shared read-only (we deepcopy fiber inside transfer_probe).
    canonical_setup = setup_raman_problem(;
        fiber_preset = P31T_CANONICAL.fiber_preset,
        β_order      = 3,
        L_fiber      = P31T_CANONICAL.L_fiber,
        P_cont       = P31T_CANONICAL.P_cont,
        pulse_fwhm   = P31T_CANONICAL.pulse_fwhm,
        Nt           = P31T_NT,
        time_window  = P31T_TIME_WINDOW,
    )
    hnlf_setup = setup_raman_problem_hnlf()

    perturb_setups = Dict{String,Any}()
    for label in keys(P31T_PERTURB_CONFIGS)
        perturb_setups[label] = setup_raman_problem_perturbed(label)
    end
    @info "Setups ready: canonical + HNLF + $(length(perturb_setups)) perturbations"

    if dry_run
        @info "dry-run complete — setups OK"
        return Dict{String,Any}[]
    end

    # Per-source probe with Threads.@threads; deepcopy(fiber) handled inside.
    results = Vector{Dict{String,Any}}(undef, length(source_rows))
    Threads.@threads for k in 1:length(source_rows)
        (branch_id, idx, row) = source_rows[k]
        t_row = time()
        results[k] = transfer_probe(row, idx, canonical_setup, hnlf_setup, perturb_setups)
        wall = time() - t_row
        @info @sprintf("[%d/%d] %s source=%d kind=%s J_can=%.2f J_HNLF=%.2f σ_3dB=%.3f  (%.1fs)",
                       k, length(source_rows), branch_id, idx,
                       results[k]["source_kind"],
                       results[k]["source_J_final"],
                       results[k]["J_transfer_HNLF"],
                       results[k]["sigma_3dB"], wall)
    end

    out_path = joinpath(P31T_RESULTS_DIR, "transfer_results.jld2")
    JLD2.jldsave(out_path; rows = results, run_tag = P31T_RUN_TAG)

    total_wall = time() - t_start
    @info @sprintf("Transfer probe complete: %d rows saved to %s (%.1fs)",
                   length(results), out_path, total_wall)

    # Provenance manifest
    manifest_path = joinpath(P31T_RESULTS_DIR,
                              "manifest_T_$(P31T_RUN_TAG).json")
    open(manifest_path, "w") do io
        JSON3.pretty(io, Dict(
            "run_tag"         => P31T_RUN_TAG,
            "total_rows"      => length(results),
            "total_wall_s"    => total_wall,
            "julia_version"   => string(VERSION),
            "threads"         => Threads.nthreads(),
            "canonical"       => Dict(String(k) => v for (k, v) in pairs(P31T_CANONICAL)),
            "hnlf"            => Dict(String(k) => v for (k, v) in pairs(P31T_HNLF)),
            "perturbations"   => collect(keys(P31T_PERTURB_CONFIGS)),
            "sigma_ladder"    => P31T_SIGMA_LADDER,
            "sigma_trials"    => P31T_SIGMA_TRIALS,
        ))
    end
    @info "manifest written" path=manifest_path

    return results
end

# Main dispatch
if abspath(PROGRAM_FILE) == @__FILE__
    dry_run = any(a -> a == "--dry-run", ARGS)
    run_transfer_probe(; dry_run = dry_run)
end
