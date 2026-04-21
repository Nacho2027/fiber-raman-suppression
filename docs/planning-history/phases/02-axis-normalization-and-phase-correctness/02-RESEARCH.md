# Phase 2: Axis, Normalization, and Phase Correctness — Research

**Researched:** 2026-03-25
**Domain:** Julia/PyPlot visualization — axis sharing, normalization, spectral phase signal processing
**Confidence:** HIGH (all findings are from direct source-code inspection of visualization.jl + project-state documents; no external library research needed)

---

## Summary

Phase 2 fixes eight requirements spanning three distinct technical concerns: (1) Before/After panel synchronization (AXIS-01, BUG-04), (2) spectral x-axis auto-zoom (AXIS-02), and (3) phase diagnostic correctness (BUG-03, PHASE-01, PHASE-02, PHASE-03, PHASE-04). All work is confined to `scripts/visualization.jl`. There are no new dependencies and no architecture changes.

The critical insight driving the work is that each column in the Before/After comparison (before optimization, after optimization) currently computes its own local P_ref and its own time-axis limits independently. This means two columns can show visually identical panels even when the optimization achieved a large improvement — the dB shift between columns is absorbed by axis rescaling rather than displayed. The fix is straightforward: compute all shared quantities (P_ref, time limits, spectral limits) outside the per-column loop and pass them in.

For phase diagnostics, the current `plot_phase_diagnostic` function already has the correct structure (mask applied after deriving group delay and GDD from the `φ_unwrapped_full` grid). The issue flagged in STATE.md for BUG-03 is in `compute_group_delay` and `compute_gdd` — they call `_manual_unwrap` on the full unmasked phase array, then the derivative is computed before NaN-zeroing. The STATE.md flag specifically calls out needing to verify `_manual_unwrap` behavior on partially-zeroed arrays; the fix is to zero low-power bins of the phase input *before* passing to `_manual_unwrap`, not after.

**Primary recommendation:** All eight requirements are localized edits within `visualization.jl`. Each requirement maps to a specific function and a specific line range. No new helper functions are needed except a `_spectral_signal_xlim` utility (for AXIS-02) and a `_gdd_ylim` utility (for PHASE-03).

---

## Project Constraints (from CLAUDE.md)

- Tech stack: Julia + PyPlot only. No new visualization dependencies.
- Output format: PNG at 300 DPI.
- Backward compatibility: Keep function signatures where possible.
- Naming: helper functions use `_` prefix. In-place mutating functions use `!` suffix.
- Code style: 4-space indentation, `@.` macro for vectorized ops, Julia-style contracts with `@assert`.
- Comments explain WHY. Physics units always stated.
- No formatter configured — match surrounding style.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

No CONTEXT.md exists for this phase. All decisions are at Claude's discretion within the project constraints above.

### Locked Decisions (from project STATE.md accumulated context)
- Phase masking must occur BEFORE unwrapping at -40 dB threshold
- `_manual_unwrap` behavior on partially-zeroed arrays needs verification with a synthetic known-phase pulse before applying to real data

