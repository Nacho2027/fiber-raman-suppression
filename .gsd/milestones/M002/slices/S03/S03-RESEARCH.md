# Phase 6: Cross-Run Comparison and Pattern Analysis - Research

**Researched:** 2026-03-25
**Domain:** Julia/PyPlot visualization, JLD2 data loading, polynomial phase decomposition, soliton physics
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 — Run Generation:** Phase 6 includes re-running all 5 production configs as its first step. The comparison script is self-contained — it calls `raman_optimization.jl` (which now saves JLD2 + manifest via Phase 5) to generate data, then loads and analyzes it. No manual user intervention needed.

**D-02 — Summary Table:** Cross-run summary table rendered as a PNG figure via matplotlib (same quality as other plots, presentation-ready). Columns: fiber type, L, P, J_before, J_after, ΔdB, iterations, wall time, soliton number N. Saved to `results/images/`. No markdown file — keep output consistent with existing visualization pipeline.

**D-03 — Overlay Plot Design:** Produce both views:
- All-runs convergence overlay: Single figure, all 5 runs on shared axes, J vs iteration, color-coded by config with clear legend. Shows relative optimization difficulty.
- Per-fiber spectral overlays: Separate SMF-28 and HNLF figures, each showing optimized output spectra on shared dB axes. Enables within-fiber-type comparison of length/power effects.
- Total: 3 overlay figures (1 convergence + 2 spectral).
- Color scheme: Use distinguishable colors per config (not COLOR_INPUT/COLOR_OUTPUT which are for single-run before/after). Suggest a 5-color palette from Okabe-Ito extended set.

**D-04 — Phase Decomposition:** Claude's discretion on decomposition method. Recommended approach: least-squares polynomial fit of φ_opt(ω) up to 3rd order in the signal-bearing spectral region. Report GDD coefficient (fs²), TOD coefficient (fs³), and residual fraction (1 - R² or norm ratio). If residual is small, the optimizer found a physically interpretable chirp. If residual is large, the phase has non-polynomial structure worth investigating.

**D-05 — Soliton Number:** Compute N = √(γ × P_peak × T₀² / |β₂|) for each run. Add to manifest.json and include in the summary table figure. T₀ = FWHM / (2 × acosh(√2)) for sech pulse assumption.

### Claude's Discretion

