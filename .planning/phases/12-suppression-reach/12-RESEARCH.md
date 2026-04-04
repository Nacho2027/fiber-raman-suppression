# Phase 12: Suppression Reach & Long-Fiber Behavior - Research

**Researched:** 2026-04-04
**Domain:** Julia fiber propagation — long-fiber z-resolved runs, phi_opt grid mismatch, segmented optimization
**Confidence:** HIGH (all findings verified against actual codebase and computed numerically)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Propagate existing phi_opt from L=0.5m and L=2m through L=10m and L=30m. Use 100 z-saves.
- D-02: Test SMF-28 (P=0.2W) and HNLF (P=0.01W).
- D-03: Always compare shaped vs flat phase.
- D-04: Use multi-start phi_opt profiles (best-performing start).
- D-05: Define L_XdB as length at which J(z) first crosses X dB. Map L_50dB and L_30dB vs power.
- D-06: Sweep 4 power levels per fiber. SMF-28: 0.05, 0.1, 0.2, 0.5W. HNLF: 0.005, 0.01, 0.02, 0.05W.
- D-07: Re-optimize at each (L_target, P) for sweep, propagate through 2×L_target.
- D-08: Report scaling — does L_50dB go as 1/P, 1/P², or other?
- D-09: Segmented optimization: optimize for L=2m, take output field, re-optimize, repeat. 3-4 segments.
- D-10: 3-4 segments (total 6-8m). Demonstrate concept.
- D-11: Compare segmented vs single-shot vs flat.
- D-12: Figures: `physics_12_XX_` prefix, save to `results/images/`.
- D-13: Data: `results/raman/phase12/`.
- D-14: Update `CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md` with finite-reach section.
- D-15: Script prefix `PR_` or `P12_`.

### Claude's Discretion
- Whether to test intermediate lengths (5m, 15m) beyond 10m and 30m.
- Figure layout for horizon mapping plots.
- Whether segmented optimization uses the same Nt or adapts per segment.
- How to handle time window expansion for 30m propagation.

### Deferred Ideas (OUT OF SCOPE)
- Multimode (M>1) extension.
- Quantum noise on top of classical optimization.
- Experimental pulse shaper design.
- Adaptive/feedback optimization during propagation.
</user_constraints>

---

## Summary

Phase 12 characterizes the finite suppression reach of spectral phase shaping. Four implementation challenges were investigated by directly inspecting the codebase and running numerical estimates.

**Critical finding 1 (time window):** The `recommended_time_window` formula uses `φ_NL = γ P L` which is only valid for `L << L_NL`. At L=30m SMF-28 (P=0.2W), `L_NL = 0.077m`, making this formula off by 400×. Auto-sizing produces Nt=524288 and tw=4276ps — physically unjustified and will allocate 1.6 GB for z-saves. The planner MUST cap Nt explicitly.

**Critical finding 2 (phi_opt interpolation):** Stored phi_opt (Nt=8192) cannot be directly applied to a new-Nt grid. The correct strategy is to interpolate phi_opt from its physical frequency axis to the new grid's physical frequency axis using `Interpolations.jl` (already a direct dependency). Outside the pulse bandwidth (~±15 THz), set phi to zero.

**Critical finding 3 (segmented optimization):** Fully feasible using existing infrastructure. The key insight: use a single fixed grid (sized for the full segment length, not each sub-segment) and call `optimize_spectral_phase()` sequentially. The output field from segment N serves directly as `uω0_base` for segment N+1 — no interpolation needed between segments.

**Critical finding 4 (memory at large Nt):** 100 z-saves at Nt=65536 (the recommended cap for L=30m SMF-28) costs 200 MB for `uω_z + ut_z`. This is manageable. The pathological case (Nt=524288) would cost 1.6 GB — avoid it.

**Primary recommendation:** Cap Nt at 65536 for all L=30m runs by passing explicit `Nt=65536, time_window=500` to `setup_raman_problem`. Do not let auto-sizing run at L=30m. Validate with boundary condition check after the first propagation.

---

## Q1: Time Window and Nt at L=30m

### What auto-sizing produces (verified by running the formula)

