# Phase 25 Research — Numerical Analysis Audit + CS 4220 / NMDS Crosswalk

## Source Frame

This update extends the earlier Phase 25 audit with David Bindel's
*Numerical Methods for Data Science* (`nmds`) book as an explicit second
external frame alongside the CS 4220 course notes. The most relevant `nmds`
chapters for this repo were:

- Performance Basics
- Notions of Error
- Floating Point
- Root Finding and Optimization
- Least Squares
- Signals and Transforms
- Krylov Subspaces
- Nonlinear Equations and Unconstrained Optimization
- Continuation and Bifurcation
- Nonlinear Least Squares
- Extrapolation and Acceleration

Compared to the earlier CS 4220 pass, the book adds stronger emphasis on:
- performance modeling and bottleneck methodology,
- explicit error-taxonomy language,
- transform-aware thinking around FFT-based computations,
- and acceleration / extrapolation as reusable numerical strategy.

## Standard Stack

- Keep the existing Julia stack and numerical libraries already present in the
  repo: `DifferentialEquations.jl`, `FFTW.jl`, `Optim.jl`, `Arpack.jl`,
  `Tullio.jl`, and the current forward/adjoint code.
- Reuse the existing matrix-free Hessian-vector-product work in
  `scripts/phase13_hvp.jl` and `scripts/phase13_hessian_eigspec.jl` rather than
  inventing a second Hessian toolchain.
- Reuse the current deterministic environment work in `scripts/determinism.jl`
  as the baseline reproducibility policy.
- Treat `.planning/codebase/CONCERNS.md` and recent phase research as local
  evidence about where the code already hurts.

## Architecture Patterns

### 1. Error analysis should be designed into the workflow, not retrofitted after surprises

The course repeatedly frames numerical work in terms of forward error,
backward error, conditioning, and mixed error, rather than only "did the code
run?" That maps directly to this repo's history: multiple high-impact issues
were only discovered after surprising results, not prevented by a standing
numerical acceptance framework.

Prescriptive implication:
- promote edge fraction, energy drift, determinism, gradient-check quality, and
  honest-grid checks from ad hoc diagnostics into first-class acceptance gates
  for future numerical phases.
- make mixed-error and forward/backward/residual language explicit in future
  numerical reports rather than leaving these ideas implicit.

### 2. Conditioning and scaling are central, not secondary

CS 4220's conditioning / nondimensionalization material applies unusually well
here. This project optimizes high-dimensional spectral phases across quantities
with mixed units, mixed magnitudes, and regime-dependent sensitivities. Several
current problems read as scaling problems more than physics failures.

Prescriptive implication:
- future optimizer work should explicitly scale variables, residuals, and
  stopping criteria in physically meaningful, dimensionless coordinates.

### 3. Globalization matters because the landscape is real and brittle

The course's line-search and globalization lectures fit this project closely.
This repo already uses L-BFGS effectively, but the codebase contains repeated
signs that convergence quality is too sensitive to initialization, parameter
scaling, and honest-grid choice.

Prescriptive implication:
- future Newton / Hessian / sharpness work should not be "raw local methods."
  They need globalization, trust diagnostics, and basin-of-convergence tests.

### 4. Matrix-free Krylov ideas are already partially here

The course's Krylov / Lanczos material is not speculative for this repo:
Phase 13 already built matrix-free HVPs and Lanczos-style eigenspectrum tools.
That means truncated-Newton, Hessian diagnostics, and low-rank curvature probes
are not greenfield research anymore; they are an extension of existing code.

Prescriptive implication:
- future second-order work should build on the HVP/Lanczos path already in
  `scripts/phase13_*.jl`, not restart from dense Hessians.

### 5. Regularization should be treated as model selection, not only smoothing

The course's regularization lectures map well onto phase-only optimization.
This codebase currently uses penalties, but much of the real design question is
which basis or reduced model best captures the physically meaningful phase
degrees of freedom.

Prescriptive implication:
- future regularization work should compare polynomial / band-limited /
  reduced-basis parameterizations, not only add scalar penalties to the current
  full-grid phase.

### 6. Performance modeling belongs in the numerics roadmap

The first audit treated performance as secondary. The `nmds` performance
chapter makes a stronger case: roofline-style reasoning, Amdahl/Gustafson
limits, and "time before you tune" are part of numerical-method design, not
just systems work.

