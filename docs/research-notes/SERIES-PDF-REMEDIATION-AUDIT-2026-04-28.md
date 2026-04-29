# Series PDF Remediation Audit

Track PDF rebuild status here. Review the source Markdown/TeX and selected figures, not just the compiled PDFs.

## 2026-04-29 MMF Completion Pass

- Reconciled `08-multimode-baselines` with the completed high-resolution MMF validation.
- Conservative public headline is now the accepted `Nt = 8192`, `96 ps` result: summed Raman metric `-17.37 dB -> -41.25 dB`, a `23.9 dB` reduction with raw temporal-edge fractions below `4e-13`.
- Kept the lower-resolution `31.7 dB` result only as context, not as the main claim.
- Removed public-facing internal milestone path language from the MMF note and readiness report; reproduction commands now use a neutral MMF validation output name.
- Recompiled `08-multimode-baselines.tex` twice with `pdflatex`.
- Rendered all 12 PDF pages to PNG and visually inspected the title/claim page, claim-boundary diagram, validation ladder/table, control page, rejected unregularized page, accepted result page, representative-result page, reproduction page, and references page.
- Scanned the MMF note/report and the research-note source directories for stale internal labels, unfinished-marker language, failed high-grid language, and weak short-fiber hero framing; no targeted hits remained.

## 2026-04-29 Final Series Gate

- Recompiled all 12 note PDFs.
- Rendered all 162 PDF pages to PNG under `/tmp/research-note-final-audit`.
- Built and inspected contact sheets for every note.
- Scanned LaTeX logs for hard errors, overfull boxes, undefined references, and undefined citations.
- Scanned public note sources for stale internal labels, unfinished-marker language, failed high-grid language, and weak short-fiber framing.
- No PDF-level blockers remained after this gate.

Notes with important claim caveats:

- `06-long-fiber`: presentation-ready as a constrained long-fiber result, not as a universal convergence claim.
- `08-multimode-baselines`: presentation-ready as an idealized six-mode MMF simulation, not as generic experimental MMF proof.
- `12-long-fiber-reoptimization`: presentation-ready as a provisional warm-start strategy lane, not as a final benchmark.