- Script organization: whether to create one `scripts/run_comparison.jl` or split into multiple files
- Exact color palette for the 5-config overlay
- Phase decomposition method details (polynomial fit vs Taylor expansion)
- Whether to include convergence history in the summary table figure or keep it separate
- Figure sizes and DPI (follow existing 300 DPI convention)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| XRUN-02 | Summary table aggregates all runs showing J_before, J_after, delta-dB, iterations, wall time in one view | matplotlib table API (`ax.table()`); all fields present in manifest.json; soliton N computed from JLD2 fields |
| XRUN-03 | Overlay convergence plot shows all runs' J vs iteration on a single figure | `convergence_history` array stored in JLD2 as `Optim.f_trace(result)`; load via `JLD2.load()` |
| XRUN-04 | Overlay spectral comparison shows all optimized spectra per fiber type on shared axes | `uomega0` + `phi_opt` in JLD2 enable re-propagation; `_spectral_signal_xlim` for shared axis limits |
| PATT-01 | Each optimized phase profile is decomposed onto GDD/TOD polynomial basis with residual fraction reported | `phi_opt` in JLD2; `band_mask` for signal region; least-squares `\` in Julia; `LinearAlgebra` stdlib |
| PATT-02 | Soliton number N annotated in metadata and summary table for each run | Formula N = √(γ × P₀ × T₀² / |β₂|); all required fields (`gamma`, `betas`, `P_cont_W`, `fwhm_fs`) in JLD2 |

</phase_requirements>

---

## Summary

Phase 6 builds the cross-run comparison and pattern analysis layer on top of the Phase 5 serialization infrastructure. The central challenge is that the 5 optimization configs use **heterogeneous grids** (Nt=2^13 or 2^14, time_window=10-30 ps), which means spectral overlays require normalization rather than direct J comparison, and phase overlays require offset removal before plotting.

The data pipeline is: (1) re-run all 5 configs via `raman_optimization.jl` to generate `.jld2` files in the existing per-run directories and update `manifest.json`, then (2) load via `JLD2.load()` and `JSON3.read()`, then (3) produce 4 output figures (1 summary table PNG, 1 convergence overlay, 2 spectral overlays) plus PATT annotations. No new dependencies are needed — JLD2, JSON3, PyPlot, and LinearAlgebra are all already in the project.

The soliton number computation and polynomial phase decomposition are pure Julia arithmetic on already-loaded data; they do not require re-propagation. Spectral overlays require one forward propagation per run (apply `phi_opt` to `uomega0`, propagate) to get the optimized output spectra, since the output field is not saved in JLD2 (only the input field and optimal phase are stored).

**Primary recommendation:** Create a single `scripts/run_comparison.jl` that (1) triggers re-runs via `include("raman_optimization.jl")`, (2) discovers JLD2 files from manifest.json, (3) produces all 4 figures. Keep all new visualization functions inside `visualization.jl` following the existing pattern.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JLD2.jl | (project compat) | Load `_result.jld2` files | Already in project; Phase 5 writes these files |
| JSON3.jl | (project compat) | Load `manifest.json` | Already in project; Phase 5 writes the manifest |
| PyPlot.jl | (project compat) | All visualization (table PNG, overlays) | Project constraint — no new viz deps |
| LinearAlgebra | stdlib | Least-squares polynomial fit (`\` operator, `qr`) | Already imported everywhere; needed for PATT-01 |
| Statistics | stdlib | `mean()` for phase normalization | Already imported in visualization.jl |

### No New Dependencies
This phase requires zero new Julia packages. All required functionality is already available:
- `JLD2.load(path)` returns a Dict with all saved fields
- `JSON3.read(str, Vector{Dict{String,Any}})` loads the manifest
- `ax.table()` in matplotlib renders a summary table as a figure
- `\` (backslash operator) in Julia solves least-squares systems

### Verified Field Names in JLD2 (from Phase 5 code, lines 485-521)
```julia
# These fields are guaranteed to exist in each _result.jld2
data = JLD2.load(jld2_path)
data["fiber_name"]        # String: "SMF-28" or "HNLF"
data["L_m"]               # Float64: fiber length in meters
data["P_cont_W"]          # Float64: peak power in Watts
data["lambda0_nm"]        # Float64: center wavelength in nm
data["fwhm_fs"]           # Float64: pulse FWHM in femtoseconds
data["gamma"]             # Float64: nonlinear coefficient W⁻¹m⁻¹
data["betas"]             # Vector{Float64}: [β₂, β₃, ...] in SI units
data["Nt"]                # Int: grid size
data["time_window_ps"]    # Float64: time window in ps
data["J_before"]          # Float64: cost before optimization
data["J_after"]           # Float64: cost after optimization
data["delta_J_dB"]        # Float64: improvement in dB
data["converged"]         # Bool: Optim.converged()
data["iterations"]        # Int: number of L-BFGS iterations
data["wall_time_s"]       # Float64: elapsed time in seconds
data["convergence_history"] # Vector{Float64}: f_trace from Optim
data["phi_opt"]           # Matrix{Float64}: optimal phase, shape (Nt, M)
data["uomega0"]           # Matrix{ComplexF64}: input field, shape (Nt, M)
data["band_mask"]         # Vector{Bool}: Raman band mask, length Nt
data["sim_Dt"]            # Float64: time step Δt in seconds
data["sim_omega0"]        # Float64: center angular frequency ω₀
```

### Verified Fields in manifest.json (from Phase 5 code, lines 525-544)
```julia
# Each manifest entry has:
entry["fiber_name"], entry["L_m"], entry["P_cont_W"]
entry["J_before"], entry["J_before_dB"], entry["J_after"], entry["J_after_dB"]
entry["delta_J_dB"], entry["converged"], entry["iterations"], entry["wall_time_s"]
entry["Nt"], entry["time_window_ps"], entry["grad_norm"], entry["E_conservation"]
entry["bc_ok"], entry["result_file"]   # result_file is the path to the JLD2
```

**Note:** `soliton_number_N` is NOT yet in the manifest. Phase 6 must compute it from JLD2 fields and add it.

---

## Architecture Patterns

### Recommended Script Organization

One new script, one visualization function group addition:

```
scripts/
├── run_comparison.jl          # NEW: Phase 6 entry point
├── raman_optimization.jl      # EXISTING: called by run_comparison.jl to generate JLD2s
├── visualization.jl           # EXISTING: add new comparison plot functions here
└── common.jl                  # EXISTING: no changes needed
```

**Single-file rationale:** With only 5 runs and 4 output figures, splitting into multiple scripts adds include-chain complexity with no benefit. `run_comparison.jl` is self-contained.

### Pattern 1: JLD2 File Discovery via Manifest

```julia
# Source: Phase 5 manifest.json structure (lines 546-570 raman_optimization.jl)
manifest_path = joinpath("results", "raman", "manifest.json")
manifest = JSON3.read(read(manifest_path, String), Vector{Dict{String,Any}})