Prescriptive implication:
- future performance work should move beyond anecdotal timing scripts and
  become a modeled performance phase for the forward/adjoint/FFT pipeline.

### 7. Extrapolation and acceleration are plausible future tools here

The `nmds` acceleration material adds a new angle: when this project solves
families of nearby problems, continuation and parameter studies may benefit
from sequence acceleration rather than only "better outer optimizers."

Prescriptive implication:
- continuation, warm-start, and parameter-study workflows should eventually be
  evaluated for acceleration / extrapolation ideas.

## Topic Crosswalk

### Floating point, mixed error, and backward error

Relevant course/book material:
- CS 4220 2026-01-30 / 2026-02-02
- `nmds`: Notions of Error, Floating Point

Direct codebase application:
- The project already had major trust failures caused by numerical setup rather
  than analytical derivation: undersized windows, FFTW plan-selection drift,
  and stale result interpretations.
- `scripts/determinism.jl` proves the team now cares about bit-identity, but
  the broader workflow still lacks a uniform numerical acceptance vocabulary.

What to do:
- Standardize a "numerical trust panel" for future phases:
  determinism status, edge fraction, energy drift, gradient-test result,
  and whether the reported metric is a forward or backward style quantity.
- Use mixed-error style metrics where relative error is misleading near zero.

Support from `nmds`:
- the error chapter foregrounds mixed error, propagation, conditioning,
  forward/backward/residual error, and saving random seeds.

### Conditioning, nondimensionalization, and scaling

Relevant course/book material:
- CS 4220 2026-01-30 / 2026-02-02
- `nmds`: Optimization theory, Root Finding and Optimization

Direct codebase application:
- `scripts/multivar_optimization.jl` already records a major 38 dB gap between
  joint and phase-only optimization that looks like preconditioning/scaling,
  not a physics impossibility.
- Current optimization variables combine quantities with very different natural
  magnitudes and curvatures.

What to do:
- Add an explicit conditioning/scaling audit phase for optimization variables,
  objective components, and stopping tolerances.
- Compare raw phase coordinates against dimensionless or basis-scaled ones.

Support from `nmds`:
- the text explicitly treats conditioning and scaling as part of problem
  formulation, not just post-hoc interpretation.

### Nonlinear solves, Newton, globalization, and basin control

Relevant course/book material:
- CS 4220 2026-03-20, 2026-03-23, 2026-03-25, 2026-04-08, 2026-04-17
- `nmds`: Root Finding and Optimization, Nonlinear Equations and Unconstrained Optimization

Direct codebase application:
- The repo's current optimizer story is good for local improvement but weak on
  explicit globalization policy.
- Several planned paths depend on Newton-like or Hessian-aware methods, yet the
  codebase does not currently benchmark basin size, safeguarded steps, or trust
  policies in a systematic way.

What to do:
- Any future Newton / sharpness / Hessian work should include backtracking or
  trust-region guards, not only a direction computation.
- Add adversarial-start benchmarks so "method worked once" is not mistaken for
  a robust numerical result.

Support from `nmds`:
- the root-finding/optimization chapters foreground initial guesses, global vs
  local search, and safeguards as part of the algorithmic story.

### Gauss-Newton / nonlinear least squares viewpoint

Relevant course/book material:
- CS 4220 2026-04-10
- `nmds`: Least Squares, Nonlinear Least Squares

Direct codebase application:
- Much of this project is framed as direct scalar optimization. But several
  subproblems naturally expose residual structure: matching target spectra,
  fitting reduced bases to `phi_opt`, or building robust surrogate diagnostics.

What to do:
- Where diagnostics are naturally residual-based, use least-squares structure
  and Gauss-Newton reasoning instead of treating every task as generic scalar
  minimization.

### Krylov / Lanczos / matrix-free second-order methods

Relevant course/book material:
- CS 4220 2026-03-16 and related eigen / Krylov lectures
- `nmds`: Krylov Subspaces, Eigenvalue Problems and the SVD

Direct codebase application:
- `scripts/phase13_hvp.jl` and `scripts/phase13_hessian_eigspec.jl` already
  implement matrix-free HVPs and Arpack-based eigenspectrum extraction.
- This is the strongest bridge from CS 4220 / `nmds` to existing code.

What to do:
- Promote a future truncated-Newton / Krylov phase that uses HVPs plus
  preconditioning ideas rather than dense Hessians.
- Also use Krylov thinking for cheaper curvature diagnostics and gauge-mode
  separation.

