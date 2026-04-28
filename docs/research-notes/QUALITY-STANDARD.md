# Research Note Quality Standard

This directory is for outward-facing technical companion notes, not internal
agent status reports.

## Non-negotiables

- Compile every note to PDF in its note directory before calling it complete.
- Render and visually inspect the compiled PDF after every substantive edit.
- Do not expose internal milestone labels in outward-facing PDFs. Use
  research-direction names instead.
- Every note must include actual figures from results, diagnostics, or generated
  summaries. A note with only prose and placeholder markers is not production
  quality.
- Tables must be designed for the page. If a table is cramped, split it,
  abbreviate it, or move full details to CSV/Markdown sidecars.
- Figures must carry interpretive captions: what the reader should conclude,
  not just where the image came from.
- When adding or regenerating figures, inspect the embedded plot text after PDF
  rendering. Axis labels, legends, annotations, and in-image captions must not
  overlap. If they do, regenerate the source figure with more whitespace,
  wrapped labels, smaller annotations, or a simpler legend rather than relying
  on LaTeX scaling to hide the issue.
- Prefer the standard `phase_diagnostic.png` style for phase/profile evidence.
  It is the clearest visual format for these notes. Use evolution images as
  supporting propagation evidence, not as replacements for phase diagnostics.
- Include heat maps when they exist for the lane. For this project, spectral or
  temporal evolution heat maps are important evidence because they show where
  energy goes during propagation, not just the final phase shape.
- Pair each representative phase diagnostic or phase-profile figure with its
  corresponding heat map on the same PDF page when both exist. The reader should
  be able to compare "what phase was applied" against "what happened in the
  fiber" without flipping pages.
- Include a control/reference page when there is a natural baseline. "Control"
  means no optimization/no shaping whenever that artifact exists. Do not use a
  zero-start optimized run as the control unless no unoptimized artifact exists.
  Pair the control diagnostic with the unshaped heat map on the same page.
- Write at an advanced-undergraduate reading level. Keep the math real, but
  explain what each equation means in plain language and avoid sounding like an
  agent status memo.
- Define the full optimization objective, not only the plotted result metric.
  If the code uses regularizers, log transforms, clipping, or chain-rule
  gradient scaling, the note must say so explicitly.
- Explain the experimental method at the level needed to reproduce the logic:
  control variable, optimizer variable, initialization, sweep dimensions,
  comparisons, transfer tests, robustness diagnostics, and final validation
  gates.
- If a lane uses a reduced, constrained, or transformed parameterization,
  explain exactly how the constraint is enforced and how gradients move between
  the physical variable and the optimizer variable. For reduced bases, this
  means showing the basis map and the reduced-gradient formula.
- Every mathematically, methodologically, or diagnostically dense section should
  include a short public-facing intuition block when it would help a reader.
  Good titles are `Intuition Check`, `TL;DR`, or `Interpretive Summary`. This
  should read like a concise explanation a student could give at a board, but it
  should not sound like private coaching or agent commentary.
- Cite research sources for the physical model, numerical method, optimizer,
  basis choice, and continuation strategy. Use a short `thebibliography`
  section if the note does not yet have a shared BibTeX workflow.
- If a claim is incomplete, say exactly what evidence is missing; do not label
  a mature lane as partial merely because follow-up questions remain.

## Minimum Evidence Bar

Each research note should normally contain:

- one headline result plot or table;
- at least two representative standard phase-diagnostic images;
- at least one heat map or propagation-evolution image when the result bundle
  includes one;
- paired phase-diagnostic/heat-map pages for the main representative cases;
- a control/reference page when a baseline artifact exists;
- one diagnostic or tradeoff figure;
- a method/math section that includes the actual scalar objective and any
  optimizer-coordinate map used by the lane;
- short intuition summaries for math-heavy or otherwise complex sections,
  written in outward-facing language;
- a short references section with external research sources and key internal
  result artifacts;
- a limitations section that distinguishes missing evidence from known negative
  results;
- a reproduction capsule that is public-facing and avoids internal bookkeeping
  names.

## Verification Bar

The closeout for any note-writing pass must state:

- the PDF path compiled under `docs/research-notes/...`;
- whether `pdflatex` exited cleanly;
- whether the PDF was rendered and visually inspected;
- any visible layout issues left unresolved.

## Reviewer Checklist

Use this as the pass/fail checklist before moving a note into the
production-ready table in `README.md`.

### 1. Claim And Scope

- [ ] The abstract states the research question, the main conclusion, and the
  evidence status in plain language.
- [ ] The claim-status box says whether the lane is established, provisional,
  exploratory, or intentionally parked.
- [ ] The note separates established claims from hypotheses, negative results,
  and future work.
