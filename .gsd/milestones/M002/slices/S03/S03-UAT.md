# S03: Cross Run Comparison And Pattern Analysis — UAT

**Milestone:** M002
**Written:** 2026-04-17T01:36:01.697Z

# S03: Cross Run Comparison And Pattern Analysis — UAT

**Milestone:** M002
**Written:** 2026-04-17

## UAT Type

- UAT mode: mixed (artifact-driven for code structure, live-runtime for figure output)
- Why this mode is sufficient: Code structure and function signatures can be verified statically. Figure correctness and physics plausibility require a live run on the burst VM producing the 4 PNGs.

## Preconditions

1. Burst VM (`fiber-raman-burst`) available and started via `burst-start`
2. Code pushed to origin so burst VM can `git pull`
3. Julia 1.12+ with `--project=.` and `-t auto` flags
4. Phase 5 serialization infrastructure operational (`run_optimization` writes JLD2 + manifest)
5. `results/raman/` directory exists

## Smoke Test

```bash
burst-ssh "cd fiber-raman-suppression && git pull && julia -t auto --project=. -e '
    include(\"scripts/common.jl\")
    include(\"scripts/visualization.jl\")
    println(\"Functions: \", [
        compute_soliton_number, decompose_phase_polynomial,
        plot_cross_run_summary_table, plot_convergence_overlay,
        plot_spectral_overlay
    ])
    println(\"Colors: \", COLORS_5_RUNS)
'"
```

**Expected:** All 5 function references print without MethodError. COLORS_5_RUNS prints 5 hex strings.

## Test Cases

### 1. compute_soliton_number correctness

```julia
N = compute_soliton_number(10.0e-3, 1000.0, 185.0, -0.5e-26)
```
**Expected:** N approximately 4.69 (HNLF at high peak power). Returns Float64, not NaN.

### 2. compute_soliton_number NaN safety

```julia
N = compute_soliton_number(1.0e-3, 100.0, 185.0, 0.0)
```
**Expected:** Returns NaN (division by zero beta2) or Inf, does not throw.

### 3. decompose_phase_polynomial returns NamedTuple

```julia
# After running a single optimization to get phi_opt, uomega0, sim_Dt, Nt:
result = decompose_phase_polynomial(phi_opt, uomega0, sim_Dt_seconds, Nt)
@assert haskey(result, :gdd_fs2)
@assert haskey(result, :tod_fs3)
@assert haskey(result, :residual_fraction)
@assert 0.0 <= result.residual_fraction <= 1.0
```
**Expected:** All assertions pass. GDD in range [-1e6, 1e6] fs^2, TOD in [-1e9, 1e9] fs^3.

### 4. Full pipeline execution

```bash
burst-ssh "cd fiber-raman-suppression && git pull && \
    tmux new -d -s run-comparison 'julia -t auto --project=. scripts/run_comparison.jl > run_comparison.log 2>&1'"
# Monitor:
burst-ssh "tail -f fiber-raman-suppression/run_comparison.log"
```
**Expected:** 
- 5 optimization runs complete without error
- manifest.json updated with `soliton_number_N` field for each entry
- 4 PNGs generated in `results/images/`:
  - `cross_run_summary_table.png`
  - `convergence_overlay_all_runs.png`
  - `spectral_overlay_SMF28.png`
  - `spectral_overlay_HNLF.png`
- Box-drawing summary log printed at end

### 5. Summary table PNG content

Open `results/images/cross_run_summary_table.png`.

**Expected:**
- 9 columns: Fiber, L(m), P(W), J_before(dB), J_after(dB), delta-dB, Iter., Time(s), N
- At least 5 rows (one per optimization config)
- J_after values negative (dB suppression)
- delta-dB values negative (improvement)
- Soliton N values in [0.5, 10] range
- Footnote about heterogeneous grid comparison

### 6. Convergence overlay PNG content

Open `results/images/convergence_overlay_all_runs.png`.

**Expected:**
- All 5 runs plotted on shared axes
- Y-axis: J (dB), X-axis: iteration number
- Each run has distinct Okabe-Ito color with legend label
- Curves decrease monotonically (L-BFGS convergence)
- All runs plateau by ~30-50 iterations

### 7. Spectral overlay PNGs

Open both `spectral_overlay_SMF28.png` and `spectral_overlay_HNLF.png`.

**Expected:**
- X-axis in wavelength (nm), Y-axis in dB
- Each run plotted with distinct color and label
- SMF-28 figure has 3 runs (configs 1, 2, 5), HNLF has 2 runs (configs 3, 4)
- Raman-shifted region visible as suppressed spectral content
- Spectra physically plausible (no NaN gaps, no >0 dB artifacts in noise floor)

### 8. Manifest soliton number annotation

```julia
using JSON3
manifest = JSON3.read(read("results/raman/manifest.json", String))
for entry in manifest
    @assert haskey(entry, :soliton_number_N) "Missing soliton_number_N in $(entry[:run_label])"
    N = entry[:soliton_number_N]
    @assert isfinite(N) && N > 0 "Invalid N=$N for $(entry[:run_label])"
end
```
**Expected:** All entries have finite positive soliton_number_N.

## Edge Cases

### Phase decomposition on flat (zero) phase

If an optimization run converges to phi_opt ≈ 0 everywhere, decompose_phase_polynomial should return gdd_fs2 ≈ 0, tod_fs3 ≈ 0, residual_fraction ≈ 0 (or very small). Should not throw or return NaN.

### Manifest with extra legacy entries

If manifest.json contains entries from prior runs without matching JLD2 files, Section 3 should skip them with a @warn and continue. The pipeline should not crash.

## Failure Signals

- Julia LoadError or MethodError during `include("scripts/visualization.jl")` — function definition broken
- `AssertionError: length(all_runs) >= 5` — JLD2 files missing or manifest corrupted
- NaN values in summary table — unit conversion bug in soliton number or phase decomposition
- Empty spectral overlay — fiber type filtering failed (no runs match "SMF-28" or "HNLF")
- Matplotlib error in plot generation — PyPlot dependency or figure construction bug

## Not Proven By This UAT

- Publication-quality aesthetic judgment (font sizes, spacing, color contrast at print resolution)
- Performance impact of re-propagation in plot_spectral_overlay on optimization runtime
- Correctness of re-propagation inside plot_spectral_overlay vs original optimization output (would require saving uomega_f in JLD2)
- Behavior with >5 runs (COLORS_5_RUNS wraps via mod1 but visual distinguishability not tested)

## Notes for Tester

- The full pipeline (Test Case 4) takes ~15-25 minutes due to 5 optimization re-runs. Run on burst VM only.
- Test Cases 1-3 can be run as quick standalone checks without the full pipeline.
- If spectral overlay shows unexpected spectra, check that `plot_spectral_overlay` is reconstructing sim/fiber correctly from JLD2 scalar fields — the function rebuilds the full simulation environment from stored parameters.