### Claude's Discretion
- Auto-zoom threshold for AXIS-02 (signal detection dB level)
- Percentile bounds for PHASE-03 GDD clipping
- Whether wrapped phase panel in PHASE-02 uses `set_phase_yticks!` (already defined at line 62-67) or inline tick setting
- Layout of the 5-panel phase diagnostic (PHASE-02 adds wrapped phase — 2×2 becomes 2×3 or 3×2)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BUG-03 | Apply spectral power mask BEFORE phase unwrapping | Masking order in `plot_phase_diagnostic` lines 267-284: unwrap happens on full array, then NaN-mask applied. Fix: zero/NaN the phase array at low-power bins before passing to `_manual_unwrap`. |
| BUG-04 | Use global normalization (shared P_ref) across Before/After columns | In `plot_optimization_result_v2` (lines 677-781) and `plot_amplitude_result_v2` (lines 817-890), P_ref is computed per-column inside the loop (lines 690, 830). Fix: compute global P_ref from ALL columns before the loop. |
| AXIS-01 | Before/After comparison columns share identical xlim and ylim | Time xlim computed per-column at lines 732-735 and 866-868. Spectral xlim is already hardcoded equal, but ylim is set per-column. Fix: compute union of time limits and shared ylim for both columns before the loop. |
| AXIS-02 | Spectral plots auto-zoom to signal-bearing region, not 800 nm of noise floor | All spectral functions currently use `λ0_nm ± fixed_offset` (lines 301, 378, 636, 698, 769, 847). Fix: compute signal extent from where power exceeds -40 dB relative to peak, then pad by 50-100 nm. |
| PHASE-01 | Group delay τ(ω) as primary phase display in opt.png row 3 | Already implemented in `plot_optimization_result_v2` lines 759-771 (group delay panel). This requirement appears satisfied — verify and mark done. |
| PHASE-02 | Phase diagnostic shows ALL views: wrapped φ, unwrapped φ, group delay, GDD, instantaneous frequency — all masked | Current `plot_phase_diagnostic` (lines 257-320) shows: unwrapped φ, group delay, GDD, instantaneous frequency. Missing: wrapped phase φ(ω) [0,2π] with π-ticks. Expand from 2×2 to 2×3 or 3×2 layout. |
| PHASE-03 | Clip GDD to sensible range (2nd-98th percentile of valid samples) | Current `plot_phase_diagnostic` does not clip GDD axis — spike values dominate. Fix: after computing `gdd_masked`, extract valid (non-NaN) samples, compute 2nd/98th percentile, call `axs.set_ylim`. |
| PHASE-04 | Wrapped phase panel uses π-labeled y-ticks (0, π/2, π, 3π/2, 2π) | `set_phase_yticks!` function already defined at lines 62-67. Apply it to the new wrapped phase panel added in PHASE-02. |
</phase_requirements>

---

## Standard Stack

No new dependencies. All work uses the existing stack.

### Core (unchanged)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PyPlot.jl | (project) | Matplotlib wrapper | Project constraint — locked |
| FFTW.jl | (project) | FFT for spectral ops | Already used throughout |
| Statistics | stdlib | `percentile` equivalent via `quantile` | Needed for PHASE-03 GDD clipping |

### Key PyPlot APIs Used in This Phase
| API | Purpose | Where Used |
|-----|---------|-----------|
| `ax.set_xlim(lo, hi)` | Freeze shared axis limits | AXIS-01, AXIS-02 |
| `ax.set_ylim(lo, hi)` | Freeze shared power/temporal limits | AXIS-01, BUG-04 |
| `quantile(v, p)` | Percentile for GDD clip | PHASE-03 — Julia `Statistics.quantile` |
| `set_phase_yticks!(ax)` | π-labeled ticks | PHASE-04 — already defined in codebase |

**Note on percentile:** Julia's `Statistics.quantile(v, 0.02)` returns the 2nd percentile. `Statistics` is already imported in `visualization.jl` (line 26: `using Statistics`).

---

## Architecture Patterns

### Pattern 1: Pre-loop Shared Quantity Computation (for BUG-04 + AXIS-01)

**What:** Extract all normalization and axis-limit computations that must be consistent across columns to before the `for (col, ...) in enumerate(...)` loop.

**Current broken pattern (per-column, inside loop):**
```julia
# Lines 677-781 — plot_optimization_result_v2
for (col, (φ, label)) in enumerate([(φ_before, "Before"), (φ_after, "After")])
    uω0_shaped = @. uω0_base * cis(φ)
    # ...run forward solve...
    spec_out = abs2.(fftshift(uωf[:, 1]))
    spec_in  = abs2.(fftshift(uω0_shaped[:, 1]))
    P_ref = max(maximum(spec_in), maximum(spec_out))  # ← local, per-column
    # ...
    t_lims_in  = _energy_window(P_in, ts_ps)
    t_lims_out = _energy_window(P_out, ts_ps)
    t_lims = (min(t_lims_in[1], t_lims_out[1]), max(t_lims_in[2], t_lims_out[2]))
    axs[2, col].set_xlim(t_lims...)  # ← different for each column
end
```

