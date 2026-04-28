# Research Note Verification Closure Matrix

Evidence snapshot: 2026-04-28

This matrix tracks what must be true before the mini research-note series can be
treated as near-standalone lab or paper-prep documentation. A note can compile
and still be incomplete if its math, code path, reproduction command, or result
artifact is not verified.

## Global Quality Bar

Every production-ready note should answer these questions before the reader has
to ask:

- What exact problem is being solved?
- What exact scalar objective is optimized?
- What variables are optimized, and in what coordinates?
- What algorithm is used, and why is it appropriate?
- What equations does the implementation rely on?
- Which source files implement those equations?
- Which tests or finite-difference checks verify the gradients or diagnostics?
- Which saved run artifacts produce the reported numbers and images?
- How can someone reproduce the representative result?
- What is the no-optimization or simpler baseline?
- What evidence would change or weaken the conclusion?
- What remains unverified or intentionally parked?

## Series-Wide Verification Tasks

| Task | Status | Required Action |
|---|---|---|
| Build every PDF from source | current PDFs present | Re-run full batch compile after any source edit. |
| Render every PDF page after compile | done for 2026-04-28 audit | Repeat contact-sheet inspection after substantive figure/table edits. |
| Remove internal milestone labels from public PDFs | passed 2026-04-28 scan | Re-run text grep across all PDFs before final freeze. |
| Verify all external citations | first audit complete | See `CITATION-AUDIT-2026-04-28.md`; final paper pass should migrate to BibTeX. |
| Verify each reported number against an artifact | partial | See `ARTIFACT-PROVENANCE-LEDGER-2026-04-28.md`; add exact per-note provenance tables before publication freeze. |
| Verify each algorithm against code path | partial | Add source-path capsules with exact scripts/helpers. |
| Verify analytic gradients and equations | local closure updated | See `EQUATION-CODE-CLOSURE-2026-04-28.md`; heavyweight physics verification still requires burst. |
| Re-run heavyweight physics verification | stale | Run `scripts/research/analysis/verification.jl` on burst. |
| Close or label missing simulation gaps | partial | Run only gap-closing simulations; otherwise label lanes provisional. |

## Note-by-Note Status

| Note | Current Document State | Main Verification Gaps | Next Action |
|---|---|---|---|
| `01-baseline-raman-suppression` | presentation-ready | Needs exact result-provenance table and source-path capsule tied to current canonical command. | Audit canonical artifact, code path, and trust report; add a small reproducibility appendix. |
| `02-reduced-basis-continuation` | presentation-ready | Needs final cross-check that all reported values map to saved artifacts and that basis math matches current code. | Add result-provenance table and a basis-code verification capsule. |
| `03-sharpness-robustness` | presentation-ready | Needs sharper source verification for the sharpness objective and Hessian/robustness diagnostics. | Audit sharpness source path and Hessian evidence before publication use. |
| `04-trust-region-newton` | presentation-ready as methods/result context | Needs final HVP/trust-ratio convention comparison against the equation verification doc. | Keep as diagnostic lane; do not present as a default optimizer. |
| `05-cost-numerics-trust` | presentation-ready methodology note | Needs source-provenance table and fresh equation-verification links after rerun. | Keep as backbone; update once verification suite is rerun. |
| `06-long-fiber` | presentation-ready with caveat | Long-fiber values are achieved milestones, not converged optima. | Revisit only if a converged or cleaner lab-ready long-fiber mask appears. |
| `07-simple-profiles-transferability` | presentation-ready | Needs final artifact provenance for transfer/robustness numbers. | Keep the simple/deep/transferable claim split; verify numbers before paper use. |
| `08-multimode-baselines` | presentation-ready with caveat | Grid refinement, launch sensitivity, and random-coupling gates remain open. | Present as qualified idealized GRIN-50 simulation only. |
| `09-multi-parameter-optimization` | presentation-ready with caveat | Lab handoff still needs amplitude calibration and stronger convergence closure. | Use staged amplitude refinement as the positive claim; keep broad joint optimization as negative. |
| `10-recovery-validation` | presentation-ready | Needs exact saved-state provenance and reproduction commands for each recovered case. | Add provenance table after verification backbone. |
| `11-performance-appendix` | presentation-ready appendix | Needs citation verification and benchmark provenance, but no optical phase/heat-map pages are expected. | Add citation audit and benchmark provenance if doing final publication pass. |
| `12-long-fiber-reoptimization` | visually checked provisional strategy note | Needs fresh rerun/provenance before promotion. | Keep provisional until warm-start/reoptimization artifacts are freshly confirmed. |

## Simulation Or Verification Runs That May Close Gaps

These should run on burst, not on the editing host.

1. Full physics verification:
   `julia -t auto --project=. scripts/research/analysis/verification.jl`

2. Multivariable gradient smoke/regression suite:
   passed on 2026-04-28 with
   `julia -t auto --project=. scripts/dev/smoke/test_multivar_gradients.jl`

3. MMF shared-phase and mode-coordinate verification:
   the planning dry-run passed on 2026-04-28; full MMF verification should use
   the dedicated MMF validation driver on burst.

4. Cost-audit missing matrix only if we decide the cost-audit note needs a
   completed matrix rather than an honest incomplete matrix:
   `julia -t auto --project=. scripts/research/cost_audit/cost_audit_driver.jl`

5. Multimode clean-window validation only if `08` is to become a stronger
   paper-grade claim:
   use the existing MMF validation driver identified in the lane audit.

6. Long-fiber checkpoint guard:
   the lightweight checkpoint self-test passed on 2026-04-28 after a soft-scope
   bug in the test harness was fixed.

## Immediate Priority

The next high-leverage task is the public verification backbone:

1. Update or replace the old reference verification document so it matches the
   current codebase.
2. Re-derive the active equations in a compact, readable form.
3. Link each equation to source files and tests.
4. Run the verification suite on burst and attach the report.
5. Feed the verified equations and run status back into each research note.

Until that is done, the polished notes are useful lab handouts, but not yet a
fully closed publication-grade documentation set.
