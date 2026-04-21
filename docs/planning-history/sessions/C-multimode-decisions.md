# Session C — Multimode Raman Suppression: Autonomous Decisions

**Date:** 2026-04-17
**Session:** sessions/C-multimode
**Worktree:** /home/ignaciojlizama/raman-wt-C
**Scope:** Extend Raman suppression to M=6 multimode fibers; explore launch conditions / length generalization / fiber-type sensitivity.

---

## Context gathered

### Codebase state (already in place, no mods needed)

- `src/simulation/simulate_disp_mmf.jl` — GMMNLSE forward ODE with full 4D Kerr tensor γ[i,j,k,l] via @tullio contractions. Works at arbitrary M.
- `src/simulation/sensitivity_disp_mmf.jl` — adjoint ODE for any M. Gradient of J w.r.t. ũ(ω, 0) is returned.
- `src/simulation/fibers.jl::get_params()` — builds GRIN dispersion + Kerr tensor from (radius, core_NA, alpha, M). Uses Arpack eigensolver + Sellmeier for silica.
- `scripts/raman_optimization.jl::cost_and_gradient` — the chain rule `∂J/∂φ = 2·Re(conj(λ₀)·i·uω0_shaped)` already works at any M on the spectral phase φ of shape (Nt, M). The M=1 setup is wired through `setup_raman_problem`, but the machinery past that point is M-agnostic.
- `scripts/common.jl::spectral_band_cost(uωf, band_mask)` — cost already sums over all modes via `sum(abs2.(uωf))`, so `J = E_band / E_total` generalizes trivially to M>1. No modification needed.

### What is missing (the session's work)

1. A GRIN MMF preset library (sits outside `FIBER_PRESETS`, which is SMF-only by docstring contract).
2. A setup helper that builds the M=6 fiber dict via `get_params` (not `get_disp_fiber_params_user_defined`, which is the SMF bypass).
3. An entry-point script `scripts/mmf_raman_optimization.jl`.
4. A cost-variant module `src/mmf_cost.jl` that exposes sum-over-modes, worst-mode, and fundamental-only variants.
5. Numerical correctness checks: energy conservation at M=6 and M=1-limit reduction.
6. Per-mode figures distinct from the SMF output.

### Literature anchors (drawn from RIVERA_RESEARCH.md + web search 2026-04-17)

- **Rivera arXiv:2509.03482 (2025)** "Programmable control of the spatiotemporal quantum noise of light" — shows that shaping the spatial input wavefront of a MMF reduces output quantum noise by 12 dB. Identifies XPM as the dominant noise mechanism in MMF supercontinuum. *Implication: launch-condition optimization (option (a)) is the directly Rivera-connected free-exploration thread.*
- **Renninger & Wise (Cornell, 2013+)** multimode soliton physics — MM solitons form via compensation of chromatic and modal dispersion. Raman-induced SSFS leads to soliton fission that preferentially ends up in the fundamental mode. *Implication: at longer fibers + higher N_sol, a large fraction of the Raman-shifted spectrum ends up in LP01, making the sum-over-modes cost and the LP01-only cost diverge. Important to track both.*
- **Wright, Ziegler et al. (2020)** "Kerr self-cleaning" in GRIN fibers — Kerr redirects energy toward low-order modes. Raman then preferentially grows on low-order modes. *Implication: asymmetry between input mode content and output mode content — input wavefront optimization is a legitimate control knob separate from spectral phase.*
- **Real-time mode dynamics (ScienceDirect 2025)** — in GRIN Raman fiber lasers, first-six-mode weights fluctuate by 40% near the Raman threshold. *Implication: noise/stability of per-mode Raman energy is a real experimental concern; a robust cost should not be brittle to small input-mode-coefficient perturbations.*

---

## Decisions

### D1. Baseline cost function at M=6

**Choice:** Sum-over-modes `J = (Σ_m E_band_m) / (Σ_m E_total_m)`.

**Rationale:**
- The spectrum measured by an integrating detector at the fiber output is mode-insensitive; it aggregates over all modes. The sum-over-modes fraction is the direct experimental observable.
- `scripts/common.jl::spectral_band_cost` already implements exactly this when given a (Nt, M) field, so M=1 and M=6 use literally the same function. This is the simplest physically-correct choice.
- Phase 14 explored sharpness on top of J (not a replacement for J). My session's baseline stays with vanilla J at M=6 — Phase 14's sharpness-aware variant is M=1-only and out of scope.

**Variants exposed in `src/mmf_cost.jl` for exploration:**
- `mmf_cost_sum`        — the baseline above
- `mmf_cost_fundamental` — `E_band_LP01 / E_total_LP01` (what the fundamental sees alone)
- `mmf_cost_worst_mode` — `max_m (E_band_m / E_total_m)` (robustness / pessimistic)

### D2. Initial input mode content

**Choice:** `c_m = (0.95, 0.20, 0.20, 0.05, 0.05, 0.02)` (un-normalized) then normalized. LP01-dominant with controlled LP11a/b and LP21a/b content, LP02 residual.

**Rationale:**
- Pure LP01 launch is the boring default and misses the MMF point. Pure uniform `c_m = 1/√M` is unphysically clean.
- The chosen content matches a typical "good free-space coupling through a 50-μm OM4 fiber into a fundamentally-dominated but imperfect launch" — representative of experimental reality per Renninger/Wise.
- It sets up the (a) exploration (joint φ + c_m optimization) with headroom: LP11/LP21 are small-but-nonzero, so the optimizer has something to work with.