**Fixed pattern (pre-compute, then render in separate loop):**
```julia
# Step 1: simulate both columns, collect data
results = []
for (φ, label) in [(φ_before, "Before"), (φ_after, "After")]
    uω0_shaped = @. uω0_base * cis(φ)
    sol = MultiModeNoise.solve_disp_mmf(...)
    push!(results, (uω0_shaped=uω0_shaped, uωf=..., utf=..., ut_in=..., label=label))
end

# Step 2: compute shared quantities from ALL results
P_ref_global = maximum(max(maximum(abs2.(r.spec_in)), maximum(abs2.(r.spec_out)))
                       for r in results)
all_t_lims   = [_energy_window(abs2.(r.ut_in[:,1]), ts_ps) for r in results]
t_lo = minimum(t[1] for t in all_t_lims)
t_hi = maximum(t[2] for t in all_t_lims)
t_lims_shared = (t_lo, t_hi)

# Step 3: render using shared quantities
for (col, r) in enumerate(results)
    spec_in_dB  = 10 .* log10.(r.spec_in  ./ P_ref_global .+ 1e-30)
    spec_out_dB = 10 .* log10.(r.spec_out ./ P_ref_global .+ 1e-30)
    axs[2, col].set_xlim(t_lims_shared...)
end
```

**When to use:** Any multi-column comparison figure where panels should reflect absolute differences, not relative ones.

### Pattern 2: Mask-Before-Unwrap for Phase Signal Processing (for BUG-03)

**What:** Zero the phase array at low-power spectral bins before passing to `_manual_unwrap`. This prevents the unwrapper from propagating phase noise from the noise floor into the signal region.

**Current broken order:**
```julia
φ_shifted       = fftshift(φ[:, 1])
φ_unwrapped_full = _manual_unwrap(φ_shifted)  # ← unwrap first (noise propagates)
# ... compute derivatives ...
φ_masked = _apply_dB_mask(φ_unwrapped, spec_pos)  # ← then mask (too late)
```

**Fixed order:**
```julia
φ_shifted  = fftshift(φ[:, 1])
spec_power = abs2.(fftshift(uω0_base[:, 1]))
P_peak     = maximum(spec_power)
dB_mask    = 10 .* log10.(spec_power ./ P_peak .+ 1e-30) .> -40.0
# Zero the phase at low-power bins before unwrapping
φ_premask  = copy(φ_shifted)
φ_premask[.!dB_mask] .= 0.0
φ_unwrapped_full = _manual_unwrap(φ_premask)  # ← unwrap on masked phase
# Derivatives computed on φ_unwrapped_full — noise floor bins are zero
# Apply NaN mask for display only (not for derivative computation)
τ_display = _apply_dB_mask(_central_diff(φ_unwrapped_full, dω) .* 1e3, spec_power)
```

**Key insight:** Zeroing to 0.0 (not NaN) before `_manual_unwrap` is essential — the unwrapper iterates with `out[i] - out[i-1]` which would produce Inf/NaN if NaN were used.

**STATE.md flag:** "Verify `_manual_unwrap` behavior on partially zeroed arrays with synthetic test." The synthetic test should be: create a sech² pulse with known quadratic phase, zero the noise floor bins, unwrap, compute group delay, verify it matches the known β₂·L group delay to within 1%.

### Pattern 3: Signal-Content Auto-Zoom (for AXIS-02)

**What:** Compute xlim from where the spectrum first/last exceeds a power threshold, then add padding.

```julia
"""Compute wavelength xlim containing all spectral content above threshold_dB."""
function _spectral_signal_xlim(P_spec_shifted, λ_nm; threshold_dB=-40.0, padding_nm=80.0)
    P_peak = maximum(P_spec_shifted)
    above_threshold = 10 .* log10.(P_spec_shifted ./ P_peak .+ 1e-30) .> threshold_dB
    if !any(above_threshold)
        return (λ_nm[1], λ_nm[end])
    end
    idx = findall(above_threshold)
    λ_lo = λ_nm[minimum(idx)] - padding_nm
    λ_hi = λ_nm[maximum(idx)] + padding_nm
    return (λ_lo, λ_hi)
end
```

**When to use:** All standalone spectral plot calls. In comparison functions, compute from the union of all curves' signal extents.

### Pattern 4: GDD Percentile Clipping (for PHASE-03)

**What:** After computing GDD, clip the y-axis of the GDD panel to the 2nd–98th percentile of valid (non-NaN) samples.

