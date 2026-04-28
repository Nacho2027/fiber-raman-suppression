# Presentation Building Blocks

Evidence snapshot: 2026-04-28

Goal: the research-note series should be enough to build a presentation on the
project without rereading months of planning logs. This file maps the findings
to presentation units and flags gaps where the notes still need more evidence,
figures, or pedagogy.

## Presentation Arc

Use this as the default deck structure.

Taste rule: do not build the main physical story around a short 500 mm case
unless the unoptimized control visibly shows Raman growth. Those runs can be
valid for methods, recovery, and robustness, but they are often weak
before/after teaching examples.

| Slide block | Main point | Note source | Best visual type |
|---|---|---|---|
| Problem | Raman transfer limits pulse propagation; spectral phase can suppress it. | `01-baseline-raman-suppression` | baseline workflow + before/after heat map |
| Baseline optimizer | Phase-only adjoint/L-BFGS gives the core working result. | `01-baseline-raman-suppression` | phase diagnostic + optimized evolution |
| Trust and numerics | The result is only meaningful if objective scale, gauge, gradients, and grid checks are coherent. | `05-cost-numerics-trust`, `current-equation-verification.pdf` | objective pipeline + trust checklist |
| Reduced basis | A low-dimensional phase basis can find useful basins and explains `phi = Bc` cleanly. | `02-reduced-basis-continuation` | basis diagram + reduced/full-grid figure pair |
| Simple profiles | Simple, transferable, and deepest are different claims. | `07-simple-profiles-transferability` | depth-transfer tradeoff + phase/evolution examples |
| Robustness | Sharpness penalties trade depth for robustness; they are knobs, not magic. | `03-sharpness-robustness` | robustness-depth tradeoff |
| Second order | Newton/trust-region work reveals saddle geometry and why naive second-order steps are risky. | `04-trust-region-newton`, `10-recovery-validation` | saddle spectrum + trust workflow |
| Recovery | Honest-grid recovery separates real claims from retired/numerically fragile ones. | `10-recovery-validation` | recovery workflow + recovered/control pair |
| Compute | Adjoint and threading behavior explain how to run this program efficiently. | `11-performance-appendix` | cost model + threading plot |
| Long-fiber milestones | Phase-only suppression reaches 100--200 m in image-backed single-mode runs. | `06-long-fiber` | 100 m / 200 m control and optimized heat-map pairs |
| Long-fiber strategy | Short-fiber masks can warm-start expensive long-fiber re-optimization. | `12-long-fiber-reoptimization` | warm-start workflow + 100 m control/optimized pair |
| Multivariable refinement | Extra controls do not automatically help; staged amplitude refinement after phase-only shaping is the useful result. | `09-multi-parameter-optimization` | control/phase-only/amplitude-refined paired figures |
| Multimode extension | Idealized GRIN-50 MMF shared-phase shaping works under strict edge diagnostics. | `08-multimode-baselines` | rejected-vs-accepted trust ladder + per-mode spectra |
| Close | What is established, what is provisional, and what the next experiments should test. | `README.md`, `VERIFICATION-CLOSURE-MATRIX.md` | status table |

## Finding Coverage Matrix