| Config | tw (auto) | Nt (auto) | Memory (uω_z+ut_z, 100 saves) | Valid? |
|--------|-----------|-----------|-------------------------------|--------|
| SMF-28 L=10m, P=0.2W | 500 ps | 65536 | 200 MB | Marginal |
| SMF-28 L=30m, P=0.2W | 4276 ps | 524288 | 1600 MB | NO — formula breaks down |
| HNLF L=30m, P=0.01W | 463 ps | 65536 | 200 MB | Reasonable |

### Why the formula fails at L=30m SMF-28

The SPM term in `recommended_time_window` is:
```
φ_NL = γ × P_peak × L
δω_SPM = 0.86 × φ_NL / T0
Δt_SPM = |β₂| × L × δω_SPM
```

This is linear in L and valid only for `L << L_NL`. For SMF-28 at P=0.2W:
- `P_peak ≈ 11,800 W`
- `L_NL = 1/(γ P_peak) = 0.077 m`
- `L_D = T0²/|β₂| = 0.507 m`
- `N = 2.57`

At L=30m the pulse has undergone soliton fission at z ≈ L_D = 0.5m, shed radiation, and experienced Raman self-frequency shift. The temporal extent is determined by soliton dynamics, not the naive SPM formula. The auto-sized window of 4276ps is physically unjustified.

### Recommended Nt caps (VERIFIED)

| Config | Explicit Nt | Explicit tw | Rationale |
|--------|-------------|-------------|-----------|
| SMF-28 L≤2m | auto (8192) | auto (40ps) | Already stored in JLD2 — reproduce exactly |
| SMF-28 L=5–10m | 65536 | 500 ps | L=10m auto-sizing gives same; verify with bc_check |
| SMF-28 L=30m | 65536 | 500 ps | Cap: soliton fission at z=L_D; use L=10m window |
| HNLF L≤10m | auto | auto | Low P_peak, L_NL=0.17m; formula not as extreme |
| HNLF L=30m | 65536 | 463 ps | auto-sizing reasonable; coincides with cap |

**Implementation pattern (for the script):**
```julia
# For L=30m SMF-28: override auto-sizing explicitly
uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
    L_fiber=30.0, P_cont=P_cont, β_order=3, fiber_preset=:SMF28,
    Nt=65536, time_window=500.0   # explicit — do NOT omit
)
```

**Validation step (required after first L=30m propagation):**
```julia
ok, frac = check_boundary_conditions(sol["uω_z"][end, :, :], sim)
# If frac > 1e-4: increase time_window and re-run before saving JLD2
```

---

## Q2: Applying phi_opt to a Different Nt Grid

### The problem

Stored phi_opt files (from `results/raman/sweeps/smf28/L0.5m_P0.2W/opt_result.jld2`):
- `Nt=8192`, `time_window=5.0ps`, `Δf=200 GHz/bin`, freq range ±819 THz
- phi_opt is a `Matrix{Float64}` of shape `(8192, 1)` in FFT order

Target grid for L=30m:
- `Nt=65536`, `time_window=500ps`, `Δf=2 GHz/bin`, freq range ±65 THz

The two grids have incompatible frequency axes. You cannot just resize or zero-pad the phi array — the bins represent different physical frequencies.

### Correct interpolation strategy (VERIFIED: Interpolations.jl v0.16.2 available)

```julia
using Interpolations
using FFTW

function interpolate_phi_to_new_grid(phi_stored, Nt_old, tw_old_ps, Nt_new, tw_new_ps)
    # Build physical frequency axes (Hz) in FFT order
    dt_old = tw_old_ps * 1e-12 / Nt_old
    dt_new = tw_new_ps * 1e-12 / Nt_new
    freqs_old = fftfreq(Nt_old, 1.0 / dt_old)   # Hz, FFT order
    freqs_new = fftfreq(Nt_new, 1.0 / dt_new)   # Hz, FFT order

    # phi_stored is meaningful only within pulse bandwidth (~±15 THz from carrier)
    # Outside that range, phi is optimizer noise — set to zero on new grid.
    # Use linear interpolation (Interpolations.jl) within the overlap region.
    phi_1d = vec(phi_stored)

    # Sort by frequency for interpolation (Interpolations requires monotone axis)
    sort_idx = sortperm(freqs_old)
    freqs_sorted = freqs_old[sort_idx]
    phi_sorted   = phi_1d[sort_idx]

    itp = linear_interpolation(freqs_sorted, phi_sorted; extrapolation_bc=0.0)

    phi_new = Matrix{Float64}(undef, Nt_new, 1)
    for i in 1:Nt_new
        f = freqs_new[i]
        if freqs_sorted[1] <= f <= freqs_sorted[end]
            phi_new[i, 1] = itp(f)
        else
            phi_new[i, 1] = 0.0   # outside old grid range → zero
        end
    end
    return phi_new
end
```