Support from `nmds`:
- the Krylov chapter reinforces the idea that basis/approximation choices are
  central, which matches this repo's matrix-free HVP direction well.

### Quasi-Newton / Jacobian reuse / chord-style ideas

Relevant course material:
- CS 4220 2026-04-13 / 2026-04-15

Direct codebase application:
- This repo repeatedly solves nearby problems in sweeps, continuation studies,
  and warm-start transfers.
- That makes "reuse linearization information across related solves" a plausible
  future improvement, especially for expensive Hessian/Jacobian approximations.

What to do:
- Investigate whether nearby-parameter runs can reuse curvature models,
  reduced Hessians, or warm-started quasi-Newton state.

### Regularization, factor selection, and reduced models

Relevant course/book material:
- CS 4220 2026-02-25
- `nmds`: Least Squares, Nonlinear Least Squares

Direct codebase application:
- The project already studies polynomial decomposition of `phi_opt`, which is a
  strong hint that basis selection is the right abstraction.
- A full-grid phase vector is likely an over-parameterized model in some
  regimes.

What to do:
- Compare full-grid, polynomial, band-limited, and low-rank phase models with
  explicit explained-variance and robustness tradeoffs.

### Continuation and homotopy

Relevant course/book material:
- CS 4220 2026-03-25
- `nmds`: Continuation and Bifurcation

Direct codebase application:
- This repo already uses warm starts informally across fiber length, power, and
  long-fiber transfers, but not as a disciplined continuation framework.

What to do:
- Build an explicit continuation schedule over `L`, `P`, `N_phi`, regularizer
  strength, or multimode complexity for hard regimes.

### Performance modeling, transforms, and FFT-aware structure

Relevant `nmds` material:
- Performance Basics
- Signals and Transforms

Direct codebase application:
- This repo is FFT-heavy, convolution-heavy, and already has a standalone
  threading benchmark in `scripts/benchmark_threading.jl`.
- The current performance story is still mainly empirical rather than modeled.

What to do:
- Add a future roofline/performance-modeling phase for the forward solve,
  adjoint solve, FFT plans, and tensor contractions.
- Use Amdahl-style decomposition to quantify when more threading or burst-VM
  scale can no longer help because the serial/non-scalable fraction dominates.

### Extrapolation and acceleration for study families

Relevant `nmds` material:
- Extrapolation and Acceleration

Direct codebase application:
- This project repeatedly computes sequences of related solves:
  sweeps over `L,P`, continuation-like warm starts, basis-size scans, and
  long-fiber transfer studies.

What to do:
- Investigate whether sequence acceleration can reduce the number of expensive
  fully optimized points needed in parameter studies.

## Blockers and Failure Modes Surfaced by the Audit

### 1. Planning drift is now a real engineering risk

Evidence:
- `.planning/STATE.md` references missing files such as
  `.planning/notes/newton-vs-lbfgs-reframe.md` and
  `.planning/research/questions.md`.
- `ROADMAP.md` lags behind `STATE.md` in visible detail and status in several
  places.

Why it matters numerically:
- it becomes harder to know which results are current, which assumptions were
  superseded, and which numerical fixes were already absorbed.

### 2. The workflow still contains stale or broken numerical surfaces

Evidence:
- `src/analysis/analysis.jl` is marked broken in planning and remains parked as
  such.
- `STATE.md` records an urgent follow-up to check burst results and stop the VM.

Why it matters numerically:
- broken analysis surfaces and stale background jobs reduce trust in derived
  claims and waste attention on infrastructure debt.

### 3. Numerical trust checks are still fragmented

Evidence:
- honest-grid logic, determinism, gradient testing, and boundary-condition
  checks exist, but they live in different scripts and phases rather than as a
  stable acceptance bundle.

Why it matters numerically:
- future phases can still accidentally report impressive numbers without the
  full trust stack.

### 4. Performance investigation is still mostly empirical

Evidence:
- `scripts/benchmark_threading.jl` exists, but the repo still lacks a stable
  performance model for FFTs, tensor contractions, and serial fractions.

Why it matters numerically:
- compute decisions are harder to justify,
- parallel speedup expectations are easier to overclaim,
- and future optimization work may spend effort on the wrong bottlenecks.

### 5. Shared architecture choices make numerical reasoning harder

Evidence:
- `Dict{String,Any}` parameter passing in `src/helpers/helpers.jl`
- include-based script composition and duplicated orchestration patterns