# Discover all JLD2 paths from manifest
runs = []
for entry in manifest
    jld2_path = entry["result_file"]
    if isfile(jld2_path)
        data = JLD2.load(jld2_path)
        push!(runs, merge(Dict(entry), data))
    else
        @warn "JLD2 file missing for manifest entry" result_file=jld2_path
    end
end
```

### Pattern 2: Soliton Number Computation

```julia
# D-05: N = sqrt(gamma * P_peak * T0^2 / |beta2|)
# T0 = FWHM / (2 * acosh(sqrt(2))) for sech^2 pulse assumption
# Units: gamma [W^-1 m^-1], P [W], T0 [s], beta2 [s^2/m]
function compute_soliton_number(gamma_Wm, P_peak_W, fwhm_fs, beta2_s2m)
    T0_s = (fwhm_fs * 1e-15) / (2 * acosh(sqrt(2)))
    N_sq = gamma_Wm * P_peak_W * T0_s^2 / abs(beta2_s2m)
    return sqrt(N_sq)
end

# For each run:
beta2 = data["betas"][1]   # first element is β₂ [s²/m]
gamma = data["gamma"]       # W⁻¹m⁻¹
P0    = data["P_cont_W"]    # Watts
fwhm  = data["fwhm_fs"]     # femtoseconds
N = compute_soliton_number(gamma, P0, fwhm, beta2)
```

**Expected N values** (from CONTEXT.md comments in raman_optimization.jl):
- Run 1: SMF-28 L=1m P=0.05W → N~2.3
- Run 2: SMF-28 L=2m P=0.30W → N~5.6
- Run 3: HNLF L=1m P=0.05W → N~6.9
- Run 4: HNLF L=2m P=0.05W → N~4.9
- Run 5: SMF-28 L=5m P=0.15W → N depends on betas

### Pattern 3: Polynomial Phase Decomposition (PATT-01)

The optimal phase is defined on the full frequency grid. The polynomial fit must be restricted to the signal-bearing region (where the optimizer actually shaped the phase) and must remove global offset and linear term first (Pitfall 4).

```julia
# PATT-01: Least-squares polynomial fit of phi_opt over signal band
# Step 1: Build signal-band mask from spectral power (mirror of BUG-03 fix)
function decompose_phase_polynomial(phi_opt, uomega0, sim)
    # phi_opt shape: (Nt, M) — use mode 1 ([:, 1])
    # Build signal mask at -40 dB threshold (matches BUG-03 fix in visualization.jl)
    spec_power = abs2.(fftshift(uomega0[:, 1]))
    P_peak = maximum(spec_power)
    dB = 10 .* log10.(spec_power ./ P_peak .+ 1e-30)
    signal_mask = dB .> -40.0   # Bool vector, length Nt

    # Angular frequency grid (fftshifted)
    Nt = sim["Nt"]
    Δt = sim["Δt"]    # in seconds (sim_Dt from JLD2)
    dω = 2π * fftshift(fftfreq(Nt, 1 / Δt))[2]  # rad/s per bin
    ω_shifted = 2π .* fftshift(fftfreq(Nt, 1 / Δt))  # rad/s

    # Extract signal-band phase
    phi_shifted = fftshift(phi_opt[:, 1])
    phi_signal = phi_shifted[signal_mask]
    ω_signal = ω_shifted[signal_mask]

    # Step 2: Remove global offset and linear term (group delay normalization)
    # Fit 1st-order polynomial: phi = a0 + a1*ω (offset + group delay)
    A_linear = hcat(ones(length(ω_signal)), ω_signal)
    coeffs_linear = A_linear \ phi_signal
    phi_detrended = phi_signal .- (coeffs_linear[1] .+ coeffs_linear[2] .* ω_signal)

    # Step 3: Fit 2nd+3rd order polynomial to detrended phase
    # phi_residual ≈ gdd_coeff * ω^2 / 2 + tod_coeff * ω^3 / 6
    A_poly = hcat(ω_signal.^2 ./ 2, ω_signal.^3 ./ 6)
    coeffs_poly = A_poly \ phi_detrended

    gdd_coeff_s2 = coeffs_poly[1]   # in rad·s²  (GDD)
    tod_coeff_s3 = coeffs_poly[2]   # in rad·s³  (TOD)

    # Convert to standard units: GDD [fs²], TOD [fs³]
    gdd_fs2 = gdd_coeff_s2 * 1e30   # 1 s² = 1e30 fs²
    tod_fs3 = tod_coeff_s3 * 1e45   # 1 s³ = 1e45 fs³

    # Residual fraction: norm(actual - polynomial fit) / norm(actual)
    phi_poly_fit = A_poly * coeffs_poly
    residual_fraction = norm(phi_detrended .- phi_poly_fit) / (norm(phi_detrended) + 1e-30)

    return (gdd_fs2=gdd_fs2, tod_fs3=tod_fs3, residual_fraction=residual_fraction)
