# Research Note Series Plan

## Executive recommendation

Do not write one monolithic "project report." Write a compact series of **10
main LaTeX notes** plus **1 optional methods appendix**. The main split should
track actual research lanes in the repo, not just phase numbers.

## Quality correction after first PDF review

The notes must be outward-facing research companions, not compiled agent
bookkeeping. Future mini-researcher agents must follow
`docs/research-notes/QUALITY-STANDARD.md`:

- compile the PDF into its note directory after every substantive edit;
- render and visually inspect the compiled PDF before calling the note done;
- keep internal milestone labels out of the PDF body, captions, titles, and
  tables;
- include actual result images and diagnostic diagrams in every note, with the
  standard `phase_diagnostic.png` style preferred for phase/profile evidence;
- inspect embedded plot text after rendering the PDF; if axis labels, legends,
  annotations, or in-image captions overlap, regenerate the source figure with
  better spacing instead of relying on LaTeX scaling;
- include heat maps or propagation-evolution images when the lane has them,
  because those show the in-fiber energy evolution rather than only the final
  phase diagnostic;
- pair each representative phase diagnostic or phase-profile figure with the
  corresponding heat map on the same PDF page whenever both exist;
- include a control/reference page, using no-optimization/no-shaping artifacts
  when available rather than a zero-start optimized run;
- split or abbreviate tables that do not fit cleanly on the rendered page;
- write at an advanced-undergraduate level and keep the voice close to a clear
  student research note rather than an agent report;
- define the full optimization objective used in code, including regularizers,
  log transforms, clipping conventions, and gradient chain-rule scaling when
  they matter;
- describe the experimental method in enough detail that a reader understands
  the control variable, optimizer variable, initialization, sweep dimensions,
  comparison groups, transfer tests, robustness diagnostics, and validation
  gates;
- for reduced, constrained, or transformed parameterizations, explain exactly
  how the constraint is enforced and how gradients move between the physical
  variable and the optimizer variable;
- include short outward-facing intuition blocks for mathematically,
  methodologically, or diagnostically dense sections when they help the reader;
  good titles are `Intuition Check`, `TL;DR`, or `Interpretive Summary`;
- cite external research sources for the model, numerics, optimizer, bases, and
  continuation ideas, plus internal result artifacts for project-specific data;
- treat the reduced-basis continuation lane as an established basin-access
  result with open robustness/transfer questions, not as a merely partial lane.

The strongest structure is:

1. a short **foundational baseline note**
2. several **science-lane notes** (continuation, sharpness, trust-region,
   long-fiber, simple profiles, multimode, multivar, recovery)
3. one **methods-integrity note** for cost/numerics/trust conventions
4. one optional **performance appendix**

This keeps each note readable while still making the full program legible to
the author, the lab, future agents, and later paper drafting.

## Recommended note inventory

### Main notes

1. **Baseline Raman Suppression and Core Optimization Surface**
   - Purpose: the common entry note for the repo's single-mode phase-only path.
   - Why standalone: every other note depends on this setup, cost definition,
     and standard image vocabulary.

2. **Reduced-Basis Continuation and Basin Access**
   - Scope: `sweep_simple`, Phase 30 scaffolding, Phase 31 results, Phase 32
     acceleration status where relevant.
   - Why standalone: this is the roadmap-changing lane.

3. **Sharpness, Robustness Penalties, and Hessian Geometry**
   - Scope: Phase 22 and related sharpness drivers.
   - Why standalone: distinct scientific question from depth-only suppression.

4. **Trust-Region / Newton / Preconditioning in a Saddle-Dominated Landscape**
   - Scope: Phase 33 and Phase 34.
   - Why standalone: separate optimizer family and separate conclusion.

5. **Cost Audit, Numerics Coherence, and Trust Diagnostics**
   - Scope: cost-audit experiments, objective-surface conventions, numerics
     fixes, trust-report interpretation.
   - Why standalone: this is a methods-validity note that underwrites the other
     notes.

