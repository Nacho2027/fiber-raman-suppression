# Phase 10: Propagation-Resolved Physics & Phase Ablation - Research

**Researched:** 2026-04-02
**Domain:** Julia / GNLSE propagation diagnostics, spectral phase ablation, JLD2 serialization
**Confidence:** HIGH (codebase is primary source; all claims verified by direct file inspection)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** 50 z-save points per fiber — `LinRange(0, L, 50)`. 10 cm resolution for 5 m fiber.
- **D-02:** Compute `E_band(z) / E_total(z)` at each z-point using `band_mask` and `spectral_band_cost` pattern.
- **D-03:** Also compute full spectral evolution along z (heatmap), not just scalar Raman fraction.
- **D-04:** 6 representative configurations (3 SMF-28 + 3 HNLF) spanning N_sol range: low (~1.5), medium (~3), high (~5-6). Include best and worst suppression points from Phase 9.
- **D-05:** Full phase ablation on 2 canonical configs: SMF-28 (N≈2.6, multi-start config) and HNLF (best suppression).
- **D-06:** Each configuration propagated twice: flat phase (unshaped) and phi_opt (shaped).
- **D-07:** Frequency-band zeroing: divide signal band into 8-10 equal-width sub-bands, zero one at a time, propagate, measure suppression loss.
- **D-08:** Super-Gaussian roll-off at band edges to avoid Gibbs ringing when zeroing.
- **D-09:** Cumulative ablation: zero bands from edges inward, tracking suppression degradation vs bandwidth.
- **D-10:** Global scaling: multiply phi_opt by [0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], propagate.
- **D-11:** Spectral shift: translate phi_opt by ±1, ±2, ±5 THz on frequency grid, propagate.
- **D-12:** No noise-addition perturbations — deterministic only.
- **D-13:** Re-propagate existing phi_opt with z-saves only. No new optimization runs.
- **D-14:** Save all z-resolved data to JLD2 in `results/raman/phase10/`.
- **D-15:** All new figures to `results/images/` with prefix `physics_10_XX_`.

### Claude's Discretion

- Which 6 specific (L,P) configurations from the sweep to use as representatives
- Figure layout and panel arrangement for z-resolved plots
- Whether to add spectrogram-style (time-frequency) analysis at selected z-points
- Whether to compute z-resolved group delay evolution
- Statistical presentation of ablation results (bar charts vs heatmaps vs tables)

### Deferred Ideas (OUT OF SCOPE)

- Multimode (M>1) extension
- Quantum noise on top of classical optimization
- New optimization cost functions (e.g., minimize Raman at specific z)
- FROG/XFROG-style time-frequency analysis
</user_constraints>

---

## Summary

Phase 10 runs NEW forward propagations with z-resolved snapshots and conducts spectral phase ablation experiments to understand the 84% of Raman suppression that Phase 9 attributed to "configuration-specific nonlinear interference." The codebase already has all the machinery needed: `fiber["zsave"]` activates intermediate snapshot saving in `solve_disp_mmf`, `spectral_band_cost` computes the Raman fraction at any z-slice, and `plot_spectral_evolution` / `plot_temporal_evolution` produce heatmaps from the resulting `sol["uω_z"]` / `sol["ut_z"]` arrays. Phase ablation requires constructing modified phi vectors (band zeroing with super-Gaussian windows, global scaling, frequency shift) and re-propagating — no solver changes needed.

The primary technical challenges are: (1) selecting the 6 canonical configurations from the sweep (informed by soliton number coverage), (2) memory management for 50-z-point propagation over 12 configurations × 2 conditions, (3) implementing band zeroing without Gibbs artifacts, and (4) designing figure layouts that make z-resolved Raman fraction curves readable alongside full heatmaps.

