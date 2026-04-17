# Project Research Summary

**Project:** SMF Gain-Noise — v2.0 Verification & Discovery
**Domain:** Correctness verification, cross-run comparison, parameter sweeps, and pattern detection for Julia nonlinear fiber optics simulation (MultiModeNoise.jl)
**Researched:** 2026-03-25
**Confidence:** HIGH

## Executive Summary

This milestone (v2.0) adds scientific rigor infrastructure on top of an already-working optimization pipeline. The existing codebase (Julia 1.12, DifferentialEquations.jl, Optim.jl, PyPlot.jl) handles forward propagation, adjoint gradient computation, and L-BFGS phase optimization correctly at the per-run level. What is missing is the ability to (a) verify that the solver is physically correct against known analytical solutions, (b) persist structured results across runs, and (c) compare and analyze outcomes across fiber configurations systematically. The recommended approach is a four-phase build: verification first, then serialization infrastructure, then cross-run comparison, then parameter sweeps — each phase de-risking the next.

The most important infrastructure decision is introducing JLD2.jl (v0.6.3) for structured binary run data and JSON3.jl (v1.14.3) for human-readable run manifests. These are the only two new dependencies required; all other capabilities come from packages already in `Project.toml` or Julia stdlib. The verification suite must use small grids (Nt=2^7–2^8) so it completes in under 60 seconds and can act as a fast-feedback correctness gate before any expensive sweep runs.

The dominant risk for this milestone is that a subtle physics error (wrong FFT normalization, incorrect interaction-picture phase factors, adjoint domain mismatch) would corrupt all downstream comparison and sweep results without being detectable from the normalized cost J alone. The mitigation is strict: build verification against analytical solutions (fundamental soliton N=1, photon number conservation, Taylor remainder gradient test) before writing a single line of cross-run comparison code. Secondary risks are grid misalignment across runs and phase ambiguity in phase-profile overlays — both have well-defined, low-cost fixes that must be built into the comparison infrastructure from the start.

## Key Findings

### Recommended Stack

The existing stack is validated and unchanged. Only two new packages are needed: JLD2.jl for structured per-run data persistence (HDF5-compatible binary, round-trips Julia types including complex arrays and nested Dicts) and JSON3.jl for append-only run manifests (grep-able, diff-able metadata index). BSON.jl and NPZ.jl were considered but rejected — BSON has no compression and no HDF5 compatibility; NPZ cannot store nested Dict metadata cleanly. DrWatson.jl was evaluated and deferred — it is appropriate at >50 runs but adds unnecessary framework overhead at the current 5-run scale. All pattern detection is implemented as 3–5 line computations using LinearAlgebra stdlib (cosine similarity) and FFTW.jl (cross-correlation) — no clustering library is needed.

**Core technologies (new additions only):**
- JLD2.jl v0.6.3: Per-run structured data persistence — HDF5-compatible, preserves Julia types, enables cross-run loading without re-running simulations
- JSON3.jl v1.14.3: Run manifest files — append-only, human-readable metadata index linking scalar summaries to JLD2 binary data
- Statistics stdlib: Pattern detection — mean, std, correlation across sweep results (already imported in `visualization.jl`)

### Expected Features

**Must have (table stakes — P1, v2.0 lab meeting deliverables):**
- Fundamental soliton N=1 propagation test — ground truth for the forward ODE solver; catches interaction-picture phase factor errors and FFT normalization bugs that J cannot detect
- Photon number conservation check — physically correct invariant for GNLSE with self-steepening; energy alone (already tracked) is insufficient
- Taylor remainder gradient test — proves adjoint correctness to O(ε²) on a log-log slope plot; strictly stronger than the existing 5-index finite-difference check
- Per-run metadata JSON output — infrastructure prerequisite for every cross-run feature; without it, all aggregation requires log parsing
- Cross-run J summary table (all 5 configs) — single table with J_before, J_after, ΔdB, iterations, wall time; the primary lab meeting deliverable
- Overlay convergence plot (all 5 runs) — single figure showing J(iteration) across all runs; reveals relative optimization difficulty

**Should have (P2, add after P1 passes):**
- Overlay spectral comparison — before/after spectra for all runs in one figure per fiber type
- Phase projection onto GDD/TOD basis — quantifies how much of the optimal phase is a physically interpretable polynomial chirp; reports residual fraction
- Soliton number N annotation in metadata — N = sqrt(L_D/L_NL) per run; enables correlation plots without re-running

**Defer (v2.0+, dedicated planning):**
- Parameter sweep L×P heatmap — computationally expensive (5×5 grid at 50s/run = ~2.5 CPU-hours); requires canonical grid policy and sweep infrastructure from Phase 4
- Phase universality test at matched N — requires custom run design beyond current 5 configs
- Multi-start robustness analysis — infrastructure exists in `benchmark_optimization.jl` but is not wired to the standard pipeline

### Architecture Approach

The v2.0 architecture adds three new script files and minimally modifies one existing file, following the project's "new file for new concern" pattern. `scripts/verification.jl` encapsulates all physics correctness tests; `scripts/run_comparison.jl` handles cross-run loading and overlay plotting; `scripts/run_sweep.jl` manages parameter iteration. The only existing file that requires modification is `raman_optimization.jl`, which gets ~30 lines of JLD2 serialization added to `run_optimization()` — no signature changes, purely additive. A new data layer of `_result.jld2` files per run directory feeds the comparison layer; the comparison layer feeds the existing output layer of per-run PNG files plus new cross-run PNGs in `results/images/`.

**Major components:**
1. `scripts/verification.jl` — Physics correctness test suite (soliton, photon number, Taylor remainder); outputs structured VerificationResult named tuples to `results/raman/validation/`; depends only on `common.jl` and MultiModeNoise; stateless relative to optimization
2. `scripts/raman_optimization.jl` (extended) — Adds JLD2 serialization at the end of `run_optimization()`; captures cost history in callback; no changes to public interface
3. `scripts/run_comparison.jl` — Loads `_result.jld2` files without re-running simulations; produces overlay phase profiles, overlay convergence curves, and summary bar charts; accepts `run_dirs::Vector{String}` as parameter (no hardcoded paths)
4. `scripts/run_sweep.jl` — Iterates `run_optimization()` over parameter grids; calls `run_comparison_suite()` after all sweep points complete; enforces fresh `sim`/`fiber` Dict construction per iteration

### Critical Pitfalls

1. **Energy conservation masked by normalized cost J** — `spectral_band_cost` returns E_band/E_total; this ratio is finite even when the solver diverges or E_total changes significantly. Verification must check `abs(E_out - E_in) / E_in < 0.05` using raw `sum(abs2.(uω))` values, independently of J. Address in Phase 1 before any other work.

2. **Cross-run comparison with misaligned spectral grids** — Two runs with different `Nt` or `time_window` have different `band_mask` window sizes and physically different Raman response functions (`hRω`). Their J values are not scientifically comparable. Fix: define a canonical grid policy and add `assert_grids_compatible(sim_a, sim_b)` as the first line of every comparison function. Address in Phase 3.

3. **Phase ambiguity corrupting phase profile overlays** — The optimal phase φ_opt is defined only up to a global constant and a linear term (time-shift symmetry of J). Runs for the same config appear uncorrelated when overlaid without normalization. Fix: subtract mean and linear trend over the signal-bearing frequency band before any multi-run phase plot. Address in Phase 3.

4. **Non-converged optimizer runs treated as valid sweep data** — L-BFGS stops at `max_iter=50` regardless of convergence. The current pipeline does not check `Optim.converged(result)`. Non-converged runs introduce biased outliers that look like real physics in pattern analysis. Fix: tag every sweep result with `converged::Bool`, `iterations::Int`, and `gradient_norm::Float64`; exclude `converged=false` runs from pattern claims. Address in Phase 4.

5. **Dict mutation corrupting parameter sweeps** — `fiber["zsave"]` is mutated inside the optimization loop; reusing the same `fiber` Dict across sweep iterations silently propagates unexpected state. Fix: call `setup_raman_problem` fresh per sweep point; never hoist `sim` or `fiber` outside the sweep loop. Address in Phase 4.

## Implications for Roadmap

Based on research, the build order is strictly dependency-constrained: verification must precede comparison because comparison results are meaningless without confirmed solver correctness; comparison infrastructure must precede sweeps because sweeps reuse both `run_optimization` (serialization) and `run_comparison_suite` (overlay plots). No phase can be parallelized with its predecessor.

### Phase 1: Correctness Verification

**Rationale:** Verification depends only on already-stable `common.jl` and MultiModeNoise — no new infrastructure required. If the forward solver or adjoint has a bug, every downstream result is contaminated. This phase either confirms the existing code is correct or finds a bug before sweeps amplify it. Run first, unconditionally.

**Delivers:** `scripts/verification.jl` with soliton test, photon number check, Taylor remainder test, and Parseval check; structured VerificationResult report in `results/raman/validation/verification_report.txt`; explicit pass/fail determination before any other phase begins.

**Addresses features:** Fundamental soliton N=1 propagation test (P1), photon number conservation check (P1), Taylor remainder gradient test (P1), cost J mask correctness check.

**Avoids pitfalls:** Energy conservation masked by J (Pitfall 1), dB vs. linear gradient check confusion. Uses small grids (Nt=2^7–2^8) so the suite completes in <60 seconds.

### Phase 2: Result Serialization

**Rationale:** Per-run metadata is the prerequisite for every cross-run feature. Without `_result.jld2` files, Phase 3 has nothing to load. This phase re-runs the 5 existing production runs to generate structured output, and adds cost history capture to the callback.

**Delivers:** JLD2.jl and JSON3.jl added to `Project.toml`; ~30 lines added to `run_optimization()` in `raman_optimization.jl` for serialization; cost history captured in callback; one `_result.jld2` per run directory for all 5 existing configs; top-level `results/raman/manifest.json` with scalar summaries.

**Addresses features:** Per-run metadata JSON output (P1), convergence history capture (required for overlay convergence plot).

**Avoids pitfalls:** Log parsing anti-pattern (structured results, not log parsing). Establishes canonical grid policy — all 5 runs must use the same Nt and time_window recorded in the JLD2 file.

### Phase 3: Cross-Run Comparison

**Rationale:** The 5 existing `_result.jld2` files from Phase 2 are the test input. Overlay and summary figures can be verified against known outputs before any new sweep runs are introduced.

**Delivers:** `scripts/run_comparison.jl` with `load_run_result()`, `overlay_phase_profiles()`, `overlay_cost_curves()`, `summary_bar_chart()`, and `run_comparison_suite()`; cross-run J summary table (P1); overlay convergence plot for all 5 configs (P1); overlay spectral comparison (P2); phase GDD/TOD projection (P2); soliton number N annotation (P2); all cross-run PNGs written to `results/images/`.

**Addresses features:** Cross-run J summary table (P1), overlay convergence plot (P1), overlay spectral comparison (P2), phase projection (P2).

**Avoids pitfalls:** Grid misalignment (Pitfall 2) — `assert_grids_compatible()` built in; phase ambiguity (Pitfall 3) — global offset and linear trend removal applied before all phase overlays; re-running simulations inside comparison scripts (Architecture Anti-Pattern 2).

### Phase 4: Parameter Sweeps

**Rationale:** Sweeps reuse `run_optimization()` (Phase 2) and `run_comparison_suite()` (Phase 3) as black boxes. The only new code is the iteration harness and sweep-specific output organization. Sweeps are expensive (50s/run × N configs) and should only execute after verification confirms the solver is correct.

**Delivers:** `scripts/run_sweep.jl` with `sweep_fiber_length()`, `sweep_peak_power()`, `sweep_fiber_type()`, and `run_parameter_sweep()`; at least one canonical sweep (SMF-28 length sweep over [0.5, 1.0, 2.0, 5.0] m) with comparison output; `results/raman/sweeps/` directory with per-run subdirs, summary PNGs, and `sweep_results.jld2`.

**Addresses features:** Parameter sweep infrastructure (P3 in FEATURES.md — separated into its own dedicated phase).

**Avoids pitfalls:** Non-converged runs as valid data (Pitfall 4) — convergence tagging built into sweep infrastructure; Dict mutation across iterations (Pitfall 5) — fresh `setup_raman_problem()` per sweep point; grid artifacts mistaken for physics (Pitfall 6 from PITFALLS.md) — `edge_fraction` and `E_total` recorded per point; auto-sized `time_window` causing grid drift — canonical fixed grid enforced.

