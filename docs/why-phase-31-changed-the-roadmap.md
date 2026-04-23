# Why Phase 31 Changed The Roadmap

Phase 31 changed the roadmap because it answered a more important question than "which basis is nicer?"

It showed that the project's main difficulty is not lack of control freedom. It is basin access.

## The short version

Before Phase 31, it was still plausible that:

- full-grid optimization was fundamentally the right formulation
- reduced bases were mainly for interpretability or mild regularization
- penalty tuning might recover most of the missing performance without changing the optimizer path

Phase 31 made that story hard to defend.

On the canonical SMF-28 case:

- reduced-basis continuation in a cubic basis at `N_phi = 128` reached about `-67.6 dB`
- full-grid zero-init L-BFGS repeatedly plateaued around `-57.75 dB`
- penalty families did not bridge that gap

The unrestricted problem had more degrees of freedom, but the structured path found a better basin.

That is a roadmap-changing result.

## What changed conceptually

Phase 31 forced three updates to project strategy.

### 1. Optimizer trajectory matters as much as parameterization

The win was not "cubic splines are inherently better physics." The win was that continuation through a lower-dimensional, structured family gave the optimizer a route into a deeper basin.

So future work had to focus on:

- continuation design
- globalization
- curvature-aware methods
- basin diagnostics

not just richer penalty catalogs.

### 2. The project has a real tradeoff, not a single best solution

Phase 31 separated three goals that had often been blurred together:

- deepest suppression
- robustness / basin width
- transferability across fibers or perturbations

The deepest cubic solutions were narrow and canonical-specific. The shallow polynomial solutions were much more transferable. That means later phases must report which objective they are optimizing for, instead of implying that one scalar score settles everything.

### 3. Second-order and continuation work became justified, not speculative

Once Phase 31 showed that full-grid zero-start L-BFGS misses a deeper basin, it became reasonable to ask:

- can a globalized second-order method recover that basin?
- can a better continuation path reach it more reliably?
- is the reduced-basis basin masking ambient saddle structure?

That directly motivated the emphasis in Phases 33 and 34.

## What the roadmap should now assume

Future sessions should assume:

- reduced-basis continuation is a basin-discovery tool, not just a simplification tool
- penalty tuning alone is unlikely to recover the deepest reduced-basis results
- competitive regimes may still be saddle-dominated even when a reduced basis looks well-behaved
- transferability and robustness must be reported alongside depth

## What still remains open

Phase 31 did not settle everything.

Open questions that still matter:

- whether full-grid methods with better globalization can close the roughly 10 dB gap
- whether the best cubic solutions are intrinsically fiber-specific or just artifacts of the path used to find them
- how much ambient indefiniteness is hidden by the reduced basis

That is why Phase 31 changed the roadmap without finishing it.

## Pointers

- Main findings: `agent-docs/phase31-reduced-basis/FINDINGS.md`
- Follow-on second-order work: `docs/planning-history/phases/33-globalized-second-order-optimization-for-raman-suppression/33-REPORT.md`
- Preconditioning follow-up: `docs/planning-history/phases/34-truncated-newton-krylov-preconditioning-path/34-01-SUMMARY.md`
