# Requirements: SMF Gain-Noise

**Defined:** 2026-03-25
**Core Value:** Physically correct simulation and optimization of Raman suppression, with every output plot clearly communicating the underlying physics.

## v2.0 Requirements

Requirements for Verification & Discovery milestone. Each maps to roadmap phases.

### Verification

- [x] **VERIF-01**: Fundamental soliton (N=1 sech) propagates one soliton period with <2% shape error, confirming NLSE solver correctness
- [x] **VERIF-02**: Photon number integral |U(w)|^2/w is conserved to <1% across forward propagation for all standard configs
- [x] **VERIF-03**: Taylor remainder test confirms adjoint gradient is O(eps^2) — slope ~2 on log-log residual vs eps plot
- [x] **VERIF-04**: Cost J from spectral_band_cost matches direct spectral integration to machine precision, confirming mask correctness

### Cross-Run Infrastructure

- [x] **XRUN-01**: Each optimization run saves structured metadata (fiber params, J values, convergence history, wall time) to JSON
- [x] **XRUN-02**: Summary table aggregates all runs showing J_before, J_after, delta-dB, iterations, wall time in one view
- [x] **XRUN-03**: Overlay convergence plot shows all runs' J vs iteration on a single figure
- [x] **XRUN-04**: Overlay spectral comparison shows all optimized spectra per fiber type on shared axes

### Pattern Detection

- [x] **PATT-01**: Each optimized phase profile is decomposed onto GDD/TOD polynomial basis with residual fraction reported
- [x] **PATT-02**: Soliton number N = sqrt(gamma*P0*T0^2/|beta2|) annotated in metadata and summary table for each run

### Parameter Exploration

- [x] **SWEEP-01**: L x P parameter sweep runs optimization over a coarse grid and produces J_final heatmap per fiber type
- [x] **SWEEP-02**: Multi-start analysis runs optimization from 5-10 random initial phases and reports convergence variance

## v3.0 Requirements — NMDS Performance/Roofline (derived)

Derived from the Phase 27 numerics-audit report (`.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md` §E "Performance-modeling / roofline audit") and locked via the Phase 29 CONTEXT.md decisions D-1..D-4. These are the first non-v2.0 requirements and are intentionally scoped to a single performance-modeling phase (Phase 29).

- [ ] **NMDS-PERF-01**: Every performance kernel in the forward/adjoint pipeline — raw FFT, Kerr tullio contraction, Raman frequency convolution, single forward-RHS step, single adjoint-RHS step — has a reproducible median-of-N wall-time measurement at the canonical configuration (SMF-28, Nt=2^13, M=1, L=2 m, P=0.2 W), persisted to `results/phase29/kernels.jld2` with a captured hardware profile in `results/phase29/hw_profile.json`. Ties to D-1 ("audit covers FFT execution, forward solve, adjoint solve, tensor contractions, and serial orchestration overhead") and D-3 ("deliverables are a benchmark suite plus a modeled performance memo").
- [ ] **NMDS-PERF-02**: Forward-solve, adjoint-solve, and full `cost_and_gradient` wall times are measured across Julia thread counts {1, 2, 4, 8, 16, 22} in fresh Julia subprocesses, with the three modes measuring distinct quantities (forward-only via `solve_disp_mmf`; adjoint-only via `solve_adjoint_disp_mmf` with a pre-captured forward ODE solution; full `cost_and_gradient`). Ties to D-1 and D-2 ("the phase models kernels before tuning them") and to Phase 27 NMDS recommendation on forward/adjoint bottleneck decomposition.
- [ ] **NMDS-PERF-03**: Measured per-mode timings are fit to an Amdahl model (`T(n) = T(1)·[(1−p) + p/n]`) producing a serial fraction `p`, an extrapolated speedup ceiling `1/(1−p)`, and a fit RMSE, persisted to `results/phase29/amdahl_fits.json`. Ties to D-4 ("hardware decisions must be tied to measured serial fractions and roofline reasoning").
- [ ] **NMDS-PERF-04**: Each measured kernel is labeled `MEMORY_BOUND`, `COMPUTE_BOUND`, or `SERIAL_BOUND` against the captured hardware roofline (ridge = peak_FLOPs / peak_bandwidth) for both `claude-code-host` (e2-standard-4, ridge ≈ 6.5 FLOP/byte) and `fiber-raman-burst` (c3-highcpu-22, ridge ≈ 13 FLOP/byte), and a final performance memo (`.planning/phases/29-.../29-REPORT.md`) opens with a one-paragraph Executive Verdict naming the dominant bottleneck plus a single-line `-t N` + burst-VM recommendation. Ties to D-3 ("modeled performance memo, not a grab-bag of micro-optimizations") and D-4.

