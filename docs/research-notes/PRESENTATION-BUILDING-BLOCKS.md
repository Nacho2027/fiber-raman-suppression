# Presentation Building Blocks

Build the presentation from claims, not chronology. The research notes are now
organized so the talk can be assembled from these blocks without depending on
chat history or internal milestone names.

## Core Story

1. Baseline: spectral phase can strongly change Raman-band generation even when
   input energy is unchanged.
2. Trust: a lower scalar objective is not enough; the result must pass
   boundary, grid, image, and cost-definition checks.
3. Structure: reduced bases and simple profiles make the search more legible,
   but depth, smoothness, transferability, and robustness trade against each
   other.
4. Extensions: long-fiber, multimode, and multiparameter controls work only
   under narrower claim boundaries.
5. Engineering: adjoints, standard images, reproducible drivers, and AI-assisted
   documentation made the project auditable.

## Minimum Slide Blocks

| Block | Use these notes | What to show |
|---|---|---|
| Baseline physics | `01` | No-optimization control page, optimized phase/heat-map page, baseline objective diagram. |
| Reduced basis | `02` | Basis diagram, coefficient-to-phase math, control/deep/moderate/transfer result pages. |
| Robustness and sharpness | `03`, `04` | Robustness tradeoff bars, saddle/Hessian diagrams, accepted-vs-risky phase pages. |
| Trust and numerics | `05`, `10` | Cost-audit diagrams, recovery verdict table, checked-grid/recovery result pages. |
| Simple profiles | `07` | Simple polynomial/naive/deep profiles with matching heat maps and transfer plot. |
| Multivariable controls | `09` | No-shaping control, phase-only reference, amplitude-refined result, ablation table. |
| Long-fiber | `06`, `12` | 100 m/200 m comparison, long-fiber optimized heat maps, warm-start reoptimization diagram. |
| Multimode | `08` | Claim-boundary diagram, rejected unregularized gate, accepted high-resolution result. |
| Compute strategy | `11` | Adjoint-vs-finite-difference diagram and runtime charts if the audience asks about feasibility. |

## Talk Discipline

- Lead every result with the exact claim and caveat.
- Put control and optimized images next to each other whenever possible.
- State when a result is a simulation candidate, a validated run, a rejected
  candidate, or a provisional strategy.
- Avoid internal chronology. The audience does not need milestone labels; they
  need the scientific reason each branch mattered.
