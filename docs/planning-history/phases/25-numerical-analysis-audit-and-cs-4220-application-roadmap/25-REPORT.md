# Phase 25 Report — Numerical Analysis Audit and CS 4220 / NMDS Application Roadmap

## Executive Verdict

The CS 4220 material is highly relevant to this project, but not because the
repo is "missing advanced math" in general. The best applications are targeted:

1. **Conditioning and scaling** are the clearest open numerical problem.
   Several current pain points read as poorly scaled optimization problems more
   than missing physics.
2. **Globalization** should be mandatory for any future Newton / Hessian-aware
   optimizer path.
3. **Krylov/Lanczos methods** are already partly implemented here via the Phase
   13 HVP tooling, so they are realistic next steps, not speculative research.
4. **Regularization and reduced models** are likely a better next leverage point
   than immediately adding more optimizer sophistication.
5. **Performance modeling** is more important than the first audit made it
   sound; this repo should have a roofline/Amdahl-style performance phase rather
   than only empirical threading experiments.
6. **Planning drift and fragmented trust checks** are now material blockers to
   clean numerical progress.

The `nmds` book reinforces the earlier audit and adds two new directions:
- treat performance modeling as part of numerical method design,
- and keep extrapolation/acceleration on the roadmap for study families and
  continuation workflows.

## What the Course and Book Add

### Highest-value topics for this repo

| Topic | Why it matters here | Repo evidence | Recommendation |
|---|---|---|---|
| Conditioning and scaling | Optimization variables and objectives have mixed units / curvatures | `scripts/multivar_optimization.jl`, current scaling problems in planning concerns | Run a dedicated scaling / conditioning audit before more optimizer expansion |
| Forward / backward / mixed error | Wrong grids or nondeterministic plans can fake good results | Phase 4, 15, 21, `scripts/determinism.jl` | Standardize numerical trust metrics across future phases |
| Globalization / line search | Future Newton-like work will be fragile without safeguards | planned Newton / sharpness work, local-optimizer behavior | Require backtracking/trust-region logic in future second-order work |
| Krylov / Lanczos | Matrix-free HVPs already exist | `scripts/phase13_hvp.jl`, `scripts/phase13_hessian_eigspec.jl` | Build truncated-Newton / curvature diagnostics on top of these |
| Regularization / factor selection | Full-grid phase optimization is likely over-parameterized in some regimes | Phase decomposition work, reduced-basis hints in planning | Compare basis choices, not only penalty weights |
| Continuation / homotopy | The project already warm-starts informally across regimes | sweep / long-fiber / matched-baseline workflows | Turn warm starts into explicit continuation schedules |
| Performance modeling / roofline / Amdahl | The code is FFT-heavy and burst-compute-heavy; empirical timings alone are not enough | `scripts/benchmark_threading.jl`, FFT-heavy forward/adjoint pipeline | Add a modeled performance phase before further compute scaling work |

### Medium-value topics

| Topic | Relevance | Recommendation |
|---|---|---|
| Gauss-Newton / nonlinear least squares | Strong for residual-based diagnostics and reduced-model fitting, moderate for the main scalar Raman objective | Use for diagnostic/model-fitting subproblems rather than forcing it onto the core objective |
| Quasi-Newton / Broyden / chord-style reuse | Potentially useful for nearby-parameter solves and reused linearizations | Worth experimenting with only after scaling and trust policy are cleaner |
| Extrapolation / acceleration | Potentially useful for parameter studies and continuation-style workflows | Keep as a future experimental phase, not a first-line change |
| Dense factorization details | Conceptually useful, but less leverage than matrix-free second-order tools in this repo | Lower priority |

### Low-priority or indirect topics

| Topic | Why lower priority here |
|---|---|
| Classical dense direct linear algebra | Already handled by library calls; not the current bottleneck |
| Sparse direct methods | Only indirectly relevant unless the project shifts toward very large structured Jacobians/Hessians |
| Generic 1D root-finding tactics | Helpful conceptually, but not a major practical gap in the current code |

## Current Numerical Assets the Repo Already Has

These are real strengths and should be built on rather than replaced:

- **Deterministic FFT environment**:
  `scripts/determinism.jl` plus ESTIMATE plan usage in `src/simulation/*.jl`.
- **Forward/adjoint validation culture**:
  Taylor remainder tests, validation scripts, and explicit solver correctness
  work already exist.
- **Matrix-free Hessian tooling**:
  `scripts/phase13_hvp.jl` and `scripts/phase13_hessian_eigspec.jl`.
- **Honest-grid thinking**:
  Phase 21 recovery work shows the project now knows that "good dB on a bad
  grid" is not an acceptable result.
- **Strong execution memory of prior failures**:
  The planning artifacts preserve lessons from several important bugs.

## What Is Actually Going Wrong

### 1. Numerical trust is still distributed, not governed

The repo has individual fixes for determinism, honest grids, and gradient
validation, but no single standing contract for what makes a new numerical
claim trustworthy.

Symptoms:
- trust checks are spread across multiple phases/scripts,
- future work can still bypass part of the trust stack,
- it is easy to report a metric without also reporting its numerical honesty.

Impact:
- every new numerical phase risks re-learning the same lessons manually.

### 2. Conditioning / scaling is under-specified

This is the strongest technical gap surfaced by the audit.

Symptoms:
- multivariable optimization is already flagged as likely broken by
  preconditioning/scaling rather than by physics,
- stopping criteria and gradients are not consistently discussed in scaled,
  dimensionless terms,
- optimization variables live in coordinate systems chosen mostly for
  implementation convenience.

Impact:
- new optimizer comparisons will be noisy or misleading if scaling is not
  addressed first.

### 3. Globalization policy is missing for future second-order work

The repo has strong local machinery but weak explicit basin / safeguard policy.

Symptoms:
- current planning discussions around Newton/Hessian work focus heavily on
  curvature extraction and method choice,
- there is less concrete infrastructure around step acceptance, basin tests,
  or trust-region logic.

Impact:
- a Newton path could look mathematically sophisticated while remaining
  operationally brittle.

### 4. Planning drift is now harming numerical work

This is not cosmetic.

Evidence from this audit:
- `.planning/STATE.md` references missing files.
- `ROADMAP.md` and `STATE.md` are not fully aligned in visible detail/status.
- urgent compute/job notes remain live in state.

Impact:
- makes it harder to know what is settled,
- increases integration/recovery errors,
- weakens trust in reported numerical conclusions.

### 5. Performance investigation is still mostly empirical

Symptoms:
- `scripts/benchmark_threading.jl` benchmarks opportunities, but the project
  still lacks a stable performance model for FFTs, tensor contractions,
  serial/non-serial fractions, and honest expected speedups.

Impact:
- compute decisions are harder to justify,
- parallel speedup expectations are easier to overclaim,
- and future optimization work may burn effort on the wrong bottlenecks.

### 6. Shared architecture still makes numerical reasoning harder than necessary

Symptoms:
- heavy use of `Dict{String,Any}` for simulation/fiber state,
- include-based composition and script-level orchestration,
- mutable conventions that make exact state tracking harder.

Impact:
- harder to reason cleanly about invariants, scaling, and reproducibility.

## Immediate Recommendations

These are not separate future phases yet; they are the most actionable findings
from the audit.

1. Define a standard numerics acceptance bundle for future optimization work.
   Minimum fields: determinism status, edge fraction, energy drift, gradient
   validation status, optimizer convergence status, and whether the headline
   metric is on an honest grid.

2. Run a dedicated conditioning/scaling audit before extending optimizer logic.
   This is the most likely place to unlock current pathologies efficiently.

3. Treat globalization as a hard requirement for any future Newton/Hessian path.
   No unguarded second-order rollout should be treated as serious evidence.

4. Fix planning drift and stale references in `.planning/**`.
   This is engineering debt that now blocks good numerical work.

5. Add a real performance-modeling pass for the FFT/adjoint pipeline.
   This should use the repo's existing benchmark script as input, but go beyond
   raw timings into bottleneck and scaling models.

6. Prefer reduced-basis investigations before adding more full-grid optimizer
   complexity.

## Recommended Future Work

### A. Conditioning and backward-error framework