6. **Long-Fiber Single-Mode Raman Suppression**
   - Scope: 50-100 m path, Phase 16, validation, matched-quadratic
     interpretation, reach/propagation helpers.
   - Why standalone: physically distinct regime with its own grid discipline and
     claims boundary.

7. **Simple Profiles, Universality, and Transferability**
   - Scope: Phase 17-style simple-profile lane and related transferability /
     simplicity synthesis.
   - Why standalone: this is the cleanest note for interpretable structure and
     cross-regime transfer.

8. **Multimode Raman Baselines and Cost Choice**
   - Scope: MMF baseline lane and current cost recommendation.
   - Why standalone: different physics surface, different trust checks, and
     different headline objective.

9. **Multi-Parameter Optimization Beyond Phase-Only Shaping**
   - Scope: joint phase/amplitude/energy path.
   - Why standalone: different control space and different optimizer path.

10. **Recovery and Honest-Grid Validation**
    - Scope: Phase 21 recovery and re-anchoring logic.
    - Why standalone: this is the provenance / verification note for several
      historically important optima.

### Optional appendix note

11. **Performance Model and Compute Strategy**
    - Scope: Phase 29, threading findings, kernel inventory, task-level
      parallelism.
    - Why optional: useful and real, but not necessary for the first science
      reading pass. It can also live as an appendix to Note 5.

## Notes that should not be standalone

- **Phase 30 continuation methodology**: section inside Note 2.
- **Phase 32 acceleration experiments**: section inside Note 2, with explicit
  "incomplete evidence" labeling.
- **Phase 34 dispersion-preconditioning closure**: section inside Note 4.
- **Lab-readiness rollout strategy**: not a research note; keep as status /
  ops documentation.

## Shared LaTeX template

Every note should use the same skeleton, with a target length of roughly
4-8 pages plus figures.

### Recommended directory layout

- `docs/research-notes/`
- `docs/research-notes/_shared/preamble.tex`
- `docs/research-notes/_shared/macros.tex`
- `docs/research-notes/_shared/note-template.tex`
- `docs/research-notes/<slug>/<slug>.tex`
- `docs/research-notes/<slug>/figures/`
- `docs/research-notes/<slug>/tables/`

### Shared note structure

1. **Title block**
   - note title
   - repo path / lane
   - status: `established`, `partial`, `experimental`, or `closed`
   - primary scripts, primary artifacts, last evidence date

2. **Question and thesis**
   - 3-6 sentences
   - state what the lane tried to answer and the current best claim

3. **Setup and common notation**
   - short recap of fiber, cost, control variable, and reporting convention
   - only 1-2 equations here

4. **Math delta for this note**
   - only the equations unique to this lane
   - examples: reduced basis map, trust-region model, robustness penalty,
     multivar block parameterization, MMF sum/fund/worst costs

5. **Implementation surface**
   - 1 table:
     - key scripts
     - key reusable helpers
     - key result directories
   - enough for a future reader to find the code fast

6. **Experimental strategy**
   - configs, ladders, comparisons, trust gates, and known exclusions

7. **Representative results**
   - 1 summary table
   - 2-4 representative figures
   - 1 short "what this figure shows" paragraph per figure group

8. **Interpretation**
   - key lessons
   - what is actually established
   - what is still provisional

9. **Limitations and missing evidence**
   - artifact gaps
   - unresolved confounders
   - what would have to be rerun before publication-strength claims

10. **Reproduction capsule**
    - canonical command(s)
    - required machine
    - expected outputs

### Template rules

- Each note must include a short **"claim status"** box near the front.
- Each note must separate **established results** from **incomplete or
  provisional evidence**.
- Each note should use the repo's standard image set where possible, but not
  dump four PNGs blindly. Pick the one or two most informative standard images
  and supplement them with one lane-specific figure.
- Each note should contain a **"math delta"** section instead of re-deriving
  the entire project from scratch.

## Per-note outlines and required inputs

## 1. Baseline Raman Suppression and Core Optimization Surface