### Phase Ordering Rationale

- Physics verification before data persistence: if the solver is wrong, serializing its output is wasted effort and produces misleading artifacts.
- Data persistence before comparison: the comparison layer is a pure reader of JLD2 files; it cannot be built or tested until those files exist.
- Comparison before sweeps: sweeps call `run_comparison_suite()` at the end of each sweep; this function must be stable before the sweep infrastructure wraps it.
- Small grid for verification tests: decouples "is the physics right?" from "is the grid big enough for optimization?" — the existing `validate_gradient` in `raman_optimization.jl` conflates these by using production grid size.

### Research Flags

Phases with standard patterns (skip additional research):
- **Phase 1 (Verification):** Analytical solutions are textbook-documented (Agrawal Ch.5, Dudley 2006). Taylor remainder test is standard practice in PDE-constrained optimization. Implementation is straightforward given the verification test cases already written out in `results/raman/MATHEMATICAL_FORMULATION.md`.
- **Phase 2 (Serialization):** JLD2 and JSON3 integration patterns are well-documented and versions verified against the project stack.
- **Phase 3 (Comparison):** PyPlot overlay patterns are standard; phase normalization algorithm is defined explicitly in PITFALLS.md Pitfall 4.

Phases that may need deeper planning-time research:
- **Phase 4 (Sweeps):** The canonical grid policy for the L×P heatmap requires empirical validation — `recommended_time_window()` output for each (L, P) pair must be inspected to determine if a single fixed `time_window` is physically adequate across all sweep points or if separate canonical windows per fiber type are needed. Recommend a 10-minute exploratory run at the start of Phase 4 planning.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | JLD2 and JSON3 versions verified against Julia General registry on this machine; all other packages already in Project.toml; DrWatson and alternatives explicitly evaluated and rejected |
| Features | HIGH for P1; MEDIUM for P2; LOW for P3 | Verification methods are textbook-established; phase pattern interpretation is domain-specific; parameter sweep scope is novel for this project with no prior run history |
| Architecture | HIGH | Based on direct code inspection of all scripts (641 lines of raman_optimization.jl, 399 lines of common.jl); all integration points confirmed by code observation, not inference |
| Pitfalls | HIGH for codebase-specific; MEDIUM for numerical | Energy conservation masking, Dict mutation, and grid misalignment identified from direct code audit; Raman tail wrapping and attenuator grid-dependence from physics domain knowledge and literature |

**Overall confidence:** HIGH

### Gaps to Address

- **Photon number conservation tolerance:** The 1% tolerance for photon number drift (vs. 5% for energy) needs empirical calibration on at least one real production run before the verification suite sets its threshold as a hard assertion. Run one SMF-28 L=1m reference config and measure actual photon number drift before coding the `@assert`.
- **Canonical grid for sweeps:** The `recommended_time_window()` values for extreme sweep points (L=0.5m/high-power and L=5m/low-power) have not been inspected. The Phase 4 planning pass must verify that a single fixed `time_window` covers all planned sweep points without excessive edge fraction.
- **Cost history storage:** The optimization callback currently logs cost via `@debug` but does not accumulate it. The exact location in `raman_optimization.jl` where `push!(cost_history, ...)` should be added needs a 10-line code inspection at Phase 2 start — documented in ARCHITECTURE.md but not yet implemented.

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `scripts/raman_optimization.jl` (641 lines), `scripts/common.jl` (399 lines), `scripts/test_optimization.jl`, `scripts/visualization.jl`, `src/helpers/helpers.jl` — architecture and pitfalls ground truth
- JLD2.jl GitHub (v0.6.3), JSON3.jl GitHub (v1.14.3), Julia General Registry — stack verification
- Julia stdlib documentation (Statistics, TOML, Printf, Dates, LinearAlgebra) — confirmed bundled with Julia 1.9+
- `results/raman/MATHEMATICAL_FORMULATION.md` — verification test case specifications already written

### Secondary (MEDIUM confidence)
- Agrawal, "Nonlinear Fiber Optics," 6th ed. — soliton N=1 propagation, photon number conservation benchmarks
- Dudley, Genty, Coen. Rev. Mod. Phys. 78, 1135 (2006) — canonical supercontinuum GNLSE verification benchmark
- gnlse-python (WUST-FOG) — soliton test structure reference; `test_nonlinearity.py` and `test_raman.py`
- Luna.jl — validates against Dudley 2006; grid compatibility patterns
- IEEE JLT 2021 — photon number as correct invariant for GNLSE with self-steepening
- Steven G. Johnson, MIT 18.336 adjoint notes — Taylor remainder test as standard gradient verification
- rp-photonics NLSE simulation best practices tutorial — numerical artifact identification
- arXiv:1504.01331 — robust split-step Fourier methods, grid artifact analysis

### Tertiary (LOW confidence)
- Optim.jl convergence flags behavior — inferred from PyTorch LBFGS issue; needs empirical validation against actual Optim.jl result structs
- DrWatson.jl documentation — consulted to confirm overkill at current project scale; not directly used

---
*Research completed: 2026-03-25*
*Ready for roadmap: yes*

# Architecture Patterns: Verification, Cross-Run Comparison, Parameter Sweep

**Domain:** Nonlinear fiber optics simulation — correctness verification and systematic discovery
**Researched:** 2026-03-25
**Milestone:** v2.0 — Verification & Discovery
**Confidence:** HIGH (based on direct code inspection of all existing scripts)

---

## Context: What the Existing Architecture Gives Us

Before detailing what needs to be added, the relevant existing pieces that new features integrate with:

| Existing piece | Location | What it owns |
|----------------|----------|-------------|
| `cost_and_gradient` | `scripts/raman_optimization.jl` | Forward + adjoint pipeline; callable with any φ |
| `validate_gradient` | `scripts/raman_optimization.jl` | Finite-difference gradient check (currently per-run, informal) |
| `run_optimization` | `scripts/raman_optimization.jl` | Single run: setup → optimize → save plots → return result |
| `setup_raman_problem` | `scripts/common.jl` | Builds `uω0, fiber, sim, band_mask` from physical parameters |
| `FIBER_PRESETS` | `scripts/common.jl` | Named fiber configs; expanding this is the entry point for sweeps |
| Run output files | `results/raman/<fiber>/<params>/` | `opt.png`, `opt_evolution.png`, `opt_phase.png` per run |
| `MATHEMATICAL_FORMULATION.md` | `results/raman/` | Full math derivation with code references — already ready for verification |

The five runs in `raman_optimization.jl` (`if abspath(PROGRAM_FILE) == @__FILE__` block) currently produce isolated per-run outputs. There is no mechanism to load a previous run's result, compare across runs, or systematically iterate over parameter values.

---

## New Components Required

Three new components are needed. Each is a new file, not a modification to existing files:

### 1. `scripts/verification.jl`

**Purpose:** Correctness tests against NLSE/Raman theory that can be run at any time, independent of optimization.

**What it contains:**
- Analytical reference functions (soliton period, dispersion broadening factor, Raman shift estimate)
- `verify_forward_solver(; Nt, L, fiber_preset)` — runs 4-5 canonical physics tests, returns a structured result
- `verify_adjoint_gradient(; Nt, L, fiber_preset, n_checks, epsilon)` — Taylor remainder test + finite-difference check, returns structured result
- `verify_raman_suppression(; Nt, L, fiber_preset)` — confirms optimization actually reduces J vs baseline
- `run_verification_suite()` — calls all three, prints a consolidated pass/fail table, saves a report to `results/raman/validation/`
- Include guard: `_VERIFICATION_JL_LOADED`

**Integration with existing code:** Calls `setup_raman_problem` from `common.jl` and `MultiModeNoise` solver directly. Does not call `run_optimization` — avoids generating plots during verification.

**Key design constraint:** Tests must use small grids (`Nt=2^7` or `2^8`) so the suite runs in under 60 seconds. The existing `validate_gradient` in `raman_optimization.jl` (which uses full-size `Nt`) is for debug use; the verification suite is for pass/fail correctness.

**Output:** Structured named tuples per test (not just pass/fail booleans) so the roadmap phase that does cross-run analysis can consume verification results programmatically.

```julia
# Example return structure
struct VerificationResult
    test_name::String
    passed::Bool
    expected::Float64
    measured::Float64
    tolerance::Float64
    notes::String
end
```

**What does NOT go here:** Optimization runs, plot generation, parameter sweeps. Verification is stateless relative to optimization.

---

### 2. `scripts/run_comparison.jl`

**Purpose:** Load saved optimization results across multiple runs and produce overlay/amalgamation plots.

**What it contains:**
- `load_run_result(run_dir)` — loads a `.jld2` or `.npz` result file from a run directory, returns a structured named tuple
- `overlay_phase_profiles(results; save_path)` — plots all optimized φ(λ) on one figure with fiber/params legend
- `overlay_cost_curves(results; save_path)` — plots J(iteration) convergence history across runs
- `summary_bar_chart(results; save_path)` — J_before vs J_after as grouped bars per run config
- `run_comparison_suite(run_dirs; save_path)` — calls all three, saves to `results/images/`

**Integration with existing code:** Consumes the saved data that `run_optimization` must be extended to write (see "Modifications to Existing Files" section below). Calls visualization helpers from `visualization.jl` where panels are reusable.

**Key design constraint:** `run_comparison.jl` must work without re-running any simulation. It reads saved data, it does not call the solver. This makes it fast and allows re-running the comparison plots without 10-minute optimization waits.

---

### 3. `scripts/run_sweep.jl`

**Purpose:** Systematic iteration over parameter space, with uniform output organization.

**What it contains:**
- `sweep_fiber_length(; fiber_preset, lengths, P_cont, kwargs...)` — runs `run_optimization` for each length, collects results, calls comparison suite
- `sweep_peak_power(; fiber_preset, powers, L_fiber, kwargs...)` — analogous power sweep
- `sweep_fiber_type(; fiber_presets, L_fiber, P_cont, kwargs...)` — cross-fiber comparison
- `run_parameter_sweep(sweep_config::NamedTuple)` — generic dispatcher using a sweep config struct

**Integration with existing code:** Calls `run_optimization` from `raman_optimization.jl` as a black box. No modifications to `run_optimization` needed for sweeps — it already accepts all parameters as keyword arguments. The key integration point is that `run_optimization` must return the result dict (which it already does) and now also save it to disk (new).

**Output directory convention:**
```
results/raman/sweeps/<sweep_name>/
  ├── <fiber>_<params>/          # individual run output (same as standalone runs)
  ├── summary_comparison.png     # overlay plots
  ├── sweep_config.json          # reproducibility record
  └── sweep_results.jld2         # structured results for later analysis
```

---

## Modifications to Existing Files

Only two existing files need modification. Both changes are additive (no signature changes).

### `scripts/raman_optimization.jl` — Add result serialization

**What to add:** At the end of `run_optimization`, before returning, serialize the key results to disk:

```julia
# Serialize result for cross-run comparison (VER-01 requirement)
result_data = (
    fiber_name = run_meta.fiber_name,
    L_m = fiber["L"],
    P_cont_W = run_meta.P_cont_W,
    lambda0_nm = run_meta.lambda0_nm,
    J_before = J_before,
    J_after = J_after,
    J_before_dB = MultiModeNoise.lin_to_dB(J_before),
    J_after_dB = MultiModeNoise.lin_to_dB(J_after),
    delta_J_dB = ΔJ_dB,
    n_iterations = result.iterations,
    elapsed_s = elapsed,
    phi_opt = φ_after,        # Nt × M matrix — needed for phase overlays
    cost_history = ...,        # iteration cost trace
    convergence_norm = grad_norm,
)
save("$(save_prefix)_result.jld2", "result", result_data)
```

**Format choice:** Use `JLD2.jl` rather than NPZ. It handles Julia arrays natively without type conversion and preserves the NamedTuple structure. NPZ is already used for cross-section data (`.npz` files in the gain module) but requires explicit array type handling.

**Caveat:** `JLD2.jl` must be added to `Project.toml`. If adding a dependency is undesired, use `NPZ.jl` (already in the project) with explicit array saving — `phi_opt` as a plain array, metadata as a separate small dict. This is less convenient but avoids a new dependency.

**Impact:** `run_optimization` return signature is unchanged. The serialization is a side effect only. Existing callers continue to work.

### `scripts/common.jl` — Add cost history tracking