Why it matters numerically:
- weak typing and mutable dictionary conventions make it easier to smuggle
  inconsistent state into experiments and harder to reason about scaling /
  invariants.

### 6. Optimizer behavior is not yet framed in CS 4220 / NMDS terms

Evidence:
- current optimization code has good local machinery, but limited explicit
  language around conditioning, basin size, backward error, or globalization.

Why it matters numerically:
- it is harder to compare methods honestly, especially if Newton-like paths are
  added.

## Prescriptive Guidance

1. Add a numerics-governance layer before adding more optimizer complexity.
   This should unify conditioning/scaling, trust metrics, and honest stopping
   criteria.
2. Treat globalization as mandatory for future second-order work.
3. Build future curvature work on the existing HVP/Lanczos path.
4. Prioritize reduced-basis / regularized parameterization work before
   expanding optimizer sophistication further.
5. Add a real performance-modeling phase rather than relying only on ad hoc
   timing scripts.
6. Fix planning drift and stale state references; they are now impeding clean
   numerical work.
7. Keep extrapolation/acceleration in the backlog, but only after the trust and
   scaling layers are cleaner.

## Confidence

- High confidence on the direct applicability of conditioning, globalization,
  Krylov/Lanczos, and regularization ideas.
- Medium-high confidence on performance-modeling relevance because this repo is
  already FFT-heavy and has an existing benchmarking script that can be matured.
- Medium confidence on extrapolation/acceleration payoff; it is promising, but
  more indirect than scaling or trust governance.
- Medium confidence on how much quasi-Newton / Jacobian-reuse ideas will pay
  off in this specific codebase without experiments.
- High confidence that planning drift and fragmented trust checks are current
  blockers independent of any future algorithm choice.

---

*Compiled 2026-04-20 for Phase 25.*

---

## Second-Opinion Addendum (2026-04-20)

Verification trail for this addendum:
`.planning/quick/260420-oyg-independent-numerics-audit-of-fiber-rama/260420-oyg-NOTES.md`.

### Topic-by-topic CS 4220 / NMDS crosswalk (second pass, code-verified)

The original crosswalk is directionally sound. The additions below tie
each topic to a specific code location so future phases know where
to start.

#### Floating-point, mixed error, and backward error — addition

The repo's mixed-unit representation in `sim` (`src/helpers/helpers.jl:48-67`)
is a concrete *scaling* instance that NMDS's error chapter treats
explicitly: `time_window` in ps, `Δt` in ps, `ts` in **seconds**, `f0` in THz,
`ω0` in rad/ps, `ε` carrying two `1e-12` conversions, `hRt` multiplying
`ts * 1e15` to get fs (line 107). This is the exact *nondimensionalize-first*
target the text prescribes. The original research doc names the topic
but not the file.

The gradient-validation pattern in the repo is a *ratio check* (line
280 of `raman_optimization.jl`). CS 4220's standard idiom is a
**Taylor-remainder-2** slope test:
compute `r(ε) = |J(φ+εv) − J(φ) − ε∇J·v|` for a geometric sequence of
ε and verify that `r(ε/2) / r(ε) ≈ 1/4`. A ratio check accepts gradients
that are uniformly mis-scaled; the slope test does not. Adding this is a
few dozen lines and is a standing recommendation.

#### Conditioning, nondimensionalization, and scaling — addition

Phase 25 flagged scaling generically. Code-verified specifics:

1. **Log-cost scale factor is state-dependent.**
   `raman_optimization.jl:124` multiplies the physics gradient by
   `10/(J · ln 10)`. As J → 0 this grows without bound. The GDD
   regularizer gradient on line 143 and boundary regularizer on line 171
   are **not** multiplied by this factor. Effective regularizer weight
   therefore drops by 10 dB per 10 dB of suppression. The user-facing
   knob `λ_gdd = 1e-4` is not a fixed weight.
2. **Hessian probe objective ≠ L-BFGS objective.** `phase13_hvp.jl:74`
   probes the linear physics Hessian; `raman_optimization.jl` optimizes
   dB cost with regularizers. Eigenspectrum analysis is of a related but
   distinct surface.
3. **`sim` dict** carries a hybrid unit system (above). This is the
   prototypical CS 4220 "change coordinates before optimizing" target.

#### Nonlinear solves, globalization, basin control — refinement