- **Math**
  - GNLSE / interaction-picture recap
  - Raman-band energy fraction objective
  - log-cost transform and adjoint gradient
- **Implementation**
  - `scripts/lib/common.jl`
  - `scripts/lib/raman_optimization.jl`
  - `scripts/lib/visualization.jl`
  - `scripts/lib/standard_images.jl`
  - `docs/architecture/{cost-function-physics,cost-convention}.md`
- **Strategy**
  - explain canonical single-mode setup and why phase-only is the default
  - define standard result bundle and standard images
- **Representative results / figures**
  - canonical SMF-28 optimized vs unshaped evolution
  - phase profile and phase diagnostic
  - one HNLF or alternate-fiber comparison
  - one convergence trace if available
- **Key lessons / limitations**
  - baseline objective is clear and useful, but many later lanes question basin
    access, not the basic physics setup
- **Missing inputs**
  - one clean canonical result table pulled from current canonical artifacts
  - one explicit figure manifest for a baseline note

## 2. Reduced-Basis Continuation and Basin Access

- **Math**
  - basis map `phi = B c`
  - continuation / upsampling ladder
  - optional acceleration formulas only as short subsections
- **Implementation**
  - `scripts/research/sweep_simple/*`
  - `scripts/research/analysis/continuation.jl`
  - `agent-docs/phase31-reduced-basis/FINDINGS.md`
  - `docs/status/{phase-30-status,phase-32-status}.md`
- **Strategy**
  - Sweep 1 knee-finding
  - Sweep 2 robust-candidate hunting across `(L,P,fiber)`
  - Phase 31 Branch A vs Branch B comparison
  - continuation-to-full-grid follow-up
  - Phase 32 only as "what acceleration did and did not establish"
- **Representative results / figures**
  - `results/raman/phase_sweep_simple/sweep1_Nphi.jld2`
  - `results/raman/phase_sweep_simple/sweep2_LP_fiber.jld2`
  - `results/raman/phase31/pareto.png`
  - `results/raman/phase31/L_curves/*.png`
  - one polynomial vs cubic vs full-grid phase-profile comparison
- **Key lessons / limitations**
  - continuation changes basin reachability
  - robustness / transferability / depth are different objectives
  - Phase 30 flagship evidence incomplete; Phase 32 partial only
- **Missing inputs**
  - one compact table extracted from `path_comparison.jld2`
  - one short summary figure for Phase 30 status
  - one explicit closure paragraph for Phase 32 unresolved experiments

## 3. Sharpness, Robustness Penalties, and Hessian Geometry

- **Math**
  - sharpness objective variants: MC, SAM, trace-H penalty
  - sigma-based robustness metric
  - Hessian indefiniteness interpretation
- **Implementation**
  - `scripts/research/sharpness/*`
  - `results/raman/phase22/SUMMARY.md`
  - `docs/planning-history/phases/22-sharpness-research/*`
- **Strategy**
  - compare plain objective against robustness-oriented penalties
  - evaluate depth loss versus sigma gain
  - inspect Hessian definiteness rather than only objective value
- **Representative results / figures**
  - `docs/figures/phase22_pareto.png`
  - one canonical and one pareto57 standard-image comparison
  - one Hessian summary table from `results/raman/phase22/SUMMARY.md`
- **Key lessons / limitations**
  - optima remained indefinite
  - `trH` can buy robustness, but at a large depth cost
  - default objective remains plain log-dB
- **Missing inputs**
  - phase22 result bundle should be normalized into one note-ready table
  - likely need a fresh figure-export pass from the archived phase22 image set

## 4. Trust-Region / Newton / Preconditioning in a Saddle-Dominated Landscape

- **Math**
  - quadratic trust-region model
  - matrix-free HVP and PCG / Steihaug subproblem
  - gauge projection and negative-curvature handling
