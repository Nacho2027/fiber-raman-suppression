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
