# Claude Code Prompt: Independent Numerical Analysis Audit

You are doing an independent numerical-analysis audit of this project. Treat prior planning docs as inputs to review, not as truth.

## Repo

`~/fiber-raman-suppression`

## Primary external sources to study

1. Cornell CS 4220 class repo:  
   `https://github.com/dbindel/cs4220-s26/`
2. Cornell textbook / notes:  
   `https://www.cs.cornell.edu/~bindel/nmds/`

## Mission

Build your own understanding of both the codebase and the numerical-analysis material, then review and extend the existing Phase 25 numerics audit. I want an independent, skeptical pass that uses your larger context window well.

## Important constraints

- Research and mapping only.
- Do not refactor `src/`.
- Do not silently trust existing `.planning` docs; verify against the code.
- If you add findings, put them into the same Phase 25 docs if appropriate, and add new seeds in `.planning/seeds/` for anything large enough to deserve its own future phase.
- Focus on numerical methods, optimization, conditioning, solver behavior, stability, performance, diagnostics, and research workflow bottlenecks.
- Be concrete about what is wrong, what is missing, and what is promising.

## Existing artifacts to review first

- `.planning/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-RESEARCH.md`
- `.planning/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/25-REPORT.md`
- `.planning/phases/25-numerical-analysis-audit-and-cs-4220-application-roadmap/SUMMARY.md`
- Existing seeds in `.planning/seeds/` related to numerics

## Code areas likely relevant

- `scripts/common.jl`
- `scripts/raman_optimization.jl`
- `scripts/amplitude_optimization.jl`
- `scripts/run_benchmarks.jl`
- `scripts/phase13_hessian_eigspec.jl`
- `scripts/determinism.jl`
- `scripts/benchmark_threading.jl`
- `src/simulation/`
- `src/helpers/helpers.jl`
- `src/analysis/analysis.jl`
- any adjoint / sensitivity / optimization related code

## What I want you to do

### 1. Study the external material deeply

- Read enough of `cs4220-s26` to extract the class’s most relevant numerical-analysis themes for this project.
- Read enough of `nmds` to identify additional ideas not fully captured by the class repo alone.
- Pay special attention to:
  - conditioning and scaling
  - backward vs forward error
  - ill-posedness vs ill-conditioning
  - line search / trust region / globalization
  - Newton, quasi-Newton, truncated Newton, Krylov ideas
  - preconditioning
  - spectral transforms / FFT-aware numerics
  - continuation / homotopy
  - extrapolation / acceleration
  - performance modeling, roofline thinking, memory bandwidth, Amdahl/Gustafson
  - diagnostics for convergence failure and numerical unreliability

### 2. Map those ideas onto this specific codebase

- Identify where the project’s current numerical approach is sound.
- Identify where the project appears fragile, ad hoc, numerically under-instrumented, or likely to fail silently.
- Distinguish:
  - immediate blockers
  - medium-term architecture problems
  - research opportunities
- Be explicit about whether issues are:
  - mathematical formulation issues
  - optimization strategy issues
  - discretization / resolution issues
  - conditioning / scaling issues
  - implementation / performance issues
  - diagnostics / observability issues

### 3. Review the existing Phase 25 work critically

- Check whether the current Phase 25 report is missing important themes from the class or textbook.
- Call out any overclaims, weak inferences, or places where the earlier writeup is plausible but insufficiently supported by code evidence.
- Strengthen or correct the existing report where needed.
- Add new seeds if you find additional substantial future phases.

### 4. Produce practical output

Update the Phase 25 docs in place if appropriate:

- `25-RESEARCH.md`
- `25-REPORT.md`
- `SUMMARY.md`

Add seeds in `.planning/seeds/` for any major new future workstreams.

Also produce a compact review section in the report that answers:

- What are the top 5 numerical risks in this codebase?
- What are the top 5 highest-leverage improvements?
- Which recommendations are low-risk and immediately actionable?
- Which recommendations require deeper research or experiments before implementation?
- Which parts of the current code seem fundamentally misframed, if any?

## Standards for the review

- Be specific and evidence-based.
- Tie claims back to code locations and to ideas from the course/book.
- Prefer “this code likely needs X because Y” over generic advice.
- Surface missing diagnostics as first-class problems.
- Treat performance as a numerical-method design issue, not just an engineering afterthought.
- If you infer something that the code does not prove directly, label it clearly as an inference.

## Desired deliverables

1. Improved Phase 25 docs with your independent findings folded in.
2. New `.planning/seeds/*.md` files for substantial future phases.
3. A concise final summary of:
   - what you agreed with from the existing audit
   - what you changed or added
   - what you think the single most important next numerics phase should be

## Workflow

Use the project’s GSD process if needed, but the goal here is the audit itself, not implementation. Research hard, verify against code, and write a review that would actually be useful to a numerics-focused advisor.

Do not give me a shallow endorsement. I want a real second opinion.
