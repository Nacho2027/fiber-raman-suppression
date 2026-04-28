# Citation Audit

Evidence snapshot: 2026-04-28

Scope: external URLs cited in the numbered research-note LaTeX files and in
`docs/reference/current-equation-verification.tex`.

## Method

- Extracted all `\url{...}` entries from the note sources and equation
  reference.
- Checked URL reachability with redirected HTTP requests.
- Manually inspected ambiguous failures where publisher sites block automated
  clients.
- Patched citations that were confirmed to be wrong, not merely blocked.

## Summary

| Category | Count | Status |
|---|---:|---|
| Unique external URLs checked | 38 | Complete for this audit pass |
| Directly reachable or redirected successfully | 23 | Accepted |
| Publisher-blocked automated checks | 12 | Accepted with manual/source caveat |
| Confirmed broken or wrong citations | 3 | Fixed |

Publisher-blocked links include common DOI targets at AIP, APS, IEEE Xplore,
SIAM, ACM, Taylor & Francis, and ScienceDirect. These returned `403` or `418`
to automated requests but correspond to normal publisher pages or DOI targets;
they should be considered reachable by a browser unless a later manual check
shows otherwise.

## Fixes Applied

| Location | Problem | Fix |
|---|---|---|
| `docs/reference/current-equation-verification.tex` | RK4IP citation used a bad IEEE DOI suffix. | Changed Hult RK4IP DOI to `https://doi.org/10.1109/JLT.2007.909373`. |
| `docs/research-notes/10-recovery-validation/10-recovery-validation.tex` | Dauphin saddle-point NeurIPS URL used the wrong hash page and returned 404. | Replaced with the short stable arXiv page for the same paper, avoiding an overfull bibliography line. |
| `docs/research-notes/03-sharpness-robustness/03-sharpness-robustness.tex` | Nohadani/Bertsimas robust-electromagnetic-scattering citation had the wrong AIP DOI. | Changed DOI to `https://doi.org/10.1063/1.2715540`. |

## Follow-Up Before Publication

- Recompiled the three changed PDFs:
  `03-sharpness-robustness.pdf`, `10-recovery-validation.pdf`, and
  `current-equation-verification.pdf`.
- Rechecked the affected LaTeX logs. No hard errors, undefined references, or
  overfull boxes remain after the citation fixes.
- Rechecked extracted PDF text for the corrected citation strings.
- For final paper writing, replace bare URLs with BibTeX entries or a
  bibliography file so author/title/year metadata is controlled centrally.