**Primary recommendation:** Build two independent scripts — `scripts/propagation_z_resolved.jl` and `scripts/phase_ablation.jl` — each using `include("common.jl")` and `include("visualization.jl")` with unique constant prefixes. Both save their heavy data to JLD2 and figures to `results/images/`.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MultiModeNoise | 1.0.0-DEV | Forward solver, fiber params, `solve_disp_mmf` | Project's own package — the only solver available |
| JLD2 | 0.6.3 | Save/load z-resolved arrays and ablation results | Already used everywhere for sweep data; in Project.toml |
| PyPlot | (unversioned) | All figures — heatmaps, line plots, bar charts | Project constraint: Julia + PyPlot only |
| FFTW | (unversioned) | FFT for band construction, spectral operations | Already used in visualization and common |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Statistics | (stdlib) | `mean`, `std` for suppression statistics across ablation sweep | Ablation result summary tables |
| Printf | (stdlib) | Formatted logging, figure annotations | All scripts |
| Logging | (stdlib) | `@info`, `@warn` for run summaries | All scripts |
| Dates | (stdlib) | RUN_TAG for output file naming | Script-level constant initialization |
| Interpolations | 0.16.2 | Interpolating phi_opt onto ablation frequency sub-bands (if grids differ) | Band construction only |

### No New Dependencies
The tech stack constraint (Julia + PyPlot, no new visualization dependencies) means no Makie, Plots.jl, or additional signal processing packages. Everything needed already exists in the project.

**Installation:** None required — all dependencies already in `Project.toml`.

---

## Architecture Patterns

### Recommended Script Structure
```
scripts/
├── propagation_z_resolved.jl    # Plan 10-01: z-snapshots, Raman fraction curves
├── phase_ablation.jl            # Plan 10-02: band zeroing, scaling, shift
├── common.jl                    # (existing) setup_raman_problem, spectral_band_cost
└── visualization.jl             # (existing) plot_spectral_evolution, plot_temporal_evolution

results/raman/phase10/
├── smf28_L{X}m_P{Y}W_shaped_zsolved.jld2
├── smf28_L{X}m_P{Y}W_unshaped_zsolved.jld2
├── hnlf_L{X}m_P{Y}W_shaped_zsolved.jld2
├── hnlf_L{X}m_P{Y}W_unshaped_zsolved.jld2
├── ablation_smf28_canonical.jld2
└── ablation_hnlf_canonical.jld2

results/images/
├── physics_10_01_raman_fraction_vs_z.png
├── physics_10_02_spectral_evolution_shaped.png
├── physics_10_03_spectral_evolution_unshaped.png
├── physics_10_04_temporal_evolution_shaped.png
├── physics_10_05_ablation_band_zeroing.png
└── ...
```

### Pattern 1: Z-Resolved Propagation
**What:** Set `fiber["zsave"]`, call `solve_disp_mmf`, compute `J(z)` at each slice.
**When to use:** For every configuration in the 6-config sweep.
**Example:**
```julia
# Source: src/simulation/simulate_disp_mmf.jl lines 181-197, scripts/verification.jl lines 112-122
uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
    L_fiber=L, P_cont=P_cont, fiber_preset=:SMF28
)
fiber["zsave"] = LinRange(0, fiber["L"], 50)

# Shaped propagation (apply phi_opt)
uω0_shaped = uω0 .* exp.(1im .* phi_opt)
sol_shaped = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber, sim)

# Unshaped propagation (flat phase)
sol_unshaped = MultiModeNoise.solve_disp_mmf(uω0, fiber, sim)

# Raman fraction at each z-slice
J_z_shaped   = [spectral_band_cost(sol_shaped["uω_z"][i, :, :],   band_mask)[1] for i in 1:50]
J_z_unshaped = [spectral_band_cost(sol_unshaped["uω_z"][i, :, :], band_mask)[1] for i in 1:50]
```

**Critical detail:** `phi_opt` from JLD2 is length Nt in FFT order (NOT fftshifted). Apply as `uω0 .* exp.(1im .* phi_opt)` directly — no fftshift needed because `uω0` is also in FFT order.

