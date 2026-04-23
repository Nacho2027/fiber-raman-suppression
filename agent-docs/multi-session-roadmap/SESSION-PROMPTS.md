# Multi-Session Roadmap And Session Prompts

This file captures the recommended multi-session Codex split after synthesizing phases 29-34 and the original project priorities.

## High-Level Split

### Session A — Phase 31 follow-up

- Main lane
- Extend the strongest positive result: reduced-basis + continuation
- Likely to run moderate simulations

### Session B — numerics / objective coherence cleanup

- Shared numerics lane
- Unify cost / gradient / HVP / trust conventions
- Mostly code + tests, light simulation only if needed for validation

### Session C — multimode baseline stabilization

- Multimode lane
- Establish meaningful multimode regimes and trustworthy baselines
- Likely to run moderate to heavy simulations

### Session D — docs + light refactor

- Documentation and low-risk cleanup lane
- Mostly docs, summaries, and isolated helper cleanup
- Should avoid significant simulation work

### Session E — parked sharpness / Newton follow-up

- Future lane, only after Session B groundwork is in better shape
- Revisit second-order methods in reduced-basis or warm-started settings
- Likely to run moderate to heavy simulations when activated

## File Ownership Guidance

- Session A owns new Phase 31 follow-up scripts and `agent-docs/phase31-reduced-basis/*`
- Session B owns shared objective / HVP / trust / numerics plumbing
- Session C owns `scripts/mmf_*`, multimode analysis, and multimode result summaries
- Session D stays mostly in `docs/` and isolated helper utilities
- Session E should avoid broad shared-file edits and work in a dedicated second-order namespace

## Simulation Expectations

### Likely to run simulations

- Session A: yes
- Session C: yes
- Session E: yes, when activated

### Might run light validation solves

- Session B: maybe, but this should mostly be tests and consistency checks rather than large campaigns

### Should mostly avoid simulations

- Session D: yes, avoid unless a tiny reproduction is needed for documentation accuracy

## Session A Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- agent-docs/current-agent-context/METHODOLOGY.md
- agent-docs/phase31-reduced-basis/CONTEXT.md
- agent-docs/phase31-reduced-basis/FINDINGS.md
- agent-docs/phase31-reduced-basis/SUMMARY.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Build the next step after Phase 31. Treat reduced-basis + continuation as the main positive result to extend.

Main questions:
1. Can reduced-basis continuation be used to reach a strong full-grid refinement result?
2. Can we preserve most of the depth of the best cubic Phase 31 result while improving robustness or transferability?
3. Is there a better continuation path than the current one (for example cubic -> denser cubic -> full-grid, or linear -> cubic -> full-grid)?

Deliverables:
- A concrete follow-up plan or implementation for Phase 31 extension
- Scripts/results/docs that compare at least 2 continuation/refinement paths
- Updated agent-docs under agent-docs/phase31-reduced-basis/
- Tests for any non-trivial code changes
- Clear statement of what worked and what failed

Constraints:
- Own Phase 31 namespace and adjacent new files only
- Avoid shared-file edits unless absolutely necessary
- Do not edit scripts/common.jl or scripts/raman_optimization.jl unless blocked and justified
- Save standard image sets for any phi_opt output
- Run relevant tests before finishing

Output style:
Focus on experimental clarity: what path was tested, what improved, what regressed, and what it suggests next.
```

## Session B Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- docs/planning-history/seeds/cost-surface-coherence-and-log-scale-audit.md
- docs/planning-history/seeds/numerics-conditioning-and-backward-error-framework.md
- docs/planning-history/seeds/globalized-second-order-optimization.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Clean up the objective/cost/HVP/trust consistency layer so future sharpness/Newton/optimizer comparisons are honest.

Main questions:
1. Are optimizer, HVP, diagnostics, and plots all differentiating the same scalar objective?
2. Is log-vs-linear cost treatment explicit everywhere?
3. Can we add tests that would catch mismatched cost/gradient/HVP conventions?

Deliverables:
- A concrete cost-convention spec in code and docs
- Code changes that unify or clearly separate cost paths
- Regression tests for gradient/HVP/objective consistency
- Clear note on what remains open vs what is fixed
- Minimal disruption to physics behavior

Constraints:
- This session owns shared numerics/plumbing work
- Coordinate by avoiding Phase 31-specific or MMF-specific code unless needed for consistency
- If shared-file edits are necessary, keep them surgical and well-tested
- Prefer trust/reporting and interface cleanup over broad refactors
- Run relevant tests before finishing

Output style:
State exactly what convention is now authoritative and what comparisons are safe after your changes.
```

