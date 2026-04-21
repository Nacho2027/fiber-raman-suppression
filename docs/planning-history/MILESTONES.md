# Milestones

## v1.0 Visualization Overhaul (Shipped: 2026-03-25)

**Phases completed:** 3 phases, 6 plans, 10 tasks

**Key accomplishments:**

- Two-sided Raman band shading (+/-2.5 THz) replacing broken half-spectrum highlight, plus Okabe-Ito COLOR_INPUT/COLOR_OUTPUT consistency across all comparison functions
- 3x2 phase diagnostic with mask-before-unwrap (BUG-03), _spectral_signal_xlim auto-zoom helper, and GDD percentile clipping
- Two-pass Before/After comparison functions with global P_ref normalization, shared temporal xlim/ylim, and auto-zoom
- Metadata annotation block (fiber type, L, P0, lambda0, FWHM) on every saved figure, expanded J before/after/Delta-J display
- Merged 2x2 evolution comparison figure replacing the two separate evolution PNGs — each run now produces exactly 3 output files

**Known gaps:** BUG-02 (jet→inferno), AXIS-03 (grid on pcolormesh), STYLE-03 (evolution floor/colormap) not completed.

---
