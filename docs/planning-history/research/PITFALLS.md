# Pitfalls Research

**Domain:** Verification, cross-run comparison, parameter sweeps, and pattern detection — added to existing nonlinear fiber optics simulation platform (MultiModeNoise.jl)
**Project:** smf-gain-noise, milestone v2.0 Verification & Discovery
**Researched:** 2026-03-25
**Confidence:** HIGH for codebase-specific pitfalls (direct code audit); MEDIUM for numerical methods pitfalls (physics domain knowledge + literature)

---

## Critical Pitfalls

---

### Pitfall 1: Verifying Energy Conservation Through a Normalized Cost Function

**What goes wrong:**
`spectral_band_cost` returns `J = E_band / E_total` — a ratio that is by construction invariant to total energy. A verification test that checks "energy in the Raman band decreased" by looking at J alone will pass even if the underlying propagation is completely wrong — for example, if the solver diverges and the output field is zero (E_band = 0, E_total = 0 triggers the `@assert sum(abs2.(uωf)) > 0` guard, but any nonzero noise distribution would give a finite J with no error). The normalized cost masks genuine conservation failures.

**Why it happens:**
The optimization loop already uses J as its only diagnostic. When writing verification code, it is natural to re-use the same quantities the optimizer tracks. The mistake is treating J as a physics correctness metric when it is a pure ratio that absorbs absolute energy errors.

**How to avoid:**
Verification must track absolute (unnormalized) energies independently of the cost function. For a lossless fiber run:
- `E_in = sum(abs2.(uω0))` before the solve
- `E_out = sum(abs2.(uωf))` after the solve
- Check `abs(E_out - E_in) / E_in < 0.05` (5% tolerance for a short fiber with Tsit5/Vern9)