- **Implementation**
  - `scripts/research/trust_region/*`
  - `results/raman/phase33/SYNTHESIS.md`
  - `docs/status/{phase-34-preconditioning-caveat,phase-34-bounded-rerun-status}.md`
  - `docs/synthesis/why-phase-34-still-points-back-to-phase-31.md`
- **Strategy**
  - cold / warm / perturbed benchmark matrix
  - bounded reruns after wiring and gauge fixes
  - continuation-style starts versus cold starts
- **Representative results / figures**
  - phase33 master-table excerpt
  - exit-code distribution / rejection-cause table
  - one continuation-dispersion pair from `results/raman/phase34/...pairs/`
  - one ladder comparison from `.../continuation_dispersion_ladder/`
- **Key lessons / limitations**
  - honest failure matters
  - saddle structure is real
  - local second-order improvements help only after path quality improves
  - dispersion preconditioning branch is closed for this Raman agenda
- **Missing inputs**
  - one note-ready figure that summarizes `:none` vs `:dispersion`
  - one compact explanation figure for `RADIUS_COLLAPSE` / saddle cases

## 5. Cost Audit, Numerics Coherence, and Trust Diagnostics

- **Math**
  - objective-surface definition:
    `J_surface = physics + regularizers`, optional `10 log10`
  - why mixed objective scales are invalid
  - trust metrics and boundary-edge interpretation
- **Implementation**
  - `scripts/research/cost_audit/*`
  - `docs/architecture/cost-convention.md`
  - `agent-docs/current-agent-context/NUMERICS.md`
  - `agent-docs/cost-convention-consistency/SUMMARY.md`
- **Strategy**
  - compare linear, log-dB, sharp, and curvature variants on fixed configs
  - connect audit results to later shared numerics rules
- **Representative results / figures**
  - `results/cost_audit/*`
  - `docs/figures/fig3_linear_vs_log_cost.png`
  - one objective-surface contract table
  - one trust-report / edge-fraction example
- **Key lessons / limitations**
  - some earlier mismatches are fixed and regression-covered
  - HVP results are only comparable when they target the same scalar surface
  - deep-suppression regimes still deserve caution
- **Missing inputs**
  - a current, note-quality summary table for cost-audit runs A/B/C
  - one compact illustration of "safe vs unsafe comparison"

## 6. Long-Fiber Single-Mode Raman Suppression

- **Math**
  - long-window / long-grid setup constraints
  - warm-start transfer across grids
  - matched-quadratic / pre-chirp interpretation
- **Implementation**
  - `scripts/research/longfiber/*`
  - `scripts/research/propagation/{matched_quadratic_100m,propagation_reach,propagation_z_resolved}.jl`
  - `agent-docs/current-agent-context/LONGFIBER.md`
  - `results/raman/phase16/FINDINGS.md`
- **Strategy**
  - 2 m seed -> 100 m warm start
  - bounded, checkpointed L-BFGS path
  - post-run validation and interpretation
- **Representative results / figures**
  - `results/raman/phase16/FINDINGS.md` headline table
  - `docs/figures/phase21_100m_phase_profile.png`
  - one matched-quadratic comparison
  - one validation table for edge fraction / energy drift
- **Key lessons / limitations**
  - supported exploratory single-mode path at 50-100 m
  - 100 m result is scientifically useful but not tightly converged
  - long-fiber should not be oversold as group-grade infrastructure yet
- **Missing inputs**
  - one concise 50 m vs 100 m comparison summary
  - one note-ready export from `matched_quadratic_100m.jl`
  - a clear supported-range statement to embed in the note

## 7. Simple Profiles, Universality, and Transferability

- **Math**
  - low-complexity profile families
  - simplicity metrics: TV, entropy, stationary count, quadratic fit
  - transfer / perturbation metrics
- **Implementation**
  - `scripts/research/simple_profile/*`
  - related transferability logic in Phase 17 synthesis workflow
  - Phase 31 transfer findings can be cited as a bridge, not as the main source
- **Strategy**
  - compare baseline optimum to simpler approximants
  - test perturbation robustness and cross-target transfer
  - ask whether a simple, interpretable profile captures most of the effect