### Pattern 2: Band Zeroing with Super-Gaussian Window
**What:** Zero out phi_opt in one frequency sub-band using a smooth window to avoid Gibbs.
**When to use:** Phase ablation experiments (D-07, D-08).
**Example:**
```julia
# Source: Derived from common.jl spectral_band_cost pattern + D-08 decision

function make_ablation_window(fs_fftshifted, band_lo, band_hi; sg_order=6, sg_width_frac=0.1)
    # Super-Gaussian roll-off at both edges of the zeroed band
    # fs_fftshifted: frequency axis in THz (fftshifted)
    window = ones(length(fs_fftshifted))
    # Zero the band interior; super-Gaussian transitions at edges
    band_width = band_hi - band_lo
    sg_sigma = sg_width_frac * band_width
    for (i, f) in enumerate(fs_fftshifted)
        if band_lo < f < band_hi
            dist_lo = f - band_lo
            dist_hi = band_hi - f
            margin = min(dist_lo, dist_hi)
            window[i] = 1.0 - exp(-(margin / sg_sigma)^sg_order)
        end
    end
    return window
end

# Apply: phi_ablated = phi_opt .* fftshift(window)  # convert to FFT order
```

### Pattern 3: Load phi_opt and Reconstruct Initial State
**What:** Load saved phi_opt from JLD2, reconstruct the same initial condition (same Nt, time_window, P_cont) for re-propagation.
**When to use:** All Phase 10 propagations — existing phi_opt is not re-optimized.
**Example:**
```julia
# Source: scripts/phase_analysis.jl lines 141-183 (data loading pattern)
data = JLD2.load("results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2")
phi_opt = vec(data["phi_opt"])           # FFT order, length Nt
L = Float64(data["L_m"])
P_cont = Float64(data["P_cont_W"])
fwhm_fs = Float64(data["fwhm_fs"])
time_window = Float64(data["time_window_ps"])
Nt = Int(data["Nt"])
fiber_name = data["fiber_name"]

# Reconstruct with same parameters
uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
    L_fiber=L, P_cont=P_cont, Nt=Nt, time_window=time_window,
    fiber_preset=fiber_name == "SMF-28" ? :SMF28 : :HNLF
)
# uω0 matches original initial condition; phi_opt was found for this exact setup
```

**Unit warning (from STATE.md):** `sim_omega0` in JLD2 is stored in rad/ps, not rad/s. `sim_Dt` is in picoseconds. Do not use these to reconstruct sim — use `setup_raman_problem` with the stored L, P, Nt, time_window.

### Pattern 4: Save z-Resolved Data to JLD2
**What:** Save all heavy arrays (uω_z, ut_z, J_z curves) to JLD2 for future analysis.
**When to use:** After each z-resolved propagation, before plotting.
**Example:**
```julia
# Source: scripts/raman_optimization.jl pattern (same JLD2.save convention)
mkpath("results/raman/phase10")
JLD2.save("results/raman/phase10/smf28_L2m_P02W_shaped_zsolved.jld2",
    "uω_z",       sol_shaped["uω_z"],           # ComplexF64 [50 × Nt × 1]
    "ut_z",        sol_shaped["ut_z"],            # ComplexF64 [50 × Nt × 1]
    "J_z",         J_z_shaped,                    # Float64 [50]
    "zsave",       collect(fiber["zsave"]),        # Float64 [50]
    "phi_opt",     phi_opt,                        # Float64 [Nt]
    "L_m",         L,
    "P_cont_W",    P_cont,
    "fiber_name",  fiber_name,
    "Nt",          Nt,
    "sim_Dt",      sim["Δt"],
    "band_mask",   band_mask
)
```

### Pattern 5: Include Guard and Script Constants
**What:** Use unique constant prefix and include guard to avoid REPL redefinition errors.
**When to use:** Every new script.
**Example:**
```julia
# Prefix PZ_ for propagation_z_resolved.jl (from CONTEXT.md code_context section)
if !(@isdefined _PZ_SCRIPT_LOADED)
const _PZ_SCRIPT_LOADED = true
const PZ_N_ZSAVE = 50
const PZ_RESULTS_DIR = "results/raman/phase10"
const PZ_FIGURE_DIR = "results/images"
end

if abspath(PROGRAM_FILE) == @__FILE__
    # main execution
end
```