end
```

**Unit check:** The simulation grid uses `Δt` in seconds (from `sim["Δt"]`). The JLD2 field `sim_Dt` stores this value. `ω_shifted` will be in rad/s. GDD = d²φ/dω² in rad·s², converted to fs² by multiplying by 1e30.

### Pattern 4: Matplotlib Summary Table PNG

```python
# matplotlib table via PyCall — ax.table() renders a grid
fig, ax = subplots(figsize=(14, 4))
ax.axis("off")
columns = ["Config", "L (m)", "P (W)", "J_before (dB)", "J_after (dB)",
           "ΔdB", "Iterations", "Time (s)", "N_soliton"]
cell_text = [...]   # rows × columns list of strings
table = ax.table(cellText=cell_text, colLabels=columns,
                 loc="center", cellLoc="center")
table.auto_set_font_size(False)
table.set_fontsize(10)
table.scale(1, 2)  # row height multiplier
fig.savefig("results/images/cross_run_summary_table.png",
            dpi=300, bbox_inches="tight")
```

**Note:** matplotlib's `ax.table()` returns a `Table` object that supports per-cell color via `table[row, col].set_facecolor(color)`. Use light green for J_after < -20 dB (good Raman suppression) and no fill otherwise — avoids green/red colorblindness trap.

### Pattern 5: Spectral Overlay (XRUN-04)

The overlay requires re-propagating each run's shaped input field. This is the same operation done inside `plot_optimization_result_v2` for each column.

```julia
# For each run in a fiber-type group:
function compute_optimized_spectrum(data, sim_reconstructed)
    uomega0 = data["uomega0"]           # (Nt, M) complex
    phi_opt = data["phi_opt"]           # (Nt, M) real
    uomega0_shaped = @. uomega0 * cis(phi_opt)
    fiber = reconstruct_fiber(data)     # build fiber dict from JLD2 fields
    fiber["zsave"] = [0.0, data["L_m"]]
    sol = MultiModeNoise.solve_disp_mmf(uomega0_shaped, fiber, sim_reconstructed)
    uomega_out = sol["uω_z"][end, :, :]
    return uomega_out
end
```

**Critical:** Each run has a different `sim` dict (different Nt, Δt). You cannot use one shared `sim` for all runs. Build a `sim` per run from the JLD2 fields (`sim_Dt`, `sim_omega0`, `Nt`, `time_window_ps`). Use `get_disp_sim_params` or build manually from the stored values.

**Grid heterogeneity fact:** The 5 runs use:
- Run 1: Nt=2^13, time_window=10 ps
- Run 2: Nt=2^13, time_window=20 ps
- Run 3: Nt=2^14, time_window=15 ps
- Run 4: Nt=2^14, time_window=30 ps
- Run 5: Nt=2^13, time_window=30 ps

For spectral overlays, the wavelength axis differs between runs. Plot on a shared wavelength axis by interpolating to a common grid, or use `xlim` to show the common physical range and let each trace use its native grid. The second approach (native grids, shared xlim) is simpler and avoids interpolation artifacts.

### Pattern 6: Convergence Overlay (XRUN-03)

```julia
# convergence_history is Vector{Float64} of J values (linear, not dB)
# Convert to dB for the overlay, since dB is more readable for Raman suppression
fig, ax = subplots(figsize=(8, 5))
for (i, run) in enumerate(runs)
    J_history_dB = MultiModeNoise.lin_to_dB.(run["convergence_history"])
    iterations = 1:length(J_history_dB)
    ax.plot(iterations, J_history_dB, color=COLORS_5[i], label=run_label(run), lw=1.5)
