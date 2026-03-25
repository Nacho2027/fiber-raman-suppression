# Requirements: Visualization Overhaul

**Defined:** 2026-03-24
**Core Value:** Every plot clearly communicates the underlying physics without external context.

## v1 Requirements

### Bug Fixes

- [x] **BUG-01**: Raman band `axvspan` shading must only cover the ~13 THz Raman gain band (~1600-1700 nm for 1550 nm center), not the entire red-shifted half of the spectrum
- [ ] **BUG-02**: Replace jet colormap with inferno on all evolution heatmaps (jet creates ~3 dB false perceptual features)
- [x] **BUG-03**: Apply spectral power mask BEFORE phase unwrapping, not after (current order propagates noise into valid phase data)
- [x] **BUG-04**: Use global normalization (shared P_ref) across Before/After comparison columns so dB values are directly comparable

### Phase Representation

- [x] **PHASE-01**: Use group delay τ(ω) [fs] as the primary phase display in opt.png row 3 (most physically intuitive)
- [x] **PHASE-02**: In phase diagnostic (opt_phase.png), show all phase views: wrapped φ(ω) [0,2π], unwrapped φ(ω), group delay τ(ω), GDD, and instantaneous frequency — all masked to signal region before derivative computation
- [x] **PHASE-03**: Clip GDD display to a sensible range (percentile-based or physics-based) to prevent outlier spikes from dominating the axis
- [x] **PHASE-04**: Wrapped phase panel uses π-labeled y-ticks (0, π/2, π, 3π/2, 2π) for readability

### Axis and Layout

- [x] **AXIS-01**: Before/After comparison columns must share identical xlim and ylim for all matched panel pairs
- [x] **AXIS-02**: Spectral plots must auto-zoom to the region with actual signal, not show 800 nm of noise floor
- [ ] **AXIS-03**: Disable grid lines on pcolormesh heatmap axes (grid appears as data artifacts)

### Annotations and Metadata

- [x] **META-01**: Every figure includes a metadata annotation block: fiber type, length L, peak power P₀, center wavelength λ₀, pulse FWHM
- [x] **META-02**: Optimization cost J (before/after, in dB) annotated on comparison figures
- [x] **META-03**: Evolution figures include fiber length and title identifying optimized vs unshaped

### Color and Style

- [x] **STYLE-01**: Consistent color identity across all plot types: Input = blue (#0072B2), Output = vermillion (#D55E00)
- [x] **STYLE-02**: Reduce Raman band shading opacity (keep shading, make it subtle)
- [ ] **STYLE-03**: Evolution heatmaps use -40 dB floor with inferno colormap, shared colorbar labeled "Power [dB]"

### Plot Organization

- [x] **ORG-01**: Merge the two separate evolution PNGs (optimized + unshaped) into a single 4-panel comparison figure (2×2: temporal/spectral × optimized/unshaped)
- [x] **ORG-02**: Each run produces 3 output files: opt.png (comparison), opt_phase.png (phase diagnostic), opt_evolution.png (merged evolution)

## v2 Requirements

### Future Improvements

- **FUT-01**: Spectrogram (XFROG) plot for complex pulse characterization
- **FUT-02**: Solver decoupling — remove `solve_disp_mmf` calls from inside plotting functions
- **FUT-03**: Energy conservation tracking plot along fiber length
- **FUT-04**: Publication-mode toggle for journal-ready figure sizes and fonts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Simulation physics changes | Visualization-only project |
| Interactive/web-based plots | Static PNG/PDF output sufficient for research group |
| Notebook-specific plotting | Focus on scripts/visualization.jl pipeline |
| New data formats | Keep existing solver output structure |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUG-01 | Phase 1 | Complete |
| BUG-02 | Phase 1 | Pending |
| BUG-03 | Phase 2 | Complete |
| BUG-04 | Phase 2 | Complete |
| PHASE-01 | Phase 2 | Complete |
| PHASE-02 | Phase 2 | Complete |
| PHASE-03 | Phase 2 | Complete |
| PHASE-04 | Phase 2 | Complete |
| AXIS-01 | Phase 2 | Complete |
| AXIS-02 | Phase 2 | Complete |
| AXIS-03 | Phase 1 | Pending |
| META-01 | Phase 3 | Complete |
| META-02 | Phase 3 | Complete |
| META-03 | Phase 3 | Complete |
| STYLE-01 | Phase 1 | Complete |
| STYLE-02 | Phase 1 | Complete |
| STYLE-03 | Phase 1 | Pending |
| ORG-01 | Phase 3 | Complete |
| ORG-02 | Phase 3 | Complete |

**Coverage:**
- v1 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 — traceability filled after roadmap creation*