Use `PA_` prefix for phase_ablation.jl to stay consistent with Phase 9's `PA_` prefix convention... actually Phase 9 uses `PA_` for phase_analysis.jl. Use `PZ_` for z-resolved and `PAB_` for phase_ablation to avoid collision.

### Anti-Patterns to Avoid

- **Calling `setup_raman_problem` with default Nt/time_window:** The stored sweep data used specific (possibly auto-sized) Nt and time_window values. Always restore the exact Nt and time_window from JLD2 to reproduce the same grid, or the `phi_opt` phase will be applied to a mismatched frequency grid.
- **fftshift on phi_opt before applying:** `phi_opt` and `uω0` are both in FFT order. Applying `exp.(1im .* fftshift(phi_opt))` would introduce a spectral rotation instead of the correct phase shaping.
- **Mutating the same `fiber` dict across configurations:** `fiber["zsave"]` is set after `setup_raman_problem`. Each configuration should use its own `fiber` dict (deepcopy or create fresh via `setup_raman_problem`).
- **Using `spectral_band_cost` return value at index 1 vs full return:** `spectral_band_cost` returns `(J, dJ)`. Only `J` is needed for diagnostics — always index as `J, _ = spectral_band_cost(...)` or `spectral_band_cost(...)[1]`.
- **Assuming `band_mask` from JLD2 matches current grid:** The stored `band_mask` is a Boolean vector for the specific Nt at that sweep point. If Nt differs, the mask must be recomputed via `setup_raman_problem`.

---

## Recommended Configuration Selection (Claude's Discretion)

Based on the soliton number inventory from the actual sweep data:

### SMF-28 Candidates (3 configurations)
| Config | N_sol | Suppression | Why Choose |
|--------|-------|-------------|------------|
| L0.5m_P0.05W | 1.29 | -45.7 dB | Low N regime representative |
| L0.5m_P0.2W  | 2.57 | -67.6 dB | Medium N, best short-fiber suppression |
| L5m_P0.1W    | 1.82 | -50.8 dB | Long fiber, medium N — tests whether z-resolved shows different dynamics for same N but longer propagation |

Alternatively for high-contrast: replace L5m_P0.1W with L5m_P0.2W (N=2.57, -35.6 dB) to include a configuration where suppression degraded at long fiber — z-resolved might reveal why.

### HNLF Candidates (3 configurations)
| Config | N_sol | Suppression | Why Choose |
|--------|-------|-------------|------------|
| L1m_P0.005W  | 2.55 | -64.5 dB | Low N, best HNLF suppression |
| L1m_P0.01W   | 3.61 | -67.4 dB | Medium N, strong suppression |
| L0.5m_P0.03W | 6.25 | -48.5 dB | High N — the regime where Phase 9 showed weaker N_sol clustering |

This gives N_sol spanning 1.29 to 6.25 with roughly equal logarithmic spacing (1.3, 1.8/2.6, 3.6, 6.3) and includes both best and worst suppression points.

### Canonical Ablation Configurations (D-05)
- **SMF-28 canonical:** L2m_P0.2W (N=2.57, -59.4 dB) — this is the multi-start configuration from Phase 9, so 10 different phi_opt profiles are available for ablation comparison
- **HNLF canonical:** L1m_P0.01W (N=3.61, -67.4 dB) — strongest HNLF suppression

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Forward propagation | Custom ODE | `solve_disp_mmf` | Handles interaction picture, RK45, tolerances, zsave natively |
| Raman fraction at z | Manual E_band/E_total | `spectral_band_cost(uω_z[i,:,:], band_mask)[1]` | Validated, contract-checked, handles M dimensions |
| Spectral heatmaps | Custom pcolormesh | `plot_spectral_evolution(sol, sim, fiber)` | Already handles wavelength conversion, dB normalization, pump/Raman markers |
| Temporal heatmaps | Custom pcolormesh | `plot_temporal_evolution(sol, sim, fiber)` | Already handles ps conversion, energy window auto-zoom |
| Fiber parameter setup | Manual Dict construction | `setup_raman_problem(fiber_preset=:SMF28, ...)` | Handles Raman response, auto-time-window sizing, band_mask |
| Phase loading | Manual npz/csv | `JLD2.load("opt_result.jld2")` | All sweep data already in JLD2 format with known keys |
| Polynomial decomposition | Hand-coded Vandermonde | `pa_extended_poly_fit` (phase_analysis.jl) | Already handles normalization, QR solve, physical units |