end
ax.set_xlabel("Iteration")
ax.set_ylabel("J [dB]")
ax.legend()
```

### Recommended 5-Color Palette (D-03)

Okabe-Ito extended set (colorblind-safe, distinguishable at 300 DPI print):
```julia
const COLORS_5_RUNS = [
    "#0072B2",   # blue       — Run 1: SMF-28 L=1m
    "#E69F00",   # orange     — Run 2: SMF-28 L=2m
    "#009E73",   # green      — Run 3: HNLF L=1m
    "#CC79A7",   # pink/purple — Run 4: HNLF L=2m
    "#56B4E9",   # sky blue   — Run 5: SMF-28 L=5m
]
```
These are all from the canonical Okabe-Ito set already referenced in CLAUDE.md. They avoid the existing `COLOR_INPUT` (#0072B2 = blue) and `COLOR_OUTPUT` (#D55E00 = vermillion) confusion since those are for single-run before/after. Run 1 coincidentally maps to #0072B2, but in a multi-run figure the label "Run 1: SMF-28 L=1m" provides disambiguation.

### Anti-Patterns to Avoid

- **Avoid:** Comparing J values across runs without noting that they use different `band_mask` windows (different Nt/time_window → different spectral resolution). The summary table should display J values, but include a footnote: "J values not directly comparable across runs due to grid differences."
- **Avoid:** Calling `plot_optimization_result_v2()` inside the comparison loop. Each call re-runs the ODE solver twice; for 5 runs, that is 10 full ODE solves just for display. The comparison script should be output-focused, not re-using per-run diagnostic plots.
- **Avoid:** Overlaying phase profiles without removing global offset and linear term (Pitfall 4 — documented in PITFALLS.md lines 97-124).
- **Avoid:** Using warm-start from a previous run's `phi_opt` when re-running. The point of Phase 6 is to generate clean JLD2 files from a single self-contained run; warm-starting would make the comparison depend on execution order.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Polynomial least-squares fit | Custom Vandermonde + Gaussian elimination | Julia `\` backslash operator on `hcat(ω^2, ω^3)` | `\` calls LAPACK dgelsd; robust to ill-conditioning; available via LinearAlgebra stdlib |
| Convergence history extraction | Re-run optimization to collect J values | Load `convergence_history` from JLD2 (already stored by Phase 5) | Saves ~30s per run; history was saved by `Optim.f_trace(result)` |
| Summary table rendering | Custom grid of `ax.text()` calls | `ax.table()` matplotlib API | Handles cell sizing, borders, color; manual text placement breaks on font size changes |
| Grid frequency axis from JLD2 | Re-construct from scratch | Compute from `sim_Dt` and `Nt` stored in JLD2 | `fftshift(fftfreq(Nt, 1/Δt))` fully recovers the grid |
| Output field for spectral overlay | Load output field (not saved in JLD2) | Apply `phi_opt` to `uomega0`, then call `solve_disp_mmf` | Only `uomega0` and `phi_opt` are in JLD2; one propagation per run is necessary and fast (~3s each) |

---

## Common Pitfalls

### Pitfall 1: Phase Ambiguity in Cross-Run Overlay
**What goes wrong:** Overlaying `phi_opt` curves from 5 runs without removing global offset and linear group delay term produces visually random-looking curves even when runs are physically similar. L-BFGS finds the closest minimum from zero-phase init, which can differ by a constant or linear term across runs.
**Why it happens:** The optimal J is invariant to `phi + C` and `phi + alpha*omega`. Different runs converge to different representatives.
**How to avoid:** Before any phase overlay: (1) subtract `mean(phi[signal_mask])`, (2) fit and subtract a linear polynomial over `signal_mask`. Documented in PITFALLS.md Pitfall 4.
**Warning signs:** Phase curves look like independent noise even for nearly identical configs (e.g., Run 1 vs Run 5, both SMF-28).

### Pitfall 2: Heterogeneous Grids Break Direct J Comparison
**What goes wrong:** The 5 production runs use different Nt and time_window values, giving different spectral resolutions and band_mask windows. J values are not directly comparable across runs.
**Why it happens:** `band_mask` is derived from `raman_threshold` applied to the FFT frequency grid; different grids → different number of bins in the Raman band.
**How to avoid:** Add a footnote to the summary table: "J values use run-specific band masks (Nt/time_window vary). See individual run PNGs for per-run context." Do NOT assert grid compatibility for the comparison script — these runs are intentionally heterogeneous.
**Warning signs:** Run 3 (Nt=2^14) shows much lower J_before than Run 1 (Nt=2^13) with same fiber length — this may be grid resolution, not physics.

### Pitfall 3: Re-Run Order Sensitivity
**What goes wrong:** `run_comparison.jl` calls `raman_optimization.jl` via `include()`. If `raman_optimization.jl` uses `if abspath(PROGRAM_FILE) == @__FILE__` guard, the guard will NOT fire when included — the heavy runs in section 10 will not execute.
**Why it happens:** The `PROGRAM_FILE` guard is specifically designed to prevent execution on `include`. The comparison script cannot trigger the runs by simply including the file.
**How to avoid:** Instead of including the optimization script, the comparison script should invoke the runs directly using the `run_optimization()` function (which is defined in the non-guarded section). Call `run_optimization(...)` for each of the 5 configs directly inside `run_comparison.jl`. Import/include just the function definitions, not the guarded main block.
**Warning signs:** `run_comparison.jl` includes `raman_optimization.jl` but JLD2 files are never written — the guard prevented execution.

### Pitfall 4: Fiber Reconstruction for Re-Propagation
**What goes wrong:** `solve_disp_mmf` requires a full `fiber` Dict including `Dω` (dispersion operator array, shape Nt), `γ` (4D tensor), `hRω` (Raman response array), `L`, `zsave`. Only scalars (`gamma`, `betas`, `L_m`) are saved in JLD2, not the pre-computed arrays.
**Why it happens:** The JLD2 save block (lines 494-496) stores `gamma=fiber["γ"][1]` (scalar) and `betas=...` but not the full `Dω` or `hRω` arrays (too large).
**How to avoid:** For spectral overlays, reconstruct the full fiber dict using `get_disp_fiber_params_user_defined()` from `src/helpers/helpers.jl`, passing the scalars recovered from JLD2. Also reconstruct `sim` using `get_disp_sim_params()`. The `setup_raman_problem()` function in `common.jl` does this — call it with the run's parameters.
**Warning signs:** `KeyError: "Dω"` when calling `solve_disp_mmf` with a partially-reconstructed fiber dict.

### Pitfall 5: betas Array Indexing for Soliton Number
**What goes wrong:** `data["betas"]` is saved as `haskey(fiber, "betas") ? fiber["betas"] : Float64[]`. The fiber dict in `raman_optimization.jl` may not have a "betas" key (it could use the pre-computed `Dω` instead). If betas is empty, soliton N cannot be computed directly.
**Why it happens:** The fiber dict building path via `get_disp_fiber_params_user_defined` takes `betas_user` as a kwarg; if the fiber was built differently, no "betas" key exists.
**How to avoid:** For the 5 production configs, the betas are hardcoded constants: `SMF28_BETAS = [-2.17e-26, 1.2e-40]` and `HNLF_BETAS = [-0.5e-26, 1.0e-40]`. If `data["betas"]` is empty, fall back to the fiber_name-based lookup using these constants. Add a guard: `beta2 = isempty(data["betas"]) ? FIBER_BETA2_LOOKUP[data["fiber_name"]] : data["betas"][1]`.
**Warning signs:** Empty `betas` field in JLD2 causes `N = sqrt(NaN)`.

### Pitfall 6: convergence_history Units
**What goes wrong:** `convergence_history = Optim.f_trace(result)` stores the value of the objective that Optim.jl actually minimizes. In `run_optimization()`, the objective passed to Optim is `only_fg!` which returns linear J (not dB) — verify this.
**Why it happens:** The dB transformation `lin_to_dB(J)` is applied in the callback for display but `only_fg!` returns linear J. However, it's worth verifying that `f_trace` does not capture the callback output.
**How to avoid:** In the convergence overlay, check `minimum(run["convergence_history"])` matches `run["J_after"]` (both should be linear J values). If they match, the overlay is in linear J; convert to dB for the figure via `lin_to_dB.()`.

---

## Code Examples

### Complete Soliton Number Function
```julia
# Source: D-05 decision + physics formula from Agrawal "Nonlinear Fiber Optics"
# N = sqrt(gamma * P0 * T0^2 / |beta2|)
# T0 = FWHM / (2 * acosh(sqrt(2))) for sech^2 pulse
function compute_soliton_number(gamma_Wm::Float64, P0_W::Float64,
                                 fwhm_fs::Float64, beta2_s2m::Float64)
    T0_s = (fwhm_fs * 1e-15) / (2.0 * acosh(sqrt(2.0)))
    N_sq = gamma_Wm * P0_W * T0_s^2 / abs(beta2_s2m)
    return sqrt(max(N_sq, 0.0))