Phase 25 writes "the repo has strong local machinery but weak explicit
globalization policy." Code check:

- `scripts/raman_optimization.jl:235` — `LBFGS()` from Optim.jl uses
  **HagerZhang** line search (strong Wolfe conditions) by default.
- `scripts/amplitude_optimization.jl:273` — `Fminbox(LBFGS(m=10))` with
  true box constraints.

Both are real globalization layers for **1st-order** work. The real gap
is for **indefinite 2nd-order** updates, which is what Newton / truncated-
Newton on HVPs would need. Trust-region (Steihaug-Toint), Cauchy-point
logic, and negative-curvature detection are the class of safeguards that
matter here — not "add a line search to L-BFGS".

#### Gauss-Newton / NLS — unchanged

Second-opinion verdict: agree with original. No addition.

#### Krylov / Lanczos / matrix-free second-order — refinement

Phase 25 correctly identifies this as the strongest existing bridge.
Two code-verified caveats:

1. `P13_DEFAULT_EPS = 1e-4` in `phase13_hvp.jl:48` is a fixed FD step.
   NMDS's Krylov chapter and CS 4220's FD notes both call this out:
   optimal ε scales as `sqrt(eps_mach · ‖∇J‖) / ‖v‖`. Fixed ε is
   right at one specific gradient magnitude and wrong everywhere else.
   Near L-BFGS convergence, ‖∇J‖ is small → fixed 1e-4 step is now
   dominated by round-off, corrupting the Arpack-reported
   eigenspectrum at exactly the regime where curvature information
   would matter most.
2. Matrix-free shift-invert for interior eigenvalues is acknowledged
   impossible in `phase13_hessian_eigspec.jl:30-33`. The remedy (if
   near-zero modes matter for gauge analysis) is LOBPCG or inexact-Newton
   CG with a diagonal preconditioner, **not** Arpack. The existing
   infrastructure is Lanczos; it will find extreme eigenvalues, not
   interior ones.

#### Quasi-Newton / Jacobian reuse — unchanged

Second-opinion agreement. No addition beyond noting that the `m=10`
memory in `Fminbox(LBFGS(m=10))` is already a quasi-Newton-with-limited-
memory choice; further work should start from comparing `m` scaling, not
from reimplementing limited-memory ideas.

#### Regularization, factor selection, reduced models — refinement

**Key correction:** DCT reduced-basis is already implemented and
gradient-validated for amplitude optimization:
- `scripts/amplitude_optimization.jl:180-192` — `build_dct_basis`.
- `:201-209` — `cost_and_gradient_lowdim` with chain rule
  `grad_c = δ · B' · grad_A`.
- `:257-276` — `Fminbox(LBFGS)` over coefficient space with
  `c_k ∈ [-1, 1]`.
- `:316-338` — analytic-vs-FD gradient validation in the coefficient space.

The `reduced-basis-phase-regularization` seed should **extend** this
machinery (swap amplitude → phase; use `cis(Σ c_k · B_k)` for the
parameterization; adjoint chain rule remains `B'·grad`) rather than
invent from scratch. Correct scope = "port DCT from A(ω) to φ(ω) and
measure", which is small, not phase-sized, unless paired with a
systematic basis-family sweep (polynomial / DCT / Chebyshev / band-
limited).

#### Continuation and homotopy — unchanged

Second-opinion agreement.

#### Performance modeling, transforms, FFT-aware structure — addition

The original NMDS pass correctly scopes the seed. One connection it
doesn't make:

- `scripts/determinism.jl` pins FFTW to **ESTIMATE**. `FFTW.ESTIMATE`
  picks a plan without timing, costing measurable throughput vs
  `FFTW.MEASURE` / `FFTW.PATIENT` (typically 1.5–3× slower for repeated
  transforms at fixed size). The determinism seed and the
  performance-modeling seed do not reference each other. They should —
  "the reproducibility tax on FFT throughput" is a standard CS 4220 /
  NMDS framing, and the performance phase's roofline analysis must
  budget for it.

#### Extrapolation and acceleration — unchanged

Second-opinion verdict: agree, low priority, stays in backlog.

### New numerical failure modes surfaced in the code pass

Each is distinct from the six failure modes in §Blockers and Failure
Modes Surfaced by the Audit above.