**Key insight:** This phase is primarily about analysis — almost all computation is `solve_disp_mmf` (existing) + `spectral_band_cost` (existing) + visualization (existing). The only genuinely new code is (1) the band-zeroing window function, (2) the loop that calls `solve_disp_mmf` for each ablation variant, and (3) the figure that plots `J(z)` as a 1D line rather than a heatmap.

---

## Common Pitfalls

### Pitfall 1: Grid Mismatch Between Stored phi_opt and Re-Propagation
**What goes wrong:** Setup_raman_problem auto-sizes Nt and time_window. If called with different defaults than the original run, `phi_opt` has length `Nt_old` but `uω0` has length `Nt_new`. Applying the phase will throw a dimension error — or worse, silently broadcast incorrectly.
**Why it happens:** The auto-sizing logic in `setup_raman_problem` depends on L, P_cont, and fiber preset. Different L and P values in Phase 9's sweep produced different (Nt, time_window) pairs.
**How to avoid:** Always pass `Nt=Int(data["Nt"])` and `time_window=Float64(data["time_window_ps"])` explicitly to `setup_raman_problem` when reproducing a sweep point.
**Warning signs:** `phi_opt` length != `size(uω0, 1)`.

### Pitfall 2: Memory Explosion for 12 configs × 2 conditions × 50 z-points
**What goes wrong:** Each z-resolved propagation stores `uω_z` of shape `[50 × Nt × 1]` in ComplexF64. For Nt=8192, that is 50 × 8192 × 16 bytes ≈ 6.5 MB per propagation. Storing all 12 × 2 = 24 propagations simultaneously would use ~160 MB. With Nt=16384, doubles to 320 MB. Not a problem for modern hardware, but if scripts accumulate all results before saving, GC pressure may slow things.
**Why it happens:** Julia's GC may not collect large arrays promptly during long loops.
**How to avoid:** Save each propagation to JLD2 immediately after completion and `uω_z = nothing` to release the reference before the next propagation.
**Warning signs:** Script slows dramatically after the 4th-6th propagation; `@allocated` reports GB-level usage.

### Pitfall 3: Gibbs Ringing in Band-Zeroed Phase
**What goes wrong:** Hard-clipping phi_opt to zero in a frequency band creates sharp edges. IFFT of the modified phase is equivalent to convolving the original pulse with a sinc function — leading to oscillatory ringing in the temporal domain that can couple to Raman processes in unexpected ways. The ablation result would then reflect both "removed phase" and "introduced ringing," conflating two effects.
**Why it happens:** Sharp frequency-domain cutoffs always produce time-domain ringing via the uncertainty principle.
**How to avoid:** Use super-Gaussian windows (order 6, D-08) at band edges. Verify the temporal pulse profile before propagation looks physically reasonable (no oscillatory tails at the 1% intensity level).
**Warning signs:** The ablated phi_opt has large sharp steps at band boundaries when plotted; the temporal intensity of the reconstructed pulse shows oscillatory side structure not present in the original.