Rationale:
- This is the most foundational missing layer.
- It improves almost every later optimizer / robustness phase.

Expected outputs:
- dimensionless variable scaling,
- optimizer stopping criteria tied to scaled residuals,
- standard trust report for every run family.

### B. Globalized second-order optimizer path

Rationale:
- The repo already has HVP/Lanczos machinery.
- The next step is not "add Newton"; it is "add safeguarded second-order
  methods with honest acceptance criteria."

Expected outputs:
- truncated Newton or related method,
- backtracking or trust-region policy,
- basin-size / robustness benchmarks.

### C. Reduced-basis / regularized phase models

Rationale:
- Likely lower-dimensional structure exists in many regimes.
- This may give a bigger practical payoff than raw optimizer sophistication.

Expected outputs:
- polynomial / band-limited / low-rank parameterizations,
- explained-variance and robustness tradeoff study,
- clearer link between physics interpretation and numerical model size.

### D. Continuation framework

Rationale:
- Warm starts are already central to this project.
- Formal continuation would turn an informal tactic into a reusable numerical
  strategy.

Expected outputs:
- path-following over `L`, `P`, `N_phi`, or regularizer strength,
- honest continuation failure detection,
- better basin control in hard regimes.

### E. Performance-modeling / roofline audit

Rationale:
- The `nmds` book makes a stronger case that performance modeling is part of
  numerical method design, not an afterthought.
- This repo is sufficiently FFT-heavy and burst-compute-aware that the missing
  model is now a real planning gap.

Expected outputs:
- bottleneck decomposition of forward solve, adjoint solve, FFT plans, and
  tensor contractions,
- Amdahl-style upper bounds on useful parallel speedup,
- better decisions about where burst-VM compute actually buys value.

### F. Extrapolation and acceleration for study families

Rationale:
- The repo repeatedly solves families of nearby problems.
- Sequence acceleration may reduce total expensive solve count in sweeps or
  continuation-like studies.

Expected outputs:
- one or more acceleration experiments on structured study families,
- comparison against naive warm-start pipelines,
- explicit verdict on whether acceleration is worth the added complexity.

## Seeds Planted

This phase planted the following seeds:

1. `numerics-conditioning-and-backward-error-framework.md`
2. `globalized-second-order-optimization.md`
3. `truncated-newton-krylov-preconditioning.md`
4. `reduced-basis-phase-regularization.md`
5. `continuation-and-homotopy-schedules.md`
6. `performance-modeling-and-roofline-audit.md`
7. `extrapolation-and-acceleration-for-parameter-studies.md`

## Bottom Line

The strongest lesson from the CS 4220 / NMDS crosswalk is not "switch to
Newton." It is:

- make numerical trust explicit,
- scale the problem properly,
- globalize future second-order methods,
- model performance instead of guessing at it,
- and use the matrix-free/HVP infrastructure already in the repo.

If those steps are taken in that order, the project is well positioned to turn
its current solver/optimizer stack into something much more systematic without
discarding the substantial numerical work already done.

---

## Second-Opinion Addendum (2026-04-20)

**Source:** Independent audit done after the first Phase 25 pass, with all
claims cross-checked against the actual code in `sessions/numerics`. Full
verification trail in
`.planning/quick/260420-oyg-independent-numerics-audit-of-fiber-rama/260420-oyg-NOTES.md`.
References: Cornell CS 4220 s26 (`https://github.com/dbindel/cs4220-s26/`) and
Bindel's *Numerical Methods for Data Science* (`https://www.cs.cornell.edu/~bindel/nmds/`).

**Method:** for each claim in §Assets / §What Is Actually Going Wrong /
§Recommended Future Work, find a file:line citation in the code. Where the
code says something different from the report, flag it. Where the code
surfaces a numerical issue the report doesn't mention, flag it.

### What the original Phase 25 got right

- **FFTW determinism is wired consistently.** `scripts/determinism.jl:75-76`
  pins FFTW + BLAS to 1 thread; every FFT plan in `src/simulation/*.jl` uses
  `flags=FFTW.ESTIMATE` (`simulate_disp_mmf.jl:84-87`,
  `sensitivity_disp_mmf.jl:229-234`). The determinism contract holds.