end
# acosh(sqrt(2)) ≈ 0.8814 — standard result for sech^2 FWHM to T0 conversion
```

### Manifest Discovery and Loading Pattern
```julia
# Source: Phase 5 manifest structure + JLD2 API
manifest_path = joinpath("results", "raman", "manifest.json")
@assert isfile(manifest_path) "Run raman_optimization.jl first to generate JLD2 files"
manifest = JSON3.read(read(manifest_path, String), Vector{Dict{String,Any}})
all_run_data = Dict{String,Any}[]
for entry in manifest
    jld2_path = entry["result_file"]
    if !isfile(jld2_path)
        @warn "Missing JLD2 file" path=jld2_path
        continue
    end
    data = merge(Dict{String,Any}(entry), JLD2.load(jld2_path))
    push!(all_run_data, data)
end
@info "Loaded $(length(all_run_data)) runs from manifest"
```

### Manifest Soliton Number Update
```julia
# Add N to manifest after computing from JLD2 data
for (i, entry) in enumerate(manifest)
    data = JLD2.load(entry["result_file"])
    betas = data["betas"]
    beta2 = isempty(betas) ? -2.17e-26 : betas[1]  # fallback to SMF28 value
    N = compute_soliton_number(data["gamma"], data["P_cont_W"],
                                data["fwhm_fs"], beta2)
    manifest[i]["soliton_number_N"] = N