The current optimization loop has a `callback` function that logs iteration cost via `@debug` but does not accumulate it. For cross-run convergence plots, the cost trace must be captured:

```julia
cost_history = Float64[]
function callback(state)
    push!(cost_history, state.value)
    @debug @sprintf("Iter %3d: J = %.6f (%.2f dB)",
        state.iteration, 10^(state.value / 10), state.value)
    return false
end
```

The `cost_history` vector is then included in the serialized result. This is a 3-line change to `optimize_spectral_phase` in `raman_optimization.jl` (not `common.jl` — the callback lives in `raman_optimization.jl`).

---

## System Overview After v2.0

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Entry Points                                      │
│  raman_optimization.jl  │  run_sweep.jl   │  verification.jl           │
│  (5 production runs)    │  (param sweeps) │  (physics correctness)     │
└──────────┬──────────────┴────────┬────────┴───────────┬────────────────┘
           │                       │                    │
           ↓                       ↓                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    Optimization Layer (unchanged)                        │
│  run_optimization() ─→ cost_and_gradient() ─→ MultiModeNoise solver    │
│  optimize_spectral_phase()                                               │
└──────────┬──────────────────────────────────────────────────────────────┘
           │ serializes _result.jld2
           ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    Data Layer (new in v2.0)                              │
│  results/raman/<fiber>/<params>/_result.jld2  (per-run structured data) │
│  results/raman/sweeps/<name>/sweep_results.jld2  (sweep aggregates)     │
│  results/raman/validation/verification_report.txt                       │
└──────────┬──────────────────────────────────────────────────────────────┘
           │ consumed by
           ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    Comparison Layer (new in v2.0)                        │
│  run_comparison.jl                                                       │
│  ├── load_run_result()                                                   │
│  ├── overlay_phase_profiles()                                            │
│  ├── overlay_cost_curves()                                               │
│  └── summary_bar_chart()                                                 │
└──────────┬──────────────────────────────────────────────────────────────┘
           │ outputs to
           ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                    Output Layer                                          │
