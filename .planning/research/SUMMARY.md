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