```julia
gdd_valid = filter(isfinite, gdd_masked)
if length(gdd_valid) > 10
    lo = quantile(gdd_valid, 0.02)
    hi = quantile(gdd_valid, 0.98)
    margin = max(abs(hi - lo) * 0.05, 1.0)  # 5% margin, min 1 fs²
    axs[2, 1].set_ylim(lo - margin, hi + margin)
end
```

**Note:** `Statistics.quantile` is already available — `using Statistics` is on line 26. No import needed.

### Anti-Patterns to Avoid

- **Per-column normalization:** Computing P_ref inside the loop, then using `ax.set_ylim` based on that local value, hides the optimization improvement.
- **Hard-coded ±400/±700 nm offsets:** `λ0_nm - 400, λ0_nm + 700` will include 400-800 nm of empty noise floor for typical 1550 nm pulses. Use signal-content detection instead.
- **Unwrapping after masking:** Applying NaN mask before `_manual_unwrap` causes the unwrapper to propagate discontinuities across NaN boundaries.
- **Clipping GDD with `clamp`:** `clamp.(gdd, -max_val, max_val)` flattens the curve at the spike values, making it appear physical. Use `set_ylim` instead — matplotlib will show the valid region without distorting the signal.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Percentile of valid samples | Custom loop over sorted array | `Statistics.quantile(filter(isfinite, v), p)` | Already in stdlib, correct edge cases |
| Phase unwrapping | New algorithm | `_manual_unwrap` (already in codebase, lines 143-151) | Known behavior, tested in smoke test |
| Signal extent detection | Scan for nonzero bins | `_spectral_signal_xlim` pattern (new helper) | Simple findall pattern, 5 lines |

**Key insight:** Julia's `Statistics.quantile` handles the percentile clipping entirely. The remaining work is pure matplotlib axis configuration (`set_xlim`, `set_ylim`) and loop restructuring.

---

## Requirement-by-Requirement Analysis

### BUG-03: Mask Before Unwrap

**Current code location:** `plot_phase_diagnostic` lines 267-284 and `compute_group_delay`/`compute_gdd` (lines 215-231).

**Root cause:** `φ_unwrapped_full = _manual_unwrap(φ_shifted)` at line 269 runs on the full frequency grid including noise floor bins. The noise floor has essentially random phase, so `_manual_unwrap` adds 2π corrections based on noise transitions. These corrections then propagate into signal bins at the edges of the signal region, distorting the group delay and GDD.

**Fix scope:** `plot_phase_diagnostic` only. `compute_group_delay` and `compute_gdd` are general utilities that accept pre-masked input — they should not be modified. The masking responsibility belongs in the caller.

**STATE.md validation requirement:** Before applying to real data, add a synthetic test in `test_visualization_smoke.jl`:
1. Create Gaussian pulse with known quadratic phase (GDD = β₂·L).
2. Zero noise floor bins at -40 dB threshold.
3. Call `_manual_unwrap` on masked array.
4. Verify recovered GDD matches input β₂·L to within 1%.
This test must pass before the BUG-03 implementation is committed.

### BUG-04: Global P_ref for Before/After Spectra

**Current code locations:**
- `plot_optimization_result_v2` line 690: `P_ref = max(maximum(spec_in), maximum(spec_out))`
- `plot_amplitude_result_v2` line 830: `P_ref = max(maximum(spec_in), maximum(spec_out))`

Both are inside the column loop. The Before column normalizes to Before's peak; the After column normalizes to After's peak. If optimization drops the peak by 3 dB, both columns show 0 dB peak — the improvement is invisible.

**Fix:** Two-pass structure (simulate → collect → compute global P_ref → render). The global P_ref is the maximum across ALL spectra (both columns, both input and output).

**Impact on y-axis:** After the fix, the After column's output spectrum will sit lower than the Before column's output spectrum by the actual optimization improvement in dB. This is the correct visual representation.

### AXIS-01: Shared xlim/ylim for Before/After

**Current issues:**
- Temporal xlim: computed per-column from `_energy_window` (lines 732-735 in phase opt, 866-868 in amplitude opt). If the shaped pulse is more compressed, the After column shows a narrower time window, making compression appear as axis rescaling rather than pulse narrowing.
- Temporal ylim: Not explicitly set — matplotlib auto-scales per-column, potentially showing different vertical scales.
- Spectral xlim: Already equal (both use `λ0_nm - 300, λ0_nm + 500`) — no change needed.
- Spectral ylim: Set to `(-60, 3)` in both columns — already correct.

