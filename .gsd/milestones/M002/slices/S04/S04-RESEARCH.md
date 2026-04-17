# Phase 7: Parameter Sweeps - Research

**Researched:** 2026-03-26
**Domain:** Parameter sweep infrastructure, SPM-aware time window sizing, heatmap visualization, multi-start robustness for Raman suppression optimization
**Confidence:** HIGH (all findings from direct codebase audit + physics computation)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 (Time Window Fix):** Fix `recommended_time_window()` with SPM broadening estimate AND validate every sweep point with photon number drift <5%. Both changes required:
- New SPM term: SPM bandwidth ≈ γ × P_peak × L, convert to temporal broadening via β₂, add to linear walk-off total.
- Every sweep point gets a post-run photon number check. Points with >5% drift are flagged "window-limited" in results (not treated as valid suppression measurements).
- Evidence from Phase 4: `results/raman/validation/verification_20260325_173537.md` (2.7-49% drift across 5 configs).

**D-02 (Sweep Grid):** Both SMF-28 and HNLF fiber types. Grid spans low-N to high-N. Include the 5 production configs as grid points. ~40-50 total points. Claude designs the exact grid. Use the fixed `recommended_time_window()` to size each point's time window adaptively.

**D-03 (Compute Budget):** No time limit. Sequential execution. No parallelization needed within the sweep.

