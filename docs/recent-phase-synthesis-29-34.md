# Recent Phase Synthesis (29-34)

This note is the short human-facing summary of what Phases 29-34 actually taught the project.

It is intentionally narrower than the full planning history. The goal is to make the recent lessons easy to recover without rereading six phase folders.

## Status at a glance

| Phase | Status | What changed |
|-----|-----|-----|
| 29 | Executed | Replaced vague performance intuition with a measured bottleneck model. |
| 30 | Researched / designed | Turned warm-start folklore into an explicit continuation method with failure gates. |
| 31 | Executed | Showed reduced-basis continuation reaches a much deeper basin than full-grid zero-start optimization. |
| 32 | Researched / designed | Framed acceleration as optional and only worth keeping if it saves solves without weakening trust. |
| 33 | Executed | Built a trust-region Newton path that fails honestly and confirmed the saddle-rich landscape story. |
| 34 | Partially executed | Showed Phase 33 cold-start failure is not a bad initial radius problem; preconditioning is the next lever. |

## The simple story

The main lesson across these phases is that the project is no longer blocked on "more freedom" in the control variable. It is blocked on how we move through the landscape.

- Phase 29 said the immediate runtime problem is not "turn on more threads." For the canonical single-mode workload, extra intra-solve threading barely helps, and FFTW internal threading actively hurts.
- Phase 30 then reframed warm starts as a real numerical method: if hard regimes need careful path-following, that path should be explicit, measurable, and trust-gated.
- Phase 31 supplied the key empirical result: a reduced-basis continuation path can reach about `-67.6 dB`, while full-grid zero-init L-BFGS stalls around `-57.75 dB` on the same canonical problem.
- Phase 32 kept the project honest by narrowing the acceleration question. The right baseline is not cold-start. It is the explicit continuation chain from Phase 30, and "not worth it" is an acceptable outcome.
- Phase 33 tested whether second-order globalization would escape the problem cleanly. It did not produce new minima, but it did produce a better diagnosis: many competitive points are saddles, and from cold start the quadratic model is often untrustworthy.
- Phase 34 removed one easy excuse for the Phase 33 failures. Shrinking the initial trust radius does not help; the cold-start Hessian is already badly indefinite, so preconditioning or a better path is required.

## Phase-by-phase lessons

### Phase 29: performance reasoning became concrete

What mattered:

- The forward solve is not "just FFTs."
- At multimode settings, Kerr-style tensor contractions dominate the forward RHS.
- Even in the canonical single-mode regime, the adjoint path is materially more expensive than the forward path.
- FFTW internal threading at `Nt = 2^13` is the wrong lever.

Practical consequence:

- Do not justify compute-heavy changes by hand-wavy "parallelism should help" reasoning.
- For single-solve speedups, focus on RHS kernels and adjoint structure first.
- For throughput, prefer parallelizing across independent solves, sweeps, or starts.

This is why `agent-docs/current-agent-context/PERFORMANCE.md` preserves Phase 29 as active context.

### Phase 30: continuation stopped being an ad hoc habit

Phase 30 did not claim a numerical win yet. Its value was conceptual cleanup.

It established that:

- continuation should be treated as a method, not a convenience
- ladders must be explicit
- every step needs trust checks and failure detectors
- cold-start baselines are mandatory for comparison

That matters because Phase 31 later showed the optimizer path is the real story. Phase 30 defined the discipline needed to talk about that path honestly.

### Phase 31: the roadmap changed here

Phase 31 is the pivot.

The core finding was not merely that a reduced basis can regularize a solution. It was that the reduced-basis continuation path reaches a basin that unrestricted zero-start L-BFGS does not reach, even though the unrestricted problem has more nominal degrees of freedom.

The measured picture was:

- cubic basis, `N_phi = 128`: about `-67.6 dB`
- best full-grid zero-init L-BFGS plateau: about `-57.75 dB`
- the deepest reduced-basis solution was also tighter and less transferable
- shallow polynomial solutions were much more transferable but far less suppressive