**Fix:** Compute the union of both columns' `_energy_window` results before the render loop. Apply the union to both columns.

**On temporal ylim:** The max power can differ significantly between Before and After (the optimizer may concentrate/spread power). Sharing ylim may require a `max_P` scan across both columns and then setting `axs[2, col].set_ylim(0, max_P * 1.05)`.

### AXIS-02: Spectral Auto-Zoom

**Current behavior:** All spectral plots use fixed ±400/±700 nm offsets from center. For 1550 nm center wavelength, this is 1150–2250 nm — an 1100 nm window where signal occupies perhaps 100–300 nm, leaving 800+ nm of noise floor.

**Fix locations:** Every `set_xlim` call on a wavelength-axis panel:
- `plot_phase_diagnostic` line 301
- `plot_spectral_evolution` line 378 (default path)
- `plot_spectrum_comparison` line 636 (default path)
- `plot_optimization_result_v2` line 698
- `plot_amplitude_result_v2` line 847
- `plot_optimization_result_v2` group delay xlim line 769

**Implementation approach:** Add `_spectral_signal_xlim(P, λ_nm; threshold_dB=-40.0, padding_nm=80.0)` helper. In comparison functions, call once on the union of all spectra, then apply to all spectral panels.

**Threshold choice:** -40 dB matches the existing heatmap floor (`dB_range=40.0`). Consistent threshold means the auto-zoom window matches what the heatmap shows.

### PHASE-01: Group Delay as Primary Phase Display in opt.png

**Current state:** `plot_optimization_result_v2` rows 3 already shows group delay τ(ω) at lines 759-771. The title is "Group delay τ(ω)" and the ylabel is "Group delay [fs]". **This requirement is already satisfied.**

**Action:** Mark PHASE-01 as complete in REQUIREMENTS.md. No code change needed.

### PHASE-02: All Phase Views in Diagnostic

**Current `plot_phase_diagnostic` (2×2 layout):**
- (1,1): Unwrapped phase φ(ω)
- (1,2): Group delay τ(ω)
- (2,1): GDD
- (2,2): Instantaneous frequency (time domain)

**PHASE-02 requires adding:** Wrapped phase φ(ω) [0,2π] with π-ticks

**Recommended layout change:** 2×2 → 3×2 or 2×3. Given the content:
- Option A: 3×2 layout — row 1: wrapped phase + unwrapped phase; row 2: group delay + GDD; row 3: instantaneous freq + (empty or reserved)
- Option B: 2×3 layout — row 1: wrapped phase + unwrapped phase + group delay; row 2: GDD + instantaneous freq + (empty)

Option A (3×2) is cleaner — spectral quantities in rows 1-2, time-domain in row 3. Use `figsize=(12, 12)` for 3×2.

**`set_phase_yticks!` availability:** Already defined at lines 62-67 of visualization.jl. Call it on the wrapped phase panel.

### PHASE-03: GDD Y-Axis Percentile Clipping

**Root cause of spike issue:** The GDD is computed as a second derivative (`_second_central_diff`) on the phase array. At the edges of the signal region, even after masking, the transition from signal-phase to zero-phase creates a large second derivative. These become GDD spikes at the signal band edges.

**Fix:** After computing `gdd_masked`, filter out NaN values, compute `quantile(valid, 0.02)` and `quantile(valid, 0.98)`, and call `set_ylim`.

**Physical sanity check:** For a typical 185 fs pulse through 1 m of SMF-28 (β₂ = -21.7 fs²/mm), the accumulated GDD is ~-21,700 fs². The 2nd-98th percentile of the shaped phase's GDD will typically be within ±50,000 fs². Any spike to ±10^6 fs² is clearly numerical artifact at signal edges and should be clipped.

### PHASE-04: π-Labeled Wrapped Phase Ticks