**D-04 (Multi-Start):** 10 random starts on SMF-28 L=2m P=0.30W (N=3.1, didn't converge at 50 iterations). Initial phases: Gaussian φ₀ ~ N(0, σ²) with σ ∈ {0.1, 0.5, 1.0}. Report: distribution of J_final values, convergence iteration counts, basin convergence analysis.

### Claude's Discretion

- Exact L and P grid values (within low-N to high-N constraint)
- Whether to increase max_iter beyond 50 for sweep points
- Heatmap visualization details (colormap, convergence markers)
- Whether to save full JLD2 per sweep point or just scalars in aggregate
- Multi-start config selection and random seed strategy
- Script organization (single `run_sweep.jl` or split)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SWEEP-01 | L×P parameter sweep runs optimization over a coarse grid and produces J_final heatmap per fiber type | Grid design, time window fix, heatmap implementation pattern, convergence tagging — all covered below |
| SWEEP-02 | Multi-start analysis runs optimization from 5-10 random initial phases and reports convergence variance | `multistart_optimization()` in `benchmark_optimization.jl` provides the exact pattern; Phase 7 must adapt it sequentially (not threaded) and save results to JLD2 |
</phase_requirements>

---

## Summary

Phase 7 is the final and most computationally intensive phase. It has two independent deliverables: (1) an L×P heatmap sweep for both fiber types (SWEEP-01) and (2) a multi-start robustness analysis (SWEEP-02). Before either can run, `recommended_time_window()` must be fixed to account for SPM-driven spectral broadening, which is the root cause of the 2.7-49% photon number drift documented in Phase 4.

The core physics fact driving the time window fix: SMF-28 peak powers are enormous (2960-17755 W for P_cont = 0.05-0.30 W given 185 fs pulses at 80.5 MHz rep rate). The nonlinear length L_NL = 1/(γ·P_peak) is 50-300 mm — shorter than the fiber lengths in the sweep. This means the pulse undergoes multiple nonlinear lengths of propagation, generating SPM-broadened spectra that require much wider time windows than the current linear walk-off formula provides.

The grid design is constrained by a practical upper bound: very high phi_NL (long fiber + high power) requires Nt=2^15 or larger to maintain resolution, which dramatically increases per-point wall time. The recommended grid uses moderate phi_NL values (≤40 for SMF-28, ≤60 for HNLF) where time windows stay ≤50 ps (Nt=2^13 or 2^14). The multi-start analysis reuses the `multistart_optimization()` pattern from `benchmark_optimization.jl` but runs sequentially rather than threaded.

**Primary recommendation:** Fix `recommended_time_window()` first (no sweep runs before that), then design the grid so that time_window per point stays ≤50 ps. Use max_iter=100 for all sweep points (Phase 6 showed most interesting configs hit the 50-iteration limit without converging). Save full JLD2 per sweep point to enable retrospective diagnostics.

---

## Standard Stack

### Core (all pre-existing, no new dependencies)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Optim.jl | 1.13.3 | L-BFGS optimization with `only_fg!` interface | Already in use; `Optim.converged()`, `Optim.iterations()`, `Optim.f_trace()` required for sweep tagging |
| JLD2.jl | current | Per-point result persistence | Already in use from Phase 5; `jldsave()` and `load()` pattern established |
| JSON3.jl | current | Manifest append-safe update | Already in use from Phase 5 |
| PyPlot.jl | current | Heatmap via `pcolormesh()` and `contour()` | Already in use; inferno colormap is project standard |
| FFTW.jl | current | FFT for photon number computation | Already in use |

**Installation:** No new packages. All dependencies already in `Project.toml`.

---

## Architecture Patterns

### Recommended Project Structure

```
scripts/
├── run_sweep.jl              # NEW: sweep entry point (includes common.jl, raman_optimization.jl, visualization.jl)
├── common.jl                 # MODIFIED: recommended_time_window() gets SPM correction
├── raman_optimization.jl     # UNCHANGED: run_optimization() called per sweep point
└── visualization.jl          # MODIFIED: add plot_sweep_heatmap() function

results/raman/sweeps/
├── smf28/
│   ├── L0.5m_P0.05W/opt_result.jld2   # per-point JLD2
│   └── ...
├── hnlf/
│   └── ...
├── sweep_results_smf28.jld2  # aggregate scalar summary (SMF-28)
├── sweep_results_hnlf.jld2   # aggregate scalar summary (HNLF)
└── multistart_L2m_P030W.jld2 # multi-start result
```

### Pattern 1: Fixed recommended_time_window() with SPM Term

**What:** The current formula only accounts for linear dispersive walk-off. The fixed version adds an SPM spectral broadening correction.

**Physics:** SPM generates bandwidth Δω_SPM ≈ γ·P_peak·L. After dispersive propagation, this bandwidth converts to temporal spread Δt_SPM ≈ |β₂|·L·Δω_SPM. The total time window must cover both the Raman walk-off AND the SPM-broadened pulse envelope.

**Current implementation (common.jl line 182-191):**
```julia
function recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27)
    Δω_raman = 2π * 13e12
    walk_off_ps = beta2 * L_fiber * Δω_raman * 1e12
    pulse_extent = 0.5
    return max(5, ceil(Int, (walk_off_ps + pulse_extent) * safety_factor))
end
```

**Fixed implementation — add gamma and P_peak parameters:**
```julia
function recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27,
                                  gamma=0.0, P_peak=0.0)
    @assert L_fiber > 0
    @assert safety_factor > 0
    @assert beta2 > 0

    Δω_raman = 2π * 13e12
    walk_off_ps = beta2 * L_fiber * Δω_raman * 1e12

    # SPM broadening correction (belt-and-suspenders per D-01)
    # Δω_SPM ≈ γ * P_peak * L  (peak nonlinear phase → spectral bandwidth)
    # Δt_SPM ≈ |β₂| * L * Δω_SPM  (temporal broadening via group velocity dispersion)
    spm_ps = 0.0
    if gamma > 0 && P_peak > 0
        Δω_SPM = gamma * P_peak * L_fiber
        spm_ps = beta2 * L_fiber * Δω_SPM * 1e12
    end

    pulse_extent = 0.5  # initial pulse half-width (~T0/2 in ps)
    total_ps = walk_off_ps + spm_ps + pulse_extent
    return max(5, ceil(Int, total_ps * safety_factor))
end
```

**Callers must pass gamma and P_peak.** Both `setup_raman_problem` and `setup_amplitude_problem` already have gamma and P_peak available at the call site. The planner must update those call sites too.

**Critical note on SPM estimate accuracy:** The SPM broadening formula Δω_SPM = γ·P_peak·L is a first-order estimate valid for φ_NL = γ·P_peak·L ≤ 10. At higher φ_NL (which occurs for SMF-28 L=5-10m or HNLF high-P), the actual bandwidth can be significantly larger due to higher-order soliton dynamics. For sweep points with φ_NL > 20, a larger safety_factor (3.0) is recommended. See the grid design section for per-point φ_NL values.

**Important: time_window determines both Raman mask and Nt.** The `band_mask` is computed as `Δf_fft .< raman_threshold` where `Δf = 1/(time_window/Nt)`. Different time windows yield different `band_mask` sizes (different numbers of bins for the same physical bandwidth). For cross-run comparability, J values from runs with different time_window are not directly comparable. The heatmap must record and display `time_window_ps` and `Nt` alongside J_final.

### Pattern 2: Sweep Loop Infrastructure

**What:** A loop over (L, P) grid points, calling `run_optimization()` per point, saving scalars to aggregate JLD2.

**Critical pitfall: Never reuse `fiber` Dict across loop iterations.** `run_optimization()` calls `setup_raman_problem()` internally, which creates a fresh `sim` and `fiber` per call. The sweep loop passes kwargs — it does NOT reuse any Dict.

```julia
# Correct sweep loop pattern (from PITFALLS.md and CONTEXT.md)
sweep_results = []
for (L, P) in grid_points
    # Fresh setup per point — run_optimization calls setup_raman_problem internally
    tw = recommended_time_window(L;
        beta2 = abs(fiber_betas[1]),
        gamma = fiber_gamma,
        P_peak = RC_SECH_FACTOR * P / (RC_PULSE_FWHM * RC_PULSE_REP_RATE),
        safety_factor = 2.0)
    Nt_point = nt_for_window(tw)   # next power of 2 ≥ tw / dt_min

    dir_path = mkpath(joinpath("results", "raman", "sweeps", fiber_dir,
                               @sprintf("L%sm_P%sW", L, P)))
    save_prefix = joinpath(dir_path, "opt")

    result, uω0, fiber, sim, band_mask, _ = run_optimization(
        L_fiber = L, P_cont = P,
        Nt = Nt_point, time_window = Float64(tw),
        max_iter = 100, validate = false,
        fiber_name = fiber_label,
        gamma_user = fiber_gamma, betas_user = fiber_betas,
        save_prefix = save_prefix
    )

    # Photon number drift check (D-01 post-run validation)
    drift_pct = compute_photon_drift(result, uω0, fiber, sim)
    window_limited = drift_pct > 5.0

    # Convergence tagging (PITFALLS.md Pitfall 2)
    converged = Optim.converged(result)
    iterations = Optim.iterations(result)
    J_after = 10^(Optim.minimum(result) / 10)

    # Soliton number annotation
    P_peak_W = RC_SECH_FACTOR * P / (RC_PULSE_FWHM * RC_PULSE_REP_RATE)
    N = compute_soliton_number(fiber_gamma, P_peak_W, RC_PULSE_FWHM * 1e15, fiber_betas[1])

    push!(sweep_results, (
        L_m = L, P_cont_W = P, J_after = J_after,
        converged = converged, iterations = iterations,
        window_limited = window_limited, photon_drift_pct = drift_pct,
        N_sol = N, time_window_ps = Float64(tw), Nt = Nt_point,
        result_file = save_prefix * "_result.jld2"
    ))

    GC.gc()   # free ODE solution memory between points
end
```

### Pattern 3: Photon Number Drift Check

**What:** Per-point photon number validation (D-01 requirement). This function is already implemented in `scripts/verification.jl` as `compute_photon_number(uomega, sim)` — copy it into `run_sweep.jl` (or include verification.jl).

```julia
function compute_photon_number(uomega, sim)
    omega_s = sim["ωs"]
    Delta_t = sim["Δt"]
    abs_omega = abs.(omega_s)
    return sum(abs2.(uomega) ./ abs_omega) * Delta_t
end

function compute_photon_drift(result, uω0, fiber, sim)
    # Re-propagate with optimized phase to get output field
    φ_after = reshape(result.minimizer, sim["Nt"], sim["M"])
    uω0_opt = @. uω0 * cis(φ_after)
    fiber_prop = deepcopy(fiber)
    fiber_prop["zsave"] = [fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0_opt, fiber_prop, sim)
    uωf = sol["uω_z"][end, :, :]
    N_in  = compute_photon_number(uω0_opt, sim)
    N_out = compute_photon_number(uωf, sim)
    return abs(N_out / N_in - 1.0) * 100.0  # percent drift
end
```

**Performance note:** This adds one additional forward ODE solve per sweep point. At ~50-100s per solve, this doubles sweep wall time. For sweep points that are clearly window_limited (as detected early via boundary check), the planner should consider whether to skip full re-propagation. However, D-01 mandates post-run photon number check for every point, so it cannot be skipped.

### Pattern 4: Adaptive Nt for Time Window

**What:** The time window varies per sweep point (via fixed `recommended_time_window()`). Nt must scale with time_window to maintain temporal resolution sufficient to represent the 185 fs pulse.

The resolution constraint is: `dt = time_window / Nt < T0 / 10` where T0 = 104.9 fs (pulse half-width). This means `dt < 10.5 fs = 0.0105 ps`.

```julia
function nt_for_window(time_window_ps::Int; dt_min_ps = 0.0105)
    nt_min = ceil(Int, time_window_ps / dt_min_ps)
    nt = 1
    while nt < nt_min; nt <<= 1; end
    return nt
end
```

**Practical Nt table:**
| time_window | Nt_min | use Nt |
|-------------|--------|--------|
| 5-10 ps | 476-952 | 2^10 = 1024 |
| 11-20 ps | 1048-1905 | 2^11 = 2048 |
| 21-50 ps | 2000-4762 | 2^13 = 8192 |
| 51-100 ps | 4858-9524 | 2^14 = 16384 |

For the recommended grid below, time windows stay ≤30 ps → Nt stays at 2^13 or below. This means per-point wall time is comparable to or faster than the existing Nt=2^14 runs.

### Pattern 5: Heatmap with Convergence and N Contour Overlay

**What:** `pcolormesh()` on the (L, P) grid with J_final values in dB, non-converged points marked with "X" or hatching, N contour lines overlaid.

```julia
function plot_sweep_heatmap(sweep_results, fiber_name; save_path="heatmap.png")
    L_vals = sort(unique([r.L_m for r in sweep_results]))
    P_vals = sort(unique([r.P_cont_W for r in sweep_results]))
    nL, nP = length(L_vals), length(P_vals)

    J_grid     = fill(NaN, nL, nP)
    N_grid     = fill(NaN, nL, nP)
    conv_grid  = fill(false, nL, nP)
    wlim_grid  = fill(false, nL, nP)   # window_limited

    for r in sweep_results
        i = findfirst(==(r.L_m), L_vals)
        j = findfirst(==(r.P_cont_W), P_vals)
        J_grid[i, j]    = MultiModeNoise.lin_to_dB(r.J_after)
        N_grid[i, j]    = r.N_sol
        conv_grid[i, j] = r.converged
        wlim_grid[i, j] = r.window_limited
    end

    fig, ax = subplots(figsize=(8, 6))
    # pcolormesh expects (y_edges, x_edges) but for imshow-style we use pcolormesh on center coords
    L_mesh = [l for l in L_vals, _ in P_vals]
    P_mesh = [p for _ in L_vals, p in P_vals]
    pcm = ax.pcolormesh(P_vals, L_vals, J_grid, cmap="inferno",
                        vmin=minimum(filter(!isnan, J_grid)),
                        vmax=maximum(filter(!isnan, J_grid)))
    colorbar(pcm, ax=ax, label="J_final [dB]")

    # N contour lines
    cs = ax.contour(P_vals, L_vals, N_grid,
                    levels=[1.5, 2.0, 3.0, 5.0, 8.0],
                    colors="white", linewidths=0.8, alpha=0.7)
    ax.clabel(cs, fmt="N=%.1f", fontsize=8)

    # Non-converged points: "X" marker
    for i in 1:nL, j in 1:nP
        if !conv_grid[i, j]
            ax.plot(P_vals[j], L_vals[i], "wx", markersize=10, markeredgewidth=2)
        end
        if wlim_grid[i, j]
            ax.plot(P_vals[j], L_vals[i], "w^", markersize=8, markeredgewidth=1.5,
                    label=(i==1&&j==1 ? "window-limited" : ""))
        end
    end

    ax.set_xlabel("P_cont [W]")
    ax.set_ylabel("L [m]")
    ax.set_title("$fiber_name: J_final heatmap (X=not converged, △=window-limited)")
    fig.tight_layout()
    savefig(save_path, dpi=300)
    close(fig)
end
```

### Pattern 6: Multi-Start Analysis

**What:** 10 starts from different initial phases on SMF-28 L=2m P=0.30W, following D-04. The existing `multistart_optimization()` in `benchmark_optimization.jl` uses `Threads.@threads`. Phase 7 must use a sequential loop (D-03: no parallelization needed) and save each start's JLD2 independently for forensics.

```julia
# Multi-start: sequential version adapted from benchmark_optimization.jl
function run_multistart_sequential(uω0, fiber_gamma, fiber_betas, L_fiber, P_cont,
                                   time_window_ps, Nt; n_starts=10, max_iter=100,
                                   sigmas=[0.1, 0.5, 1.0])
    results = []
    # Include zero-phase start
    starts = [zeros(Nt, 1)]
    # Add 3 starts per sigma value
    for σ in sigmas
        for _ in 1:3
            push!(starts, σ .* randn(Nt, 1))
        end
    end
    # Pad or truncate to n_starts
    starts = starts[1:min(n_starts, length(starts))]

    for (k, φ0) in enumerate(starts)
        dir = mkpath(joinpath("results", "raman", "sweeps", "multistart",
                              @sprintf("start_%02d", k)))
        save_prefix = joinpath(dir, "opt")
        result, uω0_k, fiber_k, sim_k, band_mask_k, _ = run_optimization(
            L_fiber = L_fiber, P_cont = P_cont,
            Nt = Nt, time_window = Float64(time_window_ps),
            max_iter = max_iter, validate = false,
            φ0 = φ0,
            fiber_name = "SMF-28",
            gamma_user = fiber_gamma, betas_user = fiber_betas,
            save_prefix = save_prefix
        )
        push!(results, (
            start_idx = k, sigma = (k == 1 ? 0.0 : sigmas[(k-2)÷3+1]),
            J_final = 10^(Optim.minimum(result) / 10),
            converged = Optim.converged(result),
            iterations = Optim.iterations(result),
            result_file = save_prefix * "_result.jld2"
        ))
        GC.gc()
    end
    return results
end
```

### Anti-Patterns to Avoid

- **Reusing `fiber` Dict across sweep loop iterations:** Dict is mutable; `run_optimization()` sets `fiber["zsave"] = nothing` inside `optimize_spectral_phase`. Always call `run_optimization()` (which internally calls `setup_raman_problem()`) fresh per point, not reuse a pre-built dict.
- **Using J to check time window adequacy:** J is normalized — it cannot detect absolute energy loss from the attenuator. Only photon number drift reveals window-sizing problems.
- **Comparing J across points with different time_window and Nt:** `band_mask` bin count varies with `Δf = 1/(time_window/Nt)`. The grid must record `Nt`, `time_window_ps`, and `sum(band_mask)` alongside each J_final. The heatmap caption must note that J values are only directly comparable within a fixed grid config.
- **Calling `run_optimization()` with `validate=true` in sweep:** Gradient validation does 3 full ODE solves per point — tripling wall time for no benefit after Phase 4 confirmed gradient correctness.
- **Calling evolution plots inside sweep loop:** `run_optimization()` generates 3 PNG files per run by default (optimization result, evolution, phase diagnostic). At 40+ sweep points, this generates 120+ PNGs. The sweep script should call a lighter version or suppress plots. Alternatively, pass a flag to `run_optimization()` — but that requires adding a `plot=false` kwarg, which modifies `raman_optimization.jl`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Optimization call | Custom L-BFGS | `run_optimization()` from `raman_optimization.jl` | Already handles JLD2 save, manifest update, boundary checks, GC |
| Multi-start initial phases | Custom phase generator | Adapt `multistart_optimization()` from `benchmark_optimization.jl` | Band-limited random phase generation already implemented |
| Soliton number annotation | Inline formula | `compute_soliton_number()` from `visualization.jl` | Handles sech² pulse factor correctly; already used in Phase 6 |
| Per-point JLD2 persistence | Custom serialization | `jldsave()` as used in `run_optimization()` | All 18 fields already defined; just point to sweeps/ directory |
| Photon number | New computation | `compute_photon_number()` from `verification.jl` | Already handles `abs.(sim["ωs"])` correctly (no double-counting ω₀) |

---

## Grid Design (Claude's Discretion — D-02)

### SMF-28 Grid: 5 L × 4 P = 20 points

**Fiber params:** γ = 1.1×10⁻³ W⁻¹m⁻¹, β₂ = -2.17×10⁻²⁶ s²/m, β₃ = 1.2×10⁻⁴⁰ s³/m

The soliton number N for SMF-28 depends only on P (not L), so the L axis of the heatmap traces "how much Raman shift accumulates" at fixed N.

| L (m) | P=0.05W N=1.3 | P=0.10W N=1.8 | P=0.20W N=2.6 | P=0.30W N=3.1 |
|-------|--------------|--------------|--------------|--------------|
| 0.5   | φ_NL=1.6     | φ_NL=3.3     | φ_NL=6.6     | φ_NL=9.9     |
| 1.0   | φ_NL=3.3     | φ_NL=6.6     | φ_NL=13      | φ_NL=20 ★   |
| 2.0   | φ_NL=6.6     | φ_NL=13      | φ_NL=26      | φ_NL=39 ★★  |
| 5.0   | φ_NL=16      | φ_NL=33      | φ_NL=65 ⚠   | φ_NL=98 ⚠   |
| 10.0  | φ_NL=33      | φ_NL=65 ⚠   | φ_NL=130 ⚠  | φ_NL=195 ⚠  |

Legend: ★ = production run included, ⚠ = high phi_NL, large time window needed.

**Production runs included at:** L=1m/P=0.05W (★), L=2m/P=0.30W (★★), L=5m/P=0.15W (not in grid — use L=5m/P=0.10W or add P=0.15W as a 5th column).

**Note on L=10m:** At P=0.20W (φ_NL=130), the required time window would be hundreds of ps (Nt=2^16+). These points will likely be window-limited unless the ODE solver crashes first. Include them with a large safety_factor and flag expected window_limited status. Alternatively, restrict SMF-28 to L ≤ 5m (4×4 = 16 points) and add P=0.15W as a 5th P value to maintain 20 points.

**Recommended SMF-28 grid (20 points):**
- L_vals = [0.5, 1.0, 2.0, 5.0, 10.0] m
- P_vals = [0.05, 0.10, 0.20, 0.30] W

**Time window per point (with SPM correction, safety_factor=2):**
For SMF-28 with β₂_abs=2.17×10⁻²⁶, the SPM temporal broadening from the revised formula at moderate φ_NL is manageable:
- L=0.5m, P=0.05W: ~5 ps → Nt=2^10
- L=1m, P=0.30W: ~10-15 ps → Nt=2^11 or 2^12
- L=2m, P=0.30W: ~25-30 ps → Nt=2^13
- L=5m, P=0.30W: ~60-80 ps → Nt=2^14
- L=10m, P=0.30W: >100 ps → Nt=2^15 (slow: ~500s/point)

The L=10m row significantly increases compute time. If D-03 (no time limit) is accepted, include it; otherwise restrict to L ≤ 5m.

### HNLF Grid: 4 L × 4 P = 16 points

**Fiber params:** γ = 10.0×10⁻³ W⁻¹m⁻¹, β₂ = -0.5×10⁻²⁶ s²/m, β₃ = 1.0×10⁻⁴⁰ s³/m

HNLF is 9× more nonlinear than SMF-28. At β₂_abs = 0.5×10⁻²⁶ s²/m (much smaller than SMF-28), the temporal SPM broadening is smaller (by factor ~4.3), so time windows for HNLF are more tractable despite higher γ.

N values for HNLF:
- P=0.005W: N=2.6, P=0.010W: N=3.6, P=0.030W: N=6.3, P=0.050W: N=8.1

| L (m) | P=0.005W N=2.6 | P=0.010W N=3.6 | P=0.030W N=6.3 | P=0.050W N=8.1 |
|-------|----------------|----------------|----------------|----------------|
| 0.5   | φ_NL=1.5       | φ_NL=3.0       | φ_NL=8.9       | φ_NL=15        |
| 1.0   | φ_NL=3.0       | φ_NL=5.9       | φ_NL=18        | φ_NL=30 ★     |
| 2.0   | φ_NL=5.9       | φ_NL=12        | φ_NL=36        | φ_NL=59 ★★    |
| 5.0   | φ_NL=15        | φ_NL=30        | φ_NL=89 ⚠     | φ_NL=148 ⚠    |

Legend: ★ = production run included (L=1m/P=0.05W), ★★ = production run included (L=2m/P=0.05W)

**Time windows for HNLF are generally ≤15 ps** due to small β₂, so Nt stays at 2^10-2^12 for most points. High φ_NL (L=5m/P=0.05W) may still require larger windows.

**Note:** HNLF at P=0.10W crashed the ODE solver in Phase 6 at L=5m (NaN in solver). Keep HNLF max power at P=0.05W. Approach high-N regime via long fiber (L=5m/P=0.005W is N=2.6, same as L=1m but longer propagation).

### Total Sweep: 36 points

- SMF-28: 5 × 4 = 20 points
- HNLF: 4 × 4 = 16 points
- Total: 36 points (within the 40-50 target from D-02)

**Estimated total wall time:** Each point takes 50-500s depending on Nt and convergence. Budget ~150s average = ~1.5 hours for the full grid. With D-03 (no time limit), this is acceptable.

### Multi-Start Config (D-04)

- **Target config:** SMF-28 L=2m P=0.30W (N=3.1)
- **Why this config:** Existing Phase 6 result showed convergence=false at 50 iterations with J_after=-42.2 dB starting from zero phase. Interesting optimization landscape (hard to converge, moderate suppression).
- **Time window for this config:** ~25-30 ps, Nt=2^13
- **n_starts:** 10
- **Initial phases:**
  - Start 1: φ₀ = zeros (baseline, matches production run)
  - Starts 2-4: φ₀ ~ N(0, 0.1²) (small perturbations near zero)
  - Starts 5-7: φ₀ ~ N(0, 0.5²) (moderate random)
  - Starts 8-10: φ₀ ~ N(0, 1.0²) (large random — σ=1.0 rad)
- **max_iter:** 100 per start
- **Random seed:** Set `Random.seed!(42)` before generating phases for reproducibility

---

## Common Pitfalls

### Pitfall 1: Soliton Number N Does NOT Depend on L

**What goes wrong:** Plotting a heatmap of J_final on an L×P grid and annotating N contour lines — but drawing N contours as if N varies with L. N = sqrt(γ·P_peak·T₀²/|β₂|) is independent of L. N contour lines in the L×P heatmap are therefore vertical lines (constant P).

**Why it happens:** N is called "soliton order" and intuitively scales with fiber length, but mathematically it only depends on the fiber parameters and pulse power.

**How to avoid:** When computing N contour levels for the heatmap, compute N_grid[i,j] = compute_soliton_number(gamma, P_peak(P_vals[j]), fwhm, beta2) — this is constant along each column (all L values for a given P). The N contour plot will show vertical lines, which is physically correct.

### Pitfall 2: run_optimization() Generates Full Visualization Per Point

**What goes wrong:** `run_optimization()` calls `plot_optimization_result_v2()`, `propagate_and_plot_evolution()`, and `plot_phase_diagnostic()` for every call. In a 36-point sweep, this generates 108 PNG files and runs an extra forward ODE solve per point for evolution plots. Wall time roughly doubles.

**Why it happens:** `run_optimization()` was designed for interactive single-run use, not batch sweep use.

**How to avoid:** Two options:
1. Add a `plot=false` kwarg to `run_optimization()` that skips all visualization calls. This requires modifying `raman_optimization.jl`.
2. Call `optimize_spectral_phase()` directly in the sweep loop (bypassing `run_optimization()`'s plot calls) and handle JLD2 save + manifest update explicitly. This replicates code from `run_optimization()`.

Option 1 is cleaner. Add `; do_plots=true` kwarg to `run_optimization()` and wrap all visualization in `if do_plots ... end`. Call sweep points with `do_plots=false`. Call post-sweep canonical runs with `do_plots=true`.

### Pitfall 3: Non-Converged Results Appearing in Heatmap Without Annotation

**What goes wrong:** Phase 6 showed all 5 production configs hit `converged=false` except Run 1. In a 36-point sweep, a large fraction will be non-converged. If the heatmap shows only J_final without convergence annotation, the viewer cannot distinguish "J=-30 dB because optimizer found a good solution" from "J=-30 dB because optimizer didn't converge and is 30% into a partial solution."

**How to avoid:** Every non-converged point gets an "X" overlay on the heatmap. The aggregate JLD2 saves `converged`, `iterations`, and `grad_norm` for every point. Pattern analysis (finding trends in J) is only done on `converged=true` points.

### Pitfall 4: SPM-Only Time Window Formula Underestimates at High phi_NL

**What goes wrong:** The formula Δω_SPM ≈ γ·P_peak·L is a first-order approximation. At φ_NL > 20, soliton fission and modulation instability create spectral wings far beyond SPM prediction. The photon number drift check (D-01) catches this — a point with drift > 5% gets flagged regardless of how the time window was estimated.

**Why it happens:** SPM broadening is a perturbative formula; it breaks down at high nonlinearity.

**How to avoid:** Use safety_factor=3.0 for points where φ_NL > 20 (or where L > L_NL). The post-run photon drift check is the definitive gate.

### Pitfall 5: JLD2 Sweep Aggregate File Race Condition (Not Applicable Here)

**Note:** D-03 specifies sequential execution, so there is no parallel write race. The aggregate file is only written after all sweep points complete.

### Pitfall 6: Dict Mutation in Sweep Loop

**What goes wrong:** If the planner designs the sweep to pre-build one `sim` and `fiber` and mutate `fiber["L"]` between iterations, downstream runs will inherit corrupted state from previous iterations.

**How to avoid:** Always call `run_optimization(..., L_fiber=L, P_cont=P, ...)` with fresh kwargs per iteration. `run_optimization()` internally calls `setup_raman_problem()` which creates a fresh Dict. Never hoist Dict construction outside the loop.

---

## Code Examples

### Photon Number Drift (verified pattern from verification.jl)

```julia
# Source: scripts/verification.jl (compute_photon_number, lines 189-198)
function compute_photon_number(uomega, sim)
    omega_s = sim["ωs"]    # absolute angular frequency (ω₀ included), rad/ps
    Delta_t = sim["Δt"]    # time step, ps
    # abs.(omega_s) — do NOT add sim["ω0"] again (it's already in omega_s)
    abs_omega = abs.(omega_s)
    return sum(abs2.(uomega) ./ abs_omega) * Delta_t
end
```

### Aggregate JLD2 Structure

```julia
# Save aggregate sweep scalars to JLD2
jldsave(aggregate_path;
    fiber_name    = fiber_label,
    L_vals        = unique_L_vals,
    P_vals        = unique_P_vals,
    J_after_grid  = J_grid,        # Matrix{Float64} (nL × nP)
    N_sol_grid    = N_grid,         # Matrix{Float64} (nL × nP)
    converged_grid = conv_grid,     # Matrix{Bool}
    window_limited_grid = wlim_grid, # Matrix{Bool}
    drift_pct_grid = drift_grid,    # Matrix{Float64}
    time_window_grid = tw_grid,     # Matrix{Int} (ps)
    Nt_grid       = Nt_grid,        # Matrix{Int}
    result_files  = file_grid,      # Matrix{String}
)
```

### Nt Scaling Function

```julia
# Determine Nt from time window while maintaining pulse resolution
function nt_for_window(time_window_ps::Int; dt_min_ps = 0.0105)
    # T0 = 104.9 fs → dt_min = T0/10 ≈ 10.5 fs = 0.0105 ps
    nt_min = ceil(Int, time_window_ps / dt_min_ps)
    nt = 1
    while nt < nt_min; nt <<= 1; end
    return nt
end
```

---

## Runtime State Inventory

This is a sweep phase — no renames or migrations. Standard state inventory is not applicable. The sweep creates new files only:
- New directory: `results/raman/sweeps/` (does not exist yet)
- New JLD2 files per point: `results/raman/sweeps/{fiber}/{params}/opt_result.jld2`
- New aggregate JLD2: `results/raman/sweeps/sweep_results_{fiber}.jld2`
- Updates to: `results/raman/manifest.json` (each `run_optimization()` call appends to it)

**Manifest growth:** The existing manifest has 5 entries (from production runs). The sweep adds 36 more entries. The append-safe pattern in `run_optimization()` handles this correctly.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All | Yes | 1.12.4 | — |
| JLD2.jl | Sweep persistence | Yes | current | — |
| JSON3.jl | Manifest update | Yes | current | — |
| PyPlot.jl | Heatmap generation | Yes | current | — |
| Optim.jl | L-BFGS sweep | Yes | 1.13.3+ | — |
| `results/raman/sweeps/` dir | Sweep output | Missing — must be created | — | `mkpath()` in script |

**All dependencies available. Only the output directory needs creation.**

---

## Open Questions

1. **Should the sweep suppress per-point evolution plots?**
   - What we know: `run_optimization()` generates 3 PNGs per run by default; 36 runs = 108 PNGs; each evolution plot runs an extra ODE solve.
   - What's unclear: Whether the planner wants per-point evolution plots for post-hoc inspection or just aggregate heatmaps.
   - Recommendation: Add `do_plots=false` kwarg to `run_optimization()` as part of the sweep setup. Run all 36 points with `do_plots=false`. Run 4-5 "interesting" canonical points with `do_plots=true` after the sweep.

2. **How to handle ODE solver NaN crashes in the sweep?**
   - What we know: HNLF at L=5m P=0.10W caused NaN in Phase 6. The grid avoids this by capping HNLF at P=0.05W. But other high-φ_NL points may also crash.
   - What's unclear: Whether crashes are trapped by `run_optimization()` or propagate to the script level.
   - Recommendation: Wrap each sweep point in a `try-catch` block. On catch, record `J_after=NaN`, `converged=false`, `error="ODE solver NaN"` and continue. Log the crash prominently but don't abort the sweep.

3. **Should L=10m be included in SMF-28 grid?**
   - What we know: L=10m P=0.15W crashed (NaN in warm-start Phase 6 attempt); L=5m P=0.15W took 280s at 100 iterations without converging (49% drift). L=10m time windows would be 100-1000+ ps, requiring Nt=2^15-2^17.
   - What's unclear: Whether L=10m points will converge within solvable time windows.
   - Recommendation: Include L=10m P=0.05W only (lowest power, smallest time window ~35 ps, most likely to be stable). Exclude L=10m for P≥0.10W from the default grid.

4. **What max_iter to use for sweep points?**
   - What we know: All production configs except Run 1 hit max_iter=50 or max_iter=80 without converging. Run 5 (L=5m P=0.15W) used max_iter=100 and still didn't converge.
   - Recommendation: Use max_iter=100 for all sweep points. This matches the Phase 6 heavy runs. For the multi-start analysis, 100 is also appropriate. The cost of 100 iterations vs 50 iterations is only 2× wall time — acceptable given D-03 (no time limit).

---

## Sources

### Primary (HIGH confidence — direct code audit)
- `scripts/common.jl` (lines 182-191) — `recommended_time_window()` current implementation; direct read
- `scripts/raman_optimization.jl` (lines 370-601) — `run_optimization()` full implementation; direct read
- `scripts/verification.jl` (lines 189-248) — `compute_photon_number()` and VERIF-02 photon drift check; direct read
- `scripts/benchmark_optimization.jl` (lines 577-680) — `multistart_optimization()` implementation; direct read
- `results/raman/validation/verification_20260325_173141.md` — quantitative photon drift evidence (2.7-49%); direct read
- JLD2 result files for all 5 production runs — timing and convergence data; direct read via julia

### Secondary (HIGH confidence — physics computation)
- Physics calculations in this document — P_peak values, N values, φ_NL values, time window estimates computed from first principles using project parameters

### Prior Project Research (HIGH confidence)
- `.planning/research/PITFALLS.md` — pitfall catalog from v2.0 research; all pitfalls directly relevant to sweep infrastructure
- `.planning/research/FEATURES.md` — parameter sweep heatmap specification and anti-feature catalog

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all patterns are extensions of existing code
- Architecture patterns: HIGH — derived from direct code audit of `run_optimization()`, `multistart_optimization()`, `compute_photon_number()`
- Grid design: MEDIUM — N values and φ_NL computed from physics are exact; time window estimates are first-order (SPM formula is approximate); actual behavior at high φ_NL is uncertain and will be caught by photon drift check
- Pitfalls: HIGH — 4 of 6 pitfalls are directly documented in `.planning/research/PITFALLS.md` from prior research; 2 are new (Phase 7-specific)

**Research date:** 2026-03-26
**Valid until:** No external dependencies; valid indefinitely until codebase changes