**Key detail:** `extrapolation_bc=0.0` sets phi to zero outside the stored frequency range. This is correct because phi_opt has no information about those frequencies (they lie outside the pulse spectrum).

**Simpler alternative (avoids Interpolations.jl):** Since the pulse is analytically defined (`sech²`), reconstruct `uω0_shaped` directly:

```julia
# On the stored grid, apply phi_opt and get shaped time-domain pulse
uω0_stored = data["uomega0"]                         # shape (8192, 1)
phi_opt    = data["phi_opt"]                          # shape (8192, 1)
ut_shaped_stored = ifft(uω0_stored .* exp.(1im .* phi_opt), 1)

# Rebuild on new grid from scratch using setup_raman_problem, then apply
# interpolated phi. The pulse shape is the same; only grid differs.
```

The interpolation approach is cleaner for the segmented optimization case too.

### What NOT to do

- Do not simply resize or truncate the phi array by index.
- Do not assume the same `uω0` can be reused — it was created with the stored `Nt` and `time_window`.
- Do not zero-pad phi in frequency domain — zero-padding changes spectral resolution, not the window.

---

## Q3: Segmented Optimization Feasibility

### Architecture

D-09 calls for: optimize phi for L=2m → propagate to z=2m → take output field `uωf` → re-optimize phi at that point → propagate another 2m → repeat (3-4 segments).

**This is fully feasible with zero new infrastructure.** The `optimize_spectral_phase()` function takes `uω0_base` as its first argument — just pass the output field of the previous segment.

### Implementation pattern

```julia
# One-time setup: size for the segment length, not the full chain
# Use a window large enough for one 2m segment
uω0, fiber_base, sim, band_mask, Δf, _ = setup_raman_problem(
    L_fiber=2.0, P_cont=0.2, β_order=3, fiber_preset=:SMF28
)
# → Nt=8192, tw=40ps (from stored JLD2 metadata)

# Accumulators
phi_each_segment = Vector{Matrix{Float64}}()
J_z_all = Vector{Float64}()
current_field = uω0   # start with fresh sech² pulse

for seg in 1:4
    fiber_seg = deepcopy(fiber_base)

    # Optimize spectral phase for this segment
    result = optimize_spectral_phase(current_field, fiber_seg, sim, band_mask;
        log_cost=true, max_iter=50)
    phi_seg = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
    push!(phi_each_segment, phi_seg)

    # Propagate with z-saves to get J(z) profile
    fiber_zsave = deepcopy(fiber_base)
    fiber_zsave["zsave"] = collect(LinRange(0, 2.0, 25))
    uω0_shaped = current_field .* exp.(1im .* phi_seg)
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_zsave, sim)

    J_z_seg = [spectral_band_cost(sol["uω_z"][i,:,:], band_mask)[1] for i in 1:25]
    append!(J_z_all, J_z_seg)

    # Output field becomes input for next segment
    # Extract lab-frame field at z=L from ODE solution
    L = fiber_base["L"]
    Dω = fiber_base["Dω"]
    current_field = cis.(Dω .* L) .* sol["ode_sol"](L)
end
```

**Grid note:** All 4 segments use the SAME `sim` and `fiber_base`. No grid change between segments. No interpolation needed.

**Physical note:** The output field after segment 1 is not a fresh sech² pulse — it is dispersed and partially Raman-shifted. The optimizer for segment 2 works on this degraded field. This is exactly the point: does re-shaping the degraded field recover suppression? If yes, that demonstrates segmented reach extension.

