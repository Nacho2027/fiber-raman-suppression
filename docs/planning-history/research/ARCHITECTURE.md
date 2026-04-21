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