**`set_phase_yticks!` function (lines 62-67):**
```julia
function set_phase_yticks!(ax)
    ax.set_yticks([0, π/2, π, 3π/2, 2π])
    ax.set_yticklabels(["0", "π/2", "π", "3π/2", "2π"])
    ax.set_ylim(0, 2π)
    ax.set_ylabel("Phase [rad]")
end
```

**Action:** When the wrapped phase panel is added in PHASE-02, call `set_phase_yticks!(axs[1, 1])` immediately after creating the panel. `wrap_phase(φ)` (line 59) provides the data.

---

## Common Pitfalls

### Pitfall 1: _manual_unwrap on NaN-Containing Arrays
**What goes wrong:** If NaN is used for masking before `_manual_unwrap`, the difference `out[i] - out[i-1]` becomes NaN, and the `if abs(d) > π` check evaluates to `false` (NaN comparisons are always false). The unwrapper silently passes NaN through without fixing jumps.
**Why it happens:** NaN propagation in IEEE 754 arithmetic.
**How to avoid:** Zero low-power bins to 0.0 before `_manual_unwrap`. Apply NaN masking only after all derivative operations, for display only.
**Warning signs:** Group delay shows flat zero segments interspersed with spikes at signal edges.

### Pitfall 2: P_ref Local vs Global in Before/After Comparison
**What goes wrong:** Each column normalizes to its own peak, so the dB offset between columns reflects only relative shape, not absolute improvement. J improvements of 3-10 dB are invisible.
**Why it happens:** P_ref is computed inside the column loop.
**How to avoid:** Two-pass structure: simulate all columns first, then compute global P_ref, then render.
**Warning signs:** Both columns show output peak near 0 dB; annotated J values differ but spectra look similar.

### Pitfall 3: Fixed Spectral xlim Hiding Optimization Region
**What goes wrong:** The Raman band (1600-1700 nm for 1550 nm center) may be entirely outside the displayed range if the xlim is too narrow, or the signal occupies only 10% of the displayed range if xlim is too wide.
**Why it happens:** `λ0_nm - 300, λ0_nm + 500` is a heuristic that doesn't adapt to the actual signal content.
**How to avoid:** `_spectral_signal_xlim` based on -40 dB threshold relative to peak, with 80 nm padding.
**Warning signs:** Raman band annotation invisible on spectral plot; signal curve occupies narrow strip with wide noise floor on both sides.

### Pitfall 4: Shared Time xlim Hiding Pulse Compression
**What goes wrong:** `_energy_window` computed per-column gives a narrower window for the compressed After pulse. The before/after panels appear to show the same-width pulse because they use different axis scales.
**Why it happens:** `_energy_window` correctly finds the minimal window for each pulse independently.
**How to avoid:** Compute union of both columns' energy windows: `t_lo = min(before_lo, after_lo)`, `t_hi = max(before_hi, after_hi)`.
**Warning signs:** Both panels appear to show approximately 3× padding around their respective pulse widths.

### Pitfall 5: GDD Y-Axis Dominated by Edge Spikes
**What goes wrong:** The GDD panel appears as a flat line at zero (or near-zero) because spike values at ±10^6 fs² compress the physically meaningful ±50,000 fs² range into a thin band.
**Why it happens:** Second derivative amplifies noise at the signal/noise-floor boundary even after masking.
**How to avoid:** `set_ylim` from percentiles of valid samples. Do NOT use `clamp.` — that modifies the data and creates flat plateaus at ±max values which look like real GDD values.
**Warning signs:** GDD panel shows thin flat band at ~0 with no visible curvature; peak GDD displayed values at axis limits.

---

## Code Examples

### Example 1: Two-pass Before/After Normalization

