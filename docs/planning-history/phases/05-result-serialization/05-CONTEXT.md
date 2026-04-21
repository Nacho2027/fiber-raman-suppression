# Phase 5: Result Serialization - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Add structured data persistence to `run_optimization()` so every optimization run saves its results to disk. Downstream phases (6, 7) load these files for cross-run comparison and parameter sweeps. Does NOT modify the optimization algorithm, add new run configs, or create comparison plots.

</domain>

<decisions>
## Implementation Decisions

### Serialization Format
- **D-01:** Use JLD2.jl for binary result files. NPZ is already in the project but cannot cleanly store Julia NamedTuples, Dicts, or string metadata. JLD2 round-trips native Julia types (complex arrays, Dicts, NamedTuples) and produces HDF5-compatible files. Requires `Pkg.add("JLD2")` — the only new dependency for this phase.

### Data Scope Per Run
- **D-02:** Each run saves: scalars (J_before, J_after, ΔJ_dB, grad_norm, wall_time, E_conservation, Nt, time_window), φ_opt (optimized spectral phase, shape Nt×M), convergence_history (J per iteration), uω0 (input field for re-propagation in Phase 6), run_meta NamedTuple (fiber_name, L, P, λ0, fwhm), and converged flag. Do NOT save full evolution solution (100 z-slices × Nt × M) — too large and can be recomputed from uω0 + φ_opt. Expected size: ~256 KB per run at Nt=2^14.

### Manifest Structure
- **D-03:** Single `results/raman/manifest.json` listing all runs with scalar summaries (fiber_type, L, P, J_before, J_after, delta_dB, wall_time, converged, result_file path). Each run also gets a `{save_prefix}_result.jld2` file next to its existing PNGs in the same directory. The manifest is what Phase 6 loads first to discover available runs.

### Convergence History
- **D-04:** Use Optim.jl's built-in `store_trace=true` option and `Optim.f_trace(result)` to extract J values per iteration. No custom callback needed. Pass `store_trace=true` to `optimize()` inside `optimize_spectral_phase` and extract the trace from the returned result object.

### Claude's Discretion
- Whether to also save band_mask and sim Dict fields in the JLD2 (useful for Phase 6 re-propagation but increases file size slightly)
- Exact JSON schema field names and formatting
- Whether manifest.json is pretty-printed or compact
- Error handling if JLD2 write fails (likely just @warn and continue)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core Implementation Target
- `scripts/raman_optimization.jl` (lines 368-507) — `run_optimization()` function. This is where JLD2 save and manifest update must be added. Read the full function to understand available variables (J_before, J_after, φ_after, run_meta, elapsed, etc.)
- `scripts/raman_optimization.jl` (lines 400-403) — `optimize_spectral_phase` call site where `store_trace=true` must be threaded through
- `scripts/common.jl` — `setup_raman_problem`, `FIBER_PRESETS`, `spectral_band_cost`

### Optimization Interface
- `scripts/raman_optimization.jl` — `optimize_spectral_phase` function definition (find it). Must add `store_trace=true` to the `Optim.Options()` call and return the trace alongside the result.

### Research
- `.planning/research/STACK.md` — JLD2.jl v0.6.3 recommendation and integration pattern
- `.planning/research/FEATURES.md` — Cross-run metadata JSON schema (lines 213-242)
- `.planning/research/ARCHITECTURE.md` — Serialization integration points

### Phase 4 Findings
- `results/raman/validation/verification_20260325_173537.md` — Photon number drift data. Phase 5 should save photon_number_drift as a field so Phase 7 can check it per sweep point.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `run_meta` NamedTuple (line 378-384) — already has fiber_name, L_m, P_cont_W, lambda0_nm, fwhm_fs. Can be saved directly to JLD2.
- `result` from `optimize_spectral_phase` — Optim.jl result object. `Optim.f_trace(result)` gives convergence history if `store_trace=true`.
- `save_prefix` kwarg (line 368) — already used for PNG paths. JLD2 file should use same prefix: `"$(save_prefix)_result.jld2"`.
- `elapsed` variable (line 437) — wall time already computed.
- All scalar summary values (J_before, J_after, ΔJ_dB, grad_norm, E_conservation) computed at lines 409-431.

### Established Patterns
- `using NPZ` already in project for cross-section data — JLD2 follows same `using JLD2; save("file.jld2", "key", value)` pattern
- Results go to `results/raman/` directory, PNGs named `{save_prefix}.png`, `{save_prefix}_evolution.png`, `{save_prefix}_phase.png`
- `run_optimization` returns `(result, uω0, fiber, sim, band_mask, Δf)` — signature must NOT change per XRUN-01 success criterion

### Integration Points
- JLD2 save goes after the run summary `@info` block (line 440-472) and before the plotting section (line 478)
- Manifest update goes at the very end of `run_optimization`, before the return statement
- `Project.toml` needs JLD2 added to [deps]
- `using JLD2` added at top of `raman_optimization.jl` (or in `common.jl` if shared)

</code_context>

<specifics>
## Specific Ideas

- Save `Optim.converged(result)` as a boolean `converged` field — Phase 7 needs this to tag non-converged sweep points
- Include `Nt` and `time_window_ps` in the JLD2 so Phase 6 can verify grid compatibility before overlaying runs
- The manifest should be append-safe: read existing manifest, add/update entry, write back. Multiple runs in sequence should accumulate in one manifest.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-result-serialization*
*Context gathered: 2026-03-25*