### Memory per segment
- Nt=8192, M=1, 25 z-saves per segment: `2 × 25 × 8192 × 16 bytes = 6.4 MB` — negligible
- Each L-BFGS run: ~50 forward+adjoint solves ≈ 15–30s wall time (from L2m JLD2: 29s for 18 iter)
- Total wall time: 4 segments × ~30s = ~2 min

---

## Q4: Memory Implications of 100 Z-Saves

### Array sizes (VERIFIED numerically)

The solver allocates `uω_z` and `ut_z` as `ComplexF64` arrays:
- Shape: `(Nz, Nt, M)` = `(100, Nt, 1)` per call
- `ComplexF64` = 16 bytes

| Config | Nt | uω_z size | ut_z size | Total |
|--------|----|-----------|-----------|-------|
| SMF-28 L=2m | 8192 | 12.5 MB | 12.5 MB | 25 MB |
| SMF-28 L=10m (Nt=65536) | 65536 | 100 MB | 100 MB | 200 MB |
| SMF-28 L=30m (capped Nt=65536) | 65536 | 100 MB | 100 MB | 200 MB |
| SMF-28 L=30m (naive Nt=524288) | 524288 | 800 MB | 800 MB | 1600 MB |
| HNLF L=30m (Nt=65536) | 65536 | 100 MB | 100 MB | 200 MB |

**200 MB per propagation call is safe.** The JLD2 save releases the array after writing.

### Saving pattern from Phase 10 (`pz_save_to_jld2`)

The existing save function writes and releases immediately — do not hold both shaped and unshaped in memory simultaneously. Save each right after computation:

```julia
fiber_shaped["zsave"] = collect(LinRange(0, L_target, 100))
sol_shaped = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped, sim)
save_to_jld2(sol_shaped, ...)   # write immediately
sol_shaped = nothing            # release before unshaped run
GC.gc()

sol_unshaped = MultiModeNoise.solve_disp_mmf(uω0, fiber_unshaped, sim)
save_to_jld2(sol_unshaped, ...)
sol_unshaped = nothing
```

### ODE solution memory (dense vs saveat)

When `fiber["zsave"]` is set, the solver uses `saveat=fiber["zsave"]` (line 186 of `simulate_disp_mmf.jl`). This stores only the 100 requested z-slices, not the full dense solution. The ODE integrator itself holds O(10) internal stages in memory — not 100× the state. This is the efficient path.

---

## Available Data Sources (VERIFIED)

| Path | Nt | tw (ps) | L (m) | P (W) | J_after (dB) |
|------|----|---------|-------|-------|--------------|
| `sweeps/smf28/L0.5m_P0.2W/opt_result.jld2` | 8192 | 5.0 | 0.5 | 0.2 | -67.6 |
| `sweeps/smf28/L2m_P0.2W/opt_result.jld2` | 8192 | 40.0 | 2.0 | 0.2 | -59.4 |
| `sweeps/multistart/start_01/` through `start_10/` | 8192 | 40.0 | 2.0 | 0.2 | -59.4 |
| `sweeps/smf28/L0.5m_P0.05W/`, L0.5m_P0.1W/ | 8192 | 5.0 | 0.5 | 0.05/0.1 | varies |
| `sweeps/hnlf/L1m_P0.01W/`, L1m_P0.005W/ | varies | varies | 1.0 | 0.005/0.01 | varies |

**Note:** `betas` field in all JLD2 files is empty (`Vector{Float64}(0,)`). Must recover betas from fiber preset using `PZ_FIBER_BETAS` pattern from Phase 10. [VERIFIED: confirmed in JLD2 inspection]

**Note:** `uomega0` (the stored initial field) is in JLD2. This can be used to reconstruct the shaped field without calling `setup_raman_problem` — but the grid it was computed on is Nt=8192 at the stored `time_window`. When switching to a larger grid, use `setup_raman_problem` fresh with the same physical params.

---

## Architecture Patterns

### Long-fiber re-propagation pattern (new, for Phase 12)

Extends `pz_load_and_repropagate` from Phase 10. Key difference: decouple the stored phi grid from the propagation grid.