The resulting project lesson is:

- depth, robustness, and transferability are genuinely different objectives
- "more dimensions" does not automatically mean "better optimizer outcome"
- continuation through a structured subspace is not a cosmetic regularizer; it changes which basin is reachable

This is why later phases shifted toward globalization, curvature diagnostics, and preconditioning instead of another round of penalty tuning.

### Phase 32: acceleration was narrowed to a useful question

Phase 32 mostly removed confusion.

Its main clarifications were:

- the correct baseline is naive continuation, not cold-start
- many classical acceleration methods do not cleanly apply because these runs move across nearby problems, not repeated applications of one fixed map
- polynomial warm-start prediction is the most generally defensible low-risk candidate
- a "not worth it" verdict is scientifically acceptable

That narrowed future work and reduced the chance of building elaborate acceleration machinery for a marginal gain.

### Phase 33: second-order methods improved diagnosis more than depth

Phase 33's trust-region Newton implementation mattered even though it did not beat the first-order baseline.

What it established:

- the optimizer can now fail with typed, interpretable exit states instead of vague stagnation
- warm starts in competitive regimes often sit at first-order stationary saddles
- cold starts can be rejected honestly when the trust-region quadratic model is not predictive

This confirmed a major qualitative lesson from earlier landscape work: the interesting Raman-suppression regime is saddle-dominated.

That is useful because it separates two questions that were previously mixed together:

- "Did the optimizer fail because the code is broken?"
- "Did the optimizer fail because the local quadratic model is not usable here?"

Phase 33 says the second explanation is real and common.

### Phase 34: the next bottleneck is curvature conditioning

Phase 34's initial sweep answered a narrow but important question: was the trust-region cold-start failure caused by a bad initial radius?

The answer was no.

- sweeping `Δ0` over three decades still produced `RADIUS_COLLAPSE`
- accepted iterations stayed at zero
- the cold-start Hessian remained strongly indefinite

So the next step is not radius retuning. It is curvature handling:

- preconditioning
- spectrum shifting / regularization
- or a better continuation path into the hard regime

One caution from current state notes: there is also a documented `M`-kwarg wiring gap in the Phase 34 preconditioning path, so not every nominal preconditioner result should be interpreted as a true preconditioned run until that additive wiring fix lands.

## What should future sessions remember

If you only keep five lessons, keep these:

1. The active bottleneck is optimizer path and curvature handling, not "add more control dimensions."
2. Reduced-basis continuation is scientifically important because it changes basin reachability, not just interpretability.
3. Trust-gated honest failure is progress in this project; silent "convergence" at a saddle is worse.
4. Single-solve shared-memory tuning is low leverage for current canonical workloads; parallel work across solves is higher leverage.
5. Any future acceleration work must beat explicit continuation at equal trust, not beat a straw-man cold start.

## Remaining documentation gaps

The biggest gaps after this synthesis are:

- A short human-facing summary for Phase 30 execution status once the continuation path is fully exercised on current `main`.
- A matching short summary for what Phase 32 actually tried in practice, not only what its research phase recommended.
- One canonical "recent lessons" link from the top-level project docs, so maintainers do not have to infer that the useful narrative is buried in planning history.
- A brief status note on the Phase 34 preconditioning wiring caveat, so future readers do not over-read early preconditioner comparisons.

## Pointers

- Phase 29 report: `docs/planning-history/phases/29-performance-modeling-and-roofline-audit-for-the-fft-adjoint-/29-REPORT.md`
- Phase 31 findings: `agent-docs/phase31-reduced-basis/FINDINGS.md`
- Phase 33 report: `docs/planning-history/phases/33-globalized-second-order-optimization-for-raman-suppression/33-REPORT.md`
- Phase 34 summary: `docs/planning-history/phases/34-truncated-newton-krylov-preconditioning-path/34-01-SUMMARY.md`