- **Raman-response overflow fix is present** at `src/helpers/helpers.jl:107`
  and `:182` (`ts_pos = max.(ts, 0.0)` before `exp`).
- **dB cost fix is present** at `scripts/raman_optimization.jl:121-129`
  (`J_phys = 10·log10(J); log_scale = 10 / (J · ln 10)`).
- **Matrix-free HVP + Lanczos eigenspectrum infrastructure exists** — not
  speculative — via `scripts/phase13_hvp.jl::fd_hvp` and
  `phase13_hessian_eigspec.jl::HVPOperator` (Arpack-compatible `mul!`
  contract, top/bottom-20 wings).
- **SPM-corrected recommended time window + auto-sizing** is implemented
  (`scripts/common.jl:191-215, 348-359`).
- **L-BFGS is already safeguarded for 1st-order work.** `LBFGS()` from
  `Optim.jl` uses HagerZhang line search (strong Wolfe conditions);
  `amplitude_optimization.jl:273` uses `Fminbox(LBFGS(m=10))` with real box
  constraints. Contrast this with the original report's framing that "the
  repo has strong local machinery but weak explicit basin / safeguard
  policy" — that is accurate only for a hypothetical Newton path, not for
  current 1st-order work.
- **Dict-based state and include-based composition** are correctly
  identified as numerical-reasoning friction (REPORT §6).
- **Planning drift as trust risk** is a correct and non-trivial framing —
  the second opinion keeps this on the risks list unchanged.

### What the original Phase 25 missed, underplayed, or misframed

Per-topic verdicts for the concern areas requested by the user:

| Topic | First-audit verdict | Second-opinion verdict | Notes |
|---|---|---|---|
| Conditioning | "under-specified" (generic) | **under-specified AND specifically locatable**: `helpers.jl:51-57` mixes ps / sec / THz / rad·ps⁻¹ in one dict. This is the concrete nondimensionalization target. | Phase 25's framing was abstract; the code location is exact. |
| Scaling | "objectives and variables have mixed magnitudes" | **more severe than stated**: the log_cost factor (`raman_optimization.jl:124`) multiplies the physics gradient by `10 / (J · ln 10)` which grows without bound as J → 0. Regularizer gradients (GDD, boundary) are **not** re-scaled. So `λ_gdd = 1e-4` means "1e-4 at the start of optimization, 1e-12 near convergence" in effective weight. | **Missed.** This is a genuine conceptual error, not a cosmetic one. |
| Forward/backward error | "promote to acceptance gates" | **correct direction, missed concrete tool**: gradient validation (`raman_optimization.jl:254-285`) uses a ratio check, never a Taylor-remainder-2 slope check (`‖J(φ+εv)−J(φ)−ε∇J·v‖ = O(ε²)` as ε halves). CS 4220's standard verification idiom is the slope check, which catches the "approximately correct but mis-scaled" gradient the ratio check cannot. | **Missed.** |
| Globalization | "mandatory for Newton work" | **half right**: for 1st-order, globalization already exists (HagerZhang + Fminbox). The real gap is **trust-region / indefinite-Hessian handling** once HVPs show negative eigenvalues, which `phase13_hessian_eigspec.jl` is explicitly set up to detect. | **Misframed.** |
| Newton / Krylov / preconditioning | "build on HVP/Lanczos path" | **correct direction, under-instrumented**: FD-HVP uses fixed `ε = 1e-4` (`phase13_hvp.jl:48`). Optimal ε is `sqrt(eps_mach · ‖∇J‖) / ‖v‖`. At deep suppression (‖∇J‖_linear ~ 1e-8), a fixed 1e-4 step is way outside the noise sweet spot. Additionally, `build_oracle` uses `log_cost=false, λ_gdd=0, λ_boundary=0` (`phase13_hvp.jl:74`) — so the **Hessian being analyzed is not the Hessian of the objective L-BFGS is minimizing**. Future truncated-Newton that reuses this oracle must resolve the log-vs-linear question first. | **Missed.** |
| FFT-aware numerics | not addressed | **one specific gap**: the super-Gaussian order-30 attenuator (`helpers.jl:59-63`) is a **hard absorbing boundary**, not a tracked one. Any energy walking into the outer 15% of the time window is silently absorbed inside the ODE. `check_boundary_conditions` measures *surviving* edge energy, not *absorbed* energy. At long fiber / high power — exactly the regimes Phase 25 cares about — the reported dB is the dB of a partly-absorbed field. | **Missed.** Structural, not cosmetic. |
| Continuation | "turn warm starts into explicit schedules" | **agree, and the seed is correctly scoped**. No change. | ✓ |
| Extrapolation | "future backlog" | **agree, low priority**. No change. | ✓ |
| Performance modeling | "dedicated phase" | **correct, with one unacknowledged constraint**: ESTIMATE plans (required for determinism) cost measurable FFT throughput vs MEASURE/PATIENT. The determinism seed and the performance-modeling seed do not reference each other; they should. The classic CS 4220 / NMDS framing is "reproducibility is a performance tax you must budget". | **Partially missed.** |