## Future Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Pattern Detection (Extended)

- **PATT-03**: Phase universality test — do SMF-28 and HNLF at matched soliton number N produce similar phase profiles?

### Parameter Exploration (Extended)

- **SWEEP-03**: Dense parameter grid refinement (20x20) in regions of interest identified by coarse sweep
- **SWEEP-04**: Multi-start integration with standard run_optimization pipeline (currently separate in benchmark_optimization.jl)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Automatic differentiation (Zygote/Enzyme) for adjoint verification | Julia AD struggles with DifferentialEquations.jl in-place mutations and preallocated buffers; FD + Taylor remainder is exact and explainable |
| Cross-simulator comparison (PyNLO, Luna.jl) | Matching all physical parameters exactly creates maintenance burden; analytical solutions (soliton, photon number) are more reliable |
| Dense parameter grid (20x20 L x P) | Each point = full optimization (~50s); 400 points = 5.5 CPU-hours; coarse 4x4 grid sufficient for initial exploration |
| ML/clustering pattern detection | Only 5-12 runs — insufficient data for PCA/clustering; physical projection (GDD/TOD basis) gives more insight |
| Interactive/web dashboards | Static PNG/PDF output constraint from PROJECT.md; not needed for internal research group |
| Tuning any kernel identified by NMDS-PERF-01..04 | Phase 29 MODELS bottlenecks; fixing them belongs to a later, separate phase (per Phase 29 CONTEXT.md D-2) |
| Multi-mode (M ≥ 6) performance measurements | Phase 29 canonical config is M = 1; MMF perf belongs in a future MMF-perf phase |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| VERIF-01 | Phase 4 | Complete |
| VERIF-02 | Phase 4 | Complete |
| VERIF-03 | Phase 4 | Complete |
| VERIF-04 | Phase 4 | Complete |
| XRUN-01 | Phase 5 | Complete |
| XRUN-02 | Phase 6 | Complete |
| XRUN-03 | Phase 6 | Complete |
| XRUN-04 | Phase 6 | Complete |
| PATT-01 | Phase 6 | Complete |
| PATT-02 | Phase 6 | Complete |
| SWEEP-01 | Phase 7 | Complete |
| SWEEP-02 | Phase 7 | Complete |
| NMDS-PERF-01 | Phase 29 | Pending |
| NMDS-PERF-02 | Phase 29 | Pending |
| NMDS-PERF-03 | Phase 29 | Pending |
| NMDS-PERF-04 | Phase 29 | Pending |

**Coverage:**
- v2.0 requirements: 12 total, 12 mapped to phases, 0 unmapped
- v3.0 NMDS-PERF requirements: 4 total, 4 mapped to Phase 29, 0 unmapped

---
*Requirements defined: 2026-03-25*
*NMDS-PERF-01..04 added: 2026-04-21 as part of the Phase 29 plan-check revision (tying invented requirement IDs in 29-01-PLAN.md back to the Phase 27 NMDS report and Phase 29 CONTEXT.md D-1..D-4 decisions).*
