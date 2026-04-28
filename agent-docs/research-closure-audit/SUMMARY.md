# Research Closure Audit

Date: 2026-04-28

## Current Maintainer Decision

The active research lanes are closed enough for lab-readiness packaging:

- MMF is no longer a blocker for lab rollout. It has a qualified corrected
  4096-grid simulation candidate, but remains experimental and not
  lab-supported.
- Multivar is closed for the current packaging decision. Direct joint
  optimization is negative; staged `amp_on_phase` is the useful optional path.
- Long-fiber has a completed 200 m image-backed milestone. It should be shown
  as a research result with caveats, not as the default lab workflow.

The supported lab-ready surface remains narrow: single-mode, phase-only,
Raman-band objective, standard images, trust report, export handoff, result
indexing, and telemetry indexing.

Source of record for human-facing closure:

- `docs/reports/research-closure-2026-04-28/REPORT.md`
- `docs/guides/lab-readiness.md`
- `docs/guides/supported-workflows.md`

## Executive View

The repo no longer has a broad "everything is half-done" problem. It has a
smaller closure problem:

- **multimode** is the only clearly high-value lane that still lacks its
  decisive baseline result set
- **multivar** has working infrastructure but an unresolved value question, so
  it should either get one targeted salvage pass or be closed as a negative
  result for the current optimizer
- **long-fiber** is already scientifically useful in the narrow supported range
  and mostly needs scope discipline and summary cleanup, not another open-ended
  simulation campaign

## Lane Audit

| Lane | Code | Results | Interpretation | Classification | Recommendation |
|---|---|---|---|---|---|
| Phase 31 reduced-basis continuation | complete | complete | complete | scientifically complete and ready to archive/summarize | keep as the main positive optimizer-path result |
| Multimode baseline stabilization | mostly complete | incomplete | incomplete | needs more simulation | finish now |
| Multivariable optimization | complete enough | present | incomplete / mixed | analysis/docs only to close current L-BFGS lane, or one short salvage pass | do not leave as an implied future win |
| Long-fiber 50-100 m single-mode | complete enough | present | mostly complete | needs analysis/docs only | close as a supported exploratory result |
| Long-fiber >100 m or multimode long-fiber | experimental | absent or partial | incomplete | needs more simulation, but low priority | explicitly park |
| Cold-start trust-region / preconditioning | code + diagnostics exist | partial | complete enough for a negative methodological result | analysis/docs only | archive as a parked optimizer-method lane |
| Stability / universality | analysis lane exists | partial | incomplete | needs more analysis/docs only | keep secondary, not blocking main closure |

## Detailed Findings

### 1. Multimode

Current state:

- `scripts/research/mmf/` contains a real MMF research stack:
  `mmf_setup.jl`, `mmf_raman_optimization.jl`, `baseline.jl`,
  `run_aggressive.jl`, `mmf_joint_optimization.jl`, and analysis helpers.
- `test/phases/test_phase16_mmf.jl` provides the right kind of regression
  coverage: M=1 reduction, FD gradient checks, energy accounting, and MMF
  auto-window sizing.
- The mild regime has already been closed out honestly as a **negative result**:
  `GRIN_50`, `L=1 m`, `P=0.05 W` has no meaningful Raman headroom.
- The repo recommends the meaningful regime clearly:
  `GRIN_50`, `L=2 m`, `P=0.5 W`, `:sum` cost, shared phase.

What is still missing:

- The Phase 36 baseline run has now supplied enough signal to identify the
  next blocker: threshold/aggressive regimes show large apparent gains, but
  the optimized outputs were marked `invalid-window`.
- The missing result is no longer "any MMF baseline"; it is a clean-window MMF
  validation result.
- Because the boundary diagnostic failed, the project still cannot claim that
  MMF suppression is scientifically usable.

Verdict:

- **Highest-value incomplete lane.**
- Code is not the blocker anymore.
- One disciplined burst session should either finish the lane or justify
  parking it.

Finish criteria:

1. Run `scripts/research/mmf/mmf_window_validation.jl` on burst.
2. Keep only threshold/aggressive `GRIN_50`, `L=2 m` validation as the
   immediate scope.
3. Inspect standard images for at least:
   - best run
   - typical run
   - any suspicious boundary-edge case
4. Write one durable MMF summary that states:
   - whether `:sum` stays the primary cost
   - whether MMF shows real optimization headroom
   - whether joint `{φ, c_m}` work remains worth pursuing

Close-outs now:

- Close the mild `L=1 m`, `P=0.05 W` baseline as a **negative / non-meaningful
  regime**.
- Keep joint MMF `{φ, c_m}` and fiber-type comparison parked until the
  aggressive baseline exists.

### 2. Multivariable / Multiparameter

Current state:

- Core implementation exists in
  `scripts/research/multivar/multivar_optimization.jl`.
- Reference driver exists in `scripts/research/multivar/multivar_demo.jl`.
- Unit + gradient smoke tests exist and current-agent-context marks the helper
  and gradient infrastructure as verified.
- Result artifacts exist under `results/raman/multivar/smf28_L2m_P030W/`.
- Validation artifacts under `results/validation/` show the saved runs are not
  numerically meaningless.