- **Representative results / figures**
  - perturbation curve
  - transferability heatmap / grouped bar chart
  - simplicity-vs-suppression scatter
  - synthesis panel from `simple_profile_synthesis.jl`
- **Key lessons / limitations**
  - this note is where universality / handoff / interpretability should live
  - likely the clearest note for experiment-facing insight
- **Missing inputs**
  - current workspace does not show the Phase 17 result bundle
  - this note likely requires regeneration or explicit restoration of
    `results/raman/phase17/*`
  - figure exports named in the script are not present locally

## 8. Multimode Raman Baselines and Cost Choice

- **Math**
  - multimode band fractions
  - `:sum`, `:fundamental`, and `:worst_mode` cost definitions
  - MMF-specific windowing / trust checks
- **Implementation**
  - `scripts/research/mmf/*`
  - `src/mmf_cost.jl`
  - `docs/status/multimode-baseline-status-2026-04-22.md`
  - `agent-docs/multimode-baseline-stabilization/SUMMARY.md`
- **Strategy**
  - establish meaningful versus non-meaningful regimes
  - compare cost variants only on a trustworthy regime
- **Representative results / figures**
  - regime sweep summary table
  - one cost-comparison table on selected regime
  - one MMF standard image set example
  - one per-mode fraction plot if available
- **Key lessons / limitations**
  - mild GRIN-50 point is a negative baseline
  - recommended next baseline is `GRIN_50`, `L=2 m`, `P=0.5 W`, `:sum`
- **Missing inputs**
  - synced workspace has no `results/raman/phase36/`
  - this note cannot be written well until the aggressive rerun exists and its
    standard images are inspected

## 9. Multi-Parameter Optimization Beyond Phase-Only Shaping

- **Math**
  - packed control vector for phase / amplitude / energy
  - block scaling and regularization terms
  - relation to the shared objective-surface contract
- **Implementation**
  - `scripts/research/multivar/{multivar_optimization,multivar_demo}.jl`
  - `agent-docs/current-agent-context/MULTIVAR.md`
  - validation markdown under `results/validation/`
- **Strategy**
  - phase-only baseline
  - cold-start multivar
  - warm-start multivar
  - identify whether joint space helps or only expands optimization difficulty
- **Representative results / figures**
  - multivar vs phase-only convergence figure
  - one output-spectrum comparison
  - one table comparing `phase_only`, `mv_joint`, and `mv_joint_warmstart`
- **Key lessons / limitations**
  - machinery exists and gradients are meaningful
  - joint path still underperforms the canonical phase-only result
  - this is a research scaffold, not a supported workflow
- **Missing inputs**
  - a note-ready result summary table must be extracted from the JLD2 payloads
  - synced workspace appears to lack the expected standard PNG set for the
    multivar runs

## 10. Recovery and Honest-Grid Validation

- **Math**
  - honest-grid recovery logic
  - seed interpolation, linear-phase removal, and validation metrics
  - relation between old and recovered claims
- **Implementation**
  - `scripts/research/recovery/*`
  - `docs/planning-history/phases/21-numerical-recovery/*`
  - recovery standard images and summaries
- **Strategy**
  - re-run historical optima on honest grids
  - verify edge fractions, energy drift, and reproducibility
  - separate durable results from numerically fragile ones
- **Representative results / figures**
  - `docs/figures/phase21_recovered_smf28_phase_profile.png`
  - `docs/figures/phase21_100m_phase_profile.png`
  - one Sweep-1 recovery table
  - one reanchored Phase 13 comparison
- **Key lessons / limitations**
  - this is the integrity note for inherited artifacts
  - essential for honest citation of old optima
- **Missing inputs**
  - a concise recovered-vs-original comparison table for note use
  - one figure that summarizes why the recovery mattered

## 11. Optional appendix: Performance Model and Compute Strategy

- **Math / model**
  - roofline / kernel-inventory framing
  - forward vs adjoint cost model