```julia
# Source: Pattern derived from visualization.jl lines 677-781 (existing loop) + this research
# Fix for BUG-04 + AXIS-01 in plot_optimization_result_v2

# Pass 1: simulate and collect
struct ColResult
    uω0_shaped::Matrix{ComplexF64}
    uωf::Matrix{ComplexF64}
    utf::Matrix{ComplexF64}
    ut_in::Matrix{ComplexF64}
    label::String
end

col_results = ColResult[]
for (φ, label) in [(φ_before, "Before"), (φ_after, "After")]
    uω0_shaped = @. uω0_base * cis(φ)
    fiber_plot = deepcopy(fiber)
    fiber_plot["zsave"] = [0.0, fiber["L"]]
    sol = MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_plot, sim)
    push!(col_results, ColResult(
        uω0_shaped,
        sol["uω_z"][end, :, :],
        sol["ut_z"][end, :, :],
        fft(uω0_shaped, 1),
        label
    ))
end

# Global P_ref: maximum across ALL spectra (both columns, input and output)
P_ref_global = maximum(
    max(maximum(abs2.(fftshift(r.uω0_shaped[:, 1]))),
        maximum(abs2.(fftshift(r.uωf[:, 1]))))
    for r in col_results
)

# Shared time limits: union of all energy windows
all_t_lims = [
    let P_in  = abs2.(r.ut_in[:, 1]),
        P_out = abs2.(r.utf[:, 1])
        lo_in,  hi_in  = _energy_window(P_in,  ts_ps)
        lo_out, hi_out = _energy_window(P_out, ts_ps)
        (min(lo_in, lo_out), max(hi_in, hi_out))
    end
    for r in col_results
]
t_lo_shared = minimum(t[1] for t in all_t_lims)
t_hi_shared = maximum(t[2] for t in all_t_lims)
```

### Example 2: Mask-Before-Unwrap in plot_phase_diagnostic

```julia
# Source: Pattern from research into _manual_unwrap behavior
# Fix for BUG-03

φ_shifted  = fftshift(φ[:, 1])
spec_power = abs2.(fftshift(uω0_base[:, 1]))

# Compute signal mask at -40 dB threshold
P_peak  = maximum(spec_power)
dB_vals = 10 .* log10.(spec_power ./ P_peak .+ 1e-30)
signal_mask = dB_vals .> -40.0  # true where signal is present

# Zero phase at noise floor BEFORE unwrapping
φ_premask = copy(φ_shifted)
φ_premask[.!signal_mask] .= 0.0  # zero, not NaN — unwrapper requires finite values

# Unwrap the pre-masked phase
φ_unwrapped_full = _manual_unwrap(φ_premask)

# Compute derivatives on the unwrapped, pre-masked array
# (edge effects at signal boundaries are controlled by the pre-masking)
τ_pos   = (_central_diff(φ_unwrapped_full, dω) .* 1e3)[pos_mask][sort_idx]
gdd_pos = (_second_central_diff(φ_unwrapped_full, dω) .* 1e6)[pos_mask][sort_idx]

# Apply NaN mask for display only — after derivatives
τ_display   = _apply_dB_mask(τ_pos,   spec_pos)
gdd_display = _apply_dB_mask(gdd_pos, spec_pos)
```

### Example 3: GDD Percentile Y-Axis Clipping

```julia
# Source: Julia Statistics.quantile docs + physics reasoning
# Fix for PHASE-03

gdd_valid = filter(isfinite, gdd_display)
if length(gdd_valid) > 10
    gdd_lo = quantile(gdd_valid, 0.02)
    gdd_hi = quantile(gdd_valid, 0.98)
    # 5% headroom, minimum ±100 fs² to avoid degenerate zero range
    margin = max(abs(gdd_hi - gdd_lo) * 0.05, 100.0)
    axs_gdd.set_ylim(gdd_lo - margin, gdd_hi + margin)
    # Note: set_ylim constrains the VIEW, not the data — spikes remain in the
    # plotted line but outside the visible area. Do NOT use clamp.() which
    # would flatten spikes to axis-limit values and look like real GDD.
end
```

### Example 4: Signal-Content Spectral Auto-Zoom