│  results/raman/*/opt.png (per-run)                                       │
│  results/images/*.png (cross-run summaries)                             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

| Component | Responsibility | Communicates With | Does NOT own |
|-----------|---------------|-------------------|-------------|
| `verification.jl` | Analytical physics tests; pass/fail report | `common.jl` (setup), MultiModeNoise (solver) | Optimization, plotting |
| `raman_optimization.jl` (extended) | Optimization + result serialization | All existing dependencies + JLD2 | Cross-run analysis |
| `run_comparison.jl` | Load saved results; overlay/summary plots | `visualization.jl` (panels), JLD2 (load) | Simulation, optimization |
| `run_sweep.jl` | Parameter space iteration | `raman_optimization.jl` (run_optimization), `run_comparison.jl` | Physics, plotting internals |

---

## Data Flow for New Features

### Verification flow

```
run_verification_suite()
    │
    ├── setup_raman_problem(Nt=2^7, ...) ─→ uω0, fiber, sim   [via common.jl]
    │
    ├── MultiModeNoise.solve_disp_mmf(uω0, fiber, sim)        [direct solver call]
    │    └── compare output to analytical formula
    │
    ├── cost_and_gradient(φ_test, ...) × (1 + 2*n_checks)     [Taylor remainder test]
    │    └── check slope ≈ 2 in log-log
    │
    └── write pass/fail table to results/raman/validation/
```

### Cross-run comparison flow

```
run_comparison_suite(["results/raman/smf28/L1m_P005W",
                      "results/raman/smf28/L2m_P030W",
                      "results/raman/hnlf/L1m_P005W", ...])
    │
    ├── load_run_result(run_dir)  [reads _result.jld2 for each dir]
    │    └── returns NamedTuple with phi_opt, J values, metadata
    │
    ├── overlay_phase_profiles(results)  [φ(λ) for each run, color=fiber type]
    │
    ├── overlay_cost_curves(results)     [J(iter) for each run]
    │
    └── summary_bar_chart(results)       [J_before vs J_after grouped by config]
```

### Parameter sweep flow

```
sweep_fiber_length(fiber_preset=:SMF28, lengths=[0.5, 1.0, 2.0, 5.0], P_cont=0.05)
    │
    ├── for L in lengths:
    │    run_optimization(L_fiber=L, fiber_preset=:SMF28, save_prefix=...)
    │    [writes opt.png, opt_evolution.png, opt_phase.png, _result.jld2]
    │
    └── run_comparison_suite([dir_0.5, dir_1.0, dir_2.0, dir_5.0])
         [writes summary overlay to results/images/sweep_SMF28_lengths.png]
```

---

## Build Order (Dependency-Constrained)

The build order matters because cross-run comparison cannot be tested until there are saved results to load.

### Phase 1: Verification (no dependencies on later phases)

Build `scripts/verification.jl` first. It depends only on `common.jl` and `MultiModeNoise` — both already exist and are stable. The physics tests in `MATHEMATICAL_FORMULATION.md` are already written out; verification.jl operationalizes them.

Run the verification suite to confirm the existing code is correct before building anything else. This de-risks the entire milestone: if there is a bug in the adjoint, it will show up here.

**Deliverable:** `scripts/verification.jl` passing all tests, report in `results/raman/validation/`.

### Phase 2: Result Serialization (depends on Phase 1 confirming correctness)

Add result serialization to `run_optimization`. Re-run the 5 existing production runs to produce `_result.jld2` files. Without these files, Phase 3 has nothing to load.

**Deliverable:** Each of the 5 run directories has `_result.jld2`. Cost history is captured.

### Phase 3: Cross-Run Comparison (depends on Phase 2's saved data)

Build `scripts/run_comparison.jl`. At this point the 5 existing `_result.jld2` files are the test input. The overlay and summary figures can be verified against known run outputs.

**Deliverable:** `results/images/` has cross-run overlay plots for the 5 existing runs.

### Phase 4: Parameter Sweeps (depends on Phase 2 and Phase 3)

Build `scripts/run_sweep.jl`. Sweeps reuse `run_optimization` (Phase 2) and `run_comparison_suite` (Phase 3). Adding new sweep configs is adding new function calls, not new architecture.

**Deliverable:** At least one systematic sweep (length sweep on SMF-28) with comparison output.

---

## Architectural Patterns

### Pattern 1: Test at Small Scale, Confirm at Production Scale

The verification suite uses `Nt=2^7` (128 points) because physics tests like soliton preservation and energy conservation do not require the production grid size. The adjoint gradient test also uses a small grid — at small Nt, 29 finite-difference evaluations take seconds instead of minutes.

This is the correct pattern for the verification layer: decouple "is the physics right?" from "is the grid big enough for optimization?". The existing `validate_gradient` function in `raman_optimization.jl` conflates these by running at production grid size.

### Pattern 2: Structured Results, Not Log Parsing

The current run summary is printed to stdout as a box-drawing table (`@info @sprintf(...)`). This is good for human review but not machine-readable. The serialized `_result.jld2` is the machine-readable version. Both coexist — the stdout table is for interactive monitoring, the JLD2 file is for comparison scripts.

Do not attempt to parse the log files to extract J values. Write them to disk as structured data from the start.

### Pattern 3: New File for New Concern

The rule "don't modify existing files unless necessary" applies here. `verification.jl`, `run_comparison.jl`, and `run_sweep.jl` are new files. `raman_optimization.jl` gets one addition (serialization). `common.jl` gets nothing new in v2.0. This minimizes regression risk on working production runs.

### Pattern 4: Include Guard for All New Script Files

New files follow the same `if !(@isdefined _XXX_LOADED)` pattern. This is particularly important for `verification.jl` because `test_optimization.jl` already includes `raman_optimization.jl`, and verification needs to be includable from test contexts without re-running the full verification suite.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Parsing Log Files for Comparison Data

**What:** Reading `raman_run_*.log` and extracting J values with regex/string matching.
**Why bad:** The log format is human-readable, not contract-stable. Log messages change during development. The effort to parse them is wasted when structured serialization is available.
**Instead:** `_result.jld2` per run directory. Written once, read many times.

### Anti-Pattern 2: Re-Running Optimization Inside Comparison Scripts

**What:** `run_comparison.jl` calls `run_optimization` to get data for comparison.
**Why bad:** Cross-run comparison must not depend on re-running expensive simulations. At 5+ minutes per run, a 10-run comparison would take 50+ minutes just to show plots.
**Instead:** Load from `_result.jld2`. If the file doesn't exist, fail with a clear error message pointing to which run needs to be executed first.

### Anti-Pattern 3: Hardcoding Run List in Comparison Scripts

**What:** `run_comparison.jl` has `dirs = ["results/raman/smf28/L1m_P005W", ...]` hardcoded.
**Why bad:** As sweeps add new run directories, the comparison script needs editing. The script diverges from the actual run set.
**Instead:** Accept `run_dirs::Vector{String}` as a parameter. The caller (sweep script or manual invocation) determines which runs to compare. `run_comparison_suite` is a pure function of its input list.

### Anti-Pattern 4: Verification Tests That Require Optimization to Pass

**What:** A verification test that checks "the optimized J is less than J_baseline".
**Why bad:** This couples correctness verification to optimization convergence. If the optimizer gets stuck (known to happen on heavy HNLF runs), the verification "fails" even though the physics is correct.
**Instead:** Verification tests only check mathematical identities (soliton shape, energy conservation, gradient finite-difference) and analytical formulas. Optimization performance is separately tracked in comparison plots.

---

## Integration Points Summary

| Integration Point | What connects | Mechanism |
|------------------|--------------|-----------|
| `verification.jl` → solver | Tests forward propagation | Direct call to `MultiModeNoise.solve_disp_mmf` |
| `verification.jl` → optimizer | Tests adjoint gradient | Direct call to `cost_and_gradient` (include `raman_optimization.jl`) |
| `verification.jl` → common | Setup small test problems | `setup_raman_problem(Nt=2^7, ...)` |
| `raman_optimization.jl` → JLD2 | Serialize results | `JLD2.save(save_prefix * "_result.jld2", ...)` at end of `run_optimization` |
| `run_comparison.jl` → JLD2 | Load saved results | `JLD2.load(run_dir * "/opt_result.jld2")` |
| `run_comparison.jl` → visualization | Plot overlays | Import `visualization.jl` panels; add new assembler functions |
| `run_sweep.jl` → optimization | Execute sweep runs | Call `run_optimization(...)` for each param value |
| `run_sweep.jl` → comparison | Summarize sweep | Call `run_comparison_suite(dirs)` after all runs complete |

---

## File/Directory Structure After v2.0

```
scripts/
├── common.jl              # unchanged — fiber presets, setup, cost functions
├── raman_optimization.jl  # + result serialization (~30 lines added)
├── amplitude_optimization.jl  # unchanged
├── visualization.jl       # unchanged (new panels go here only if needed for overlays)
├── verification.jl        # NEW — physics correctness test suite
├── run_comparison.jl      # NEW — cross-run overlay and summary plots
├── run_sweep.jl           # NEW — parameter space iteration
├── test_optimization.jl   # unchanged
└── test_visualization_smoke.jl  # unchanged

results/raman/
├── smf28/
│   ├── L1m_P005W/
│   │   ├── opt.png
│   │   ├── opt_evolution.png
│   │   ├── opt_phase.png
│   │   └── opt_result.jld2         # NEW — serialized result
│   └── ...
├── hnlf/
│   └── ...
├── sweeps/                          # NEW directory
│   └── smf28_length_sweep/
│       ├── L0.5m_P005W/            # individual run dirs
│       ├── L1m_P005W/
│       ├── L2m_P005W/
│       ├── summary_comparison.png
│       ├── sweep_config.json
│       └── sweep_results.jld2
├── validation/                      # already exists
│   └── verification_report.txt     # NEW — structured pass/fail report
└── MATHEMATICAL_FORMULATION.md     # unchanged — reference for verification tests
```

---

## Sources

- Direct inspection: `scripts/raman_optimization.jl` (complete read, 641 lines)
- Direct inspection: `scripts/common.jl` (complete read, 399 lines)
- Direct inspection: `scripts/visualization.jl` (header + structure)
- Direct inspection: `scripts/test_optimization.jl` (test patterns, include structure)
- Direct inspection: `results/raman/MATHEMATICAL_FORMULATION.md` (verification test cases already specified)
- Existing run structure: `results/raman/` directory tree confirmed
- v1.0 ARCHITECTURE.md: prior research on visualization organization (not superseded — orthogonal concern)
- Confidence: HIGH — all integration points based on direct code observation, not inference

---
*Architecture research for: v2.0 Verification & Discovery (SMF Gain-Noise)*
*Researched: 2026-03-25*

# Stack Research

**Domain:** Verification, cross-run comparison, parameter sweeps, and pattern detection for Julia nonlinear fiber optics simulation
**Researched:** 2026-03-25
**Confidence:** HIGH

---

## Scope

This document covers only NEW stack additions for the v2.0 milestone. The existing
stack (Julia 1.12, DifferentialEquations.jl, FFTW.jl, Optim.jl, PyPlot.jl, Optim.jl v1.13.3) is validated and unchanged.

---

## Recommended Stack

### Core Technologies (New)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| JLD2.jl | 0.6.3 | Structured run data persistence (phase profiles, costs, fiber params, convergence history) | HDF5-compatible binary format; saves any Julia object including complex arrays with full precision; round-trips Dict{String,Any} exactly; already used by NPZ.jl (same HDF5 backend family); no Python dependency; file-level compression. Preferred over BSON.jl (no compression) and NPZ.jl (NPZ is for numpy arrays only — cannot store nested Dicts or convergence vectors cleanly). |
| JSON3.jl | 1.14.3 | Run manifest files — human-readable metadata index linking run parameters to JLD2 data files | Required for cross-run discovery: grep-able, diff-able, readable in any text editor. Stores the scalar run summary (fiber type, L, P, J_before, J_after, wall_time) separately from the heavy binary data. Lighter and faster than JSON.jl; JSON3 uses StructTypes for zero-allocation parsing. |
| Statistics (stdlib) | 1.11.1 | Pattern detection — mean, std, median, percentile across sweep results | Already in the global environment. Used in visualization.jl already. No new package needed. |
| TOML (stdlib) | bundled with Julia 1.9+ | Optional: sweep configuration files (parameter grids in TOML format) | Julia's standard TOML parser. Cleaner than Julia-syntax config files for parameter grids that non-programmers need to edit. Only use if the parameter sweep is driven by a config file; omit if sweeps are coded directly. |

### Supporting Libraries (No New Additions Needed)

| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| LinearAlgebra (stdlib) | 1.12.0 | norm(), cross-run gradient norms, cosine similarity between phase profiles | Already in project |
| Printf (stdlib) | bundled | Formatted summary tables in run manifests | Already in project |
| FFTW.jl | 1.10.0 | Cross-correlation between optimized phase profiles (pattern detection via FFT-based correlation) | Already in project |
| PyPlot.jl | 2.11.6 | Overlay plots: multiple phase profiles on one axis, cost-vs-iteration comparisons across runs | Already in project — no new plotting library needed |
| NPZ.jl | 0.4.3 | Export selected arrays to numpy for cross-language verification | Already in project — use for exporting field arrays when comparing against reference Python/MATLAB NLSE solvers |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Julia Test stdlib | Verification tests: soliton invariance, energy conservation, Taylor remainder | Already used in test_optimization.jl — extend with physics-verification tests |
| Julia Dates stdlib | Run tagging — `RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMss")` | Already used in raman_optimization.jl |

---

## Installation

```julia
# Add to Project.toml — only JLD2 and JSON3 are new
# Run from the project root:
julia --project -e 'using Pkg; Pkg.add(["JLD2", "JSON3"])'
```

All other capabilities use packages already in `Project.toml` or Julia stdlib.

---

## Architecture of New Capabilities

### Run Data Persistence (JLD2)

Each optimization run saves one JLD2 file alongside the existing PNGs:

```
results/raman/smf28/L1m_P005W/
  opt.png                  # existing
  opt_evolution.png        # existing
  opt_phase.png            # existing
  opt_run.jld2             # NEW — structured binary data
```

The JLD2 file stores:

```julia
# What to save per run
jldsave("opt_run.jld2";
    # Input parameters
    fiber_name = "SMF-28",
    L_m        = 1.0,
    P_cont_W   = 0.05,
    lambda0_nm = 1550.0,
    fwhm_fs    = 185.0,
    Nt         = 8192,
    gamma      = 1.1e-3,
    betas      = [-2.17e-26, 1.2e-40],
    fR         = 0.18,
    # Results
    phi_opt    = φ_after,      # Complex array (Nt, M) — the core result
    J_before   = J_before,
    J_after    = J_after,
    delta_J_dB = ΔJ_dB,
    grad_norm  = grad_norm,
    iterations = result.iterations,
    converged  = Optim.converged(result),
    wall_time_s = elapsed,
    # Diagnostics
    E_conservation   = E_conservation,
    bc_input_frac    = bc_input_frac,
    bc_output_frac   = bc_output_frac,
    run_tag          = RUN_TAG,
)
```

Loading a run for cross-comparison:

```julia
using JLD2
data = load("results/raman/smf28/L1m_P005W/opt_run.jld2")
phi_opt = data["phi_opt"]   # direct key access
J_after = data["J_after"]
```

### Run Manifest (JSON3)

A top-level `results/raman/manifest.json` is appended after each run, enabling fast discovery without loading heavy JLD2 files:

```json
[
  {
    "run_id": "smf28_L1m_P005W_20260325_143201",
    "fiber": "SMF-28",
    "L_m": 1.0,
    "P_cont_W": 0.05,
    "lambda0_nm": 1550.0,
    "J_before_dB": -24.8,
    "J_after_dB": -30.6,
    "delta_J_dB": 5.8,
    "converged": true,
    "iterations": 50,
    "wall_time_s": 47.0,
    "bc_ok": true,
    "jld2_path": "raman/smf28/L1m_P005W/opt_run.jld2"
  }
]
```

JSON3 write pattern:

```julia
using JSON3
entry = (; run_id, fiber_name, L_m, P_cont_W, J_before_dB, J_after_dB, ...)
open("results/raman/manifest.json", "a") do io
    JSON3.write(io, entry)
    write(io, "\n")
end
```

### Cross-Run Comparison (PyPlot only)

No new library needed. Cross-run overlay plots use PyPlot directly:

```julia
# Load multiple runs and overlay phase profiles
runs = [load("results/raman/smf28/L1m_P005W/opt_run.jld2"),
        load("results/raman/smf28/L2m_P030W/opt_run.jld2"),
        load("results/raman/hnlf/L1m_P005W/opt_run.jld2")]

fig, ax = subplots(1, 1, figsize=(6.77, 3.5))
colors = ["#0072B2", "#D55E00", "#009E73"]
for (i, data) in enumerate(runs)
    label = "$(data["fiber_name"]) L=$(data["L_m"])m"
    ax.plot(freq_thz, vec(data["phi_opt"]), color=colors[i], label=label, alpha=0.8)
end
ax.legend(); ax.set_xlabel("Frequency offset [THz]"); ax.set_ylabel("Phase [rad]")
```

### Parameter Sweep Infrastructure (plain Julia, no new packages)

Sweeps are coded as loops over parameter vectors using the existing `run_optimization()` function. Results accumulate in a named tuple array:

```julia
L_sweep = [0.5, 1.0, 2.0, 5.0, 10.0]  # meters
sweep_results = []

for L in L_sweep
    result, uω0, fiber, sim, band_mask, Δf = run_optimization(
        L_fiber=L, P_cont=0.05, max_iter=50,
        save_prefix=joinpath(run_dir("smf28", "sweep_L$(L)m"), "opt")
    )
    push!(sweep_results, (L=L, J_after=Optim.minimum(result),
                          converged=Optim.converged(result)))
end

# Summary plot: J_after vs L
fig, ax = subplots(figsize=(3.31, 2.6))
ax.plot([r.L for r in sweep_results],
        MultiModeNoise.lin_to_dB.([r.J_after for r in sweep_results]),
        "o-", color="#0072B2")
ax.set_xlabel("Fiber length [m]"); ax.set_ylabel("J [dB]")
```

### Pattern Detection (Statistics stdlib + FFTW.jl)

Pattern detection across optimized phase profiles uses:

1. **Phase correlation**: `crosscor(phi1, phi2)` via Statistics.jl — detects if two runs produce shifted versions of the same phase mask
2. **Cosine similarity**: `dot(phi1, phi2) / (norm(phi1) * norm(phi2))` via LinearAlgebra.jl — measures structural similarity independent of scale
3. **FFT-based cross-correlation**: `real(ifft(fft(phi1) .* conj(fft(phi2))))` via FFTW.jl — detects periodic patterns and relative delays between phase profiles

These are 3–5 line computations, no pattern-detection library needed.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| JLD2.jl for run data | BSON.jl | If cross-language compatibility (Python/MATLAB HDF5 readers) is not needed; BSON is simpler but no compression and no HDF5 compat |
| JLD2.jl for run data | NPZ.jl only | NPZ.jl is fine for simple arrays but cannot store nested metadata Dicts or strings without separate files. Use NPZ for field array export to Python only. |
| JLD2.jl for run data | HDF5.jl directly | HDF5.jl is the low-level library JLD2 wraps. Only use directly if you need custom HDF5 group structure or partial I/O. JLD2 is simpler. |
| JSON3.jl for manifests | CSV.jl (already in project) | Use CSV.jl if the manifest is a flat table with no nested structures and you want to open it in Excel. JSON3 is better for flexible metadata with optional fields. |
| JSON3.jl for manifests | TOML.jl | TOML is better for configuration files that users edit manually. JSON3 is better for machine-written run manifests. |
| Plain Julia sweep loops | DrWatson.jl | DrWatson is a full project management framework for scientific simulation projects. Appropriate if the project scales to hundreds of runs with complex naming schemes. For 10–50 runs, it's unnecessary overhead and a new dependency. |
| Statistics stdlib for pattern detection | Clustering.jl / MultivariateStats.jl | Use Clustering.jl if you need k-means or hierarchical clustering across >50 runs. Statistics stdlib handles mean/std/correlation for the current 5-run scale. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Serialization.jl (Julia stdlib serialize/deserialize) | Julia-version locked — .jls files written by Julia 1.11 may be unreadable by Julia 1.12 or 1.13. Cannot be read from Python/MATLAB. | JLD2.jl (HDF5-compatible, version-stable) |
| Arrow.jl / Parquet.jl | Column-oriented tabular formats. Good for millions of rows; unnecessary for 5–50 optimization runs with heterogeneous data types (arrays + scalars + strings). | JSON3.jl manifest + JLD2.jl data |
| DrWatson.jl | Full experiment management framework. Adds complexity (project-specific @produce_or_load macros, naming conventions) before the benefit threshold is reached for a 5-config codebase. | Plain Julia sweep loops + JLD2 + JSON3 |
| DifferentialEquations.jl SciMLBase ensemble API (EnsembleProblem) | Designed for Monte Carlo with identical ODE structure. Our parameter sweeps change fiber parameters between runs (different Dω operators), so EnsembleProblem doesn't apply. | Plain Julia for-loop over run_optimization() |
| Makie.jl / GLMakie / CairoMakie | New visualization dependency. The constraint "no new visualization dependencies" is explicit in the project constraints. All new plots use PyPlot.jl. | PyPlot.jl (already in project) |
| DataFrames.jl for sweep results | DataFrames.jl is already in the project but is heavy for small result tables. Using it for 5–20 sweep results adds unnecessary complexity. | Named tuple arrays + manual Printf.@sprintf tables |

---

## Stack Patterns by Variant

**If sweep has <= 20 parameter combinations:**
- Use a plain Julia for-loop with `run_optimization()`
- Collect results in a `Vector{NamedTuple}`
- Write summary as `@sprintf` table to log and to JSON3 manifest
- No framework needed

**If sweep has > 50 combinations (future):**
- Consider DrWatson.jl `@produce_or_load` for caching
- Consider EnsembleProblem if the ODE structure is fixed across all runs
- This threshold is not reached in v2.0

**If cross-language verification is needed (comparing to MATLAB/Python GNLSE solvers):**
- Export input/output fields as NPZ: `NPZ.npzwrite("field_smf28_L1m.npz", Dict("uω0" => uω0, "uωf" => uωf, "ts" => sim["ts"]))`
- NPZ is already in the project and is readable by NumPy directly
- Do NOT use JLD2 for this — MATLAB/Python cannot read JLD2 without special plugins

**If analytical verification requires comparison against published GNLSE solvers:**
- Export Dω, hRω, γ as NPZ
- Python reference: `gnlse` package (pip install gnlse) or the SCGBookCode Python port
- Comparison is done outside Julia; the Julia side only needs NPZ export

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| JLD2 v0.6.3 | Julia 1.9+ | Confirmed in General registry. HDF5 backend; files are readable by h5py in Python |
| JSON3 v1.14.3 | Julia 1.6+ | Uses StructTypes v1.10+; no conflicts with current deps |
| JLD2 v0.6.3 | NPZ v0.4.3 | No conflict — different file formats |
| Statistics v1.11.1 | Julia 1.9+ | stdlib; always compatible |

---

## Integration Points

### Where in the existing codebase to add JLD2 saves

1. **`run_optimization()` in `scripts/raman_optimization.jl`** (line ~508): Add `jldsave()` call after the run summary `@info` block, just before the plotting section. The JLD2 save is ~10ms and adds no perceptible overhead.

2. **`run_optimization()` in `scripts/amplitude_optimization.jl`**: Same pattern — save after the run summary.

3. **New `scripts/sweep_analysis.jl`**: A new script (not yet existing) that loads the manifest, loads JLD2 files for selected runs, and produces overlay plots and pattern detection tables.

### Where in the existing codebase to add manifest writes

In `run_optimization()`, after the JLD2 save:

```julia
# Append to manifest — create if missing, append if exists
manifest_path = joinpath("results", "raman", "manifest.json")
entry = (run_id = save_prefix * "_" * RUN_TAG,
         fiber  = fiber_name, L_m = fiber["L"],
         J_after_dB = MultiModeNoise.lin_to_dB(J_after),
         jld2   = relative_path_from_manifest_to_jld2)
open(manifest_path, "a") do io; JSON3.write(io, entry); write(io, "\n"); end
```

---

## Sources

- [JLD2.jl GitHub](https://github.com/JuliaIO/JLD2.jl) — HIGH confidence; confirmed v0.6.3 from Julia General registry; HDF5 compatibility documented in README
- [JSON3.jl GitHub](https://github.com/quinnj/JSON3.jl) — HIGH confidence; confirmed v1.14.3 from Julia General registry
- [Julia General Registry (pkg.julialang.org)](https://pkg.julialang.org/) — HIGH confidence; version numbers verified by `julia -e 'using Pkg; Pkg.add(["JLD2","JSON3"])'` on this machine
- Julia stdlib documentation — HIGH confidence; Statistics, TOML, Printf, Dates are bundled with Julia 1.9+; confirmed `pkgversion(Statistics)` = 1.11.1 in this environment
- Project CLAUDE.md and Project.toml — HIGH confidence; existing package versions read directly from the repo
- [DrWatson.jl documentation](https://juliadynamics.github.io/DrWatson.jl/stable/) — MEDIUM confidence (WebSearch); consulted to confirm it would be overkill at current project scale

---

*Stack research for: v2.0 verification, cross-run comparison, parameter sweeps, pattern detection*
*Researched: 2026-03-25*

# Feature Research: v2.0 Verification & Discovery

**Domain:** Correctness verification, cross-run comparison, parameter sweeps, and pattern detection for nonlinear fiber optics simulation and Raman suppression optimization
**Researched:** 2026-03-25
**Confidence:** HIGH for verification methods (established practice), MEDIUM for pattern detection (domain-specific, fewer references), LOW for automated pattern detection (novel/custom territory)

---

## Context: What Already Exists

Before mapping the feature landscape, the following capabilities are already built and should not be rebuilt:

| Already Built | Location |
|---------------|----------|
| Gradient FD check (5 random indices, 1% tolerance) | `test_optimization.jl` (lines 335–357) |
| Gradient FD check for amplitude (3 trials, 5% tolerance) | `test_optimization.jl` (lines 359–384) |
| Energy conservation check (5% tolerance, single forward pass) | `test_optimization.jl` (line 404–412) |
| Boundary energy detection (5% edge threshold) | `benchmark_optimization.jl`, `common.jl` |
| Time window sensitivity analysis (6 window sizes) | `benchmark_optimization.jl` `analyze_time_windows` |
| Chirp sensitivity (GDD and TOD sweeps, 2D sensitivity plot) | `raman_optimization.jl` `chirp_sensitivity` |
| Grid size benchmarking (Nt scaling table) | `benchmark_optimization.jl` `benchmark_grid_sizes` |
| Contract violation tests for all setup functions | `test_optimization.jl` |
| Single-run convergence plot (J vs iteration) | `visualization.jl` |
| Design-by-contract assertions throughout cost pipeline | `raman_optimization.jl`, `common.jl` |

Features below are what is **missing** for v2.0.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features the research group expects a "verified and correct" simulation to demonstrate. Missing these means the pipeline is not trustworthy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Fundamental soliton propagation test (N=1 sech pulse) | Standard NLSE correctness benchmark — N=1 sech pulse propagates without shape change over soliton period; any deviation is numerical error | MEDIUM | Requires choosing β₂ < 0 (anomalous dispersion), γ, and T₀ such that N=1; propagate one z_sol and compare input to output shape; currently no such test |
| Photon number conservation check | Energy is technically not conserved in GNLSE with self-steepening and Raman; photon number is; tracking it flags unphysical results (known issue from IEEE 2021) | MEDIUM | Compute ∫|U(ω)|²/ω dω at input and output; expect <1% drift for typical SMF-28 runs; currently only energy (which drifts more) is checked |
| Adjoint gradient full-grid FD check with Taylor remainder test | Current FD check uses 5 random indices; Taylor remainder (confirm O(ε²) convergence) is stronger — proves the adjoint is correct not just close | MEDIUM | Plot ‖J(φ+εd) - J(φ) - ε⟨∇J,d⟩‖ vs ε; expect slope 2 on log-log; currently not done |
| Cost J verified to match spectral energy ratio by direct integration | J = E_Raman/E_total; should verify the mask computation is correct by computing J both via spectral_band_cost and via direct sum and checking they agree | LOW | Simple direct-computation cross-check; catches mask index bugs |
| Cross-run J summary table (all 5 configs) | After running all 5 optimization configs, need a summary showing J_before, J_after, ΔdB, convergence iterations, wall time in one table | LOW | Currently this information is printed per-run but never aggregated; a researcher reviewing results needs the full table to understand relative performance |
| Overlay convergence plot (all runs on one axes) | Convergence curves from all 5 runs overlaid; shows whether SMF-28 converges faster than HNLF, whether longer fibers need more iterations | MEDIUM | Currently one convergence plot per run; need multi-run overlay in a single figure |
| Overlay spectral comparison (all runs, before vs after) | One panel per fiber type showing all optimized spectra together; reveals which fiber/power combos suppress most | MEDIUM | Currently separate figures per run; no cross-run spectral overlay exists |
| Per-run metadata saved to structured file (not just logs) | JSON/CSV record of {fiber_type, L, P, J_before, J_after, iterations, wall_time, phase_norm} per run | LOW | Enables downstream analysis and plotting; currently only printed to stdout/log |

### Differentiators (Competitive Advantage)

Features that elevate this from "the code works" to "the physics is understood."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Phase shape clustering: is the optimal phase quadratic, soliton-like, or irregular? | Researchers need to know if the optimizer finds a physically interpretable solution (e.g., pre-chirp to counteract SPM) or just numerical noise | HIGH | Project each optimized phase profile onto GDD/TOD basis; compute unexplained residual; if residual << total phase, phase is essentially a polynomial chirp and has physical meaning |
| Parameter sweep: J_final vs (L, P) heatmap grid | Shows the landscape of Raman suppression achievability — is HNLF at 1m x 100W very suppressible? Is SMF-28 at 5m x 200W suppression-limited? | HIGH | Run optimization over a grid of (L, P) pairs for each fiber; plot J_final as a 2D heatmap; computationally expensive but scientifically essential |
| Soliton number N vs suppression quality correlation | N = L_D/L_NL; higher N means more complex nonlinear dynamics; expect correlation between N and J_before (hard problem) and between N and ΔdB (optimization potential) | MEDIUM | Compute N for each run config; plot N vs J_before and N vs ΔdB; a correlation here validates that the optimizer is exploiting known physics |
| Phase shape universality test: do SMF-28 and HNLF at matched N produce similar phase profiles? | If optimal phase shape depends only on N (not fiber parameters), it suggests a universal strategy independent of fiber type | HIGH | Requires designing matched-N runs, then comparing normalized phase profiles; computationally expensive |
| Optimization sensitivity to initial phase (multi-start test) | Show that L-BFGS converges to the same basin from multiple random starts, establishing that the optimization landscape has a well-defined minimum | MEDIUM | Run 5–10 random initial phases; plot all convergence curves and final J values; if variance < 0.5 dB across starts, the minimum is robust. `benchmark_optimization.jl` has `multi_start_optimization` but it's not integrated into the standard run pipeline |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automatic differentiation (AD) to verify adjoint | Seems like a clean replacement for hand-derived adjoint | Julia AD (Zygote/Enzyme) struggles with DifferentialEquations.jl callbacks, pre-allocated buffers, and in-place mutations; would require major refactor with no physics insight gain | Keep the hand-derived adjoint verified by finite differences + Taylor remainder; this is exact and explainable |
| Full parameter grid with dense sampling (e.g., 20×20 L×P) | "More points = better coverage" | Each (L,P) point requires a full optimization run (~50 L-BFGS iterations × forward + adjoint solve); at 50s/run, a 20×20 grid = 55 CPU-hours; wall time on a workstation would be days | Use a coarse 4×4 or 5×4 grid first to find regions of interest, then refine selectively |
| Comparing against other simulators (PyNLO, Luna.jl) | Validates that the simulation is correct | Cross-simulator comparison requires matching all physical parameters, ODE solver tolerances, and interaction-picture conventions exactly; differences often reflect solver configuration, not physics errors; creates maintenance burden | Use analytical solutions (fundamental soliton, photon number) and internal consistency checks instead |
| Automated ML-based pattern detection | Pattern detection over many runs sounds like a differentiator | The current 5 runs are not enough data for clustering or ML methods; PCA on 5 vectors is meaningless; would need 50+ runs | Manual physical projection (GDD, TOD basis decomposition) gives more insight with less data and is directly interpretable |
| Interactive dashboard (web-based or notebook) | Useful for exploratory analysis | PROJECT.md explicitly rules out interactive plots; static PNG/PDF output is the constraint; Jupyter notebooks exist but are not the primary workflow | Well-structured static summary figure that shows all runs together |

---

## Feature Dependencies

```
[Metadata file per run]
    └──required by──> [Cross-run J summary table]
    └──required by──> [Overlay convergence plot]
    └──required by──> [Overlay spectral comparison]
    └──required by──> [Parameter sweep heatmap]
    └──required by──> [Soliton number correlation plot]

[Fundamental soliton test]
    └──validates──> [Photon number conservation check]
    (must pass before trusting photon-number as a metric)

[Taylor remainder gradient test]
    └──supersedes──> existing 5-index FD check
    (does not remove it; adds a stronger assertion on top)

[Parameter sweep L×P grid]
    └──requires──> [Metadata file per run]
    └──enhances──> [Soliton number correlation]
    (sweep generates the data; correlation uses it)

[Phase shape clustering]
    └──requires──> [Metadata file per run]
    (need per-run phase vectors saved, not just J values)
```

### Dependency Notes

- **Metadata file is the prerequisite for everything cross-run:** Every aggregation feature (summary table, convergence overlay, spectral overlay, scatter plots) requires that per-run outputs are written to a structured file, not just printed. This is the single most important infrastructure feature.
- **Fundamental soliton test validates the forward solver before any gradient work:** Run this first in the verification sequence. If the forward solver is wrong, all gradient and optimization tests are suspect.
- **Taylor remainder test is independent** of the soliton test and can run in parallel. It tests the adjoint pipeline, not the ODE propagator.
- **Parameter sweep is computationally expensive** and should only run after the verification tests pass, to avoid running a long sweep with a buggy solver.

---

## MVP Definition

This milestone is a research milestone, not a software product milestone. The MVP is: "I can trust the results and see patterns across runs."

### Launch With (v2.0 core)

These are needed to close the milestone and present results at a lab meeting.

- [ ] **Fundamental soliton propagation test** — without this, the NLSE solver has no known-ground-truth validation
- [ ] **Photon number conservation check** — energy conservation already passes at 5%; photon number is the physically correct invariant for GNLSE with self-steepening + Raman
- [ ] **Taylor remainder gradient test** — stronger than existing FD check; proves adjoint is correct to O(ε²)
- [ ] **Per-run metadata JSON output** — infrastructure prerequisite for all cross-run features
- [ ] **Cross-run J summary table** — human-readable table showing all 5 configs' J_before, J_after, ΔdB, wall time
- [ ] **Overlay convergence plot (all 5 runs)** — single figure showing convergence curves; immediately reveals relative optimization difficulty

### Add After Core Passes (v2.0 extended)

Add once verification passes and core infrastructure is in place.

- [ ] **Overlay spectral comparison** — after core J summary is working, add spectral overlays per fiber type
- [ ] **Phase projection onto GDD/TOD basis** — compute how much of the optimal phase is explainable as a polynomial chirp; report residual
- [ ] **Soliton number N annotation in metadata and summary** — annotate each run with N = sqrt(L_D/L_NL); enables correlation plots without re-running

### Future Consideration (v2.0+, separate planning)

Deferred because computationally expensive or require more runs to be meaningful.

- [ ] **Parameter sweep L×P heatmap** — expensive; requires dedicated compute session; plan separately
- [ ] **Phase universality test at matched N** — requires custom run configs beyond current 5; needs dedicated design
- [ ] **Multi-start robustness analysis** — `multi_start_optimization` exists in `benchmark_optimization.jl` but is not wired to the standard pipeline; activate separately

---

## Feature Prioritization Matrix

| Feature | Research Value | Implementation Cost | Priority |
|---------|----------------|---------------------|----------|
| Fundamental soliton N=1 propagation test | HIGH — ground truth for solver | MEDIUM | P1 |
| Photon number conservation | HIGH — physically correct invariant | MEDIUM | P1 |
| Taylor remainder gradient test | HIGH — proves adjoint correctness | MEDIUM | P1 |
| Per-run metadata JSON | HIGH — enables all cross-run analysis | LOW | P1 |
| Cross-run J summary table | HIGH — lab meeting deliverable | LOW (depends on metadata) | P1 |
| Overlay convergence plot | HIGH — shows optimization landscape | MEDIUM | P1 |
| Overlay spectral comparison | MEDIUM — visual; summary table covers the numbers | MEDIUM | P2 |
| Phase GDD/TOD projection | MEDIUM — physical insight | MEDIUM | P2 |
| Soliton number N annotation | MEDIUM — links physics to optimization | LOW | P2 |
| Parameter sweep L×P heatmap | HIGH eventually — but expensive | HIGH | P3 |
| Phase universality test | HIGH scientifically — but needs design | HIGH | P3 |
| Multi-start robustness | MEDIUM — confidence in optimizer | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v2.0 lab meeting presentation
- P2: Should have, add when P1 is complete
- P3: Future milestone or dedicated compute session

---

## Verification Method Details

### Fundamental Soliton Test

**Physical basis:** For the NLSE without Raman or self-steepening, a hyperbolic secant pulse with
```
N = sqrt(γ P₀ T₀² / |β₂|) = 1
```
is an exact soliton solution. It propagates without shape change over distance z_sol = π/2 · L_D where L_D = T₀²/|β₂|.

**Test protocol:**
1. Use SMF28_beta2_only preset (β₂ only, no β₃, no Raman: fR=0 for this test)
2. Choose T₀ such that N=1 at P_peak (e.g., T₀ = sqrt(γ P₀ / |β₂|))
3. Propagate exactly one soliton period z_sol
4. Compare temporal intensity profile |u(t,z_sol)|² to input |u(t,0)|²
5. Expect: max relative error < 2% for Nt=2^12, time_window > 10×T₀

**Why this catches real bugs:** This test fails if the interaction-picture phase factors (exp_D_p, exp_D_m) are wrong, if the step size is too large, or if FFT normalization is wrong. It cannot fail due to Raman or self-steepening complications.

**Confidence:** HIGH — fundamental soliton is a textbook result (Agrawal, Nonlinear Fiber Optics, Ch.5; gnlse-python validates against this exact test)

### Photon Number Conservation

**Physical basis:** The GNLSE with frequency-dependent nonlinearity (self-steepening) conserves photon number N_ph = ∫|U(ω)|²/ω dω, not energy. Using energy as the conservation test underestimates numerical errors for pulses where self-steepening is significant.

**Test protocol:**
1. Compute N_ph_in = sum(abs2.(uω0) ./ abs.(sim["ωs"] .+ sim["ω0"])) * sim["Δt"]
2. Run forward propagation
3. Compute N_ph_out = sum(abs2.(uωf) ./ abs.(ωs .+ ω0)) * Δt
4. Assert |N_ph_out / N_ph_in - 1| < 0.01 (1% tolerance)

**Confidence:** MEDIUM — photon number conservation in GNLSE is well-established theory (IEEE JLT 2021, Agrawal review 2024), but the tolerance (1% vs 5%) needs empirical calibration on current runs

### Taylor Remainder Test

**Physical basis:** If ∇J is the correct gradient, then J(φ + εd) - J(φ) - ε⟨∇J, d⟩ = O(ε²). Plotting this residual vs ε on a log-log scale should show slope 2 for the second-order term.

**Test protocol:**
1. Pick a random direction d (unit vector in φ-space)
2. Compute J(φ), ∇J at a fixed φ
3. For ε in [1e-6, 1e-2]: compute |J(φ + εd) - J(φ) - ε⟨∇J, d⟩|
4. Assert slope ≈ 2 in the log-log plot for the range ε ∈ [1e-5, 1e-3] (below machine epsilon effects, above truncation effects)
5. This is strictly stronger than the existing 5-index FD check, which only verifies approximate agreement at one ε value

**Expected gradient accuracy:** The current 1% FD tolerance passes with ε=1e-5. The Taylor test with slope 2 proves the adjoint is exact (not just close) to machine precision.

**Confidence:** HIGH — Taylor remainder test is standard PDE-constrained optimization verification practice (Stevens Johnson MIT 18.336 notes; Meep project documentation)

### Cross-Run Metadata JSON Schema

Each run should write a JSON file with this structure:

```json
{
  "run_tag": "RUN_20260325_v7_smf28_L2m",
  "fiber_type": "SMF-28",
  "fiber_preset": "SMF28",
  "L_fiber": 2.0,
  "P_cont": 30.0,
  "lambda0_nm": 1550.0,
  "pulse_fwhm_fs": 185.0,
  "Nt": 16384,
  "time_window_ps": 20.0,
  "soliton_number_N": 2.34,
  "J_before": 0.0234,
  "J_before_dB": -16.3,
  "J_after": 0.0012,
  "J_after_dB": -29.2,
  "delta_dB": -12.9,
  "n_iterations": 47,
  "wall_time_s": 83.2,
  "phase_norm_rad": 4.71,
  "phase_gdd_component_frac": 0.82,
  "convergence_history": [0.0234, 0.019, 0.012, ...]
}
```

This requires adding a metadata-write step at the end of each `run_optimization()` call. The `convergence_history` array enables the overlay convergence plot without re-running.

---

## Sources

- Agrawal, "Nonlinear Fiber Optics," 6th ed. — soliton N=1 propagation, photon number conservation, standard benchmark setups
- Dudley, Genty, Coen. Rev. Mod. Phys. 78, 1135 (2006) — canonical supercontinuum verification benchmark; soliton fission test cases
- gnlse-python (WUST-FOG): [github.com/WUST-FOG/gnlse-python](https://github.com/WUST-FOG/gnlse-python) — example_soliton.html shows soliton test structure; test_nonlinearity.py and test_raman.py show N=3 soliton fission benchmarks
- Luna.jl: [github.com/LupoLab/Luna.jl](https://github.com/LupoLab/Luna.jl) — validates against Dudley 2006 Fig. 3; reference for GNLSE benchmark parameters
- IEEE JLT 2021, "Revisiting Soliton Dynamics Under Strict Photon-Number Conservation": [ieeexplore.ieee.org/document/9309249](https://ieeexplore.ieee.org/document/9309249/) — photon number is the correct invariant for GNLSE with self-steepening; energy alone is insufficient
- Steven G. Johnson, MIT 18.336, "Notes on Adjoint Methods": [math.mit.edu/~stevenj/18.336/adjoint.pdf](https://math.mit.edu/~stevenj/18.336/adjoint.pdf) — Taylor remainder test as standard gradient verification
- cs231n Neural Network notes (Karpathy): gradient check tolerance — relative error > 1e-2 wrong; < 1e-4 ok; step size h=1e-5 typical — [cs231n.github.io](https://cs231n.github.io/neural-networks-3/) — confirmed standard practice
- Meep adjoint gradient inconsistency report: [github.com/NanoComp/meep/issues/1484](https://github.com/NanoComp/meep/issues/1484) — real-world example of adjoint FD discrepancy and how Taylor remainder test pinpoints the source

---

*Feature research for: v2.0 Verification & Discovery, SMF Gain-Noise project*
*Researched: 2026-03-25*

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

---
title: Advisor Meeting Questions — Multimode Extension Direction
date: 2026-04-16
meeting: Today (approx. 1 hour from 2026-04-16 exploration session)
priority: high
purpose: Resolve blockers that determine the shape of multimode Raman suppression optimization
---

# Advisor Meeting Questions (2026-04-16)

Each answer steers a concrete decision in the multimode extension plan. Priority-ordered.

## 1. SLM setup — spectral only, or also spatial?

> Does the Rivera Lab experimental setup have one SLM or two?
>
> - **Spectral SLM (pulse shaper)**: placed in the Fourier plane of a 4f geometry, controls `φ(ω)` of the pulse. This is what generates the spectral phases we optimize. Doesn't touch spatial mode content.
> - **Spatial SLM (mode shaper)**: placed in the beam path near the fiber launch, shapes the spatial wavefront to control which LP modes get excited at the fiber input.

**Why it matters:** determines whether input mode coefficients `{c_m}` are optimization parameters (spatial SLM present) or fixed boundary conditions (only spectral SLM — input is whatever a bare Gaussian beam couples into).

**If spatial SLM present:** unlocks a genuinely novel research question — does jointly optimizing spectral phase + mode content give fundamentally better multimode Raman suppression than phase-only?

## 2. If spatial SLM: phase-only or complex amplitude?

> Is the spatial SLM a standard phase-only LCoS device, or does it support complex (amplitude + phase) modulation?

**Why it matters:** phase-only SLMs can still synthesize any target mode superposition via computer-generated holograms, but with power loss to diffraction orders. Complex-amplitude SLMs are efficient but much rarer. Affects how we parameterize `{c_m}` in the optimizer (unit-norm constraint vs free complex) and how realistic we should be about achievable mode purity.

## 3. What does the current multimode experiment actually launch?

> When you've run multimode fiber experiments in the past, what's the input mode content?
>
> - Controlled superposition tuned via SLM?
> - Fiber-end LP01-matched launch, with LP11/LP21 spillage from imperfect alignment?
> - Something else (e.g., tapered SMF → MMF adiabatic launch)?

**Why it matters:** determines the baseline against which "optimized launch" is compared. If the lab routinely does LP01-only launches, the comparison is "phase-only optimization with LP01 input" vs "phase + mode-coefficient optimization." If launches are already tuned, the comparison is different.

## 4. Multimode cost function target

> When you say "reduce Raman in multimode," what's the intended measurement downstream?
>
> - **(a)** "Suppression across all output modes equally" — cost = sum over modes, `(Σ_m E_band_m) / (Σ_m E_total_m)`
> - **(b)** "Suppression only in the mode being detected" — cost = `E_band_signal / E_total_signal` for a specific output mode
> - **(c)** "Worst-case suppression across modes" — cost = `max_m (E_band_m / E_total_m)` for robustness
> - **(d)** "Detection-weighted" — cost weighted by the actual detection's mode selectivity

**Why it matters:** these give different optima. (b) is natural if the detector is single-mode-selective (LP01 via fiber coupler). (a) is natural if detection is bucket-integrated over a large-area detector. Current single-mode code implicitly uses (b) with M=1.

## 5. Long-fiber scope for multimode

> Phase 12 (suppression-reach) pushed L out to 30 m for SMF-28 and validated that phi@2m maintains -57 dB suppression at 15× the optimization horizon. For multimode, what length scales matter?
>
> - Short (0.5–5 m): quantum-noise squeezer regime
> - Intermediate (5–50 m): the current "suppression reach" regime
> - Long (50+ m): classical / telecom relevance
> - All of the above as a parametric study?

**Why it matters:** affects simulation cost estimates. Longer fibers = more ODE steps per solve = longer Newton iterations. Dictates whether we should target one length or build a length-sweep into the design.

## 6. Any physics constraints we haven't surfaced?

Open-ended question — often where the most useful information comes out:

> Is there any physics (modal walk-off, random mode coupling from fiber imperfections, polarization mixing, Raman-induced mode-specific loss, pump depletion in a cascaded amplifier, etc.) that you want us to account for in the multimode simulation that isn't in the single-mode code?

**Why it matters:** surfaces hidden requirements before they become rework. The current multimode code is "clean" — no random mode coupling, no modal noise, idealized dispersion. If the PI wants any of these effects modeled, better to know now.

## 7. Timeline check

> Given the 4-week remaining window, are there specific deliverables expected from the multimode work (conference abstract, paper figure, group meeting presentation)? What level of result satisfies the sprint goal — "first multimode simulation showing phase-shaped Raman suppression working" vs "parametric study across fiber length / input mode content"?

**Why it matters:** aligns ambition with time. Prevents either over-scoping (attempting a paper-worthy result in 4 weeks) or under-scoping (finishing too early without a follow-on plan).

---

## What I'll do with the answers

Each answer routes to a concrete plan update:
- Q1 (SLM setup) → decides whether `.planning/seeds/launch-condition-optimization.md` becomes an active phase or stays a seed.
- Q2 (SLM type) → affects parameterization in the joint-optimization implementation.
- Q3 (current launch) → sets the baseline simulation configuration.
- Q4 (cost function) → picked as the M>1 cost in the multimode forward/adjoint ODE setup.
- Q5 (fiber length) → determines sweep axes in the benchmark / results plan.
- Q6 (hidden physics) → may add new phases to the roadmap, or at minimum requirements to existing phases.
- Q7 (deliverable) → calibrates the week-by-week plan.

# Professor Nicholas Rivera -- Research Program & Connections to SMF Gain-Noise Project

**Compiled:** 2026-03-31
**Confidence:** HIGH (primary sources: Cornell faculty pages, lab website, publications list, Nature Photonics paper, Cornell Chronicle)

---

## 1. Biography & Career Trajectory

### Current Position
- **Assistant Professor**, School of Applied and Engineering Physics, Cornell University
- Joined Cornell: **July 2025**
- Office: Clark Hall, 142 Sciences Drive, Ithaca, NY 14853
- Contact: nrivera@cornell.edu
- Twitter/X: @NickRivera137

### Education

| Degree | Institution | Years | Details |
|--------|------------|-------|---------|
| **PhD, Physics** | MIT | 2016--2022 | Advisor: Prof. Marin Soljacic. Close collaborators: Prof. John Joannopoulos (MIT), Prof. Ido Kaminer (Technion). Thesis: "Light-Matter Interactions with Photonic Quasiparticles." DOE Computational Science Graduate Fellow (2016--2020), MIT School of Science Dean's Fellow (2020--2022). |
| **BS, Physics** | MIT | 2012--2016 | Undergraduate thesis recognized with the **LeRoy Apker Award** from the American Physical Society (2016) "for important advances in the field of photonics and exceptional leadership of the Society of Physics Students." First major paper published summer 2016: "Shrinking light to allow forbidden transitions on the atomic scale" in *Science*. |

### Postdoctoral Work
- **Junior Fellow**, Harvard Society of Fellows (2022--2025)
- Worked on quantum and nonlinear optics, specifically techniques to understand and control quantum noise dynamics in multimode nonlinear optical systems
- This is where the theoretical and experimental framework for quantum noise in fiber supercontinuum was developed

### Early Life
- Born and raised in New York City
- Attended Stuyvesant High School

### Awards & Honors
| Award | Year | Organization |
|-------|------|-------------|
| LeRoy Apker Award | 2016 | American Physical Society |
| DOE Computational Science Graduate Fellowship | 2016--2020 | US Department of Energy |
| MIT School of Science Dean's Fellowship | 2020--2022 | MIT |
| Andrew M. Lockett III Memorial Prize (thesis award) | 2022 | MIT |
| Junior Fellowship | 2022--2025 | Harvard Society of Fellows |
| Tingye Li Innovation Prize | -- | Optica (CLEO) |

---

## 2. Research Program Overview

The Rivera Lab investigates the **physics of light and matter**, with a strong emphasis on how theory and experiment interact. The lab does both theoretical and experimental work.

### Three Main Research Directions

#### Direction 1: Realizing Quantum States of Light in New Settings
- On-chip quantum light sources
- New wavelengths (UV, X-ray, THz)
- Ultrahigh intensities (TW/cm^2 squeezed light)
- Spatiotemporal entanglement
- **Key result:** Demonstrated intense squeezed light at 0.1 TW/cm^2 from noisy input through nonlinear fiber (Nature Photonics 2025)

#### Direction 2: New Applications of Quantum Light
- Sensitive measurements (interferometry, microscopy, imaging)
- Noiseless or low-noise amplification for optical communications
- Precision metrology

#### Direction 3: New Platforms for Nonlinear Optics
- **Multimode optical fibers** -- directly relevant to this project
- Integrated nanophotonic waveguides
- Driven material systems (phonons)
- Nonlinear photonic crystal cavities for Fock state generation
- Few-photon nonlinearities for non-Gaussian state generation

### Core Physics Vision

From Rivera's AEP seminar abstract (February 2026):

> "Noise presents a fundamental limit to the precision of sensitive measurements made using light. Interactions between photons mediated by nonlinear optical materials allow generating a range of states such as squeezed states and entangled states with nonclassical noise properties, which can extend the sensitivity of a range of instruments such as interferometers, microscopes, and imaging systems."

> "While the prospects for generating such quantum light states should improve as we increase light intensity and enhance interactions between photons, a challenge is that high-intensity light beams tend to have fluctuations far in excess of the value expected if these light beams were in quantum mechanical coherent-states -- making it challenging to produce light with nonclassical noise properties."

The central challenge: **high-intensity nonlinear optics amplifies noise, but quantum correlations can be exploited to decouple output light from dominant noise channels.**

---

## 3. Current Group Members (as of March 2026)

| Name | Role | Background | Contact |
|------|------|-----------|---------|
| **Nicholas Rivera** | PI, Assistant Professor | PhD MIT 2022, Postdoc Harvard 2022--2025 | nrivera@cornell.edu |
| **Dong Beom Kim** | Postdoctoral Associate | PhD University of Illinois Urbana-Champaign 2025 | dk932@cornell.edu |
| **Jay Sun** | Graduate Student (Applied Physics) | BS UC San Diego 2023 | ks2475@cornell.edu |
| **Fadi Farook** | Graduate Student (Applied Physics) | BS University of Toronto 2025 | ff274@cornell.edu |

The lab is actively recruiting, with preference for experimental postdocs in ultrafast or nonlinear optics. Theory candidates with exceptionally strong records are also welcome.

### Key Collaborators (not at Cornell)
| Name | Institution | Role in Rivera's Work |
|------|-----------|----------------------|
| **Marin Soljacic** | MIT | Long-term collaborator, PhD advisor. Co-author on nearly all quantum noise papers. |
| **Jamison Sloan** | MIT | Primary theory collaborator on quantum noise framework for multimode systems. Co-author on spatiotemporal noise control, non-Hermitian topology papers. |
| **Shiekh Zia Uddin** | MIT (now Nokia Bell Labs) | Lead experimentalist on the Nature Photonics 2025 fiber experiment. |
| **Ido Kaminer** | Technion | Long-term collaborator since PhD. Free-electron quantum optics, HHG, entanglement. |
| **Yannick Salamin** | MIT | Co-author on Fock state generation (PNAS 2023) and spatiotemporal noise (2025 submitted). |
| **John D. Joannopoulos** | MIT | Senior collaborator, co-author on many foundational papers. |

---

## 4. Key Publications (Organized by Relevance to This Project)

### Tier 1: Directly Relevant -- Quantum Noise in Nonlinear Fibers

**[P65] "Noise-immune quantum correlations of intense light"**
- Authors: Shiekh Zia Uddin, Nicholas Rivera, Devin Seyler, Jamison Sloan, Yannick Salamin, Charles Roques-Carmes, Shutao Xu, Michelle Sander, Ido Kaminer, and Marin Soljacic
- Journal: *Nature Photonics* 19, 751--757 (2025)
- arXiv: 2311.05535 (submitted Nov 2023, latest revision Mar 2025)
- **THIS IS THE MOST RELEVANT PAPER TO YOUR PROJECT**
- Key findings:
  - Demonstrated intense squeezed light (0.1 TW/cm^2) by propagating a classical, intense, noisy input beam through a nonlinear optical fiber
  - Achieved noise **4 dB below the shot-noise level** by selecting wavelengths whose intensity fluctuations are maximally anticorrelated
  - Used **four-wave mixing** in the fiber to create correlations between different colors of light
  - Applied **programmable spectral filter** to isolate the most stable frequency combinations
  - 30-fold noise reduction from highly noisy amplified laser input
  - Developed a new model extracting quantum noise predictions from classical laser dynamics
  - Demonstrated in the context of **supercontinuum generation by femtosecond pulses in fiber**
  - The noise-immune correlations are generic to many nonlinear systems

**[P73] "Programmable control of the spatiotemporal quantum noise of light"**
- Authors: Jamison Sloan, Michael Horodynski, Shiekh Zia Uddin, Yannick Salamin, Michael Birk, Pavel Sidorenko, Ido Kaminer, Marin Soljacic, and Nicholas Rivera
- arXiv: 2509.03482 (submitted Sep 2025)
- Status: Submitted
- Key findings:
  - Noise buildup in nonlinear **multimode** systems can be strongly suppressed by controlling the **input wavefront**
  - Achieved **12 dB noise reduction** beyond linear attenuation, approaching quantum shot-noise limits
  - System: **multimode optical fibers** with ultrafast pulses
  - Mechanism: Kerr nonlinearity and cross-phase modulation
  - Control method: **Spatial light modulators (SLMs) for wavefront shaping**
  - Identified **cross-phase modulation** as the dominant noise-generation mechanism
  - New theoretical + simulation framework for spatiotemporal quantum noise in highly multimode nonlinear systems

**[P63] "Arresting quantum noise amplification with quantum light injection" / "Ultra-broadband and passive stabilization of ultrafast light sources by quantum light injection"**
- Authors: Nicholas Rivera, Shiekh Zia Uddin, Jamison Sloan, and Marin Soljacic
- Journal: *Nanophotonics* (2025)
- Develops general theory of quantum noise from nonlinear dynamics initiated by many-photon Gaussian quantum states
- Provides guidelines to find the optimal quantum state to inject to maximally suppress noise at the output

### Tier 2: Foundational Theory -- Squeezed States and Nonlinear Quantum Optics

**[P42] "Creating large Fock states and massively squeezed states in optics using systems with nonlinear bound states in the continuum"**
- Authors: Nicholas Rivera, Jamison Sloan, Yannick Salamin, John D. Joannopoulos, and Marin Soljacic
- Journal: *PNAS* 120, e2219208120 (2023)
- Theoretical proposal for creating macroscopic Fock states and massively squeezed states using photonic crystal cavities with Kerr nonlinear media
- Nonlinear BIC creates effectively infinite Q-factor, enabling extreme squeezing

**[P60] "Driven-dissipative phases and dynamics in non-Markovian nonlinear photonics"**
- Authors: Jamison Sloan, Nicholas Rivera, and Marin Soljacic
- Journal: *Optica* 11, 1437--1444 (2024)
- Non-Markovian cavities enable >15 dB squeezing (vs 3 dB Markovian limit)
- Deterministic Fock state generation protocol at optical frequencies

**[P50] "Intense squeezed light from lasers with sharply nonlinear gain at optical frequencies"**
- Authors: Linh Nguyen, Jamison Sloan, Nicholas Rivera, and Marin Soljacic
- Journal: *Physical Review Letters* (2023)

**[P68] "Strong intensity noise condensation using nonlinear dispersive loss in semiconductor lasers"**
- Authors: Sahil Pontula et al.
- Journal: *Nanophotonics* (2025)

**[P72] "Noise immunity in quantum optical systems through non-Hermitian topology"**
- Authors: Jamison Sloan, Sachin Vaidya, Nicholas Rivera, and Marin Soljacic
- arXiv: 2503.11620 (March 2025)
- Non-Hermitian topology leads to complete immunity of certain system parts to excess noise through non-reciprocity

### Tier 3: Nanophotonics and Light-Matter Interactions

**[P27] "Light-matter interactions with photonic quasiparticles"**
- Authors: Nicholas Rivera and Ido Kaminer
- Journal: *Nature Reviews Physics* (2020) -- Review article
- Comprehensive review of how engineered photonic structures modify fundamental light-matter interactions

**[P1] "Shrinking light to allow forbidden transitions on the atomic scale"**
- Authors: Nicholas Rivera, Ido Kaminer, Bo Zhen, John D. Joannopoulos, and Marin Soljacic
- Journal: *Science* 353, 263--269 (2016)
- Rivera's first major paper -- showed that photonic quasiparticles (plasmons) can enable normally forbidden atomic transitions

**[P37] "A general framework for scintillation in nanophotonics"**
- Authors: Charles Roques-Carmes, Nicholas Rivera et al.
- Journal: *Science* (2022)
- Nanophotonic enhancement of scintillator emission by 10x

### Publication Statistics
- **73 publications** (69 published + 4 submitted as of March 2026)
- **8 US patents/provisional patents**
- Publications in: *Science* (3), *Nature Physics* (3), *Nature Photonics* (2), *Nature Reviews Physics* (1), *Nature Communications* (2), *PNAS* (3), *Physical Review Letters* (7+), *Physical Review X* (2), among others
- Google Scholar: ~4,084 citations (as of search date)

---

## 5. Connection to the SMF Gain-Noise Project

### Direct Relevance Map

| Rivera Research Theme | This Project's Focus | Connection |
|----------------------|---------------------|------------|
| Quantum noise in nonlinear fiber propagation | Forward propagation solver (GMMNLSE with Kerr + Raman) | The simulation engine in this project solves the *same equations* Rivera's group uses, but at the classical level. Rivera's quantum noise theory builds on top of the classical nonlinear dynamics. |
| Spectral correlations from four-wave mixing in fibers | Spectral phase optimization to suppress Raman band energy | Four-wave mixing (FWM) and stimulated Raman scattering (SRS) compete in fiber propagation. This project's optimizer reshapes the input spectral phase to minimize energy transfer to the Raman band -- Rivera's theory explains the *quantum noise* properties of this same process. |
| Noise-immune quantum correlations via spectral filtering | Spectral band cost function (E_band / E_total) | The `spectral_band_cost` function in this project measures energy in a spectral band. Rivera's experiments use programmable spectral filters to select frequency combinations with minimal noise -- both involve spectral selection after nonlinear propagation. |
| Input wavefront shaping to suppress noise in multimode fibers | Spectral phase shaping (phi optimization via adjoint method) | Rivera's latest work (arXiv 2509.03482) shows that shaping the *spatial* wavefront of input light suppresses quantum noise in multimode fibers. This project shapes the *spectral phase* of input light to suppress Raman energy transfer in single-mode fibers. Same conceptual approach (input shaping), different domain (space vs frequency). |
| Supercontinuum generation as test case | Raman suppression in fiber propagation | Rivera's Nature Photonics paper uses supercontinuum generation as the primary experimental system. Supercontinuum is driven by the same Kerr + Raman nonlinearities that this project simulates. |
| Cross-phase modulation as dominant noise mechanism | Kerr nonlinearity in the simulation | Rivera identifies XPM as the dominant noise-generation mechanism in multimode fibers. This project models the full Kerr tensor including self- and cross-phase modulation. |

### The Big Picture: Where This Project Fits in Rivera's Vision

Rivera's research program asks: **How can we exploit nonlinear optics to create quantum states of light (squeezed, entangled, Fock states) from classical high-power laser sources?**

This project addresses a prerequisite step: **understanding and controlling the classical nonlinear dynamics** (Raman scattering, four-wave mixing, self-phase modulation) in optical fibers. Specifically:

1. **Classical optimization grounds quantum noise theory.** Rivera's quantum noise predictions rely on understanding the classical dynamics first. The linearized quantum fluctuation equations are built *around* the classical solution. This project's forward solver computes exactly that classical solution.

2. **Raman suppression is noise suppression.** Stimulated Raman scattering is one of the primary noise sources in fiber supercontinuum generation. Suppressing Raman energy transfer via spectral phase shaping directly reduces one of the dominant noise channels that Rivera's group studies.

3. **Adjoint-method optimization is the classical analog of quantum state optimization.** This project uses the adjoint method to find optimal spectral phases. Rivera's group uses a quantum-mechanical version of the same idea to find optimal input quantum states (e.g., the "quantum light injection" paper).

4. **Parameter space exploration feeds experimental design.** The sweep infrastructure (fiber lengths x powers x fiber types) maps the landscape of Raman suppression efficiency. This informs which experimental configurations are worth pursuing for quantum noise experiments.

### Raman Scattering in Rivera's Framework

While Rivera does not have papers specifically titled "Raman suppression," Raman scattering plays a critical role in his research:

- **In supercontinuum generation:** Raman scattering is one of the two primary nonlinear processes (alongside four-wave mixing from Kerr effect) driving spectral broadening. It is also a major noise source because it couples optical modes to thermal phonon modes.
- **In quantum noise theory:** Raman scattering introduces noise through coupling to the phonon bath (which is at thermal equilibrium). This is qualitatively different from Kerr-effect noise (which preserves photon number). Rivera's work identifies "noise-immune correlations" that are robust against *both* noise sources.
- **In multimode fibers:** Cross-phase modulation (a Kerr effect) is identified as the dominant noise mechanism, but Raman scattering provides an additional incoherent noise floor.

---

## 6. Funding

### Known Funding Sources (from the Nature Photonics 2025 paper acknowledgments)
- Swiss National Science Foundation
- U.S. Department of Defense
- Army Research Office
- (Additional sources not fully extracted)

### NSF Awards
No NSF awards were found for Nicholas Rivera at Cornell as of March 2026. This is consistent with him having started in July 2025 -- NSF awards for new faculty typically take 1--2 years to appear. He likely has proposals pending or recently funded that are not yet in the public database.

---

## 7. Talks and Seminars

| Event | Date | Title | Key Content |
|-------|------|-------|-------------|
| AEP Faculty Candidate Seminar | Jan 18, 2024 | (Research overview) | Nanophotonic scintillation enhancement; new low-noise regime in supercontinuum; deterministic Fock state generation |
| LASSP/AEP Seminar | Feb 2026 | "Controlling the Spatiotemporal Quantum Noise of Light" | Full overview of noise suppression techniques: spectral filtering for shot-noise-limited light from noisy inputs; spatial phase modulation in multimode fibers; few-photon nonlinearities for non-Gaussian states |

---

## 8. Intellectual Themes and Research Style

### Theoretical Framework First, Then Experiment
Rivera's publications show a consistent pattern: develop a theoretical prediction (often with Jamison Sloan), then validate experimentally (often with Shiekh Zia Uddin). The theory papers precede the experimental results by 1--3 years.

### Classical-to-Quantum Bridge
A distinctive feature of Rivera's approach is building quantum predictions from classical dynamics. The quantum noise model developed for the Nature Photonics paper extracts quantum noise predictions from classical laser dynamics simulations. This is exactly the same simulation approach used in this project.

### Multimode as a Resource, Not a Nuisance
Traditional quantum optics focuses on single-mode systems. Rivera's program treats the multimode nature of fibers (spatial modes, spectral modes) as a *resource* for quantum state engineering rather than a complication to be avoided.

### Input Shaping as Control
Rather than engineering the fiber or nonlinear medium, Rivera's approach controls the *input* light (spectral phase, spatial wavefront, quantum state) to achieve desired output properties. This aligns directly with this project's optimization approach.

---

## 9. Research Nanophotonics Arm

In addition to fiber/quantum optics, Rivera's lab has a nanophotonics research direction:

- **Photonic quasiparticles** (plasmons, polaritons) for enhanced light-matter interactions
- **Nanophotonic scintillators** (10x enhancement of X-ray/electron detection)
- **Ultra-compact lasers** based on new gain media
- **Quantum light sources** from nanophotonic structures in compact form factors
- **Nonlinear enhancement** through nanophotonic confinement

This arm is less directly connected to the smf-gain-noise project but represents the broader lab context.

---

## 10. Key Takeaways for the PhD Student

1. **Your simulation work is foundational to Rivera's quantum noise theory.** The classical NLSE solver you are building is the starting point from which quantum fluctuation equations are linearized. Getting the classical dynamics right (which is what the dB/linear fix, adjoint verification, and sweep infrastructure accomplish) is a prerequisite for the quantum theory.

2. **Raman suppression via spectral phase shaping is directly connected to quantum noise suppression.** Rivera's Nature Photonics paper shows that spectral correlations from four-wave mixing create noise-immune channels. Your optimizer finds spectral phases that suppress Raman energy transfer -- these two problems share the same underlying physics.

3. **The adjoint method you use has a quantum analog.** The adjoint equation for computing gradients of a cost functional is mathematically related to the backward propagation of quantum fluctuations. Understanding the classical adjoint deeply prepares you for the quantum formulation.

4. **Parameter space maps are experimentally valuable.** Your sweep infrastructure (L x P heatmaps) identifies which fiber configurations give the best Raman suppression. These are the configurations where Rivera's group would want to conduct quantum noise experiments.

5. **The lab is young and building.** Rivera started in July 2025 with one postdoc and two graduate students. As an early member of the group, your contributions to the simulation infrastructure will be foundational for the lab's computational capabilities.

6. **Both theory and experiment matter.** Rivera explicitly states that "the interaction between theory and experiment is a basic feature of our work." Your simulation work bridges both -- it provides theoretical predictions that guide experiments.

---

## Sources

### Primary (HIGH confidence)
- [Rivera Lab Website](https://sites.coecis.cornell.edu/rivera/) -- bio, publications, members, openings
- [Rivera Lab Nonlinear and Quantum Optics Research Page](https://rivera.aep.cornell.edu/nonlinear-and-quantum-optics/)
- [Rivera Lab Nanophotonics Research Page](https://rivera.aep.cornell.edu/nanophotonics/)
- [Rivera Lab Members Page](https://sites.coecis.cornell.edu/rivera/members/)
- [Rivera Lab Publications Page](https://sites.coecis.cornell.edu/rivera/publications/) -- complete list of 73 papers + 8 patents
- [Cornell Engineering Faculty Profile](https://www.engineering.cornell.edu/people/nicholas-rivera/)
- [Cornell Duffield Profile](https://www.duffield.cornell.edu/people/nicholas-rivera/)
- [Nature Photonics: Noise-immune quantum correlations of intense light](https://www.nature.com/articles/s41566-025-01677-2)
- [arXiv 2509.03482: Programmable control of spatiotemporal quantum noise](https://arxiv.org/abs/2509.03482)
- [arXiv 2311.05535: Noise-immune quantum correlations (preprint)](https://arxiv.org/abs/2311.05535)
- [arXiv 2503.11620: Noise immunity through non-Hermitian topology](https://arxiv.org/abs/2503.11620)

### Secondary (MEDIUM confidence)
- [Cornell Chronicle: New technique turns noisy lasers into quantum light](https://news.cornell.edu/stories/2025/05/new-technique-turns-noisy-lasers-quantum-light)
- [Phys.org coverage of Nature Photonics paper](https://phys.org/news/2025-05-technique-noisy-lasers-quantum.html)
- [MIT News: Shining a light on the quantum world (2020 profile)](https://news.mit.edu/2020/shining-light-quantum-world-nicholas-rivera-0727)
- [APS Award: LeRoy Apker Award 2016](https://www.aps.org/programs/honors/prizes/prizerecipient.cfm?last_nm=Rivera&first_nm=Nick&year=2016)
- [Google Scholar Profile](https://scholar.google.com/citations?user=DTfZcM0AAAAJ&hl=en)
- [Cornell AEP Seminar Event Page](https://events.cornell.edu/event/lasspaep-seminar-nicholas-rivera-cornell-aep)
- [AEP Faculty Candidate Seminar Event Page](https://events.cornell.edu/event/aep_faculty_candidate_seminar_-_dr_nicholas_rivera)

### Tertiary (LOW confidence -- not independently verified)
- NSF award search returned no results for Rivera at Cornell (expected given July 2025 start date)
- Funding sources from Nature Photonics acknowledgments (partial extraction)