## Session C Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/METHODOLOGY.md
- agent-docs/current-agent-context/PERFORMANCE.md
- docs/planning-history/sessions/C-multimode-status.md
- docs/planning-history/sessions/C-multimode-decisions.md
- .planning/notes/multimode-optimization-scope.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Stabilize the multimode baseline in a regime with real Raman headroom and make the baseline scientifically trustworthy.

Main questions:
1. Which multimode configs actually have optimization headroom?
2. Which multimode cost is the right primary one to emphasize: sum-over-modes, fundamental-only, or worst-mode?
3. What baseline result is strong enough to support later reduced-basis or joint-parameter work?

Deliverables:
- A trustworthy multimode baseline result set
- Clear statement of meaningful and non-meaningful regimes
- Tests for any multimode code changes
- Results summary explaining what worked and what did not
- Clear recommendation for the next multimode step

Constraints:
- Own MMF files and MMF result analysis
- Avoid shared single-mode optimizer refactors
- Respect heavy compute rules if you launch anything substantial
- Save standard image sets for any phi_opt outputs
- Run relevant tests before finishing

Output style:
Keep the conclusion practical: which multimode setup should the project use next, and why.
```

## Session D Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- agent-docs/current-agent-context/PERFORMANCE.md
- agent-docs/phase31-reduced-basis/FINDINGS.md
- docs/planning-history/phases/33-globalized-second-order-optimization-for-raman-suppression/33-REPORT.md
- docs/planning-history/phases/34-truncated-newton-krylov-preconditioning-path/34-01-SUMMARY.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Write clear human-facing synthesis docs for phases 29-34 and perform only small research-enabling refactors that do not interfere with active science work.

Main questions:
1. Can the recent phase lessons be explained simply and clearly?
2. What small cleanup would reduce duplication or confusion without destabilizing active work?
3. What should be documented now so future sessions stop rediscovering the same lessons?

Deliverables:
- A concise synthesis doc for phases 29-34
- A concise doc explaining why Phase 31 changed the roadmap
- Optional light refactor only if low-risk and clearly beneficial
- No broad architectural rewrite
- Clear summary of remaining documentation gaps

Constraints:
- Prefer docs and isolated helpers
- Do not touch core optimizer/shared numerics files unless necessary
- No big refactor
- If you make code changes, keep them small and test them

Output style:
Optimize for clarity and learning value, not breadth.
```

## Session E Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- agent-docs/current-agent-context/METHODOLOGY.md
- agent-docs/phase31-reduced-basis/FINDINGS.md
- docs/planning-history/phases/33-globalized-second-order-optimization-for-raman-suppression/33-REPORT.md
- docs/planning-history/phases/34-truncated-newton-krylov-preconditioning-path/34-01-SUMMARY.md
- docs/planning-history/seeds/globalized-second-order-optimization.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Revisit sharpness/Newton work only in the better-conditioned settings suggested by phases 31, 33, and 34. Do not treat raw cold-start full-grid Newton as the main path.

Main questions:
1. Does second-order or sharpness-aware work help in reduced-basis space?
2. Does second-order work help when started from continuation-generated or otherwise good warm starts?
3. Is preconditioning enough to turn the trust-region path from a diagnostic into a useful optimizer?

Deliverables:
- One narrowly scoped second-order experiment in a well-justified setting
- Honest comparison against a strong reduced-basis or warm-start baseline
- Clear statement of whether the method improved robustness, depth, or neither
- Tests for any new numerical machinery
- A short note explaining whether this lane should continue or pause

Constraints:
- Avoid broad shared-file edits unless necessary
- Do not spend the session on blind trust-radius tuning
- Prefer reduced-basis, warm-started, or preconditioned settings
- Save standard image sets for any phi_opt outputs
- Run relevant tests before finishing