| Finding | Covered by note | Presentation status | Remaining work |
|---|---|---|---|
| Phase-only spectral shaping can strongly suppress Raman-band output compared with no shaping. | `01` | covered | Add final artifact provenance table before publication. |
| The optimized scalar is a Raman-band energy fraction, usually reported in dB. | `01`, `05`, reference verification doc | covered | Keep equation verification current with code. |
| Phase-only gradients need careful complex/Wirtinger and phase-chain-rule conventions. | `05`, reference verification doc | covered as methods | Link more directly from `01` if presentation questions focus on adjoints. |
| Gauge directions matter: constant phase and timing-like linear phase should not be confused with meaningful shape. | `05`, `07`, `02` | covered | Add one simple visual example if needed for teaching. |
| Standard images are required: phase diagnostic, evolution, no-shaping control, and paired pages. | `01`, `05`, `QUALITY-STANDARD.md` | covered | Keep enforcing for new notes. |
| Reduced-basis coordinates use a linear map `phi = Bc`; the reduced gradient is `B^T grad_phi`. | `02`, reference verification doc | covered | Verify final code-path capsule before publication. |
| Reduced-basis/continuation can provide basin access rather than only dimensionality reduction. | `02` | covered | Add final result provenance table. |
| Simple polynomial masks are interpretable and transferable but shallow. | `07` | covered | Keep the presentation-friendly wording and avoid calling it universal. |
| Deep full-grid or structured masks can suppress more strongly but are less robust/transferable. | `07`, `03`, `10` | covered | Verify all transfer/robustness numbers against artifacts. |
| Sharpness/robustness penalties expose a tradeoff between suppression depth and stability. | `03` | covered | Add sharper source-code provenance for the exact sharpness objective. |
| Hessian and trust-region experiments reveal indefinite/saddle-heavy geometry. | `04`, `10` | covered but should be reviewed before main presentation | Confirm HVP/objective conventions against current verification doc. |
| Recovery work matters because some earlier deep results needed honest-grid validation or retirement. | `10` | covered | Add exact saved-state provenance for each recovered case. |
| Cost/numerics audits are part of the scientific result, not just engineering cleanup. | `05`, reference verification doc | covered | Run final verification suite when burst is free. |
| Determinism/FFTW planning and threading affect reproducibility and compute strategy. | `11`, current context methodology/performance notes | covered | Verify benchmark environment before quoting speedups. |
| Long-fiber 100--200 m single-mode work is real but not a converged optimum claim. | `06`, `12` | covered with caveats | Revisit only if convergence or cleaner phase profiles improve. |
| Short-fiber masks can warm-start long-fiber optimization and save search effort. | `12` | covered as provisional strategy | Add final cost comparison after long-fiber runs finish. |
| MMF shared-phase shaping has a qualified idealized GRIN-50 simulation result. | `08` | covered with caveats | Grid refinement, launch sensitivity, and random coupling remain paper gates. |
| Multiparameter phase/amplitude/energy controls expose important chain-rule and conditioning issues. | `09`, reference verification doc | covered as a staged-refinement result | Lab handoff still needs amplitude calibration and convergence closure. |
| The project now has a documentation and verification system for future paper writing. | `README.md`, `QUALITY-STANDARD.md`, `TRACEABILITY-MAP.md` | covered | Keep maps updated as notes change. |

## Per-Note Presentation Capsules To Add During Future Polish

These should eventually become short sections inside each note. Until then,
this file is the source of truth.

### `01-baseline-raman-suppression`

- Slide takeaway: phase-only spectral shaping creates a measurable and
  interpretable Raman-suppression baseline.
- Use this figure: canonical phase diagnostic paired with optimized and
  unshaped evolution.
- Say out loud: define the Raman-band fraction; explain phase-only control;
  show no-shaping reference; state that this is the base workflow all later
  lanes modify.
- Do not overclaim: the baseline is a reference workflow, not proof that the
  found phase is globally optimal.

### `02-reduced-basis-continuation`

- Slide takeaway: a reduced phase basis changes the search problem by forcing
  the optimizer to move through structured phase families first.
- Use this figure: basis linear-algebra diagram plus cubic reduced/full-grid
  figure pair.
- Say out loud: `phi = Bc`; `grad_c = B^T grad_phi`; continuation uses simple
  structured solutions as basin access; refinement can move back to full-grid.
- Do not overclaim: portability and final artifact provenance still need a
  final audit.

### `03-sharpness-robustness`

- Slide takeaway: robustness is a second axis; deepest suppression is not
  automatically the best experimental mask.
- Use this figure: robustness-depth tradeoff. Do not lead with short-fiber
  before/after images here; the point is the tradeoff, not dramatic Raman
  suppression.
- Say out loud: sharpness penalties reduce local sensitivity; they cost depth;
  Hessian/trace estimates are diagnostics; this is a knob, not a replacement
  default.
- Do not overclaim: sharpness results depend on estimator and objective
  conventions.

### `04-trust-region-newton`

- Slide takeaway: second-order information shows the landscape is
  saddle-dominated, so naive Newton-like steps are risky.
- Use this figure: trust-region workflow and saddle spectrum.
- Say out loud: local quadratic models can predict badly; radius collapse is
  a symptom; continuation/preconditioning help but do not yet replace L-BFGS.
- Do not overclaim: this lane explains failure modes and future paths, not a
  new winning optimizer.

### `05-cost-numerics-trust`

- Slide takeaway: the result is only defensible when the cost convention,
  gauge, gradient, and visualization checks agree.
- Use this figure: objective-surface pipeline or trust-gate checklist.
- Say out loud: denominator terms matter; dB transforms change gradients;
  gauge projection prevents fake phase structure; standard images are part of
  verification.
