# Warm-start vs exploration — the trade-off and the design rule

**Captured:** 2026-04-21
**Motivated by:** Phase 33 benchmark design discussion, reinforced by Phase 13 / Phase 22 / Phase 35 landscape findings

## The problem

If every benchmark in this project warm-starts from a previously-converged `phi_opt`, we are not exploring the optimization landscape — we are only asking "does this new optimizer refine a known point better than L-BFGS did?" That's a legitimate question (robustness, local improvement) but it is NOT the same as "can this optimizer find globally better solutions?"

This matters specifically because of what the audit and saddle-escape work established:

- **Phase 13**: every L-BFGS stopping point has an indefinite Hessian (saddle, not minimum).
- **Phase 22**: regularizing for flatness across 26 optima didn't change this — saddle structure persists.
- **Phase 35 (saddle-escape)**: escaping along negative-curvature directions from a saddle lands you on *another saddle*, not a genuine minimum. Minima only exist at uncompetitively bad dB (e.g. −47 dB at N_φ=4 instead of the −68 to −86 dB we see at higher resolution).

**Translation:** our `phi_opt` files are a collection of saddles in one interconnected network. Warm-starting a new optimizer from one of them is almost guaranteed to find another nearby saddle. We are not crossing basin boundaries.

## What each start type tests

| Start type | What it tests | What it does NOT test |
|---|---|---|
| **Warm** (from converged `phi_opt`) | Local refinement, robustness, whether new optimizer improves over L-BFGS at the same operating point | Global exploration; finding qualitatively different solutions |
| **Perturbed** (warm + small random kick) | Basin-hopping-lite; whether small perturbations recover or escape | Truly new basins; large structural changes |
| **Cold** (random initial phi) | Global exploration; which basins are reachable from nowhere | Local refinement of a specific known optimum |

## The design rule

**Any benchmark for a new optimizer in this project must include cold starts, not only warm starts.** Warm-only benchmarks can validate incremental improvement but cannot claim the new method finds globally better solutions.

Phase 33's original `BENCHMARK_CONFIGS` correctly included `:warm / :perturbed / :cold` as `START_TYPES`. This is the right template. When scope pressure tempts a reduction, drop warm-perturbed duplicates or reduce the config count, but **never** drop the cold leg entirely. Losing cold = losing the exploration claim.

## What also tests exploration (beyond cold random-phi)

- **Multi-start with diverse random phi** — statistically samples basin multiplicity
- **Continuation / homotopy** — Phase 30's scope: slowly change L, P, or N_φ, follow the solution branch, watch for bifurcations where new solution families split off
- **Negative-curvature descent** — saddle-free Newton, Phase 34: use the Hessian's indefinite directions to descend along the negative-curvature modes rather than L-BFGS ignoring them
- **Basin-hopping** — after each converged run, kick the solution by `ε > σ_3dB` and re-optimize; tracks basin connectivity
- **Annealed / noisy optimization** — stochastic escape

Phases 30, 33, 34 in combination cover most of this. Phase 31 (reduced-basis) + 32 (extrapolation) operate at a different level — they're about efficient parameterization and accelerated sequences, not exploration per se, but they change *what the landscape looks like*, which indirectly affects how many basins exist.

## Practical implication for current overnight Phase 33 work

The guidance given to the Phase 33 agent to use Phase 21 honest-recovered JLD2s as warm starts is correct for the robustness claim, but the matching cold-start configs in `BENCHMARK_CONFIGS` must run. If compute pressure forces a cut, reduce from e.g. 12 runs to 8 by trimming the perturbed leg — but keep both warm and cold legs represented.

## What to say at advisor meetings

If asked "have you found deeper minima than L-BFGS?" the honest answer depends on *how* the deeper value was found:

- Warm-start from L-BFGS optimum, new method dug 2 dB deeper → "improves local refinement"
- Cold start, new method found a basin L-BFGS missed → "finds globally different solutions"
- Both → the strongest claim

Never conflate the first with the third. The Phase 22 finding that all optima remain indefinite means we have strong reason to doubt that local refinement alone crosses the relevant structural boundaries.
