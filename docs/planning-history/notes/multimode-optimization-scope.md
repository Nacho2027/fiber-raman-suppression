---
title: Multimode Optimization — Narrowed Scope Decision
date: 2026-04-16
context: Pre-advisor-meeting exploration — set direction for multimode extension of Raman suppression work
---

# Multimode Optimization Scope (2026-04-16)

## Narrowed decision

**For the current 4-week sprint: extend the existing Raman suppression framework to multimode fibers (M=6 target) with the same cost function `J = E_band / E_total`.**

Defer, for now:
- Quantum-noise-specific reframings (Raman-induced phase noise on carrier, intermodal XPM/FWM, modal walk-off, squeezing-preservation metrics). See `.planning/seeds/quantum-noise-reframing.md` for later pickup.
- Per-mode spectral phase — physically unrealizable with a single pulse shaper.

## Why this framing (rather than jumping straight to squeezing metrics)

- The existing codebase is structured around the `E_band / E_total` cost. Reusing it for M>1 is the lowest-friction path to getting results.
- Verifies the multimode forward/adjoint code paths work correctly before changing the scientific target. Prevents bug-chasing across two changes at once.
- If classical Raman suppression carries over cleanly to multimode, it likely does so for quantum noise too (the Raman-suppression-in-dB ≈ recoverable-squeezing-in-dB mapping per Rivera Lab memory, to be validated separately).
- PI interest in longer fibers (post-memory-correction 2026-04-16) means the classical regime is still in scope regardless.

## Parameter landscape for joint optimization

Beyond `φ(ω)` (spectral phase — current single optimized variable):

| Parameter | DOFs at M=6 | Physically realizable? | Expected value |
|---|---|---|---|
| Spectral amplitude `|A(ω)|` | ~Nt_φ | Yes (if pulse shaper has amplitude channel / 2D SLM) | Already explored in SMF via `scripts/amplitude_optimization.jl` — extend similarly |
| Input mode coefficients `{c_m}` | 2(M-1) = 10 real at M=6 | **Only if spatial SLM present** | Novel DOF — the big potential win for multimode |
| Pulse energy `E` | 1 | Yes | Small scalar addition; probably locks to an optimum quickly |
| Center wavelength `λ₀` | 1 | Usually fixed by laser | Out of scope (hardware-determined) |
| Per-mode `φ_m(ω)` | M × Nt_φ | **NO** — can't apply different phase to different modes with one pulse shaper | Out of scope |
| Polarization | 2–4 | Depends on fiber PM status | Out of scope for current fiber types |

**The pivotal unknown:** whether Rivera Lab's SLM setup is spectral-only (pulse shaping) or also spatial (launch mode control). If spatial, `{c_m}` becomes a real optimization parameter and the research question becomes novel. See `.planning/research/advisor-meeting-questions.md` for questions to resolve in the upcoming advisor meeting.

## Cost function options for multimode

At M=6, `E_band / E_total` has several plausible generalizations. Need to pick one (or start with one and justify later):

1. **Sum over all modes**: `J = (Σ_m E_band_m) / (Σ_m E_total_m)` — treats all modes as symmetrically important. Simplest generalization.
2. **Per-mode worst-case**: `J = max_m (E_band_m / E_total_m)` — robust target; ensures no mode leaks significantly to Stokes.
3. **Signal-mode only**: `J = E_band_signal / E_total_signal` — if the experiment detects only one output mode (e.g., LP01), this is what matters for the measurement.
4. **Detection-weighted sum**: `J = Σ_m w_m (E_band_m / E_total_m)` — generalization of (3) if there's partial mode-selective detection.

Recommend starting with (1) as baseline, verify (3) matches if the experiment is single-mode-detection.

## Implementation feasibility (per the threading benchmark)

- Core code paths at M>1 structurally work (`simulate_disp_mmf.jl`, `sensitivity_disp_mmf.jl` use 4D `γ[i,j,k,l]` tensor contractions).
- `@tullio` auto-parallelizes at M>1 — free within-solve speedup just from launching `julia -t auto`.
- Newton with parallel Hessian columns already benchmarked: 3.55× at 8 threads, expect ~8–12× on GCP c3-highcpu-22.
- Per-solve cost at M=6: unknown until benchmarked. Expected 10–50× slower than M=1 (Kerr tensor has 6⁴=1296 entries per ω bin vs 1 at M=1).
- Rough Newton iteration budget at M=6: minutes to tens of minutes on the 22-core burst VM.

## Out of scope for this sprint

- Quantum noise / squeezing metrics (deferred via seed)
- Random mode coupling from fiber imperfections (simulation currently assumes clean modes)
- Experimental noise floor comparison (that's a downstream analysis step)
- Polarization effects in non-PM fiber
- Per-mode pulse shaping (would need multi-channel pulse shaper hardware)