Output style:
Be explicit about whether the result is a real optimizer improvement or just another useful negative result.
```

## Recommended Launch Order

1. Start Session A
2. Start Session B
3. Start Session C
4. Start Session D
5. Keep Session E parked until Session B has reduced the objective-consistency ambiguity

## Practical Answer On Simulations

Yes, some of these sessions should be running simulations.

- Session A: yes, this is expected
- Session B: mostly no, except for targeted validation solves/tests
- Session C: yes, this is expected
- Session D: mostly no
- Session E: yes, when you activate it

If you want to avoid collisions and wasted compute:

- Launch Sessions A and C as the main simulation-producing sessions
- Let Session B and D mostly stay in code/tests/docs
- Only launch Session E after Session B settles the objective/trust layer enough that the results will be interpretable

## Strategic Notes From 2026-04-23 Discussion

This section records the main conclusions from the planning conversation after reviewing phases 29-34 and the first multi-session outputs.

### What we learned

- The strongest positive result is still the Phase 31 story: reduced-basis continuation finds a deeper basin than full-grid zero-init optimization.
- Sharpness / Newton work has been more useful as diagnosis than as a source of new physics or simple universal phase profiles.
- Multimode work has improved infrastructure and trust reporting, but the main baseline-evidence lane still needs completion and interpretation.
- Phase 32 is only partially resolved in practice. Richardson looks like a real negative result; the rest of the acceleration story remains incomplete.
- The project goal is not merely "better optimizer machinery." The more important scientific goal is finding simple, interpretable, transferable phase-profile families and understanding what physics makes them work.

### What this means for roadmap priority

- Keep the best parts of the numerics/objective-coherence cleanup.
- Keep the docs/synthesis/status-note work.
- Continue to use Phase 31 as the main positive optimization direction.
- Finish multimode baseline evidence before over-expanding the multimode story.
- Do not over-invest in raw cold-start Newton/trust-region tuning right now.
- Shift more attention toward universality, transferability, simple phase families, and mechanism discovery.

### Working interpretation of the science so far

- There appears to be a tradeoff between deep, narrow, canonical-specific optima and simpler, shallower, more transferable phase profiles.
- Low-order / polynomial-like compensation may capture a more universal effect.
- Deep cubic/localized structure may capture more regime-specific nonlinear physics.
- That tradeoff is probably closer to the physics story the advisor wants than another round of optimizer diagnostics.

### Practical next steps implied by this discussion

1. Integrate the strong single-mode numerics/docs work.
2. Finish multimode baseline evidence cleanly.
3. Keep Phase 31 follow-up active as the main optimization lane.
4. Start a physics-facing lane on simple phase-profile discovery and universality.
5. Design the repo for formal lab use through a stable front-layer API before attempting a giant internal refactor.

### Design philosophy for lab-readiness

- Common tasks should be one obvious function call.
- Strong defaults and presets matter more than exposing every internal knob by default.
- Outputs should be standardized, reproducible, and exportable to experimental workflows like SLM use.
- The repo should feel more like a scientific instrument than a personal research workbench.
- The public API should be defined before the large refactor, not after.

## Additional Prompt Backlog

These prompts extend the original A-E set with the new workstreams identified in the discussion above.

## Session F Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- CLAUDE.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- agent-docs/current-agent-context/METHODOLOGY.md
- agent-docs/current-agent-context/PERFORMANCE.md
- agent-docs/phase31-reduced-basis/FINDINGS.md
- docs/recent-phase-synthesis-29-34.md
- docs/why-phase-31-changed-the-roadmap.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Design and begin a serious refactor plan for this codebase. This is a public repo and it currently feels bloated, messy, script-heavy, and structurally embarrassing. The goal is to make it cleaner, more coherent, easier to work in, easier to extend, safer to evolve, and visibly more professional without losing useful existing functionality.

Main questions:
1. What are the current structural pain points in the repo for development, extension, and maintenance?
2. What should be reorganized, renamed, wrapped, or separated?
3. How can we remove real garbage, reduce visible chaos, and clearly separate canonical workflows from legacy clutter without throwing away potentially valuable research functionality?
4. What refactor boundaries are safe now, and what should wait until later?

Deliverables:
- A concrete refactor proposal with phases, not just complaints
- A map of current code organization problems
- A proposed target structure for modules/scripts/docs/results interfaces
- A proposal for what should be canonical, what should be archived, and what should be removed from the main surface area
- A distinction between immediate cleanup, medium-term refactor, and later archival/deletion work
- A note on what functionality must be preserved even if it seems niche

Constraints:
- Do not start a giant destructive rewrite
- Do not remove functionality unless you can justify it clearly
- Preserve future-facing flexibility for research work
- Focus on breadth and depth: architecture, naming, file layout, interfaces, docs, and extension points
- If you make code changes, keep them low-risk and well-tested

Output style:
Think like a lead engineer cleaning up a publicly visible research codebase that currently feels overgrown and messy. Preserve important functionality, but impose enough structure that the repo looks intentional, professional, and trustworthy to outside users.
```

## Session G Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- CLAUDE.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- agent-docs/current-agent-context/METHODOLOGY.md
- docs/recent-phase-synthesis-29-34.md
- docs/why-phase-31-changed-the-roadmap.md
- agent-docs/multi-session-roadmap/SESSION-PROMPTS.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Prepare the repo for formal usage by the lab group and advisor. Treat this as a product/usability task for scientific users. The goal is that common workflows are easy, clear, documented, reproducible, and do not require contacting the original author.

