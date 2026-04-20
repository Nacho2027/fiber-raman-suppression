# Phase 23 — Matched Quadratic-Chirp 100m Baseline

**Session:** `M-matched100m`  
**Date:** 2026-04-20  
**Status:** complete

## Headline

On the current reproducible checkout, the exact rerun of Session F's
`phi_opt@2m` forward baseline at `L = 100 m` gives **`J = -45.52 dB`**, not
the historical **`-51.50 dB`** recorded in Phase 16. Within that live state, a
pure quadratic chirp already reproduces the suppression almost exactly:

- **Best trusted quadratic by endpoint `J`:** `GDD = +4.00 ps²` → **`-45.06 dB`**
  (`Δ = +0.46 dB` vs live warm-start)
- **Best trusted quadratic by trajectory similarity:** `GDD = +1.00 ps²` →
  **`-44.35 dB`** (`Δ = +1.17 dB` vs live warm-start)

All three trusted runs satisfy the numerical gate:

- warm-start rerun: `BC edge = 9.09e-07`, `energy drift = 2.41e-03`
- `+4 ps²` quadratic: `BC edge = 3.23e-06`, `energy drift = 1.92e-07`
- `+1 ps²` quadratic: `BC edge = 2.84e-07`, `energy drift = 4.63e-04`

## Verdict

**Current live verdict:** the S5 "nonlinear structural adaptation across 50×
length" framing does **not survive** on the reproducible main-checkout state.
A generic quadratic pre-chirp matches the warm-start suppression to within
`0.5–1.2 dB`, which is well inside the user's `~3 dB` kill threshold.

**Important caveat:** the historical Phase 16 number `-51.50 dB` did **not**
reproduce in this session; the same source warm-start JLD2 reran at `-45.52 dB`
using the exact 100 m setup. If someone insists on comparing quadratics to the
historical `-51.50 dB`, the best trusted quadratic here is about `6.4 dB`
worse, which would force the weaker wording **"partially explained by
pre-chirp."** But against the live reproducible baseline, the answer is clear:
generic quadratic pre-chirp already gets essentially all of the effect.

## Visual Readout

Two visual facts matter:

1. The **best-`J` quadratic** (`+4 ps²`) lands almost exactly on the warm-start
   endpoint suppression, but its internal evolution is not especially similar.
   It suppresses by staying much more broadly stretched through the whole span.
2. The **best trajectory-matching trusted quadratic** (`+1 ps²`) is visually
   closer to the warm-start evolution and still sits only `1.17 dB` above the
   warm-start endpoint.

That means the honest interpretation is not "the quadratic reproduces the same
internal dynamics." It is: **the endpoint suppression at 100 m is not unique to
the transferred non-quadratic phase structure.** A simple quadratic chirp can
already reach essentially the same suppression level.

## Key Artifacts

- Candidate table: `results/raman/phase23/matched_quadratic_candidates.md`
- Data bundle: `results/raman/phase23/matched_quadratic_100m.jld2`
- Run notes: `results/raman/phase23/matched_quadratic_run.md`
- Warm vs best-`J` overlay:
  `.planning/phases/23-matched-baseline/images/phase23_warm_vs_matched_overlay.png`
- Warm vs trajectory-matched (`+1 ps²`) overlay:
  `.planning/phases/23-matched-baseline/images/phase23_warm_vs_gdd_p1_overlay.png`

Standard image sets were emitted for the warm-start rerun, every quadratic
sweep point (`GDD = ±1, ±2, ±4, ±8, ±16 ps²`), and the final best-`J`
quadratic under `.planning/phases/23-matched-baseline/images/`.

## Docs-Ready Paragraph

At `L = 100 m` on the current reproducible main-checkout state, the stored
`phi_opt@2m` warm-start reruns to `J = -45.52 dB` rather than the historical
`-51.50 dB` recorded in Phase 16. A pure quadratic spectral phase already
matches that live suppression: the best trusted quadratic (`GDD = +4.00 ps²`)
reaches `-45.06 dB`, and a more trajectory-matched quadratic (`GDD = +1.00 ps²`)
still reaches `-44.35 dB`. All trusted runs satisfy the edge-fraction and
energy-drift checks. The 100 m transfer is therefore best described as
**generic dispersive pre-chirp suppression**, not as evidence that preserving
the detailed non-quadratic warm-start structure is necessary to obtain the
observed endpoint Raman reduction.