```julia
# Source: Pattern from this research
# Fix for AXIS-02

"""Compute wavelength xlim containing all spectral content above threshold_dB."""
function _spectral_signal_xlim(P_spec_fftshifted, λ_nm_fftshifted;
                                threshold_dB=-40.0, padding_nm=80.0)
    # P_spec_fftshifted and λ_nm_fftshifted must be co-indexed
    # (both fftshifted, NOT wavelength-sorted)
    P_peak = maximum(P_spec_fftshifted)
    dB = 10 .* log10.(P_spec_fftshifted ./ P_peak .+ 1e-30)
    above = findall(dB .> threshold_dB)
    isempty(above) && return (λ_nm_fftshifted[1], λ_nm_fftshifted[end])
    λ_signal = λ_nm_fftshifted[above]
    # Filter out negative-frequency bins (negative λ)
    λ_pos = filter(>(0), λ_signal)
    isempty(λ_pos) && return (λ_nm_fftshifted[1], λ_nm_fftshifted[end])
    return (minimum(λ_pos) - padding_nm, maximum(λ_pos) + padding_nm)
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-column P_ref normalization | (Phase 2: global P_ref) | Phase 2 | Before/After dB offset now reflects true optimization improvement |
| Fixed ±400/±700 nm spectral window | (Phase 2: signal-content auto-zoom) | Phase 2 | Noise floor removed from spectral display |
| Per-column temporal xlim | (Phase 2: union of energy windows) | Phase 2 | Pulse compression visible as narrowing within shared window |
| Unwrap then mask | (Phase 2: mask then unwrap) | Phase 2 | Group delay and GDD no longer contaminated by noise floor phase |

---

## Open Questions

1. **PHASE-01 already satisfied?**
   - What we know: `plot_optimization_result_v2` row 3 shows group delay τ(ω) with correct title/labels (lines 759-771).
   - What's unclear: Whether the requirement was written before or after this was implemented. The requirements list status is "Pending".
   - Recommendation: Verify visually with one run, then mark PHASE-01 complete in REQUIREMENTS.md. No code change needed.

2. **`_manual_unwrap` behavior on zero-padded leading/trailing bins**
   - What we know: The unwrapper iterates forward; the difference between consecutive zero-valued bins is 0, which does not trigger a 2π correction. So the unwrapper handles leading/trailing zeros correctly — no corrections applied in zero-padded region.
   - What's unclear: Whether a transition from a zero bin to a signal bin (or vice versa) causes a spurious 2π jump.
   - Recommendation: The synthetic test in `test_visualization_smoke.jl` (from STATE.md flag) will resolve this definitively. The test should check group delay recovery near the signal/noise boundary.

3. **3×2 vs 2×3 layout for expanded phase diagnostic**
   - What we know: Adding wrapped phase to `plot_phase_diagnostic` requires a 5th panel (4 current + 1 new).
   - What's unclear: Whether leaving one cell empty (making 3×2 = 6 cells with 5 used) or rearranging to 5-panel irregular grid is better.
   - Recommendation: Use 3×2 with empty (2,3) cell. This is the simplest change to the existing function — just change `subplots(2, 2, ...)` to `subplots(3, 2, ...)` and add the wrapped phase panel.

---

## Environment Availability

Step 2.6: SKIPPED — this phase consists entirely of edits to `scripts/visualization.jl` (a Julia source file). No external tools, databases, CLIs, or services are required. Julia + PyPlot are already confirmed present from Phase 1 execution.

---

## Sources

### Primary (HIGH confidence)
- Direct inspection of `scripts/visualization.jl` (all line references above verified)
- Direct inspection of `.planning/STATE.md` (accumulated decisions, Phase 2 flags)
- Direct inspection of `.planning/REQUIREMENTS.md` (requirement descriptions, traceability)
- Direct inspection of `.planning/phases/01-stop-actively-misleading/01-VERIFICATION.md` (confirmed Phase 1 state)
- Julia `Statistics` stdlib documentation (quantile function)

### Secondary (MEDIUM confidence)
- Physics reasoning: GDD spike magnitudes from β₂·L calculation for SMF-28 parameters in `scripts/common.jl` (betas = [-2.17e-26 s²/m], L = 1 m → ~21,700 fs² accumulated GDD, spike-to-signal ratio confirms ~10^6 fs² spikes are numerical artifact)

### Tertiary (LOW confidence)
- None — all findings are from direct source inspection.

---

## Metadata

**Confidence breakdown:**
- Requirement analysis: HIGH — all requirements traced to exact line numbers in visualization.jl
- Fix patterns: HIGH — patterns derived from direct code inspection, not from external documentation
- Pitfalls: HIGH — traced to specific root causes in existing code
- PHASE-01 status: MEDIUM — code inspection says satisfied; visual verification not possible without a simulation run

**Research date:** 2026-03-25
**Valid until:** Stable (visualization.jl changes only happen in planned phases; no fast-moving dependencies)