end
open(manifest_path, "w") do io
    JSON3.pretty(io, manifest)
end
```

### Phase Normalization Before Overlay
```julia
# Source: PITFALLS.md Pitfall 4 — remove offset + group delay before comparing
function normalize_phase_for_comparison(phi_opt, uomega0, sim_Dt, Nt)
    spec_power = abs2.(fftshift(uomega0[:, 1]))
    P_peak = maximum(spec_power)
    dB = 10 .* log10.(spec_power ./ P_peak .+ 1e-30)
    signal_mask = dB .> -40.0

    phi_shifted = fftshift(phi_opt[:, 1])
    ω = 2π .* fftshift(fftfreq(Nt, 1 / sim_Dt))  # rad/s

    phi_signal = phi_shifted[signal_mask]
    ω_signal = ω[signal_mask]

    A = hcat(ones(length(ω_signal)), ω_signal)
    coeffs = A \ phi_signal
    phi_normalized = phi_shifted .- (coeffs[1] .+ coeffs[2] .* ω)
    return phi_normalized, signal_mask
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual print-based run summaries | JSON manifest + JLD2 per run | Phase 5 | Enables automated cross-run loading without re-running |
| Per-run plots only | Overlay figures + summary table | Phase 6 | First view that shows relative performance across all configs |

---

## Open Questions

1. **Whether `Optim.f_trace` captures linear J or the Optim-internal objective**
   - What we know: `only_fg!` returns linear J (from `cost_and_gradient`); Optim minimizes this
   - What's unclear: Does `f_trace` capture `only_fg!`'s return value or an internal transformed value?
   - Recommendation: In Wave 0 or early in implementation, print `minimum(convergence_history)` and compare to `J_after` from the JLD2 — if they match, convergence_history is in linear J. If not, investigate.

2. **Whether `sim_Dt` in JLD2 is in seconds or picoseconds**
   - What we know: JLD2 save line is `sim_Dt = sim["Δt"]`; the sim dict stores `Δt` in seconds (the `get_disp_sim_params` function uses SI units throughout per CLAUDE.md conventions)
   - What's unclear: One `sim` key uses ps internally for some derived quantities
   - Recommendation: Verify by checking `sim["Δt"]` scale: for `time_window=10 ps` and `Nt=2^13`, `Δt = 10e-12 / 8192 ≈ 1.2e-15 s`. If `sim_Dt` is ~1e-15, it's in seconds. If ~1e-3, it's in ps.