Main questions:
1. What are the main lab-facing use cases this repo should support?
2. What stable public API or front-layer workflow should exist for notebooks, experiment scripts, and exports?
3. How should outputs be structured so users can trust, compare, and reuse results?
4. How should the repo support future experimental handoff, especially SLM-style export workflows?

Deliverables:
- A concrete lab-usage proposal
- A proposed small public API / front-layer interface
- A recommended result-object / output-schema design
- A proposal for SLM/export support
- A proposal for example notebooks and/or config-driven experiment runners

Constraints:
- Do not begin with a giant internal rewrite
- Design the front layer before the deep refactor
- Optimize for simplicity, defaults, presets, reproducibility, and ease of use
- Keep advanced internals available, but do not make them the normal interface
- If you implement anything, keep it thin and wrap existing working paths where possible

Output style:
Think like you are designing a scientific instrument UI for a lab, not just documenting a research sandbox.
```

## Session H Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/METHODOLOGY.md
- agent-docs/current-agent-context/PERFORMANCE.md
- docs/planning-history/sessions/C-multimode-status.md
- docs/planning-history/sessions/C-multimode-decisions.md
- docs/multimode-baseline-status-2026-04-22.md
- .planning/notes/multimode-optimization-scope.md

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Push multimode exploration forward as a real physics-discovery lane. Do not artificially narrow the question too early. The goal is to run meaningful multimode simulations, identify promising regimes and mechanisms, and build a strong basis for a paper-quality multimode story.

Main questions:
1. Which multimode regimes actually show interesting optimization headroom and physics?
2. Which multimode observables or cost functions are most scientifically revealing?
3. What parameter sweeps or comparisons are worth running to discover useful multimode structure?
4. What early multimode findings would actually be exciting enough to build a paper around?

Deliverables:
- A prioritized multimode exploration plan
- At least one concrete regime/comparison worth heavy simulation effort
- A distinction between baseline, exploratory, and paper-facing multimode experiments
- A note on which multimode paths should be run now versus later
- If you run simulations: a clear result summary explaining what seems promising and what does not

Constraints:
- Use burst for substantial simulation work
- Respect compute discipline and trust checks
- Do not confuse infrastructure completion with scientific completion
- Favor experiments that can reveal mechanism, not just optimizer score changes
- Save standard image sets for any phi_opt output

Output style:
Think ambitiously but honestly: the goal is to discover interesting multimode physics, not just to produce more multimode files.
```

## Session I Prompt

```text
You are working in /home/ignaciojlizama/fiber-raman-suppression.

Read first:
- AGENTS.md
- agent-docs/current-agent-context/INDEX.md
- agent-docs/current-agent-context/NUMERICS.md
- agent-docs/current-agent-context/METHODOLOGY.md
- agent-docs/phase31-reduced-basis/FINDINGS.md
- docs/recent-phase-synthesis-29-34.md
- docs/why-phase-31-changed-the-roadmap.md

You MUST also browse the literature using primary sources and recent papers before concluding.

Start with:
git status
git fetch origin
git pull --ff-only origin main

Mission:
Investigate stability, universality, and what a genuinely "good" result should look like for this project. This is a physics/research-standards task, not just an optimizer task. Read the literature, compare against the repo's current findings, and help define what phase profiles, transferability, and suppression levels are actually meaningful and exciting.

Main questions:
1. In nonlinear fiber optics and related pulse-shaping work, what counts as a strong, interpretable, publishable result?
2. What kinds of phase profiles are considered useful, simple, universal, robust, or experimentally meaningful?
3. How should this project evaluate tradeoffs among depth, robustness, universality, and interpretability?
4. What concrete claims would be exciting and defensible to an advisor or in a paper?

Deliverables:
- A literature-grounded note on what "good results" look like
- A proposed evaluation framework for this repo: depth, robustness, transferability, simplicity, mechanism, experimental usability
- A list of candidate simple phase-family hypotheses worth testing
- A list of paper-quality questions the repo is now positioned to answer
- Source-linked references to primary papers and review sources

Constraints:
- Use the web and prefer primary sources, reviews, and official/authoritative papers
- Clearly separate literature facts from repo-specific interpretation
- Do not overclaim that current repo results already establish universality
- Keep the final output practical: what should the project test next, and why

Output style:
Think like a scientifically serious research strategist helping define what success should mean, not just like an optimizer engineer.
```
