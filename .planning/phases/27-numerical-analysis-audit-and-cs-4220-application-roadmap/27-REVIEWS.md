---
phase: 25
reviewers: [claude]
reviewed_at: 2026-04-20T16:55:59Z
plans_reviewed: [27-01-PLAN.md]
status: pending_external_review
---

# Cross-AI Plan Review — Phase 27

## Runtime Availability

Detected external CLIs in this session:
- `claude`: available
- `gemini`, `codex`, `coderabbit`, `opencode`, `qwen`, `cursor`: unavailable

## Review Status

The external review step was limited by local CLI availability. A `claude`
review was requested after the plan and report artifacts were prepared, but the
CLI did not return usable output within the local timeout despite a valid
prompt file being built. That is recorded here as an execution-environment
limitation, not a skipped workflow step.

## Claude Review

Unavailable in this session.

Observed behavior:
- prompt file `/tmp/phase25_review_prompt.md` was created successfully
- `claude -p < /tmp/phase25_review_prompt.md` did not yield output within the
  timeout window

## Internal Review Note

### Summary

The phase artifacts are directionally strong and scoped correctly. The largest
remaining risk is not in the recommendations themselves, but in the fact that
the report points to planning drift without fixing that drift comprehensively.

### Concerns

- `MEDIUM`: The report documents planning drift, but only a minimal state/roadmap
  update was done in this phase. A follow-up cleanup phase is still needed.
- `LOW`: Some recommendations intentionally remain high-level because this is a
  research-only phase. That is correct for scope, but means implementation
  details must be worked out later.

### Suggestions

1. Promote the conditioning/backward-error seed before any further optimizer
   experimentation.
2. Open a small planning-cleanup follow-up if the stale `.planning/**`
   references keep accumulating.

### Risk Assessment

Overall risk: `LOW-MEDIUM`

Rationale:
- low risk that the report is directionally wrong,
- medium risk that future sessions ignore the recommended order and jump
  straight to sophisticated optimizer work without first fixing scaling/trust
  governance.

---

## Second-Opinion Addendum (2026-04-20)

**Reviewer:** Independent code-verification pass from quick task
`260420-oyg-independent-numerics-audit-of-fiber-rama`.
**References:** Cornell CS 4220 s26, Bindel's *Numerical Methods for Data Science*.
**Scope:** skeptical recheck of Phase 27 against `sessions/numerics` HEAD
(`de17fc5`). Verification trail:
`.planning/quick/260420-oyg-.../260420-oyg-NOTES.md`.

### Verdict vs. original internal review

The original internal review classified Phase 27 overall risk as
**LOW-MEDIUM** with the observation that "the report documents planning
drift but only a minimal state/roadmap update was done in this phase."
The second-opinion pass **raises one category to MEDIUM** and adds two
items the original review could not flag because it predated the code
verification:

- `MEDIUM` (new): **Cost-surface incoherence** across
  `cost_and_gradient` (phase), `cost_and_gradient_amplitude`,
  `cost_and_gradient_lowdim`, `phase13_hvp::build_oracle`,
  `chirp_sensitivity`, and the regularizer gradient paths. Multiple files
  differentiate different surfaces. This is a **substantive numerical
  architecture issue** that will contaminate truncated-Newton, sharpness,
  and regularization comparisons if not fixed first. See
  `27-REPORT.md#Second-Opinion Addendum` defects 1–3 and the new seed
  `cost-surface-coherence-and-log-scale-audit.md`.

- `MEDIUM` (new): **Absorbing-boundary mass loss is untracked**
  (`src/helpers/helpers.jl:59-63` + use in
  `src/simulation/simulate_disp_mmf.jl:34`). `check_boundary_conditions`
  measures surviving edge energy only. This is a physics-coupled
  numerical-honesty failure distinct from the "honest grid" work already
  done. See the new seed `absorbing-boundary-and-honest-edge-energy.md`.

- `MEDIUM` (amplification of original): The recommendation "promote
  conditioning/backward-error seed first" should be **rescoped into a
  bundle** that includes cost-surface coherence, running edge-absorption
  metric, adaptive FD-HVP ε, per-run condition-number probe, and
  Taylor-remainder-2 slope tests. See the single-most-important next
  phase in `27-REPORT.md#Second-Opinion Addendum`.

### Concerns added after code verification

- `MEDIUM`: The `reduced-basis-phase-regularization` seed reads as
  greenfield but a gradient-validated DCT basis already exists for
  amplitude (`scripts/amplitude_optimization.jl:180-209`). The seed
  should explicitly scope extension, not invention.
- `LOW-MEDIUM`: `phase13_hvp.jl:48` hardcodes `ε = 1e-4` for the FD-HVP.
  This is the wrong step at L-BFGS convergence (the regime where HVP
  matters most).
- `LOW-MEDIUM`: `plot_chirp_sensitivity` at
  `raman_optimization.jl:361` applies `lin_to_dB` to values already in
  dB (domain error on negative `log10`). Either latent or silently
  swallowed; needs a regression test.
- `LOW`: ODE `abstol` is default 1e-6 on both forward and adjoint
  solvers. At -80 dB suppression, this is within two orders of the
  Raman-shifted sideband amplitude being optimized. An untested
  empirical question, not a confirmed defect.

### Items the second opinion explicitly agrees with

- FFTW determinism is wired correctly and consistently.
- Raman overflow fix is correct and present.
- dB cost fix at `raman_optimization.jl:121-129` is correct.
- HVP/Lanczos bridge is real, not speculative.
- Planning drift framing is correct.
- Continuation and extrapolation seed scoping is correct.
- Globalization as a Newton prerequisite is correct *in direction*, but
  overstated for 1st-order work — see Refinement below.

### Framing refinements

- "Weak globalization" overstates the 1st-order gap: `LBFGS()` already
  uses HagerZhang line search and `Fminbox(LBFGS(m=10))` provides box
  constraints. The real gap is **trust-region / indefinite-Hessian
  safeguards** for 2nd-order work.
- "Determinism seed + performance seed are independent" is wrong: the
  ESTIMATE-vs-MEASURE choice is a reproducibility / throughput tradeoff
  that both seeds must budget for. Cross-reference them.

### Updated overall risk

**MEDIUM** — not LOW-MEDIUM. Reason: two MEDIUM items were previously
under the radar (cost-surface incoherence and untracked boundary
absorption), and a latent chirp-sensitivity bug may be throwing silently
in canonical runs. None of these require a physics rewrite; they are
all numerical-architecture cleanups that the existing conditioning seed,
if rescoped into a bundle per the addendum in `27-REPORT.md`, cleanly
absorbs.