3. **Whether spectral overlay requires actual re-propagation or just the input shaped spectrum**
   - What we know: XRUN-04 says "optimized spectra" — the output spectrum after propagation with phi_opt
   - What's unclear: Would showing `|uomega0 * exp(i*phi_opt)|^2` (shaped input, no propagation) be sufficient for comparison purposes?
   - Recommendation: Per D-03 ("Per-fiber spectral overlays: each showing optimized output spectra"), the intent is output spectra. Re-propagation is required. This is 5 ODE solves (~15-30s total wall time) — acceptable.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| JLD2.jl | Load result files | Verified | project compat | — |
| JSON3.jl | Load manifest | Verified | project compat | — |
| PyPlot.jl | All visualization | Verified | project compat | — |
| LinearAlgebra | Polynomial fit | Verified | stdlib | — |
| JLD2 result files | XRUN-02/03/04 | NOT PRESENT | — | Must generate by re-running raman_optimization.jl |
| manifest.json | Run discovery | NOT PRESENT | — | Must generate by re-running |

**Missing dependencies with no fallback:**
- JLD2 result files and manifest.json do not yet exist. Phase 6 Wave 0 must execute `raman_optimization.jl` to generate them before any comparison plots can be produced. This is D-01 (locked decision).

**Missing dependencies with fallback:**
- None identified beyond the JLD2/manifest gap.

---

## Project Constraints (from CLAUDE.md)

- **Tech stack:** Must stay in Julia + PyPlot. No new visualization dependencies. All new functionality must fit within existing PyPlot/matplotlib API.
- **Function signatures:** Keep same naming conventions — `snake_case` for new functions, `_` prefix for private helpers.
- **Output format:** PNG at 300 DPI. `savefig.dpi = 300`, `bbox_inches="tight"` (already set in global rcParams).
- **Output location:** `results/images/` for comparison figures (already established by `mkpath("results/images")` in raman_optimization.jl).
- **Include guards:** New visualization functions go in `visualization.jl` which already has `_VISUALIZATION_JL_LOADED` guard. No new guard needed.
- **Section headers:** Use `# N. Section Title` pattern with `# ─────` separator lines.
- **Physics variables:** Unicode symbols for physics quantities (`ω`, `β₂`, `γ`, `φ`).
- **Comments:** Explain WHY, not WHAT. Units always stated.
- **Error handling:** `@assert` for preconditions, `@warn` for recoverable issues, no try/catch in numerical code.
- **GSD workflow:** All changes must go through `/gsd:execute-phase`, not direct edits.

---

## Sources

### Primary (HIGH confidence)
- `scripts/raman_optimization.jl` lines 481-570 — exact JLD2 field names and manifest schema (direct code audit)
- `scripts/raman_optimization.jl` lines 604-735 — all 5 production run configs with exact parameters (direct code audit)
- `scripts/visualization.jl` lines 1-260 — existing plot patterns, rcParams, color constants, helper functions (direct code audit)
- `.planning/research/PITFALLS.md` lines 97-124 — phase ambiguity pitfall and normalization protocol (project research)
- `.planning/research/PITFALLS.md` lines 68-93 — grid mismatch pitfall for cross-run comparison (project research)
- `.planning/phases/06-cross-run-comparison-and-pattern-analysis/06-CONTEXT.md` — all locked decisions D-01 through D-05

### Secondary (MEDIUM confidence)
- Agrawal, "Nonlinear Fiber Optics" — soliton number formula N = √(γP₀T₀²/|β₂|), T₀ = FWHM/(2 acosh(√2))
- matplotlib table documentation (`ax.table()`) — standard API for grid tables in figures

### Tertiary (LOW confidence)
- None — all critical claims verified from direct codebase audit or locked decisions

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified in Project.toml and existing scripts
- JLD2 field names: HIGH — direct audit of Phase 5 save block (lines 485-521)
- Architecture: HIGH — follows established patterns from visualization.jl and common.jl
- Soliton formula: HIGH — standard textbook formula (Agrawal); expected N values match script comments
- Polynomial decomposition: HIGH — standard least-squares, verified against existing `compute_gdd` pattern in visualization.jl
- Grid heterogeneity: HIGH — read directly from the 5 run configs in raman_optimization.jl

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (stable domain — no fast-moving dependencies)