---
title: Quantum-noise-specific reframing of the Raman cost function
type: seed
planted_date: 2026-04-16
trigger_condition: "Multimode Raman suppression working with classical E_band/E_total cost function. Sprint 1 complete, team still engaged, PI wants deeper physics."
surface_when: "After classical multimode Raman suppression results are validated and documented"
---

# Seed: Quantum-noise reframing of multimode optimization

## The idea

Rivera Lab's underlying interest is quantum noise / squeezing preservation in multimode nonlinear fibers, not classical telecom Raman. The current cost function `J = E_band / E_total` is a classical proxy that maps approximately to squeezing-in-dB-below-shot-noise, but it's not the fundamental target for quantum applications.

After classical multimode Raman suppression is working, revisit whether a quantum-noise-aware cost function would give different optimal phase shapes.

## Why this matters

The "classical Raman suppression ≈ recoverable squeezing" mapping is a rule of thumb. In multimode specifically, squeezing can be degraded by mechanisms that don't show up in `E_band / E_total`:

- **Raman-induced phase noise on the carrier.** The spontaneous-emission component of Raman adds broadband quadrature noise that couples into the squeezed quadrature. This is the dominant noise mechanism for fiber-based squeezers per Rivera Lab papers — classical Stokes-energy suppression is one proxy, but direct quadrature noise variance is the true metric.
- **Intermodal XPM/FWM.** Cross-mode nonlinear coupling redistributes photons between spatial modes. Can generate useful multi-mode entanglement OR scramble single-mode squeezing.
- **Modal walk-off.** Different LP modes have different group velocities. For pulsed squeezing, this destroys temporal coherence between modes and decoheres mode-based squeezing.
- **Kerr-Raman trade-off.** The χ(3) nonlinearity that produces squeezing is the same one that produces Raman scattering. More squeezing = more Raman noise. There's likely an optimum power / length, not just an optimum phase.

## Concrete research questions for when this activates

1. What's a tractable quantum-noise cost function to optimize against? Options:
   - Output quadrature variance (requires Heisenberg-picture propagation of variance)
   - Wigner-function negativity or some related marker
   - Quantum Fisher information (sensing context)
2. Does a phase shape that minimizes `E_Stokes` also minimize quantum noise? Or do the optima diverge significantly?
3. Does multimode fiber provide a unique advantage (e.g., multi-mode squeezing with higher total information content than single-mode fiber)?
4. How sensitive is the optimum to modal walk-off? Do short-fiber optima degrade at longer lengths for *quantum* reasons even when the classical `E_Stokes` is still suppressed?

## Relevant code / prior art

- `src/analysis/analysis.jl` has `compute_noise_map` / `compute_noise_map_mm` functions that compute quantum noise via Tullio tensor contractions. These are the downstream consumers. `compute_noise_map_modem` is abandoned per STATE.md.
- Rivera Lab papers (per project context memory):
  - "Noise-immune squeezing of intense light" — Nature Photonics 2025
  - "Spatial noise dynamics in nonlinear multimode fibers" — CLEO 2025
  - "Multimode amplitude squeezing through cascaded nonlinear processes" — CLEO 2024
- Adjoint method for variance / second-moment propagation is non-trivial and may require a different forward-adjoint structure than the current `E_band` cost.

## Why it's a seed (not active now)

Doing this AND classical multimode AND Newton implementation in 4 weeks is too much. The classical work is the foundation — if it doesn't work cleanly, there's no useful quantum result. Seed triggers once classical results are in hand, and ideally after the 4-week sprint if the team wants a follow-on.