- Do not overclaim: final heavyweight verification reruns still need to be
  refreshed before publication.
- Taste warning: this is a methods section. Avoid turning a short 500 mm audit
  case into the main physical result slide.

### `07-simple-profiles-transferability`

- Slide takeaway: simple, transferable, and deepest are three different
  categories.
- Use this figure: depth-transfer tradeoff plus simple/deep paired pages.
- Say out loud: the polynomial mask teaches the mechanism; deep masks show
  performance; robustness filters decide whether a mask is experimentally
  plausible.
- Do not overclaim: no single universal mask has been established.

### `09-multi-parameter-optimization`

- Slide takeaway: adding more optimizer variables is not automatically better;
  the successful result is staged amplitude refinement after a strong phase-only
  solution.
- Use this figure: no-shaping control, phase-only reference, and
  amplitude-refined phase-diagnostic/heatmap pages, plus the ablation bar chart.
- Say out loud: the launch field is
  `sqrt(eta) * A_k * exp(i phi_k) * u0_k`; phase rotates samples, amplitude
  changes their radius, and energy scales the whole vector.
- Do not overclaim: broad joint optimization was a negative result, amplitude
  masks need lab calibration, and several strongest runs hit iteration caps.

### `10-recovery-validation`

- Slide takeaway: honest validation turns a pile of optimization outputs into
  defensible scientific claims.
- Use this figure: recovery workflow plus recovered/control figure pair.
- Say out loud: some old claims were retired; some were recovered on honest
  grids; saddle diagnostics explain why reruns and perturbations matter.
- Do not overclaim: every recovered number still needs exact saved-artifact
  provenance for publication.

### `11-performance-appendix`

- Slide takeaway: compute strategy determines how much research can be done;
  the adjoint and solve costs are not abstract.
- Use this figure: performance cost model or threading speedup plot.
- Say out loud: forward solves are not just FFTs; adjoints are heavier;
  threading inside one solve is not always the best lever; run parallelism and
  burst discipline matter.
- Do not overclaim: benchmark numbers are hardware- and configuration-specific.

### `12-long-fiber-reoptimization`

- Slide takeaway: short-fiber masks can be used as practical warm starts for
  expensive long-fiber optimization.
- Use this figure: warm-start workflow plus 100 m control/optimized page.
- Say out loud: this is computational warm-starting; it is not automatically
  an in-line shaper experiment; warm-start alone gets close; re-optimization
  refines the long target.
- Do not overclaim: the 100 m result is not yet a converged global optimum.

## Historical Finding Audit Still Needed

The current notes cover the main public research story, but a final
presentation-quality audit should still read the following historical sources
and check whether any durable finding is missing:

- `docs/planning-history/research/SUMMARY.md`
- `docs/planning-history/phases/06-cross-run-comparison-and-pattern-analysis/`
- `docs/planning-history/phases/09-physics-of-raman-suppression/`
- `docs/planning-history/phases/10-propagation-resolved-physics/`
- `docs/planning-history/phases/11-classical-physics-completion/`
- `docs/planning-history/phases/12-suppression-reach/`
- `docs/planning-history/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/`
- `docs/planning-history/phases/16-cost-function-head-to-head-audit-compare-linear-log-scale-db/`
- `docs/planning-history/phases/21-numerical-recovery/`
- `docs/planning-history/phases/22-sharpness-research/`
- `docs/planning-history/phases/29-performance-modeling-and-roofline-audit-for-the-fft-adjoint-/`
- `docs/planning-history/phases/33-globalized-second-order-optimization-for-raman-suppression/`
- `docs/planning-history/phases/34-truncated-newton-krylov-preconditioning-path/`
- `docs/planning-history/phases/35-saddle-escape/`
- reduced-basis agent findings and summaries
- `agent-docs/stability-universality/SUMMARY.md`
- `agent-docs/equation-verification/SUMMARY.md`
- `agent-docs/current-agent-context/`

If that audit finds a durable result that is not represented by a note, create
either a new short note or a clearly marked subsection in the closest existing
note.

## Taste Audit

Presentation taste issues are tracked in
`PRESENTATION-TASTE-AUDIT.md`. In particular, the notes should stop treating
every technically useful run as a good slide example. Short-fiber diagnostic
cases, especially 500 mm runs with weak unoptimized Raman growth, should be
used carefully and usually not as the main before/after visual.
