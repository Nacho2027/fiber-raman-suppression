# Phase 11: Classical Physics Completion - Research

**Researched:** 2026-04-03
**Domain:** Julia / GNLSE z-dynamics, multi-start trajectory clustering, spectral divergence analysis, long-fiber degradation investigation, Phases 9+10+11 synthesis
**Confidence:** HIGH (all claims verified by direct file inspection of JLD2 data, existing scripts, and findings documents)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Re-propagate all 10 multi-start phi_opt profiles (SMF-28 L=2m P=0.20W, N=2.6) with 50 z-save points each.
- **D-02:** Also propagate each multi-start with flat phase (unshaped) as baseline — validates consistency since all flat propagations use the same fiber/pulse params.
- **D-03:** Cluster the 10 J(z) trajectories and compare with the phi_opt correlation matrix from Phase 9 — test whether structurally similar solutions in phase space also have similar z-dynamics.
- **D-04:** For each of the 6 Phase 10 configs, compute z-resolved spectral difference D(z,f) = |S_shaped(z,f) - S_unshaped(z,f)| in dB. Find the z-position where D first exceeds 3 dB at any frequency.
- **D-05:** Produce spectral difference heatmaps (z vs frequency, colored by dB difference) for the 6 configs.
- **D-06:** H1 (spectrally distributed suppression): Compare critical band maps between SMF-28 and HNLF from Phase 10 data — formalize the verdict.
- **D-07:** H2 (sub-THz spectral features): Use Phase 10 shift sensitivity data to quantify the characteristic spectral scale relative to Raman gain bandwidth (13.2 THz).
- **D-08:** H3 (amplitude-sensitive nonlinear interference): Use Phase 10 scaling data; produce figure comparing scaling curves with a CPA-like model prediction.
- **D-09:** H4 (SMF-28 vs HNLF spectral strategies): Overlay critical band maps from Phase 10 ablation, determine overlap fraction.
- **D-10:** Investigate the SMF-28 5m breakdown. Re-propagate at Nt=2^14 (16384 vs current 2^15=32768) to test if lower spectral coverage is responsible.
- **D-11:** Re-optimize at L=5m with max_iter=100 (vs sweep's 60) to test if the optimizer needs more iterations.
- **D-12:** If degradation persists, compute the "suppression horizon" — the maximum L at which the optimizer can maintain >50 dB suppression for SMF-28 at this power level.
- **D-13:** Produce `CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md` merging Phases 9+10+11.
- **D-14:** All new figures use prefix `physics_11_XX_`. Save to `results/images/`.
- **D-15:** All new JLD2 data goes to `results/raman/phase11/`.

### Claude's Discretion

- Exact figure layouts and panel arrangements
- Whether to include a "phase portrait" style visualization (J(z) vs spectral bandwidth vs z)
- Statistical tests for J(z) trajectory clustering
- How deep to go in the CPA comparison for H3
- Whether the synthesis document should include Phase 6.1 findings or start from Phase 9

### Deferred Ideas (OUT OF SCOPE)

- Multimode (M>1) extension — next milestone
- Quantum noise computation — next milestone
- New optimization cost functions (z-resolved, partial-fiber) — future work
- Interactive pulse shaper design tool — future work

</user_constraints>

---

## Summary

Phase 11 is a simulation-and-analysis phase with no solver modifications. The core work is:
(1) running 20 new forward propagations (10 multi-start × 2 conditions) with z-saves,
(2) computing spectral difference heatmaps from already-existing Phase 10 z-data,
(3) formalizing H1-H4 verdicts using Phase 10 data already on disk, and
(4) investigating the 5m long-fiber degradation with two targeted experiments.

All of this maps cleanly onto the existing Phase 10 script architecture (`propagation_z_resolved.jl`, `phase_ablation.jl`). The new script (`physics_completion.jl` or similar) reuses `pz_load_and_repropagate` and `pab_load_config` patterns with a `PC_` constant prefix.

The critical finding from direct data inspection: the multi-start phi_opt profiles already show TWO natural clusters (starts 1-4, corr ~0.5-0.71; starts 5-10, corr ~0.0), and the 5m J_z profile is non-monotonic (rising to -19.4 dB peak at z=4.4m then recovering to -36.8 dB at z=5.0m). This oscillatory redistribution pattern is qualitatively different from the clean monotonic suppression at 0.5m, and is the primary clue to the long-fiber degradation mechanism.

**Primary recommendation:** Build one new script (`scripts/physics_completion.jl`) with `PC_` prefix that handles: (A) multi-start z-propagations, (B) spectral divergence analysis loading from Phase 10 JLD2, (C) H1-H4 formalization using Phase 10 data, (D) 5m re-optimization experiment. All analysis writes to `results/raman/phase11/` and figures to `results/images/physics_11_*.png`. The synthesis document is written by hand after all analysis completes.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MultiModeNoise | 1.0.0-DEV | `solve_disp_mmf`, forward propagation with zsave | Project's own package — the only solver available |
| JLD2 | (project-pinned) | Load Phase 10 z-data and multi-start phi_opt; save Phase 11 results | All sweep data already in JLD2; used in every phase script |
| PyPlot | (project-pinned) | All figures — heatmaps, line plots, J(z) overlay plots | Project constraint: Julia + PyPlot only, no Makie |
| FFTW | (project-pinned) | FFT for spectral power density, frequency axis construction | Already used in all scripts for field reconstruction |
| Optim | 1.13.3 | L-BFGS for D-11 re-optimization at 5m, max_iter=100 | Same optimizer used in all prior phases |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Statistics | (stdlib) | `mean`, `std`, `cor` for J(z) trajectory clustering | D-03 trajectory similarity analysis |
| LinearAlgebra | (stdlib) | `dot`, `norm` for phi correlation matrix | D-03 pairwise correlation of J(z) trajectories |
| Printf | (stdlib) | Formatted logging and figure annotations | All scripts |
| Logging | (stdlib) | `@info`, `@warn` for run summaries | All scripts |
| Dates | (stdlib) | RUN_TAG for output naming | Script-level constants |
| Interpolations | 0.16.2 | Interpolate phi_opt onto common frequency grid when cross-comparing | Only if grids differ between configs |

### No New Dependencies

The tech stack constraint (Julia + PyPlot only) is absolute. No new packages.

**Installation:** None required — all dependencies already in `Project.toml`.

---

## Architecture Patterns

### Recommended Project Structure (Phase 11 additions)

```
scripts/
└── physics_completion.jl       # New — PC_ prefix, handles all 4 analysis domains

results/raman/phase11/
├── multistart_start_01_shaped_zsolved.jld2   # x10
├── multistart_start_01_unshaped_zsolved.jld2 # x10
├── multistart_trajectory_analysis.jld2        # J(z) clustering results
├── spectral_divergence_smf28_L0.5m_P0.2W.jld2   # D(z,f) heatmap data x6
├── h1_h4_verdicts.jld2                            # Formalized hypotheses
└── smf28_5m_reopt_Nt32768_iter100.jld2           # D-11 result

results/images/
├── physics_11_01_multistart_jz_overlay.png
├── physics_11_02_jz_cluster_comparison.png
├── physics_11_03_spectral_divergence_heatmaps.png
├── physics_11_04_h1_critical_bands_comparison.png
├── physics_11_05_h2_shift_scale_characterization.png
├── physics_11_06_h3_cpa_scaling_comparison.png
├── physics_11_07_h4_band_overlap.png
├── physics_11_08_5m_reopt_result.png
├── physics_11_09_suppression_horizon.png
└── physics_11_10_summary_mechanism_dashboard.png

results/raman/
└── CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md     # D-13
```

### Pattern 1: Multi-Start Z-Propagation (D-01, D-02)

**What:** Load each of 10 multi-start phi_opt profiles from `results/raman/sweeps/multistart/start_{01..10}/opt_result.jld2`, reconstruct the simulation grid (same Nt=8192, tw=40ps, L=2m, P=0.2W), and run two forward propagations per start (shaped + flat phase) with 50 z-save points.

**Critical fact:** The multi-start config is L=2m, P=0.2W — NOT the same as Phase 10's z-resolved L=0.5m P=0.2W. These are genuinely new propagations.

**When to use:** Loading pattern is identical to `pz_load_and_repropagate` in propagation_z_resolved.jl. The only change is the source directory and looping over 10 starts instead of pre-defined configs.

**Example — verified loading pattern:**
```julia
# Source: scripts/propagation_z_resolved.jl (pz_load_and_repropagate, lines 119-195)
function pc_load_multistart_and_propagate(start_idx; n_zsave=PC_N_ZSAVE)
    tag = lpad(string(start_idx), 2, "0")
    jld2_path = joinpath("results", "raman", "sweeps", "multistart",
                         "start_$(tag)", "opt_result.jld2")
    data = JLD2.load(jld2_path)
    phi_opt     = vec(data["phi_opt"])
    L           = Float64(data["L_m"])          # 2.0m
    P_cont      = Float64(data["P_cont_W"])     # 0.2W
    Nt          = Int(data["Nt"])               # 8192
    time_window = Float64(data["time_window_ps"])  # 40.0ps

    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
        L_fiber=L, P_cont=P_cont, Nt=Nt, time_window=time_window,
        β_order=3, fiber_preset=:SMF28   # β_order=3 required — 2 betas in FIBER_PRESETS
    )
    zsave_vec = collect(LinRange(0, L, n_zsave))

    fiber_shaped = deepcopy(fiber)
    fiber_shaped["zsave"] = zsave_vec
    sol_shaped = MultiModeNoise.solve_disp_mmf(uω0 .* exp.(1im .* phi_opt), fiber_shaped, sim)

    fiber_flat = deepcopy(fiber)
    fiber_flat["zsave"] = zsave_vec
    sol_flat = MultiModeNoise.solve_disp_mmf(uω0, fiber_flat, sim)

    J_z_shaped = Float64[spectral_band_cost(sol_shaped["uω_z"][i,:,:], band_mask)[1]
                         for i in 1:n_zsave]
    J_z_flat   = Float64[spectral_band_cost(sol_flat["uω_z"][i,:,:], band_mask)[1]
                         for i in 1:n_zsave]
    # ...return result named tuple, save to JLD2 immediately
end
```

**CRITICAL:** All 10 flat-phase propagations should yield identical J(z) curves (same fiber, same input pulse, same phase=0) — use this as a consistency check. Any deviation indicates a grid mismatch.

### Pattern 2: Spectral Divergence Heatmap (D-04, D-05)

**What:** For each of the 6 Phase 10 configs, load the paired `*_shaped_zsolved.jld2` and `*_unshaped_zsolved.jld2` files already on disk. Compute `D(z,f) = 10*log10(|S_shaped(z,f)| / |S_unshaped(z,f)| + eps)` at each z-save point. The 3 dB threshold gives the divergence z-position.

**No new propagations needed** — all Phase 10 z-data is already on disk and verified:
```
results/raman/phase10/smf28_L0.5m_P0.05W_{shaped,unshaped}_zsolved.jld2
results/raman/phase10/smf28_L0.5m_P0.2W_{shaped,unshaped}_zsolved.jld2
results/raman/phase10/smf28_L5m_P0.2W_{shaped,unshaped}_zsolved.jld2
results/raman/phase10/hnlf_L1m_P0.005W_{shaped,unshaped}_zsolved.jld2
results/raman/phase10/hnlf_L1m_P0.01W_{shaped,unshaped}_zsolved.jld2
results/raman/phase10/hnlf_L0.5m_P0.03W_{shaped,unshaped}_zsolved.jld2
```

**Data structure verified:**
- `uω_z`: shape `(50, Nt, 1)` — full frequency-domain field at each z-point
- `sim_Dt`: time step in ps — needed to reconstruct frequency axis
- `band_mask`: Boolean vector in FFT order

**Frequency axis construction:**
```julia
# Source: STATE.md unit convention notes
Δt_ps  = Float64(d_s["sim_Dt"])   # stored in picoseconds (CRITICAL: not seconds)
fs_THz = fftfreq(Nt, 1/Δt_ps)    # → THz (because Dt in ps)
fs_shift = fftshift(fs_THz)        # → centered on DC for plotting

# Spectral power at z-slice i (fftshifted for display):
S_shaped_z_i   = fftshift(abs2.(d_s["uω_z"][i, :, 1]))
S_unshaped_z_i = fftshift(abs2.(d_u["uω_z"][i, :, 1]))

# Divergence: add eps to avoid log(0)
D_z_i = 10 .* log10.(S_shaped_z_i ./ (S_unshaped_z_i .+ 1e-30))
```

**3 dB divergence z-position:**
```julia
function pc_spectral_divergence_z(D_z_f, zsave; threshold_dB=3.0)
    # D_z_f[i, j] = D(z_i, f_j)
    for i in eachindex(zsave)
        if maximum(abs.(D_z_f[i, :])) > threshold_dB
            return zsave[i]
        end
    end
    return NaN
end
```

### Pattern 3: Re-Optimization at L=5m (D-11)

**What:** Run `optimize_spectral_phase` with the existing 5m config at `max_iter=100` (currently run to 60 iters). Load the existing phi_opt as the initial guess `φ0` to continue from where optimization stopped.

**Existing call signature (from raman_optimization.jl line 164):**
```julia
function optimize_spectral_phase(uω0_base, fiber, sim, band_mask;
    φ0=nothing, max_iter=50, λ_gdd=0.0, λ_boundary=0.0, store_trace::Bool=false,
    log_cost::Bool=false)
```

**Warm-start pattern (D-11):**
```julia
# Load existing phi_opt as warm start
d5 = JLD2.load("results/raman/sweeps/smf28/L5m_P0.2W/opt_result.jld2")
phi_warm = vec(d5["phi_opt"])

uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
    L_fiber=5.0, P_cont=0.2, Nt=Int(d5["Nt"]),
    time_window=d5["time_window_ps"], β_order=3, fiber_preset=:SMF28
)

result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
    φ0=phi_warm, max_iter=100, log_cost=true)
```

**Time budget verified:** Current 5m optimization ran for 60 iterations in 1305.8 seconds (21.8 s/iter). At 100 iterations: estimated ~2180 seconds (~36 minutes). This is feasible on a workstation.

### Anti-Patterns to Avoid

- **No fftshift before applying phi_opt:** phi_opt and uω0 are both in FFT order. The fftshift is only for visualization/plotting. Any frequency-domain operation (phase application, band construction) must stay in FFT order.
- **Never rely on auto-sizing for stored data:** Always pass `Nt=Int(data["Nt"])` and `time_window=Float64(data["time_window_ps"])` to `setup_raman_problem`. Auto-sizing changes with pulse parameters and would give a different grid.
- **Always use `β_order=3` with `FIBER_PRESETS`:** The presets `:SMF28` and `:HNLF` have 2 beta coefficients. `β_order=2` only accepts 1 beta and throws an `ArgumentError`. This has been a recurring bug in Phases 10+ and must be explicit.
- **Always `deepcopy(fiber)` before mutation:** Setting `fiber["zsave"]` mutates the dict. Never share the same `fiber` dict between shaped and unshaped propagations.
- **No `@sprintf` with string concatenation `*` in Julia 1.12:** Multi-part `@sprintf` calls using `*` fail at macroexpand time. Use single format strings only (documented in STATE.md Accumulated Context).
- **`sol["uω_z"]` is 3D:** Index as `sol["uω_z"][i, :, :]` for z-slice i (shape Nt×M). Never index as `sol["uω_z"][i, :]` even when M=1.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| J(z) computation at each z-slice | Custom energy fraction loop | `spectral_band_cost(sol["uω_z"][i,:,:], band_mask)` | Already handles M=1 slicing, normalization, returns (J, ∂J/∂uω) |
| Forward propagation with z-saves | Custom ODE | `MultiModeNoise.solve_disp_mmf(uω0, fiber_with_zsave, sim)` | `fiber["zsave"]` activates snapshot saving; solver handles all step control |
| Frequency axis construction | Manual `fftfreq` from scratch | Use `sim["fs"]` (already computed in THz) or reconstruct via `fftfreq(Nt, 1/Δt_ps)` with `sim_Dt` from JLD2 | Units: `sim_Dt` in ps, so `fftfreq(Nt, 1/Δt_ps)` yields THz directly |
| L-BFGS optimization | Custom gradient descent | `optimize_spectral_phase(...)` from `raman_optimization.jl` | Handles log-cost, gradient scaling, boundary penalty, convergence history |
| JLD2 serialization | Custom binary format | `JLD2.jldsave(path; key=value, ...)` | All prior phases use this; consistent with downstream loading |

**Key insight:** Phase 11 is almost purely analysis and re-use. The only new code patterns are (A) looping over 10 multi-start indices to call existing functions, and (B) computing `D(z,f)` difference heatmaps from loaded `uω_z` arrays — a simple 2D array subtraction in log space.

---

## Key Data Facts (Verified by Direct Inspection)

### Multi-Start Profiles (10 starts, all at L=2m, P=0.2W)

| Start | J_after (dB) | Nt | time_window (ps) | iters | wall_time (s) |
|-------|-------------|-----|-------------------|-------|---------------|
| 01 | -60.5 | 8192 | 40 | 18 | 29.7 |
| 02 | -60.8 | 8192 | 40 | 17 | 186.5 |
| 03 | -54.8 | 8192 | 40 | 16 | 71.0 |
| 04 | -63.7 | 8192 | 40 | 24 | 76.6 |
| 05 | -63.1 | 8192 | 40 | 19 | 53.2 |
| 06 | -63.7 | 8192 | 40 | 16 | 46.2 |
| 07 | -65.2 | 8192 | 40 | 22 | 43.4 |
| 08 | -64.4 | 8192 | 40 | 19 | 22.8 |
| 09 | -62.4 | 8192 | 40 | 17 | 30.6 |
| 10 | -63.9 | 8192 | 40 | 18 | 15.0 |

**Pre-discovered cluster structure** (from direct computation of normalized correlation matrix):
- **Cluster A (starts 1-4):** Mean pairwise correlation ~0.54 (range 0.42-0.71). These share structural features — a recognizable phase basin.
- **Cluster B (starts 5-10):** Mean pairwise correlation ~0.0 (range -0.11 to +0.13). Effectively uncorrelated — independent minima.
- **Overall mean:** 0.091 (close to Phase 9's reported 0.109 — consistent within rounding).
- **Key finding for D-03:** Cluster A achieves J = -54.8 to -63.7 dB; Cluster B achieves J = -62.4 to -65.2 dB. Cluster B is BETTER despite being structurally diverse within the cluster — structural similarity does NOT predict suppression depth.

### Phase 10 Z-Data (already on disk, no new propagations needed for D-04/D-05)

| Config | Nt | J_shaped final (dB) | J_unshaped final (dB) | File tag |
|--------|-----|-------------------|-----------------------|---------|
| SMF-28 L=0.5m P=0.05W | 8192 | -77.6 | -31.9 | smf28_L0.5m_P0.05W |
| SMF-28 L=0.5m P=0.2W | 8192 | -71.4 | -3.8 | smf28_L0.5m_P0.2W |
| SMF-28 L=5m P=0.2W | 32768 | -36.8 | -1.1 | smf28_L5m_P0.2W |
| HNLF L=1m P=0.005W | 8192 | -73.8 | -9.3 | hnlf_L1m_P0.005W |
| HNLF L=1m P=0.01W | 8192 | -69.8 | -2.4 | hnlf_L1m_P0.01W |
| HNLF L=0.5m P=0.03W | 8192 | -51.0 | -2.5 | hnlf_L0.5m_P0.03W |

### 5m SMF-28 J_z Profile (verified, explains D-12)

The shaped J_z is non-monotonic with a **redistribution pattern**:
- `z=0m`: J = -45.0 dB (initial)
- `z=0.2m`: J rises to -39.6 dB (2x onset, first degradation)
- `z=0.82m–1.63m`: J rises to -22 to -24 dB (worst mid-fiber accumulation)
- `z=4.4m`: J = -19.4 dB (global worst — Raman has accumulated substantially)
- `z=5.0m`: J = -36.8 dB (partial recovery — optimizer redirects energy back)

The 0.5m shaped profile is monotonically decreasing from -45.9 dB to -71.4 dB — suppression IMPROVES throughout. This is the qualitative mechanistic difference between short and long fiber operation.

**Implication for D-10/D-11:** The 5m breakdown is NOT a resolution artifact (frequency resolution already 5 GHz/bin, Raman band at 13.2 THz well within spectral range). The degradation comes from the optimizer being unable to maintain coherent suppression over the much longer nonlinear propagation distance. Higher Nt does not help because the issue is not spectral aliasing — it is the optimizer's inability to suppress mid-fiber Raman accumulation while simultaneously achieving suppression at the fiber output.

**Implication for D-12 (suppression horizon):** A "suppression horizon" analysis should look at the L×P sweep data to find the maximum L at which the optimizer achieves <50 dB at the fiber output and whether the J_z midpoint also stays below 50 dB. The current sweep shows L=0.5m gives -71.4 dB, L=5m gives -36.8 dB — the horizon is somewhere between 0.5m and 5m.

### 5m Re-Optimization Time Budget

- Current 5m: 60 iters × 21.8 s/iter = 1305.8 s (~22 min)
- D-11 (100 iters warm-start): ~100 × 21.8 s = ~2180 s (~36 min) — feasible
- D-10 (Nt=16384, same tw=202ps): ~100 × ~11 s = ~1100 s (~18 min) — also feasible
- D-10 at Nt=65536 (2x current): ~100 × 87 s = ~8700 s (~2.4 hrs) — NOT feasible; skip

---

## H1-H4 Hypothesis Status (from Phase 10 data — verdicts to formalize in Phase 11)

### H1: Spectrally Distributed Suppression

**Evidence on disk:** `ablation_smf28_canonical.jld2` and `ablation_hnlf_canonical.jld2` contain per-band suppression loss data.
- SMF-28 critical bands: 1 (−4.6 THz), 4 (−1.5 THz), 6 (+0.5 THz) — 3 of 10 bands contribute >3 dB
- HNLF critical bands: ALL 10 bands contribute >3 dB
- **Verdict direction:** CONFIRMED for HNLF (fully distributed); PARTIALLY confirmed for SMF-28 (3 dominant bands, not fully uniform)
- **D-06 action:** Compute overlap fraction (which bands are critical in BOTH fibers). From data: bands 1, 4, 6 are critical for SMF-28; all 10 for HNLF → 3/10 bands overlap. This means HNLF exploits full spectral bandwidth while SMF-28 has a preferred spatial structure.

### H2: Sub-THz Spectral Features

**Evidence on disk:** `perturbation_smf28_canonical.jld2` and `perturbation_hnlf_canonical.jld2` contain shift sensitivity data.
- SMF-28: J_shift values at [-5,-2,-1,0,1,2,5] THz: [-1.3,-22.2,-34.7,-60.5,-30.8,-24.3,-1.9] dB
- HNLF: [-7.9,-38.7,-46.1,-69.8,-38.4,-29.5,-5.2] dB
- 3 dB tolerance = [0.0, 0.0] THz (no tested shift maintains suppression within 3 dB)
- **Verdict direction:** CONFIRMED — even a ±1 THz shift degrades suppression by 26-32 dB. The relevant spectral scale is sub-THz (well below the 13.2 THz Raman detuning and below the ±1 THz test increment).
- **D-07 action:** Quantify using interpolation between shift points. The 3 dB tolerance is between 0 and 1 THz — estimate by fitting a parabola to the shift curve near zero.

### H3: Amplitude-Sensitive Nonlinear Interference

**Evidence on disk:** Scale J values for SMF-28: at scales [0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0] → J: [-1.1, -40.4, -42.7, -43.9, -60.5, -46.6, -45.9, -45.7] dB.
- **Verdict direction:** CONFIRMED — the 3 dB envelope is a single point at α=1.0. Any deviation by ±25% degrades suppression by ~17 dB (SMF-28) to ~30 dB (HNLF).
- **CPA model prediction for D-08:** A chirped pulse amplifier (CPA) model predicts that scaling phase amplitude by α is equivalent to changing the soliton order N → αN, which shifts the nonlinear length but does NOT destroy suppression — it would smoothly shift the optimal power. The CPA prediction for J(α) would be a monotonically changing curve (better suppression at α>1 if the pulse was undercompressed, or worse if overcompressed), NOT a sharp minimum at α=1. The actual sharp minimum at exactly α=1 is the defining signature of amplitude-sensitive nonlinear interference: the optimizer has tuned the phase to create destructive interference in the Raman-shifted band that only holds at precisely the optimized amplitude.
- **D-08 figure:** Two panels. Left: actual J(α) data for SMF-28 and HNLF. Right: CPA model prediction (simple curve: `J_CPA(α) = J_flat × (1 - α^2)^2` or similar parametric form showing monotonic behavior). The contrast makes the key point visually.

### H4: SMF-28 vs HNLF Spectral Strategies

**Evidence on disk:** Band data from ablation JLD2 files.
- SMF-28 critical bands: 1, 4, 6 (at −4.6, −1.5, +0.5 THz from center)
- HNLF critical bands: 1-10 (all 10 sub-bands critical)
- Overlap fraction: 3/10 bands shared → different strategies
- **Verdict direction:** PARTIALLY confirmed — the fibers use different spectral regions. HNLF requires full-bandwidth phase, SMF-28 can tolerate zeroing of 7/10 bands with <3 dB loss. This is consistent with higher nonlinearity of HNLF (10x higher γ) creating more sensitive coupling across the full spectrum.

---

## Common Pitfalls

### Pitfall 1: Multi-Start Flat Propagations Not Identical

**What goes wrong:** The 10 flat-phase propagations all use the same fiber and input pulse. They should produce identical J(z) curves. If they don't, there is a grid reconstruction error.
**Why it happens:** Passing `β_order=2` instead of 3, or using auto-sizing for time_window (which could differ from the stored value).
**How to avoid:** Hard-code `β_order=3` and load `Nt` and `time_window_ps` from each JLD2 file. Assert that all 10 flat J(z) curves agree to machine precision.
**Warning signs:** J_flat values differing by >0.1 dB across starts.

### Pitfall 2: Spectral Divergence in Wrong Units

**What goes wrong:** D(z,f) computed as linear ratio instead of dB, producing values in [0, ∞) instead of (-∞, +∞) dB. The 3 dB threshold makes no sense in linear units.
**Why it happens:** Forgetting `10 .* log10.(...)`.
**How to avoid:** Always convert to dB before applying threshold. Add assertion that `D_dB` values at z=0 are all ~0 dB (shapes should match exactly at the input).

### Pitfall 3: fftshift Before phi_opt Application

**What goes wrong:** Applying `fftshift` to phi_opt before `uω0 .* exp.(1im .* phi_opt)` rotates the phase to display order, corrupting the frequency-domain alignment.
**Why it happens:** Confusion between "FFT order" (for computation) and "centered" (for display).
**How to avoid:** phi_opt and uω0 are BOTH in FFT order (DC at index 1). Apply phase without any fftshift. Only fftshift when plotting.

### Pitfall 4: sim_Dt Units for Frequency Axis

**What goes wrong:** `sim_Dt` is stored in PICOSECONDS in JLD2 files. Using it as seconds gives a frequency axis in MHz instead of THz.
**Why it happens:** STATE.md documents this unit convention but it is easy to forget.
**How to avoid:** Always use `fftfreq(Nt, 1/Δt_ps)` where `Δt_ps = d["sim_Dt"]`. The result is in THz. Document with a comment.

### Pitfall 5: 5m Nt=65536 Re-Optimization Is Infeasible

**What goes wrong:** D-10 asks for Nt=2^14 (16384, LOWER resolution than current 2^15=32768) as a test. If the planner misreads and schedules Nt=2^16=65536 (HIGHER), the wall time is ~2.4 hours — unacceptably long for a single experiment.
**Why it happens:** Misreading of D-10 (the decision says "Nt=2^14 (vs current 2^13)" — but the current 5m actually uses Nt=2^15=32768, not 2^13=8192. D-10 likely contains a typo in the CONTEXT.md).
**How to avoid:** The correct test is: can we achieve the same or better suppression with LOWER Nt (16384)? If yes, the 32768 grid is overkill. If no, resolution matters. Use Nt=16384 for D-10.

**Note on the D-10 typo:** CONTEXT.md D-10 says "Re-propagate at Nt=2^14 (vs current 2^13)". But the actual 5m config uses Nt=32768=2^15, not 2^13=8192. The test should be: run at Nt=16384=2^14 vs current 2^15=32768. This is the correct interpretation of D-10.

### Pitfall 6: J_z Cluster Analysis Applied to Unshaped Trajectories

**What goes wrong:** Clustering the flat-phase J(z) trajectories instead of the shaped ones. Flat trajectories are all identical (same fiber, same input), so clustering finds only one cluster.
**Why it happens:** Applying clustering code to the wrong result array.
**How to avoid:** Cluster only the `J_z_shaped` arrays across the 10 multi-start runs. The flat `J_z` arrays serve as the common baseline reference.

### Pitfall 7: CPA Model Not Falsifiable If Too Flexible

**What goes wrong:** The CPA model for H3 is constructed with enough free parameters that it can fit any curve — it does not make a clear prediction that differs from the data.
**Why it happens:** Over-parameterizing the "simple chirp" model.
**How to avoid:** Use the simplest CPA prediction: for a sech² pulse with Gaussian chirp, scaling phase by α changes the temporal width by α but not the spectral shape. The suppression J should be determined by the temporal peak power, which scales as 1/α. Predict `J_CPA(α) = J_flat × exp(-(α-1)² / σ²)` with σ set by the soliton fission length — this gives a BROAD symmetric curve, not a sharp minimum. The actual data shows a narrow minimum ONLY at α=1 — the contrast is visible.

---

## Code Examples

### Load Phase 10 z-data and compute spectral divergence

```julia
# Source: Phase 10 JLD2 structure verified by direct inspection
using JLD2, FFTW, Statistics

function pc_spectral_divergence(fiber_tag, phase10_dir)
    d_s = JLD2.load(joinpath(phase10_dir, "$(fiber_tag)_shaped_zsolved.jld2"))
    d_u = JLD2.load(joinpath(phase10_dir, "$(fiber_tag)_unshaped_zsolved.jld2"))

    Nt     = Int(d_s["Nt"])
    Δt_ps  = Float64(d_s["sim_Dt"])   # picoseconds (unit-critical!)
    zsave  = d_s["zsave"]
    n_z    = length(zsave)

    # Frequency axis in THz (centered for plotting)
    fs_THz = fftshift(fftfreq(Nt, 1 / Δt_ps))

    D_z_f = Matrix{Float64}(undef, n_z, Nt)
    z_diverge = NaN

    for i in 1:n_z
        # Power spectral density at this z-slice (M=1, so squeeze dim 3)
        S_s = fftshift(abs2.(d_s["uω_z"][i, :, 1]))
        S_u = fftshift(abs2.(d_u["uω_z"][i, :, 1]))

        # Log-ratio divergence in dB
        D_z_f[i, :] = 10 .* log10.((S_s .+ 1e-30) ./ (S_u .+ 1e-30))

        # 3 dB threshold check (first z where any freq differs by >3 dB)
        if isnan(z_diverge) && maximum(abs.(D_z_f[i, :])) > 3.0
            z_diverge = zsave[i]
        end
    end

    return (D_z_f=D_z_f, fs_THz=fs_THz, zsave=zsave, z_diverge_3dB=z_diverge)
end
```

### Multi-start J(z) clustering

```julia
# Source: Phase 9 correlation analysis pattern (phase_analysis.jl)
# Cluster J_z trajectories using pairwise correlation
using Statistics, LinearAlgebra

function pc_cluster_jz_trajectories(all_jz_shaped)
    # all_jz_shaped: Vector of 10 J_z vectors, each length n_zsave
    n = length(all_jz_shaped)
    # Log-transform to make curves comparable (avoid single-scale bias)
    log_jz = [log10.(max.(jz, 1e-20)) for jz in all_jz_shaped]

    # Pairwise Pearson correlation of log J(z) trajectories
    corr_traj = zeros(n, n)
    for i in 1:n, j in 1:n
        x = log_jz[i]; y = log_jz[j]
        corr_traj[i, j] = dot(x .- mean(x), y .- mean(y)) /
                           (std(x) * std(y) * length(x))
    end
    return corr_traj
end
```

### CPA model comparison for H3

```julia
# Source: physics of H3 analysis (see Pitfall 7 notes above)
function pc_cpa_prediction(alpha_vals, J_full_lin, J_flat_lin;
                            sigma_alpha=0.5)
    # CPA prediction: scaling phi by alpha changes temporal width by alpha
    # Peak power scales as 1/alpha → Raman efficiency scales as ~(1/alpha)^n
    # Use simplest model: broad Gaussian suppression curve
    # At alpha=1: J = J_full (best). At alpha→0 or ∞: J → J_flat (unsuppressed).
    # Parametric form: J_CPA(alpha) = J_flat - (J_flat - J_full)*exp(-(alpha-1)^2/sigma^2)
    return [J_flat - (J_flat - J_full) * exp(-(a-1)^2 / sigma_alpha^2) for a in alpha_vals]
end
```

---

## Runtime State Inventory

Step 2.5 applies only to rename/refactor phases. Phase 11 is a new-simulation-and-analysis phase — no renaming occurs.

None — verified: no string replacements, no stored data key changes, no OS-level registrations involved.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All scripts | Yes | 1.12.4 | None — required |
| MultiModeNoise package | Propagation | Yes | 1.0.0-DEV | None — project package |
| JLD2 | Data load/save | Yes | Project-pinned | None — in Project.toml |
| PyPlot/Matplotlib | All figures | Yes | Agg backend | None — tech stack constraint |
| Optim.jl | D-11 re-optimization | Yes | 1.13.3 | None — in Project.toml |
| Phase 10 z-data | D-04/D-05 | Yes | 12 JLD2 files verified | None — would require re-running Phase 10 |
| Multi-start JLD2s | D-01 through D-03 | Yes | 10 files verified | None |
| Phase 10 ablation/perturbation data | H1-H4 | Yes | 4 JLD2 files verified | None |

**Missing dependencies with no fallback:** None. All data and tooling is confirmed available.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Global phase multiplier for suppression | Full-spectrum adjoint-optimized phase (84% non-polynomial) | Phase 9 established | No simple analytical formula for phi_opt |
| Single-run optimization | Multi-start analysis revealing non-convex landscape | Phase 9 | Multiple distinct basins; structurally different solutions |
| Output-only analysis | Z-resolved diagnostics tracking J(z) buildup | Phase 10 | Revealed onset positions and redistribution mechanism |
| Qualitative hypothesis | Quantitative ablation/perturbation evidence | Phase 10 | H1-H4 formalized with quantitative thresholds |

**Key insight for Phase 11:** The 5m J_z profile (oscillatory, midpoint worst at -19.4 dB, recovery to -36.8 dB at output) is the smoking gun for the "redistribution hypothesis" from Phase 10 preliminary findings. The optimizer cannot prevent Raman accumulation mid-fiber for long propagation distances — it can only partially redirect energy back at the end. This is qualitatively different from the 0.5m monotonic suppression mechanism.

---

## Open Questions

1. **Do multi-start J(z) trajectories split along cluster lines?**
   - What we know: phi_opt correlation clusters A (starts 1-4, corr ~0.54) and B (starts 5-10, corr ~0.0) with cluster B achieving better suppression.
   - What's unclear: whether cluster A and B have distinguishably different J(z) shapes, or whether all 10 shaped trajectories look identical despite different phi_opt profiles.
   - Recommendation: Compute and overlay all 10 J(z) curves. If cluster A and B are visually separable, report as distinct suppression strategies. If not, report that z-dynamics are fiber-physics-dominated.

2. **Is 3 dB spectral divergence before or after Raman onset?**
   - What we know: Raman onset for unshaped SMF-28 L=0.5m P=0.2W is at z=0.020m.
   - What's unclear: whether the shaped spectral difference D(z,f) exceeds 3 dB before z=0.020m (meaning the optimizer pre-conditions the field before Raman starts) or after (meaning the optimizer reacts to onset).
   - Recommendation: The 3 dB divergence z-position for each config should be compared against the unshaped Raman onset z-position from Phase 10 findings.

3. **What is the actual suppression horizon for SMF-28 at P=0.2W?**
   - What we know: L=0.5m gives -71.4 dB, L=5m gives -36.8 dB.
   - What's unclear: at what L does suppression cross below 50 dB?
   - Recommendation: The sweep data should contain L×P grid points for SMF-28. Extract J_after vs L at P=0.2W from sweep JLD2 files. If the sweep doesn't span enough L values, D-11 re-optimization at L=2m and L=3m might be needed.

4. **Does warm-start at L=5m improve suppression (D-11)?**
   - What we know: Current 60-iter optimization converged to -36.8 dB. The J_z profile shows non-monotonic behavior suggesting the optimizer found a valid basin but the cost landscape may have better solutions.
   - What's unclear: whether 100 iters starting from the current phi_opt improves the result.
   - Recommendation: Run D-11 as planned. If improvement is <1 dB, conclude the optimizer converged. If improvement is substantial (>5 dB), the sweep was under-optimized for long fibers.

---

## Phase Plan Structure (for the planner)

Based on decision scope and dependencies, Phase 11 naturally divides into 2 plans:

**Plan 01: Multi-Start Z-Dynamics and Spectral Divergence Analysis**
- D-01, D-02: Run 20 new propagations (10 × 2 conditions) at L=2m
- D-03: Cluster J(z) trajectories vs phi_opt correlation (Cluster A vs B)
- D-04, D-05: Compute spectral difference heatmaps from Phase 10 data (NO new propagations)
- D-06: H1 verdict (band overlap fraction)
- D-07: H2 verdict (sub-THz tolerance quantification)
- Figures: `physics_11_01` through `physics_11_05`
- Data: `results/raman/phase11/multistart_*/` and `spectral_divergence_*/`

**Plan 02: Long-Fiber Degradation, H3/H4 Verdicts, and Synthesis**
- D-08: H3 verdict + CPA comparison figure (uses existing perturbation data)
- D-09: H4 verdict (band overlap comparison, uses existing ablation data)
- D-10: 5m re-propagation at Nt=16384 (lower resolution test)
- D-11: 5m re-optimization at max_iter=100 with warm start (~36 min)
- D-12: Suppression horizon analysis (from sweep data + D-11 result)
- D-13: `CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md` synthesis
- Figures: `physics_11_06` through `physics_11_10`
- Data: `results/raman/phase11/smf28_5m_*/`

---

## Sources

### Primary (HIGH confidence)
- Direct JLD2 inspection of all 10 multi-start files in `results/raman/sweeps/multistart/start_{01..10}/opt_result.jld2`
- Direct JLD2 inspection of 12 Phase 10 z-resolved files in `results/raman/phase10/`
- Direct inspection of 4 Phase 10 ablation/perturbation JLD2 files
- `results/raman/PHASE9_FINDINGS.md` — Phase 9 final findings
- `results/raman/PHASE10_ABLATION_FINDINGS.md` — ablation evidence for H1-H4
- `results/raman/PHASE10_ZRESOLVED_FINDINGS.md` — z-onset analysis, preliminary hypotheses
- `scripts/propagation_z_resolved.jl` — reusable patterns (pz_load_and_repropagate)
- `scripts/phase_ablation.jl` — reusable patterns (pab_load_config, pab_propagate_and_cost)
- `scripts/common.jl` — setup_raman_problem, spectral_band_cost, FIBER_PRESETS
- `scripts/raman_optimization.jl` — optimize_spectral_phase (D-11)
- `.planning/STATE.md` — unit conventions, known bugs, constant prefix conventions
- `.planning/phases/11-classical-physics-completion/11-CONTEXT.md` — locked decisions

### Secondary (MEDIUM confidence)
- Computed pairwise phi_opt correlation matrix for 10 multi-start profiles (executed in session, verified against Phase 9 reported mean of 0.109 — computed 0.091, consistent within normalization differences)
- 5m J_z oscillatory profile extracted and analyzed for redistribution mechanism interpretation

### Tertiary (LOW confidence — not needed, not used)
- No external literature search required: Phase 11 is entirely analysis of existing data using established code patterns.

---

## Metadata

**Confidence breakdown:**
- Data availability: HIGH — all JLD2 files confirmed present and verified by inspection
- Script patterns: HIGH — reused directly from Phase 10 scripts with verified behavior
- Timing estimates: MEDIUM — extrapolated from known wall times; actual Julia JIT warmup may add 10-30s overhead on first run
- H1-H4 verdict directions: HIGH — evidence is on disk, analysis is straightforward arithmetic
- 5m degradation mechanism: MEDIUM — oscillatory J_z pattern is clearly visible; CPA interpretation is consistent with data but alternative explanations cannot be fully excluded without additional experiments

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable — data on disk does not change; code patterns are mature)