```julia
function pr_repropagate_at_length(
    fiber_dir, config_name, preset, L_target;
    Nt_override=nothing, tw_override=nothing, n_zsave=100
)
    jld2_path = joinpath("results", "raman", "sweeps", fiber_dir, config_name, "opt_result.jld2")
    data = JLD2.load(jld2_path)
    phi_stored = vec(data["phi_opt"])
    Nt_stored  = Int(data["Nt"])
    tw_stored  = Float64(data["time_window_ps"])
    P_cont     = Float64(data["P_cont_W"])

    # Build target grid (explicitly override for L=30m to avoid formula breakdown)
    Nt_target = isnothing(Nt_override) ? Nt_stored : Nt_override
    tw_target = isnothing(tw_override) ? tw_stored  : tw_override

    uω0, fiber, sim, band_mask, Δf, _ = setup_raman_problem(
        L_fiber=L_target, P_cont=P_cont, Nt=Nt_target, time_window=tw_target,
        β_order=3, fiber_preset=preset
    )

    # Interpolate phi to new frequency grid
    phi_new = interpolate_phi_to_new_grid(phi_stored, Nt_stored, tw_stored, Nt_target, tw_target)
    uω0_shaped = uω0 .* exp.(1im .* phi_new)

    # Propagate with z-saves
    fiber_shaped = deepcopy(fiber); fiber_shaped["zsave"] = LinRange(0, L_target, n_zsave) |> collect
    fiber_unshaped = deepcopy(fiber); fiber_unshaped["zsave"] = fiber_shaped["zsave"]

    sol_shaped   = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped, sim)
    sol_unshaped = MultiModeNoise.solve_disp_mmf(uω0, fiber_unshaped, sim)

    J_z_shaped   = [spectral_band_cost(sol_shaped["uω_z"][i,:,:],   band_mask)[1] for i in 1:n_zsave]
    J_z_unshaped = [spectral_band_cost(sol_unshaped["uω_z"][i,:,:], band_mask)[1] for i in 1:n_zsave]

    return (; J_z_shaped, J_z_unshaped, zsave=fiber_shaped["zsave"], sim, band_mask, Nt=Nt_target)
end
```

### Anti-patterns to avoid (from Phase 10 docstring, extended for Phase 12)

- **Never let auto-sizing run at L=30m SMF-28** — always pass explicit `Nt` and `time_window` to override.
- **Never copy phi_opt by index** when grids differ — always interpolate in physical frequency coordinates.
- **Never hold shaped and unshaped z-save arrays simultaneously** — save and release each before computing the other.
- **Never call `optimize_spectral_phase` with `fiber["zsave"] ≠ nothing`** — the function sets `fiber["zsave"] = nothing` itself (line 181 of `raman_optimization.jl`), but the deepcopy at segment boundaries must precede this.
- **Always use `deepcopy(fiber)` before setting zsave** — established pattern from Phase 10.
- **Always save Nt and time_window to JLD2** so future phases can reconstruct the exact grid.

---

## Common Pitfalls

### Pitfall 1: Auto-sizing at L=30m allocates 1.6 GB
**What goes wrong:** Calling `setup_raman_problem(L_fiber=30.0, P_cont=0.2, fiber_preset=:SMF28)` without Nt/tw overrides triggers auto-sizing. The SPM formula gives φ_NL=2084ps, Nt=524288, and `uω_z + ut_z` at 100 z-saves = 1.6 GB.
**Why it happens:** The `φ_NL = γ P L` formula is O(L) but physics saturates at L ~ L_NL = 0.077m.
**How to avoid:** Always pass `Nt=65536, time_window=500` for SMF-28 at L≥10m.
**Warning signs:** Log message "Auto-sizing: time_window 10→4276 ps, Nt 8192→524288".

### Pitfall 2: Applying stored phi by index to a new grid
**What goes wrong:** `uω0_new .* exp.(1im .* phi_stored)` silently works (if Nt matches) or throws `DimensionMismatch`. Even if Nt happens to match by coincidence, the frequency bins represent different physical frequencies.
**Why it happens:** phi_opt index i corresponds to frequency `i/(Nt_stored * dt_stored)`, not `i/(Nt_new * dt_new)`.
**How to avoid:** Always interpolate in physical frequency space using the pattern in Q2.
**Warning signs:** J_after from re-propagation is not much better than J_before (phi applied to wrong frequencies).