What is unresolved:

- The scientific claim "joint phase/amplitude/energy beats phase-only on the
  canonical problem" is still unsupported.
- Session A and the current-agent-context agree on the main point: this is an
  optimizer-behavior problem, not a missing-infrastructure problem.
- The lane is therefore at risk of staying permanently half-open because the
  repo has working code but no clear closure rule.

Verdict:

- The **current joint L-BFGS lane should not remain an implied future win**.
- Either give it one short, targeted salvage attempt, or close it as a
  negative result for the present optimizer choice.

Recommended closure rule:

- Minimum closure path:
  - write the repo-facing summary as:
    "multivariable infrastructure is valid, but current joint L-BFGS does not
    outperform phase-only at the canonical SMF-28 point"
  - park the lane
- Optional short salvage pass if time is available:
  1. amplitude-only warm-start from `φ_phase_only`
  2. two-stage run: amplitude-only first, then joint unfreeze

Stop/go criterion:

- If neither targeted run beats phase-only by at least `3 dB`, close the lane
  as a negative result for now and stop spending burst time on generic joint
  L-BFGS tuning.

### 3. Long-Fiber

Current state:

- The repo has a real long-fiber path:
  `longfiber_setup.jl`, `longfiber_optimize_100m.jl`,
  `longfiber_validate_100m.jl`, checkpointing, and standard-image support.
- Saved artifacts exist for the 100 m run and its validation.
- `agent-docs/current-agent-context/LONGFIBER.md` already states the supported
  interpretation correctly: 50-100 m single-mode work is supported research,
  but not yet "group-grade infrastructure."

What is complete:

- The project already has a credible 100 m exploratory result:
  flat `-0.20 dB`, warm-start `-51.50 dB`, refined `-54.77 dB`.
- The most important scientific point is already present:
  the 2 m warm-start carries surprisingly far, and the 100 m optimum is not
  explained by a simple quadratic-only phase story.

What is still open:

- The run is useful but not tightly converged.
- The currently synced headline uses `β_order = 2`.
- `>100 m` remains an extrapolation, not a supported result.
- Multimode long-fiber remains explicitly experimental.

Verdict:

- **Do not keep long-fiber as a broad open lane.**
- Close the supported claim narrowly:
  "single-mode SMF-style 50-100 m exploratory optimization is supported and
  scientifically useful."

Needed next actions:

- docs/status only if keeping the supported-range claim narrow
- simulation only if you want a stronger claim than the current one, for
  example:
  - `β3` comparison
  - multistart at 100 m
  - 200 m continuation

Recommendation:

- Treat 50-100 m SMF-style long-fiber as **scientifically complete enough to
  summarize now**.
- Explicitly park `>100 m` and multimode long-fiber as low-priority
  experimental extensions.

### 4. Reduced-Basis Continuation

Current state:

- Phase 31 already answered its main scientific question.
- The 2026-04-22 follow-up closed the key extension question:
  reduced-basis continuation does carry into deep full-grid refinement.

Verdict:

- **Complete.**
- This is the main positive optimization result and should be treated as such.
- It needs preservation and human-facing summarization, not more basin hunting.

### 5. Cold-Start Newton / Preconditioning

Current state:

- Phases 33-34 did enough to answer the immediate methodological question.
- The project now knows cold-start trust-region failure is not an initial-radius
  issue.

Verdict:

- Close the raw cold-start Newton story as a **negative / diagnostic result**.
- Park preconditioning as a future optimizer-method lane, not a current science
  blocker.

## Priority Order

1. **Finish multimode baseline.**
2. **Close multivar honestly** with either one targeted salvage pass or an
   explicit negative-result summary.
3. **Narrow and archive long-fiber** to the supported 50-100 m single-mode
   claim.
4. Leave reduced-basis continuation as the settled positive result.
5. Park raw Newton/preconditioning until the science-facing lanes are closed.

## Concrete Finish-Up Plan

### Multimode

- Run `scripts/research/mmf/mmf_window_validation.jl` on burst as the next
  heavy MMF session.
- Required outputs:
  - `results/raman/phase36_window_validation/*.jld2`
  - `results/raman/phase36_window_validation/mmf_window_validation_summary.md`
  - standard images for each optimized run
- Decision after run:
  - if threshold/aggressive `:sum` gives real headroom and clean trust metrics,
    keep MMF active and decide whether joint `{φ, c_m}` is worth a follow-up
  - if not, close the current Phase 36 MMF gains as invalid-window or weak
    evidence and park deeper MMF

### Multivar

- Do **not** reopen generic optimizer tuning.
- Either:
  - run amplitude-only warm-start and two-stage unfreeze as the last salvage
    pass, or
  - write the lane down as a negative current result and archive it

### Long-Fiber

- Keep the supported claim explicit:
  - supported: 50-100 m single-mode SMF-style exploratory work
  - unsupported / parked: >100 m production claims, multimode long-fiber
- Only schedule more long-fiber burst time if the publication claim truly
  needs `β3`, multistart, or 200 m continuation evidence