### Pitfall 4: Band Definition in FFT vs Fftshifted Order
**What goes wrong:** `band_mask` in JLD2 is in FFT order (Raman Stokes at negative Δf = low indices). If sub-bands for ablation are constructed on the fftshifted frequency axis and then applied without inverting the shift, the zeroed region lands on the wrong spectral location.
**Why it happens:** `spectral_band_cost` uses FFT-order `band_mask`. The frequency axis for human-readable plotting is fftshifted. Phase profiles are stored in FFT order. It is easy to mix orders when constructing sub-band masks.
**How to avoid:** Do all band construction on the fftshifted axis (for physical interpretation), then `fftshift` the window back to FFT order before applying to `phi_opt`. Use `Δf = fftshift(fftfreq(Nt, 1/sim["Δt"]))` for the human-readable axis.
**Warning signs:** Ablation of the "red edge" of the signal band produces the same J change as ablating the "blue edge" (symmetry that shouldn't exist). Or the unshaped propagation changes when phi_opt is supposedly zeroed in the signal band (contamination of the phase outside the signal).

### Pitfall 5: `spectral_band_cost` Called on Wrong Slice
**What goes wrong:** `sol["uω_z"]` has shape `[Nz, Nt, M]`. Calling `spectral_band_cost(sol["uω_z"][i, :], band_mask)` accidentally flattens a 2D slice to 1D for M>1. For M=1 this works; for future M>1 extension it would silently produce wrong results.
**Why it happens:** Julia's slice `[i, :, :]` returns a 2D array, but `[i, :]` on a 3D array drops the trailing dimension.
**How to avoid:** Always use `sol["uω_z"][i, :, :]` (2D slice with explicit M dimension) to match `spectral_band_cost`'s expected `(Nt, M)` shape. The M=1 case works either way, but the 2D form is safe for extension.

### Pitfall 6: Perturbation Sweep Runtime Budget
**What goes wrong:** Phase ablation with 8-10 sub-bands × 2 directions (zeroing vs cumulative) + 8 scaling factors + 5 frequency shifts = ~25-30 propagations per canonical config × 2 configs = 50-60 propagations. Each propagation at Nt=8192, L=2m takes roughly the same wall time as the original optimization (sans gradient). At ~5-10s per propagation, this is 5-10 minutes total — acceptable. But if Nt or L is larger (e.g., L=5m, auto-sized Nt=16384), it could be 30+ minutes.
**Why it happens:** Propagation cost scales as O(Nt × N_zsave × N_steps).
**How to avoid:** Use the canonical SMF-28 config (L=2m, Nt=8192) and canonical HNLF config (L=1m, Nt≈8192-16384) as specified in D-05. Check wall time after the first few propagations and adjust N_zsave or Nt if runtime exceeds budget. For the perturbation sweep (D-10, D-11), zsave is not needed — save only z=0 and z=L to keep it fast.

---

## Code Examples

### Z-Resolved Raman Fraction Plot (New Visualization)
```julia
# Source: Derived from visualization.jl conventions, band_mask from common.jl
function plot_raman_fraction_vs_z(zsave, J_z_shaped, J_z_unshaped, config_label;
                                   figsize=(8, 5))
    fig, ax = subplots(figsize=figsize)
    z_m = collect(zsave)
    ax.semilogy(z_m, J_z_unshaped, color=COLOR_OUTPUT, linewidth=1.5,
        label="Unshaped (flat phase)")
    ax.semilogy(z_m, J_z_shaped, color=COLOR_INPUT, linewidth=1.5,
        label="Shaped (φ_opt)")
    ax.set_xlabel("Propagation distance [m]")
    ax.set_ylabel("Raman band fraction J(z)")
    ax.set_title("Raman energy evolution: $config_label")
    ax.legend()
    ax.grid(true, alpha=0.3)
    fig.tight_layout()
    return fig, ax
end
```

### Band Zeroing Ablation Loop
```julia
# Source: Derived from D-07, D-08 decisions in CONTEXT.md
# fs_sig: signal-band frequencies in THz (fftshifted), phi_opt in FFT order
function ablation_band_zeroing(uω0, fiber, sim, phi_opt, band_mask, fs_fftshifted;
                                n_bands=8, sg_order=6)
    Nt = length(phi_opt)
    sig_lo = minimum(fs_fftshifted[band_mask[fftshift(1:Nt) .+ 0]])  # approximate
    sig_hi = maximum(fs_fftshifted[...])
    sub_bandwidth = (sig_hi - sig_lo) / n_bands

    results = []
    for k in 1:n_bands
        band_lo = sig_lo + (k-1) * sub_bandwidth
        band_hi = sig_lo + k * sub_bandwidth
        # Build window in fftshifted order, then convert to FFT order
        window_shifted = ones(Nt)
        for (i, f) in enumerate(fs_fftshifted)
            if band_lo < f < band_hi
                dist_lo = f - band_lo
                dist_hi = band_hi - f
                margin = min(dist_lo, dist_hi)
                sg_sigma = 0.1 * sub_bandwidth
                window_shifted[i] = 1.0 - exp(-(margin/sg_sigma)^sg_order)
            end
        end
        phi_ablated = phi_opt .* ifftshift(window_shifted)  # back to FFT order
        uω0_ablated = uω0 .* exp.(1im .* phi_ablated)
        sol = MultiModeNoise.solve_disp_mmf(uω0_ablated, fiber, sim)
        uωf = sol["uω_z"][end, :, :]
        J_ablated, _ = spectral_band_cost(uωf, band_mask)
        push!(results, (band=(band_lo, band_hi), J=J_ablated, band_idx=k))
    end
    return results
end
```

### Frequency-Shift Perturbation
```julia
# Source: D-11 decision — translate phi_opt by ±Δf THz on frequency grid
function shift_phase_spectrum(phi_opt, sim, delta_f_THz)
    # phi_opt is in FFT order; fftshifted frequency axis in THz
    Nt = length(phi_opt)
    fs_shifted = fftshift(fftfreq(Nt, 1/sim["Δt"]))  # THz
    phi_shifted_interp = LinearInterpolation(fs_shifted, fftshift(phi_opt),
                                              extrapolation_bc=0.0)
    phi_new_shifted = phi_shifted_interp.(fs_shifted .- delta_f_THz)
    return ifftshift(phi_new_shifted)  # return to FFT order
end
```

---

## Z-Resolved Physics: What to Look For

### Key Diagnostic Questions (from CONTEXT.md specifics)

1. **Raman onset z-position:** Plot `J(z)` for unshaped pulse. Identify `z_onset` where J first rises significantly above input level. For shaped pulse, does phi_opt delay `z_onset` or does it prevent J growth throughout?

2. **Critical z hypothesis:** Is there a fiber length `z_critical` beyond which phi_opt loses effectiveness? If `J(z)` for the shaped pulse is flat until some `z_crit` then rises, it suggests a competition between phase-mediated suppression and accumulated Raman gain.

3. **N_sol regime contrast:** SMF-28 N=1.29 (sub-soliton) should show primarily linear chirp dynamics. N=2.57 (near fundamental soliton fission) may show a characteristic kink in J(z) near `z = L_fiss`. HNLF N=6.25 (high-order soliton) may show multiple cycles of soliton compression and re-expansion, each associated with J excursions.

4. **Multi-start z-divergence:** The 10 multi-start phases for L2m_P0.2W achieved similar final J_after. If their `J(z)` curves are propagated, do they diverge during the fiber then reconverge? Or are they parallel throughout? A converging trajectory suggests a physical "attractor" in the Raman dynamics; a parallel trajectory suggests the optimizer found genuinely different routes to the same endpoint.

---

## State of the Art

| Old Approach | Current Approach | Notes |
|--------------|------------------|-------|
| Input/output analysis only (Phase 9) | Z-resolved Raman fraction curves (Phase 10) | Adds spatial resolution to distinguish suppression mechanism |
| Binary phase ablation (zero/keep) | Smooth band zeroing with super-Gaussian window | Prevents Gibbs ringing from contaminating ablation results |
| Single phi_opt evaluation per config | Parametric sweep over scaling, shift, truncation | Enables 3 dB robustness envelope characterization (D-10, D-11) |

---

## Open Questions

1. **Should J(z) use linear or dB scale on the y-axis?**
   - What we know: J values span ~6 orders of magnitude (J_before ≈ 0.77, J_after ≈ 1e-7 in the L2m_P0.2W case). Log-scale (semilogy) is necessary to see variation.
   - What's unclear: Whether dB (10*log10(J)) or log10(J) is the right axis label for z-resolved plots. Phase 9 used dB for scalars; z-resolved curves may be clearer in log10.
   - Recommendation: Use semilogy with `J` on y-axis (dimensionless fraction), annotate dB on secondary axis or in figure caption.

2. **How many sub-bands for ablation (D-07)?**
   - What we know: D-07 specifies 8-10. The signal band spans roughly 50-100 THz for a 185 fs pulse, so 8 sub-bands gives ~6-12 THz per band.
   - What's unclear: Whether 8 or 10 gives better frequency resolution for identifying "critical bands."
   - Recommendation: 10 sub-bands. Even if some are informationally redundant, they improve frequency resolution at low computational cost.

3. **For cumulative ablation (D-09), which direction — from edges inward or center outward?**
   - What we know: "From edges inward" means the first truncation removes the outermost wings of phi_opt, progressively narrowing toward the central frequency.
   - What's unclear: Whether "edges" means the outer Raman-band edges or the pump-spectrum edges.
   - Recommendation: Define "edges" as the spectral wings of the signal band (far from pump center), truncating inward toward pump center. This tests whether phi_opt's tails contribute to suppression.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All propagation | ✓ | 1.12.4 | — |
| JLD2 | Sweep data loading, phase10 saving | ✓ | 0.6.3 | — |
| PyPlot / Matplotlib | All figures | ✓ | (via PyCall) | — |
| FFTW | Phase construction, spectral ops | ✓ | (via FFTW_jll) | — |
| results/raman/sweeps/ | phi_opt loading | ✓ | 24 points + 10 multistart | — |
| results/raman/phase10/ | Output data directory | ✗ (does not exist) | — | `mkpath("results/raman/phase10")` in script Wave 0 |

**Missing with no fallback:** None.
**Missing with fallback:** `results/raman/phase10/` — create with `mkpath` at script start (trivial).

---

## Sources

### Primary (HIGH confidence)
- `src/simulation/simulate_disp_mmf.jl` lines 181-197 — zsave mechanism confirmed: `fiber["zsave"]` activates snapshot saving, returns `sol["uω_z"][Nz×Nt×M]` and `sol["ut_z"][Nz×Nt×M]`
- `scripts/common.jl` lines 260-276 — `spectral_band_cost(uωf, band_mask)` signature and return `(J, dJ)` confirmed
- `scripts/common.jl` lines 318-377 — `setup_raman_problem` auto-sizing behavior confirmed, returns `(uω0, fiber, sim, band_mask, Δf, raman_threshold)`
- `scripts/verification.jl` lines 112-122 — canonical zsave usage: `fiber_prop["zsave"] = [0.0, z_soliton]`, extract `sol["ut_z"][1, :, 1]`
- `scripts/visualization.jl` lines 455-516, 528-570 — `plot_spectral_evolution` and `plot_temporal_evolution` signatures and behavior confirmed
- `results/raman/PHASE9_FINDINGS.md` — Phase 9 central findings: 84% unexplained suppression, H5 deferred, N_sol > 2 vs <= 2 clustering, multi-start correlation 0.109
- Direct JLD2 inspection: confirmed keys include `phi_opt`, `uomega0`, `Nt`, `sim_Dt`, `time_window_ps`, `L_m`, `P_cont_W`, `fiber_name`, `betas=Float64[]`
- Soliton number computation from live Julia execution: confirmed N_sol range 1.29-6.25 across all 24 sweep points with specific (L,P) config identities

### Secondary (MEDIUM confidence)
- `.planning/phases/09-physics-of-raman-suppression/09-RESEARCH.md` — Phase 9 research context, mechanism hypotheses, existing infrastructure summary

### Tertiary (LOW confidence)
- None identified.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries confirmed present in Project.toml and actively used
- Architecture: HIGH — all patterns derived from direct codebase inspection, verified function signatures
- Pitfalls: HIGH — each pitfall derived from specific code behavior observed in files (unit conventions from STATE.md, zsave from solve_disp_mmf.jl, band_mask ordering from common.jl)
- Configuration selection: MEDIUM — soliton number values confirmed from live Julia execution; choice of which 6 configs is Claude's discretion

**Research date:** 2026-04-02
**Valid until:** 2026-06-01 (stable codebase; only invalidated by changes to `solve_disp_mmf`, `setup_raman_problem`, or `spectral_band_cost` signatures)
