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
- [ ] **XRUN-02**: Summary table aggregates all runs showing J_before, J_after, delta-dB, iterations, wall time in one view
- [ ] **XRUN-03**: Overlay convergence plot shows all runs' J vs iteration on a single figure
- [ ] **XRUN-04**: Overlay spectral comparison shows all optimized spectra per fiber type on shared axes

### Pattern Detection

- [ ] **PATT-01**: Each optimized phase profile is decomposed onto GDD/TOD polynomial basis with residual fraction reported
- [ ] **PATT-02**: Soliton number N = sqrt(gamma*P0*T0^2/|beta2|) annotated in metadata and summary table for each run

### Parameter Exploration

- [ ] **SWEEP-01**: L x P parameter sweep runs optimization over a coarse grid and produces J_final heatmap per fiber type
- [ ] **SWEEP-02**: Multi-start analysis runs optimization from 5-10 random initial phases and reports convergence variance

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

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| VERIF-01 | Phase 4 | Complete |
| VERIF-02 | Phase 4 | Complete |
| VERIF-03 | Phase 4 | Complete |
| VERIF-04 | Phase 4 | Complete |
| XRUN-01 | Phase 5 | Complete |
| XRUN-02 | Phase 6 | Pending |
| XRUN-03 | Phase 6 | Pending |
| XRUN-04 | Phase 6 | Pending |
| PATT-01 | Phase 6 | Pending |
| PATT-02 | Phase 6 | Pending |
| SWEEP-01 | Phase 7 | Pending |
| SWEEP-02 | Phase 7 | Pending |

**Coverage:**
- v2.0 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap creation — all 12 requirements mapped*