The coefficient vector is exposed as `MMF_DEFAULT_MODE_WEIGHTS` in `scripts/mmf_fiber_presets.jl`. All tests and baselines pass it explicitly.

### D3. Fiber preset at M=6

**Choice:** `:GRIN_50` — standard OM4-like graded-index fiber.

```
radius        = 25.0  μm        (50-μm core diameter, OM4 standard)
core_NA       = 0.2              (standard for OM4)
alpha         = 2.0              (parabolic profile)
n2            = 2.3e-20 m²/W     (silica; baked into fibers.jl)
nx            = 101              (spatial grid for mode solver)
spatial_window = 80.0 μm         (3.2× core radius — captures cladding decay)
M             = 6                (LP01, LP11a, LP11b, LP21a, LP21b, LP02)
β_order       = 2                (β₂ sufficient for 185 fs pulses at 1550 nm)
fR            = 0.18             (same Raman fraction as SMF-28)
```

**Rationale:**
- 50-μm core GRIN is the workhorse of the multimode-fiber-nonlinearity literature (Wright, Krupa, Renninger). Picking a standard fiber means the results are comparable to published work.
- `β_order=2` is fine for Raman suppression at femtosecond scale — TOD matters for supercontinuum bandwidth but not for the Raman peak at 13 THz.
- `nx=101, spatial_window=80μm` gives reasonable eigenmode accuracy (checked against an `nx=151` run at the end of numerical-correctness task).

Secondary preset for the free-exploration (c): `:STEP_9` — step-index 9-μm few-mode fiber (4 modes). Included for fiber-type sensitivity comparison.

### D4. Target fiber lengths for first sweep

**Choice:** `[0.5, 1.0, 2.0, 5.0]` meters.

**Rationale:**
- Matches CLAUDE.md's per-session prompt default.
- Spans a factor of 10 in L — enough to resolve the onset of Raman-dominated regime and cross it.
- At L=5 m, 185-fs sech² at 0.2 W average power gives N_sol ≈ 3 for the fundamental — this is inside the Renninger/Wise soliton-fission regime. Good physics contrast vs L=0.5 m where we're still dispersion-limited.
- Kept the same grid as the SMF sweep (phases 11-12) so M=1-limit runs are directly comparable.

### D5. Baseline run point

L = 1 m, P_cont = 0.05 W (same as SMF canonical for direct comparison), pulse_fwhm = 185 fs, sech².

### D6. Free-exploration pick

**Pick (a):** Joint phase + {c_m} optimization at M=6, L=1m, GRIN-50.

**Rationale:**
- Directly activates `.planning/seeds/launch-condition-optimization.md` (per prompt).
- Cleanest Rivera-Lab connection: their most recent (2025) MMF paper shows input wavefront shaping reduces noise by 12 dB. This is the classical precursor experiment.
- Mathematically tractable: adding `c_m` as optimization variables means lifting the input from `uω0 = pulse * ones(M)/√M` to `uω0 = pulse * c_m`, then optimizing φ ∈ ℝ^(Nt) (shared across modes, realizable) and `c_m ∈ ℂ^M` (with |c|=1). The chain rule falls out from the existing adjoint.
- (b) and (c) become seeds: `.planning/seeds/mmf-phi-opt-length-generalization.md` and `.planning/seeds/mmf-fiber-type-comparison.md`.

### D7. Physical realizability constraint

**Shared-across-modes spectral phase:** φ is shape `(Nt,)` NOT `(Nt, M)` — the SLM applies the same φ(ω) to every mode. Expansion to (Nt, M) happens only inside the cost function via broadcast.

**Rationale:** Per-mode spectral phase is NOT physically realizable with a single pulse shaper (prompt constraint). Shaping before the MMF launch applies one phase to all mode content.

**Implementation:** `cost_and_gradient_mmf` takes φ::Vector{Float64} of length Nt, broadcasts to (Nt, M) before multiplying by `uω0`, and reduces the adjoint gradient via `sum(∂J/∂φ_expanded, dims=2)` before returning.

### D8. What stays SMF

Nothing in `scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/sharpness_optimization.jl`, or `src/simulation/*.jl` changes. The MMF path is a separate file tree under `scripts/mmf_*.jl` + `src/mmf_*.jl`. M=1-limit check calls `scripts/common.jl::setup_raman_problem` directly for the reference.

---

## Execution outline

Planned as Phase 16 "Multimode Raman Suppression Baseline":
1. `scripts/mmf_fiber_presets.jl` — GRIN_50, STEP_9, default mode weights.
2. `scripts/mmf_setup.jl` — build sim/fiber dicts for GRIN via `get_params`; wrap band mask + initial state.
3. `src/mmf_cost.jl` — cost variants (sum, fundamental, worst-mode).
4. `scripts/mmf_raman_optimization.jl` — cost_and_gradient_mmf, optimize_mmf_phase entry point, figures.
5. Numerical correctness: energy conservation <1e-4 relative, M=1-limit check within 0.1 rad.
6. Baseline M=6 run: L=1m, P=0.05W, 30 L-BFGS iters, save JLD2 + figures.
7. Free exploration (a): joint φ + {c_m} optimization at same config, comparison vs phase-only.
8. Seeds planted for (b) and (c).

All runs on the burst VM per CLAUDE.md Rule 1. Julia launched with `-t auto`. `deepcopy(fiber)` inside any `Threads.@threads` loop.