Additionally, verify conservation in the time domain: `E_t = sum(abs2.(ut))` should match `E_ω = sum(abs2.(uω)) / Nt` (Parseval's theorem). A Parseval check costs one IFFT and catches FFT normalization bugs that corrupt all frequency-domain metrics silently.

**Warning signs:**
- J shows sensible values (e.g., 0.05 to 0.30) but the run log shows solver warnings about rejected steps or stiffness
- Two runs with identical parameters but different Nt or time_window give dramatically different J values (grid-dependent normalization)
- The "optimized" pulse has J near 0 but the absolute Raman band energy is the same as baseline (optimizer suppressed E_total, not E_band)

**Phase to address:**
Correctness verification phase (first v2.0 phase). This is the single most important check before any cross-run comparison — if absolute energy conservation is not confirmed first, all downstream comparisons are on shaky ground.

---

### Pitfall 2: Counting Non-Converged Optimizer Runs as Valid Data Points in a Parameter Sweep

**What goes wrong:**
`optimize_spectral_phase` uses `Optim.Options(iterations=max_iter, f_abstol=1e-6)`. L-BFGS stops at `max_iter=50` iterations regardless of convergence — `Optim.converged(result)` may return `false`, but the script logs the last value of J and saves the phase profile as if it were a valid optimization result. In a parameter sweep over (fiber length, peak power), some configurations will be underdetermined (very short fibers where one iteration reaches J<0.05) and others will be poorly conditioned (near-zero-dispersion fibers where L-BFGS oscillates). Including non-converged runs in a "pattern detection" analysis introduces systematically biased outliers that look like real physics.

**Why it happens:**
The optimization result struct in Optim.jl contains convergence metadata, but the current `optimize_spectral_phase` function returns the raw `result` object without checking `Optim.converged(result)`. Downstream code that calls this function extracts `Optim.minimum(result)` (the final J value) without checking the convergence flag.

**How to avoid:**
At the parameter sweep level, tag every result with its convergence metadata:
```julia
converged = Optim.converged(result)
iterations_used = Optim.iterations(result)
J_final = Optim.minimum(result)
gradient_norm = Optim.g_norm_trace(result)[end]
```
Exclude runs where `!converged` and `gradient_norm > 1e-4` from pattern analysis. Log a warning (not a silent skip) when a run is excluded. For the cross-run comparison, always show a convergence indicator on aggregate plots (e.g., open vs. filled markers for converged vs. not).

**Warning signs:**
- A parameter sweep shows J values that form smooth trends except for isolated outliers at regular intervals in the (L, P) grid — likely unconverged runs that hit max_iter
- The final gradient norm from `Optim.g_norm_trace` is large (> 1e-3) for the runs that appear as "winners" or "losers" in the pattern
- Runs with near-zero-dispersion fiber (`:HNLF_zero_disp` preset) show J values scattered across [0, 1] with no trend

**Phase to address:**
Parameter sweep phase — build convergence tagging into the sweep infrastructure before running any sweeps. Do not retrofit this later.

---

### Pitfall 3: Cross-Run Comparison With Misaligned Spectral Grids

**What goes wrong:**
`setup_raman_problem` accepts `Nt`, `time_window`, and `λ0` as independent parameters. The `band_mask` for the Raman band is computed via `Δf_fft .< raman_threshold` — a boolean mask over the FFT grid. Two runs with different `Nt` or `time_window` have different frequency resolutions (`Δf = 1 / time_window` per bin), meaning the same `raman_threshold = -5.0` THz selects a different number of frequency bins. The mask for `Nt=2^13, time_window=10` covers a different physical bandwidth than the mask for `Nt=2^14, time_window=20`. J values from runs with different grid configurations are **not directly comparable** — they measure fractional energy over differently-sized spectral windows.

Additionally, `hRω` (the Raman response in frequency) depends on the grid spacing `Δt = time_window / Nt`. Two runs with the same `Nt` but different `time_window` have different Raman response functions, making their Raman suppression results physically different even if they nominally use the same fiber preset.

**Why it happens:**
The `sim` Dict encapsulates grid parameters, but there is no validation that two `sim` Dicts are grid-compatible before comparing their results. Researchers naturally run different configurations with different grid sizes and place the resulting J values in the same comparison table.

**How to avoid:**
When building cross-run comparison infrastructure, define a canonical grid for comparison runs and enforce it. A comparison function should check:
```julia
@assert sim_a["Nt"] == sim_b["Nt"] "grids not comparable: Nt $(sim_a["Nt"]) ≠ $(sim_b["Nt"])"
@assert sim_a["time_window"] ≈ sim_b["time_window"] "grids not comparable: time_window mismatch"
@assert sim_a["λ0"] ≈ sim_b["λ0"] "center wavelength mismatch"
```
Alternatively, record grid parameters alongside J in every result file and display them in comparison plots. The comparison summary header must explicitly state the common grid parameters being used.

**Warning signs:**
- A "baseline vs. optimized" comparison shows J increasing after optimization for certain fiber configurations — may indicate the baseline was run on a coarser grid that gives a different J for the same physical state
- J values for runs with the same fiber and length but different power show non-monotonic behavior at high power — may indicate `time_window` was auto-set differently per run via `recommended_time_window` and the Raman mask window changed
- `sum(band_mask)` differs between runs being compared

**Phase to address:**
Cross-run comparison infrastructure phase — define canonical grid policy before running any sweeps.

---

### Pitfall 4: Phase Ambiguity Corrupting Phase Profile Comparison

**What goes wrong:**
The optimizer minimizes J, which depends only on `|uωf(ω)|²` — the spectral power. The spectral phase of the output is irrelevant to J. Consequently, the optimal input phase `φ_opt(ω)` is defined only up to:
1. A global constant offset: `φ_opt + C` gives identical J for any constant C
2. A global linear term: `φ_opt + α·ω` gives identical J (shifts the pulse in time, not in spectrum)

When comparing phase profiles across runs or fiber configurations, two "identical" solutions can appear visually completely different because one has a global offset and the other does not. Overlaying phase curves from multiple runs on a single axes will show curves that appear uncorrelated even when they are physically the same up to a temporal shift.

**Why it happens:**
L-BFGS finds whatever phase minimum it converges to from the zero-phase initial condition. The landscape has a continuous family of equivalent solutions related by the time-shift symmetry of the problem. Different runs reach different representatives of this family.

**How to avoid:**
Before comparing or overlaying phase profiles across runs:
1. Remove the global offset: subtract `mean(φ_opt[band_mask_input, :])` where `band_mask_input` is the mask over the signal-bearing frequencies
2. Remove the linear term (group delay offset): fit a linear polynomial to `φ_opt[band_mask_input]` and subtract it
3. Display the "relative phase" (deviation from linear chirp): `φ_residual = φ_opt - (a + b·ω)` where `(a, b)` is the least-squares linear fit
4. Add a footnote to every multi-run phase comparison plot: "Global phase offset and group delay removed"

**Warning signs:**
- Multi-run phase overlay plots look like random noise even for configurations expected to be similar
- Two runs for the same fiber with slightly different P show phase curves that differ by a large constant
- The group delay (first derivative of phase) looks the same for two runs but the unwrapped phase looks completely different

**Phase to address:**
Cross-run comparison infrastructure phase. Implement the normalization before any phase overlays.

---

### Pitfall 5: Finite Difference Gradient Check Using Cost in dB Units

**What goes wrong:**
`optimize_spectral_phase` optimizes `MultiModeNoise.lin_to_dB(J)` (cost in dB), but `cost_and_gradient` returns a gradient `∂J/∂φ` with respect to the linear J. The existing `validate_gradient` function correctly computes both adjoint and finite-difference gradients using `cost_and_gradient` directly (linear J). However, if a future correctness verification writes a finite-difference check against the dB cost (as it appears in the Optim callback), the comparison will fail silently because the dB transformation introduces a factor of `10/(J·ln(10))` between the linear and log-domain gradients that is not a constant and depends on the current J value. At J=0.05 (well-optimized), this factor is ~87; at J=0.30 (baseline), it is ~14.

**Why it happens:**
The optimization callback shows dB values in the log, which are more interpretable for a physicist. A researcher writing a verification test that reads the callback output will naturally write the finite-difference check in dB.

**How to avoid:**
The gradient check must always be performed against the same objective function that the gradient was computed from. The `validate_gradient` function already does this correctly (uses `cost_and_gradient` directly). Any new gradient verification must follow the same pattern. Add a comment to `validate_gradient` explicitly stating that gradients are w.r.t. linear J and that the dB transformation in the optimizer does NOT affect the gradient being checked.

**Warning signs:**
- Finite difference gradient check shows relative errors > 10% systematically across all test indices (not scattered) — usually indicates a unit/scaling mismatch, not an actual gradient bug
- The relative error correlates with the magnitude of J (higher J = lower relative error) — the signature of an unintentional log-domain check

**Phase to address:**
Correctness verification phase — write the gradient check protocol before any physics verification.

---

### Pitfall 6: Pattern Detection Confusing Grid Artifacts With Physics

**What goes wrong:**
Several features of the FFT-based simulation produce numerical artifacts that can look like physical trends in a parameter sweep:
- The Raman response `hRω = fft(hRt)` is computed on the simulation grid. The discrete convolution wraps around at `t = ±time_window/2`. For a long Raman tail at high powers, the tail wraps from the end of the grid to the beginning, adding spurious energy to the Stokes band. This increases J without any physical justification and appears as "saturation" in a power sweep.
- The `attenuator` in `sim` is a superGaussian window that absorbs energy at the temporal edges (see `helpers.jl` line 23-26: `n_attenuation = 30`, `r_attenuation = 0.85 * time_window / 2`). Its effect depends on `time_window`: longer windows attenuate less over the same physical propagation length. A power sweep with auto-sized `time_window` (via `recommended_time_window`) will have varying attenuator profiles, causing the energy at the Raman peak to vary for reasons unrelated to the Raman physics.
- At high J (above ~0.3), spectral broadening from Kerr nonlinearity starts overlapping with the Raman band mask. Increases in J at high power may reflect spectral broadening into the mask, not true Raman generation.

**Why it happens:**
Numerical artifacts and physical effects both manifest as changes in J. Without an independent check (e.g., inspecting `sum(abs2.(ut[1:5, :]))` to detect edge wrapping, or splitting the J increase into Kerr-broadening vs. Raman-generation components), they are indistinguishable in a scalar metric.

**How to avoid:**
For each parameter sweep point, record and plot alongside J:
1. `edge_fraction` from `check_boundary_conditions` — a non-trivial value (>1e-4) signals grid-edge contamination of the results
2. `E_total_out / E_total_in` — deviation from unity signals Raman tail wrapping or attenuator absorption
3. The spectral centroid shift: `Δλ_centroid = λ_centroid(out) - λ_centroid(in)` — distinguishes Raman shift (centroid moves red) from Kerr broadening (centroid stays near pump)

Flag any sweep point where `edge_fraction > 1e-3` as potentially artifact-contaminated and exclude from pattern analysis.

**Warning signs:**
- J shows a non-monotonic trend vs. power with a local maximum before dropping — may indicate Kerr broadening overtaking Raman at high power, or Raman tail wrapping at low time_window
- J for the longest fibers in the sweep is systematically higher than expected from the soliton number scaling — check `check_boundary_conditions` for those points
- The spectral evolution heatmap shows energy appearing at the far end of the time window (temporal wrapping artifact)

**Phase to address:**
Parameter sweep phase — record all diagnostic quantities alongside J before any pattern analysis.

---

### Pitfall 7: Treating the Dict-Based Parameter System as Stateless

**What goes wrong:**
The `fiber` Dict is mutated in two places:
1. `optimize_spectral_phase` sets `fiber["zsave"] = nothing` before the optimization loop (line 165 of `raman_optimization.jl`) to suppress intermediate solution storage
2. `get_disp_fiber_params_user_defined` sets `fiber["zsave"] => nothing` at creation time

For a parameter sweep that reuses a fiber Dict across multiple runs (a natural optimization to avoid reconstruction overhead), mutation of `fiber["zsave"]` or any other field inside the cost function would corrupt subsequent runs. The existing test `"cost_and_gradient does not mutate fiber"` only checks `fiber["zsave"]` — it does not check other fields that could be added in future refactoring (e.g., per-run metadata like `fiber["run_id"]` or `fiber["L_actual"]`). In a parameter sweep loop that modifies L by updating `fiber["L"]` between runs, the Dict mutation pattern means the second run might inherit unexpected state from the first.

**Why it happens:**
Julia Dicts are mutable by reference. Passing a Dict to a function and modifying it inside is natural in Julia (especially for performance — avoids copying large arrays). The issue surfaces only when the same Dict is reused across a loop.

**How to avoid:**
In sweep infrastructure, always construct a fresh `sim` and `fiber` per sweep point by calling `setup_raman_problem` with the specific parameters for that point. Never reuse a `fiber` Dict across loop iterations. Add a comment at the sweep loop entry: `# Fresh sim and fiber per iteration — do not hoist outside loop`. If performance is a concern, benchmark whether Dict construction is actually the bottleneck before considering reuse.

**Warning signs:**
- A parameter sweep over L shows fiber length-dependent behavior that appears "sticky" — the J for L=5m looks like the J for L=2m was used
- Running the same sweep twice gives different results (first run left unexpected state in a shared Dict)
- The `fiber["L"]` value in a sweep result log does not match `fiber["L"]` extracted from the result Dict at the end of the run

**Phase to address:**
Parameter sweep phase — enforce fresh Dict construction in sweep loop design from the start.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use J (normalized ratio) as the only verification metric | Simple, already computed | Hides absolute energy loss, Raman tail wrapping, and attenuator effects | Never for correctness verification; acceptable only for optimization convergence monitoring |
| Skip convergence check on `Optim.converged(result)` | Simpler sweep loop | Non-converged runs pollute pattern analysis with biased outliers | Never in a sweep — always tag convergence metadata |
| Reuse `fiber` Dict across sweep iterations for speed | Avoids `setup_raman_problem` overhead (~50ms) | Mutation side effects corrupt later iterations silently | Never — benchmark first, then decide if 50ms/iteration is the actual bottleneck |
| Compare J values from runs with different `time_window` or `Nt` | Allows comparing arbitrary runs | Compares physically different Raman mask windows; results are not scientifically valid | Never for pattern analysis; acceptable only for informal sanity checks with explicit grid metadata shown |
| Store only `J_final` in sweep result files, not full convergence trace | Smaller result files | Cannot retrospectively diagnose whether a trend is real or reflects convergence variability | Never — gradient norm and iteration count cost nothing to store |
| Implement pattern detection as visual inspection of scatter plots | Fast to implement | Patterns confounded by convergence artifacts, grid artifacts, and phase ambiguity | Acceptable as a first pass if all artifacts are explicitly annotated |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `Optim.jl` result struct | Calling `Optim.minimum(result)` without checking `Optim.converged(result)` — gets the last iterate whether or not it converged | Always check `converged` and `g_residual` before using the minimum value |
| `cost_and_gradient` inside a sweep | Calling with a shared `fiber` Dict that gets `fiber["zsave"]` set to `nothing` on every call — harmless here, but establishes a dangerous pattern if other fields are added | Call `setup_raman_problem` per sweep point; never share `fiber` across iterations |
| `spectral_band_cost` | Using it as an energy conservation test (it is energy-normalized — conservation cannot be detected this way) | Check `sum(abs2.(uωf))` vs `sum(abs2.(uω0))` directly for conservation |
| `validate_gradient` | Using the existing function only at a single test point with zero phase — may miss gradient bugs that only appear at non-trivial phase values where the Raman lobe is already excited | Run validation at both zero-phase and at a converged optimal phase `φ_opt` |
| Phase profile comparison | Overlaying unwrapped phases from multiple runs without removing global offset and group delay term | Normalize by subtracting mean and linear trend over the signal-bearing frequency band before any comparison |
| `recommended_time_window` | Using it to auto-set `time_window` per sweep point, causing different grid configurations per point | Fix a single canonical `time_window` for all sweep points; only use `recommended_time_window` as an input validation check, not to set the actual window |
| `hRω` computation | `hRω = fft(hRt)` is computed on the grid at `get_disp_fiber_params_user_defined` time — it changes if the grid changes | Two sweep points with different grid configurations have physically different Raman response functions; this is expected but must be documented explicitly |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Running full forward+adjoint solve per finite-difference gradient check component | A gradient validation with `n_checks=5` does `2*5+1=11` full ODE solves — ~5–10 minutes per check at `Nt=2^14` | Limit `n_checks` to 3–5 for interactive validation; use `Nt=2^8` test problems for CI-style gradient checks | Whenever `n_checks` > 5 at production grid sizes |
| Running a full parameter sweep (L × P grid) without saving intermediate results | A 5×5 grid at 50 iterations each = 250 full solves; if the script crashes at point 240, all prior work is lost | Save each sweep result immediately after completion to a `results/raman/sweep_*.npz` file; never batch-accumulate then write | Sweeps of more than ~20 points — the probability of a crash or timeout scales with sweep size |
| `plot_optimization_result_v2` called inside the sweep loop | Each call generates 3 separate PNG files; at Nt=2^14, the FFT for the "with evolution" figure re-runs the ODE solver — doubles wall time | Only generate evolution plots for selected canonical runs, not every sweep point; decouple sweep execution from visualization | Any sweep loop where visualization is called per point |
| Using the full `Nt=2^14` grid for parameter exploration | At 50 iterations, one solve takes ~30s; a 5×5 sweep takes ~2.5 hours on a single core | Use a reduced grid (`Nt=2^11`) for exploration sweeps; validate trends on the reduced grid before re-running canonical points at full resolution | Exploration sweeps at full resolution exceed practical wall time |

---

## "Looks Done But Isn't" Checklist

- [ ] **Correctness verification:** Energy conservation checked — verify `E_out/E_in` is tracked independently of J, not inferred from J being finite and in [0,1]
- [ ] **Gradient correctness:** Validation runs at a non-trivial phase point (a converged `φ_opt`, not just `zeros`) — gradient bugs can be masked at φ=0 where the Raman lobe is small
- [ ] **Cross-run comparison:** Grid compatibility confirmed — verify `Nt`, `time_window`, and `λ0` are identical for all runs being compared before J values are placed in the same table
- [ ] **Phase normalization:** Global offset and group delay removed from all phase overlays — verify that two runs for the same config with different random seeds give overlapping phase residual curves (not random noise)
- [ ] **Convergence tagging:** Every sweep result has `converged::Bool`, `iterations::Int`, and `gradient_norm::Float64` stored alongside `J_final` — verify by reading back a result file
- [ ] **Artifact detection:** `check_boundary_conditions` and `E_total` tracked per sweep point — verify that edge_fraction column exists in the sweep output table
- [ ] **Pattern detection validity:** No pattern claim made on configurations where `converged=false` — verify by filtering the pattern analysis to `converged=true` runs only and checking the trend still holds

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Energy conservation not checked — need to retrofit | LOW | Add `E_in` and `E_out` logging to `cost_and_gradient`; re-run a single reference configuration to establish the conservation baseline before any other work |
| Non-converged runs included in published sweep results | MEDIUM | Re-run flagged configurations with increased `max_iter`; if the trend holds after filtering, update the analysis; if the trend disappears, retract the pattern claim |
| Grid mismatch in cross-run comparison — need to re-run on canonical grid | HIGH | Define canonical grid, re-run all sweep points that used non-canonical grids, update comparison plots; may require 1-2 days of compute time for a 5×5 grid at full Nt |
| Phase ambiguity makes comparison uninterpretable | LOW | Apply global offset and linear term removal retroactively to saved `φ_opt` arrays; does not require re-running optimization |
| Dict mutation corrupted a sweep mid-run | MEDIUM | Identify the first corrupted point (check where `fiber["L"]` in result diverges from the sweep parameters), re-run from that point; add the mutation guard to prevent recurrence |
| Grid artifact identified after pattern detection completed | HIGH | Re-run affected sweep points with `time_window` large enough that `edge_fraction < 1e-4`; rebuild pattern analysis from clean data |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Energy conservation masked by normalized cost | Correctness verification phase | Check `E_out/E_in` for 3 reference configurations (SMF28 short, SMF28 long, HNLF) and assert <5% deviation |
| Non-converged runs in sweep | Parameter sweep phase (sweep infrastructure) | Query `converged` field on all stored results; assert no unconverged result appears in pattern tables |
| Grid misalignment in cross-run comparison | Cross-run comparison infrastructure phase | Add `assert_grids_compatible(sim_a, sim_b)` as the first line of any comparison function |
| Phase ambiguity in phase profile overlays | Cross-run comparison infrastructure phase | Verify that two runs for the same config with different `φ0` seeds give overlapping phase residuals after normalization |
| dB vs. linear gradient check confusion | Correctness verification phase | Add a comment to `validate_gradient` explicitly stating that it checks the linear-J gradient, not the dB-objective gradient |
| Grid artifacts mistaken for physics | Parameter sweep phase (diagnostics) | `edge_fraction` and `E_total` columns present in all sweep output; non-trivial edge_fraction triggers a warning in the sweep log |
| Dict mutation in sweep loop | Parameter sweep phase (sweep infrastructure) | Unit test: run same sweep point twice with the same Dict and verify identical results |
| Pattern detection on artifact-contaminated data | Pattern detection phase | Pattern analysis excludes points where `edge_fraction > 1e-3` or `converged = false`; reported separately from clean-data patterns |

---

## Sources

- Codebase audit: `scripts/raman_optimization.jl` lines 149–197 (`optimize_spectral_phase`), 212–243 (`validate_gradient`) — direct observation, HIGH confidence
- Codebase audit: `scripts/common.jl` lines 210–226 (`spectral_band_cost`), 239–248 (`check_boundary_conditions`) — direct observation, HIGH confidence
- Codebase audit: `src/helpers/helpers.jl` lines 22–27 (attenuator design), 64–93 (`get_disp_fiber_params_user_defined`) — direct observation, HIGH confidence
- Codebase audit: `scripts/test_optimization.jl` TDD log lines 1–57 (prior mutation bug found during test RED 11) — direct observation, HIGH confidence
- [Nonlinear Optics and Fiber Simulation Best Practices — rp-photonics tutorial](https://www.rp-photonics.com/tutorial_modeling7.html) — MEDIUM confidence, authoritative optics reference
- [Robust split-step Fourier methods for ultra-short pulses (arXiv:1504.01331)](https://arxiv.org/abs/1504.01331) — MEDIUM confidence, peer-reviewed NLSE simulation methodology
- [Adjoint Method and Inverse Design for Nonlinear Nanophotonic Devices, ACS Photonics](https://pubs.acs.org/doi/abs/10.1021/acsphotonics.8b01522) — MEDIUM confidence, establishes adjoint gradient correctness requirements
- [Grid Convergence Index methodology, NASA GRC](https://www.grc.nasa.gov/www/wind/valid/tutorial/spatconv.html) — MEDIUM confidence, standard grid convergence verification protocol
- [Optim.jl convergence flags — project known behavior from PyTorch LBFGS issue](https://github.com/pytorch/pytorch/issues/49993) — LOW confidence (same issue class, different implementation)
- .planning/STATE.md: Known flags — `_manual_unwrap` on zeroed arrays, 60 dB vs 40 dB evolution floor — HIGH confidence (project record)

---
*Pitfalls research for: v2.0 Verification & Discovery — verification, cross-run comparison, parameter sweeps, pattern detection added to existing nonlinear fiber optics simulation platform*
*Researched: 2026-03-25*
