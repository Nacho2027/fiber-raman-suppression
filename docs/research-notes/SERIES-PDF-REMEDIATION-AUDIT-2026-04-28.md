# Series PDF Remediation Audit - 2026-04-28

This audit applies the reduced-basis note standard to the remaining research
note PDFs: compile, log scan, stale-language scan, render pages, inspect contact
sheets, then prioritize concrete fixes.

## Checks Completed

- Recompiled notes `01` and `03` through `12` twice with `pdflatex`.
- Scanned note logs for `Overfull`, undefined citations/references, and hard
  errors.
- Rendered every remaining PDF to PNG pages and built contact sheets under
  `/tmp/research-note-audit`.
- Scanned public note sources for stale internal milestone labels, placeholders,
  and weak `500 mm` hero framing.

## Compile/Log Status

No hard LaTeX failures were found in the remaining notes. The current logs for
`01` and `03` through `12` have no overfull boxes and no undefined citations or
references. Minor underfull/caption warnings are not treated as publication
blockers unless they correspond to visible page defects.

## Visual Audit Matrix

| Note | Visual status | Content status | Priority |
|---|---|---|---|
| `01-baseline-raman-suppression` | Paired control/optimized pages present; one sparse transition page. | Good baseline explanation; could use a tighter provenance capsule. | Medium |
| `03-sharpness-robustness` | Multiple paired diagnostic/heat-map pages; no obvious overlap. | Strong math and interpretation; sparse representative-results intro page. | Medium |
| `04-trust-region-newton` | Paired pages present; no obvious overlap. | Good algorithm explanation; should keep explicit that this is a methods lane. | Low-medium |
| `05-cost-numerics-trust` | Control and shaped result pages present; tables readable. | Strong diagnostics framing; provenance could be more explicit. | Low-medium |
| `06-long-fiber` | Real long-fiber figures present; dense result pages. | Needs stricter control-versus-optimized framing and provenance polish. | High |
| `07-simple-profiles-transferability` | Strong paired pages and tradeoff figures. | Good standalone story; minor sparse intro page. | Low-medium |
| `08-multimode-baselines` | Control, rejected, and accepted visuals present. | Needs careful provisional wording and exact trust-gate framing. | High |
| `09-multi-parameter-optimization` | Rich figure set; no obvious overlap. | Good result/method structure; keep as mature but verify provenance. | Medium |
| `10-recovery-validation` | Strong paired pages and scalar diagnostic figures. | Good validation structure; mostly needs final provenance hardening. | Medium |
| `11-performance-appendix` | Charts readable; appendix style acceptable. | Fine as support note, not a primary physics note. | Low |
| `12-long-fiber-reoptimization` | Too short; control page initially lacked paired phase diagnostic. | Important strategy note; needs the reduced-basis-style control/optimized pairing. | High |

## Immediate Remediation Order

1. `12-long-fiber-reoptimization`: add no-optimization phase diagnostic paired
   with the control heat map, strengthen reproducibility wording, recompile, and
   re-inspect.
2. `06-long-fiber`: make the control/optimized comparison easier to present and
   add clearer provenance/reproduction status.
3. `08-multimode-baselines`: make the trust gate and provisional status explicit
   enough that the note can stand alone.
4. `01`, `03`, `04`, `05`, `07`, `09`, `10`: page-level polish and provenance
   hardening, not emergency visual repair.
5. `11`: keep as an appendix; do not force it into the same result-note shape.

## Audit Rule Going Forward

A note is not considered remediated until the PDF has been recompiled, rendered
to page images, visually inspected, and scanned for stale/internal language after
the final edit.