### Pitfall 3: Segmented optimization time window too small for evolved field
**What goes wrong:** After segment 1, the field is dispersed and chirped. Its effective bandwidth may exceed the original time window, causing the attenuator to absorb real signal.
**Why it happens:** The time window was sized for the initial sech² pulse, not for the evolved field.
**How to avoid:** Set `time_window` for 2×L_segment, not 1×. Check `check_boundary_conditions` on the output field of each segment before using it as input to the next.
**Warning signs:** `bc_output_frac > 0.001` on segment output.

### Pitfall 4: 100 z-saves increases ODE memory (it does not)
**What might be assumed:** 100 z-saves stores 100 ODE solutions — memory scales as 100×.
**Reality:** `saveat=zsave` tells DifferentialEquations to save only at those specific points; the integrator does NOT store the full dense solution. Memory is `100 × Nt × M × 16 bytes`, not the ODE internal state multiplied by 100. [VERIFIED: simulator code lines 186-196]

---

## Suppression Horizon Sweep Design

For D-05 through D-08, the sweep requires re-optimizing at each (L_target, P) point. Given that:
- Phase 7/8 sweep already covers SMF-28: L=0.5, 1, 2, 5m × P=0.05, 0.1, 0.2W
- Phase 7/8 sweep already covers HNLF: L=0.5, 1, 2, 5m × P=0.005, 0.01, 0.03W

The Phase 12 sweep needs to add: L=10m and L=30m points for both fibers, and the HNLF P=0.05W column. Re-optimization at L=10m and L=30m will use `optimize_spectral_phase` from `raman_optimization.jl` directly — the same function used in Phase 7/8, no changes needed.

For re-optimization at L=10m SMF-28: use Nt=65536, tw=500ps. Wall time estimate: 10m propagation is ~4× slower per iteration than 2m (ODE step count scales roughly as L), so ~200s per optimization run. With 4 powers × 2 fibers × 2 lengths = 16 new optimizations: ~1 hour total.

---

## Environment Availability

Step 2.6: No new external dependencies. All required packages already in `Project.toml`:
- `Interpolations v0.16.2` — available and direct dep [VERIFIED]
- `JLD2 v0.6.3` — available [VERIFIED]
- `FFTW v1.10.0` — available [VERIFIED]
- `Optim v1.13.3` — available (from existing scripts)

---

## Sources

### Primary (HIGH confidence — verified in this session)
- `/scripts/common.jl` lines 191-241: `recommended_time_window` and `nt_for_window` — formula code read directly
- `/scripts/propagation_z_resolved.jl` lines 119-195: `pz_load_and_repropagate` pattern read directly
- `/scripts/raman_optimization.jl` lines 164-218: `optimize_spectral_phase` interface read directly
- `/src/simulation/simulate_disp_mmf.jl` lines 176-198: `solve_disp_mmf` zsave mechanism read directly
- Numerical calculations: Julia computed time windows and memory for all L values in this session
- JLD2 inspection: Confirmed `Nt=8192`, `betas=[]`, `phi_opt` shape, `uomega0` presence [VERIFIED]

### Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Wall time ~30s/iter at L=2m, scales ~4× at L=10m | Sweep design | Could affect scheduling; actual time depends on Tsit5 adaptive step |
| A2 | Tsit5 step count scales linearly with L for these nonlinear fibers | Sweep design | If nonlinear dynamics create stiff regions, cost could be higher |

**All other claims verified directly from source code or numerical computation.**

## Metadata

**Confidence breakdown:**
- Time window requirements: HIGH — computed directly from formula code
- phi_opt interpolation strategy: HIGH — verified against actual grid metadata and Interpolations.jl availability
- Segmented optimization: HIGH — traced through existing function signatures
- Memory estimates: HIGH — computed from array shape formulas verified against simulator code

**Research date:** 2026-04-04
**Valid until:** Stable — this research is based on static code; valid until `simulate_disp_mmf.jl` or `common.jl` changes.