7. **Absorbing boundary is untracked.** `src/helpers/helpers.jl:59-63`
   builds a super-Gaussian order-30 attenuator at 85% of the window
   half-width and applies it inside the ODE RHS
   (`src/simulation/simulate_disp_mmf.jl:34`). Any energy that walks
   into the outer 15% is silently absorbed. `check_boundary_conditions`
   measures **surviving** edge energy — energy already absorbed does
   not appear anywhere. At long fiber / high power, the reported dB is
   partly the dB of a boundary-attenuated field. This is a physics-
   coupled numerical-honesty failure distinct from "the grid was too
   small" and is not addressed by the current `recommended_time_window`
   formula.

8. **Cost-surface incoherence across the project.** Phase, amplitude,
   HVP oracle, and regularizer paths each choose a different
   convention for which surface they are differentiating:

   | File:line | Cost returned | Regularizer scaled? |
   |---|---|---|
   | `raman_optimization.jl:121-129` (log_cost=true default) | dB | No |
   | `raman_optimization.jl:127-128` (log_cost=false) | linear | N/A |
   | `amplitude_optimization.jl:402-446` | linear | Yes (flat 1.0 weight) |
   | `phase13_hvp.jl:74` | linear, no regularizer | N/A |
   | `chirp_sensitivity` callsite `:332` | dB (default) | N/A |
   | `plot_chirp_sensitivity:361` | **applies 10·log10 again** → DomainError | N/A |

   The optimization pipeline reaches deep suppression via a dB-scaled
   physics gradient whose effective regularizer weight is state-
   dependent. The HVP pipeline probes a different surface. Diagnostics
   (chirp sensitivity) have a latent bug in the conversion.

9. **ODE `abstol` is default (1e-6) throughout.** Both solvers
   (`simulate_disp_mmf.jl:182`, `sensitivity_disp_mmf.jl:301`) set
   `reltol=1e-8` but no `abstol`. At -60…-80 dB suppression,
   `|ũω|` in the optimized Raman sideband is O(1e-3…1e-4) on a
   baseline of O(1). Relative error of 1e-8 and absolute error of 1e-6
   means abstol dominates in the small-amplitude region being
   optimized. Whether this biases the deepest-suppression gradients is
   untested.

10. **Interaction-picture ODE is a partial ETD scheme.** The
    `cis(Dω · z)` transform in the RHS
    (`simulate_disp_mmf.jl:28-29, 60`) is mathematically equivalent to
    a first step of an exponential integrator on the linear operator,
    but the outer solver is `Tsit5()`. A true exponential integrator
    (ETDRK4, Krogstad, Magnus) would be the fully consistent form and
    may permit larger steps at equal accuracy. This is an
    **opportunity**, not a defect. `Vern9()` is documented in
    `CLAUDE.md` as an alternative but unused.

### Updated prescriptive guidance

Keep all seven original prescriptive items. Add or sharpen:

8.  Unify the log / linear / regularized cost convention across the
    optimizer, HVP oracle, and diagnostic paths **before** starting any
    truncated-Newton or sharpness work. This is the single cleanest
    cost-reduction in the numerical architecture of this repo.
9.  Treat the super-Gaussian attenuator as an **absorbing boundary** and
    add a standing "energy absorbed per ODE step" diagnostic. The
    `recommended_time_window` formula does not remove the need for this
    metric; it only shifts the onset of significant absorption.
10. Replace the fixed FD-HVP ε with an adaptive one tied to `‖∇J‖`.
11. Add Taylor-remainder-2 slope checks to every gradient-validation
    path. Keep the ratio checks, add the slope.
12. Report a condition-number proxy `κ = λ_max / max(|λ_min_nonzero|, eps)`
    from the existing Arpack infrastructure as a standard trust-report
    field.

### Confidence (updated)

- **Very high confidence** that defects 1 (chirp sensitivity), 2
  (cost-surface incoherence), and 5 (absorbing-boundary mass loss) are
  live in `sessions/numerics` HEAD (`de17fc5`); they are grep-able
  one-line bugs or documented in the code comments themselves.
- **High confidence** that defects 3 (Hessian / objective mismatch) and
  4 (FD-HVP ε) matter for any future truncated-Newton phase.
- **Medium-high confidence** that defect 9 (ODE abstol) biases
  gradients at the deepest suppression regimes. Needs one empirical
  test before being reported as a risk rather than a concern.
- **Unchanged high confidence** on the original Phase 25 conclusions
  about Krylov applicability, reduced-basis direction, and planning
  drift.