- **Implementation**
  - `scripts/research/benchmarks/*`
  - `agent-docs/current-agent-context/PERFORMANCE.md`
  - `results/phase29/*`
- **Strategy**
  - explain why task-level parallelism beats intra-solve threading here
- **Representative results / figures**
  - roofline or kernel-inventory plot
  - benchmark table for threading
- **Missing inputs**
  - if promoted to a standalone note, it needs one human-readable figure export
    from `results/phase29/*`

## Missing ingredients that should be generated before note-writing

### Missing or incomplete evidence

- **Multimode note blocked** on a real `phase36` aggressive baseline artifact
  set.
- **Simple-profile note blocked** on missing local `phase17` result artifacts or
  a regeneration pass.
- **Multivar note partially blocked** on missing synced standard PNGs and a
  concise result summary table.
- **Continuation note partially blocked** on a compact, current summary of Phase
  30 and the unresolved Phase 32 accel paths.

### Existing evidence that still needs note-ready summarization

- Phase 31 follow-up `path_comparison.jld2` needs one note-quality table.
- Phase 33 / 34 need one compact figure or table that explains the failure
  modes without forcing readers through raw telemetry.
- Cost-audit runs need one normalized comparison table across configs / variants.
- Recovery work needs one old-vs-recovered summary table.
- Long-fiber needs one short 50 m / 100 m capability summary and one matched
  quadratic interpretation panel.

### Shared production assets that should be created once

- a common LaTeX preamble with macros for `J`, `J_dB`, `phi`, `sigma_3dB`,
  `Nt`, `L`, `P`
- a common result-table style
- a common figure-caption style that distinguishes:
  - what is shown
  - what comparison matters
  - whether the result is established or provisional
- a small figure-export manifest per note so later agents do not rediscover file
  names manually

## Production plan for later mini-researcher agents

### Recommended writing order

1. **Baseline note**
2. **Cost / numerics note**
3. **Reduced-basis / continuation note**
4. **Trust-region / Newton note**
5. **Long-fiber note**
6. **Recovery note**
7. **Sharpness note**
8. **Multivar note**
9. **Simple-profile note**
10. **Multimode note**
11. optional performance appendix

Reasoning:

- start with the common language and most stable evidence
- write the roadmap-driving notes early
- delay notes that are artifact-blocked or scientifically incomplete

### Agent decomposition

Use small single-note agents, not one giant writing agent. Each agent should own
one note only.

For each note-writing agent:

1. Read the shared template, this plan, and the note-specific source list.
2. Produce a one-page evidence map:
   - scripts
   - artifacts
   - status docs
   - unresolved gaps
3. Export or copy only the figures that note needs.
4. Write the note in LaTeX with explicit claim-status labeling.
5. Leave a short `SUMMARY.md` beside the note explaining:
   - what was included
   - what was omitted
   - what still needs rerun data

### Pre-writing agent roles

Before the main note-writing pass, run 3 narrow prep agents:

1. **Artifact summarizer**
   - produce compact CSV / markdown tables from:
     - Phase 31 follow-up
     - cost audit
     - multivar results
     - recovery comparisons

2. **Figure curator**
   - identify and copy representative figures into per-note `figures/`
     directories
   - note which figures are missing and require regeneration

3. **LaTeX scaffolder**
   - create shared preamble, template, and note directory skeletons
   - do not write full prose yet

### Blocking tasks before full note production

- regenerate or restore Phase 17 simple-profile artifacts
- execute and sync the multimode `phase36` aggressive rerun
- verify whether multivar standard-image PNGs exist elsewhere and sync them if
  they do not
- produce note-ready summary tables for Phase 31 follow-up, cost-audit, and
  recovery

## Final recommendation

Treat the series as:

- **8 fully supported core notes** that can be written mostly from current
  evidence
- **2 notes that are real but currently artifact-blocked**:
  - simple profiles
  - multimode
- **1 optional methods appendix** for performance

That gives the project a clean technical-note series without pretending that
every research lane is equally mature right now.