### Specific code-verified defects not in Phase 25

1. **Latent bug — `plot_chirp_sensitivity` applies `lin_to_dB` to values
   already in dB.** `raman_optimization.jl:332` invokes
   `cost_and_gradient(...)` with the default `log_cost=true` (set at
   `:77`), so `J_gdd[i]` is negative dB. Then `:361` runs
   `J_gdd_dB = lin_to_dB.(J_gdd)` which is `10·log10(-40.0)` →
   `DomainError`. Either the canonical driver (`:776`) is throwing and the
   failure is being swallowed, or the code path is effectively dead.
   Either way, a regression test is missing. **Severity: medium (could
   break full runs; under-instrumented).**

2. **Cost-surface incoherence.** Gradient of physics cost is log-scaled;
   gradient of GDD / boundary regularizers is not
   (`raman_optimization.jl:121-172`). Effective regularizer weight
   becomes state-dependent and drops by ~50 dB over a 50 dB
   optimization. **Severity: high (will contaminate any future
   regularization study, including the reduced-basis seed).**

3. **Hessian probe vs. objective mismatch.** `phase13_hvp.jl:74`
   probes the **linear physics-only** Hessian. L-BFGS in
   `raman_optimization.jl` optimizes the **dB cost with GDD + boundary
   regularization**. Future truncated-Newton work built on this HVP path
   inherits the confusion. **Severity: medium.**

4. **No `abstol` specified on Tsit5 solves.** Both
   `simulate_disp_mmf.jl:182` and `sensitivity_disp_mmf.jl:301` rely on
   the default `abstol=1e-6`. At -80 dB suppression, `|ũω|` in the
   optimized Raman sideband is O(1e-4), which is within two orders of
   magnitude of the abstol floor. Whether this biases the gradient at the
   deepest regimes (Session D, Phase 18 / 21) is an untested empirical
   question. **Severity: medium, previously unexamined.**