- [ ] The note does not overstate incomplete runs, non-converged optimizations,
  or exploratory sweeps.
- [ ] The note has a presentation capsule: one slide-level takeaway, one
  canonical figure pair, and the 2--4 points a presenter should say out loud.

### 2. Math And Objective

- [ ] The full scalar objective is written, including numerator, denominator,
  band mask, quadrature convention when relevant, and dB transform.
- [ ] The controlled variable is explicit: phase, reduced coefficients,
  amplitude, energy, mode weights, or another coordinate.
- [ ] Any parameter map is written as an equation, for example
  `phi = Bc`, `a = A exp(i phi)`, or a normalized mode-coordinate map.
- [ ] Gradient chain rules are included when the optimizer coordinates differ
  from the physical coordinates.
- [ ] Regularizers, projections, gauge removal, clipping, smoothing, or
  trust-region models are described if they affect the optimized scalar.
- [ ] Dense equations include an `Intuition Check`, `TL;DR`, or equivalent
  outward-facing explanation.

### 3. Implementation And Reproduction

- [ ] The note identifies the main driver scripts and shared helpers.
- [ ] The note says which result files or summaries support the headline
  numbers.
- [ ] The reproduction capsule gives enough information to rerun the logic:
  machine boundary, command family, key parameters, expected outputs, and
  standard-image requirement.
- [ ] If the exact command is not yet stable, the note says so and labels the
  missing entry point as a gap.
- [ ] The note does not rely on private agent-history names as the only way to
  find the result.

### 4. Figures And Tables

- [ ] Every representative result has real images, not placeholders.
- [ ] The preferred phase evidence is the standard phase diagnostic.
- [ ] Each main phase diagnostic/profile is paired with the corresponding
  heat map/evolution figure on the same page when both exist.
- [ ] A no-optimization/no-shaping control page is included when the artifact
  exists.
- [ ] Captions explain what conclusion the reader should draw from the figure.
- [ ] Tables fit the page without cramped columns, overflowing text, or
  unreadable abbreviations.
- [ ] Embedded plot text has been inspected after PDF rendering; labels and
  annotations do not overlap.
- [ ] The note includes at least one figure or diagram that teaches the method,
  not only a final result plot.
- [ ] The most presentation-ready figures are clearly identifiable by caption
  or by a `Presentation Capsule` section.

### 5. Sources And Provenance

- [ ] Physics sources are cited for nonlinear fiber propagation, Raman response,
  and pulse-shaping context where relevant.
- [ ] Numerical sources are cited for RK4IP, L-BFGS, trust-region methods,
  continuation, Hessian diagnostics, randomized trace estimation, or other
  methods used by the lane.
- [ ] Citation links/DOIs have been checked against primary or stable sources.
- [ ] Internal result provenance is listed separately from external research
  sources.
- [ ] The note avoids weak citations for central claims when a primary source
  is available.

### 6. Verification And Visual QA

- [ ] The PDF was compiled from the note directory with `pdflatex`.
- [ ] The PDF was rendered to images and visually inspected page-by-page or by
  contact sheet plus targeted page inspection.
- [ ] The LaTeX log was checked for overfull boxes, undefined references,
  missing citations, fatal errors, and unresolved labels.
- [ ] Extracted PDF text was scanned for internal milestone labels,
  placeholder text, private coaching language, and obvious draft phrases.
- [ ] Build artifacts were cleaned after verification unless intentionally
  retained for debugging.

### 7. Promotion Decision

- [ ] If every item above is satisfied, promote the note in `README.md`.
- [ ] If not, leave it provisional and add the missing ingredients to
  `PROVISIONAL-UPGRADE-WORKSHEETS.md` or
  `VERIFICATION-CLOSURE-MATRIX.md`.
- [ ] If the note is technically correct but uses weak teaching examples,
  record that in `PRESENTATION-TASTE-AUDIT.md` before calling it
  presentation-ready.

## Presentation-Readiness Bar

The research-note series should be sufficient to build a lab presentation
without rereading months of agent logs. A presentation-ready note must include:

- one sentence that answers, "What did we learn?";
- one sentence that answers, "Why should the audience care?";
- one diagram or workflow figure for the method;
- one result figure pair that can be used directly on a slide;
- one control/baseline figure or table row;
- one limitations paragraph that prevents overclaiming during questions;
- one reproduction/provenance capsule so the presenter can defend where the
  numbers came from.

The series-level presentation map lives in
`PRESENTATION-BUILDING-BLOCKS.md`. If a historical finding is not represented
there, treat it as not yet presentation-covered.

The series-level taste audit lives in `PRESENTATION-TASTE-AUDIT.md`. If a
figure is technically valid but pedagogically weak, it should be downgraded from
the main slide path even if it remains in the research note.