5. **FD-HVP step size is fixed at `1e-4`.** `phase13_hvp.jl:48`.
   The HVP-symmetry note in the file docstring ("guaranteed only up to
   finite-difference noise") becomes a live concern at L-BFGS
   convergence, which is exactly where curvature probes matter most.
   **Severity: medium (limits the quality of any Krylov/Newton work
   built on the existing oracle).**

6. **Interaction picture ODE is not a true exponential integrator.**
   The interaction-picture transform in `disp_mmf!` is mathematically a
   partial ETD treatment of the dispersion term, but the outer solver is
   still `Tsit5()` (explicit 5th-order Runge-Kutta).
   CS 4220 / NMDS would suggest experimenting with ETDRK4 or Magnus
   integrators here — that is the fully-consistent formulation of the
   same idea. `Vern9()` is mentioned in `CLAUDE.md` as a documented
   alternative but not used. **Severity: low-medium, opportunity rather
   than defect.**

7. **Reduced-basis infrastructure already exists for amplitude.**
   `amplitude_optimization.jl:180-209` implements `build_dct_basis` and
   `cost_and_gradient_lowdim` with gradient-validated DCT-II
   parameterization. The `reduced-basis-phase-regularization` seed
   reads as greenfield but should explicitly say "extend this DCT
   machinery from `A(ω)` to `φ(ω)`". **Severity: framing-only but
   meaningful for plan accuracy.**

8. **Regularizer `clamp!(A, 1e-6, Inf)`** introduces a non-smooth
   barrier (`amplitude_optimization.jl:206`). If the optimizer trajectory
   touches the clamp it can stall a gradient method silently.
   **Severity: low.**

9. **Condition-number probe would be almost free.** Arpack already
   extracts top-K and bottom-K eigenvalues in
   `phase13_hessian_eigspec.jl`. Reporting
   `κ = λ_max / max(|λ_min_nonzero|, eps)` as a per-run trust metric is
   a handful of lines and plugs directly into the conditioning seed.
   **Severity: leverage.**

### Ranking (three outputs the user asked for)

#### Top 5 numerical risks (blast radius × likelihood, ordered)

1. **Cost-surface incoherence** (defect 2 + defect 3 + regularizer scale).
   Risk that every future optimizer / Hessian / regularization phase
   produces numbers that look good but cannot be compared across modes
   or against published baselines. Affects interpretation of
   *everything* downstream.
2. **Absorbing-boundary mass loss is untracked** (defect in row 6 of
   table above). Long-fiber / high-power dB numbers are partly artifacts
   of boundary absorption, and we have no metric that catches this
   short of end-to-end post-hoc inspection.
3. **Chirp sensitivity latent bug** (defect 1). Canonical driver may be
   failing silently.
4. **Planning drift** (from Phase 25, unchanged).
5. **Scaling / conditioning of the full-grid φ vector, specifically the
   mixed-unit `sim` dict** (Phase 25 risk + defect 4 + concrete
   nondimensionalization target).

#### Top 5 highest-leverage improvements (ordered)

1. **Cost-surface coherence + log-scale unification.** One short phase
   that unifies `cost_and_gradient`, `phase13_hvp` oracle, regularizer
   gradients, and `chirp_sensitivity`. Fixes defects 1, 2, 3 and the
   latent regularizer-scale error in one pass.
2. **Extend DCT reduced-basis machinery from amplitude to phase.** Small,
   reuses existing code, directly tests Phase 25's over-parameterization
   hypothesis.
3. **Trust-report bundle with running edge-absorption metric and
   condition-number probe per run.** Small code, high governance value,
   ties together Phase 25's conditioning seed + the absorbing-boundary
   gap surfaced here.
4. **Adaptive FD-HVP step size** (`ε = sqrt(eps_mach · ‖∇J‖) / ‖v‖`).
   Unlocks meaningful curvature probes near convergence, which is the
   regime where truncated-Newton work is supposed to pay off.
5. **Taylor-remainder-2 tests for all gradient paths**
   (phase, amplitude, low-dim DCT, HVP). Catches mis-scaled gradients
   that self-consistent FD ratio checks cannot.

#### Single most important next numerics phase

**Numerical-governance bundle: conditioning + cost-surface coherence +
standing trust report.**

This is a refinement — not a replacement — of Phase 25's
`numerics-conditioning-and-backward-error-framework` seed. The refinement
is to scope that seed to include, explicitly:

- (a) log / linear cost convention unification across
      `cost_and_gradient`, `cost_and_gradient_amplitude`,
      `cost_and_gradient_lowdim`, `phase13_hvp::build_oracle`,
      `chirp_sensitivity`, and the regularizer gradients;
- (b) adaptive FD-HVP step size tied to `‖∇J‖`;
- (c) running edge-absorption metric exposed by the ODE RHS or by a
      post-solve diagnostic;
- (d) per-run condition-number probe (cheap — reuse Arpack);
- (e) Taylor-remainder-2 slope verification as the standard gradient
      test.

Without this bundle, the truncated-Newton / globalization / sharpness
phases Phase 25 correctly identifies as future work will be built on a
weakly-defined objective surface. With it, every downstream numerical
phase gets a sharper contract to compare against. See the new seed
`cost-surface-coherence-and-log-scale-audit.md` and the extended seed
`absorbing-boundary-and-honest-edge-energy.md` for the specific
deliverables of items (a) and (c).

