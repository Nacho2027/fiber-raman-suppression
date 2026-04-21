# Phase 19: Physics Audit 2026-04-19 — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning
**Mode:** Auto-generated (autonomous-mode context injection)

<domain>
## Phase Boundary

Verdict-classify every substantive physics claim in
`results/SYNTHESIS-2026-04-19.md` and the Phase 13/15/16/17 session
findings. Output: `results/PHYSICS_AUDIT_2026-04-19.md` with
defensible / shaky / wrong verdict per claim, sourced to
file:line, phase summary, validation markdown, or new burst-VM
verification runs. Diagnose the Session F 100m three-failure-mode
anomaly. Flag any existing `docs/*.tex` claim that contradicts
what survives.
</domain>

<decisions>
## Implementation Decisions

### Build on the prior pass — do not redo from scratch

A prior partial pass (commit `3e69c7a`) already produced
`results/PHYSICS_AUDIT_2026-04-19.md` and edited the three
canonical .tex files. The audit is **detailed and substantively
correct**. This phase REFINES it; it does not replace it.

### Verification work already completed in this session (LOCKED)

(1) **Source citations confirmed** by an Explore agent against the
actual artifacts: D1 (J=-76.86 dB at SMF-28 L=0.5 m P=0.05 W), D2
(σ_3dB=0.025 rad), D3 (warm-start transfer 11/11), D4 (Pareto
-82.33 dB), D5 (|λmin|/λmax = 2.6%/0.41%), D6 (FFTW determinism
+21.4%), W1 (R²=0.015@100 m, 0.037@2 m on weighted quadratic fit;
a₂ ratio -3.30 vs +50 GVD prediction). Only one minor citation
issue (S2's "honest -65.8 dB" line is at
`docs/verification_document.tex:1388`, not :1161 — the .tex is
already correct, only the audit's reference needs updating if
strictness matters).

(2) **W1 (Session F 100 m anomaly) diagnosis confirmed.** The
audit's verdict (sign-flip + R²<0.04 means the a₂ ratio carries
no signal) is correct. Refinement: the precise statement is not
"ratio of noise" but "ratio of two coefficients in a misspecified
quadratic model where 98.5% of weighted variance is non-quadratic
residual structure" — the a₂ projection has no scaling-law
content because the underlying φ_opt isn't quadratic on the signal
band. Three failure modes (wrong sign, wrong magnitude, R²<0.04)
all reduce to one: model misspecification.

(3) **NEW finding (the actual phase 19 contribution):** Cross-check
the audit's D5 against the Phase 18 numerical-trustworthiness
report at `results/validation/`. Found:
   - `results/validation/phase13_hessian_smf28.md`: J reported
     -60.5 dB, J recomputed on validator's clean grid -48.2 dB
     (12.3 dB gap, edge_fraction 1.01% — just over SUSPECT
     threshold).
   - `results/validation/phase13_hessian_hnlf.md`: J reported
     -74.4 dB, J recomputed -44.0 dB (30.4 dB gap, edge_fraction
     2.10%).
   - In both cases adjoint ‖g‖ at the saved φ_opt is ~1e-5 (small,
     confirms true stationarity on the recomputed grid).
   - Conclusion: the Hessian eigenstructure verdict (D5:
     |λmin|/λmax = 2.6%/0.41%, 100% same-sign wings) is at a true
     stationary point and stands. Only the dB anchoring of the
     "optimum" was time-window-affected. D5 should be demoted from
     "defensible" to "shaky with caveat" and a new section X1
     added.

### Out of scope for this phase

- New burst-VM forward solves: NOT NEEDED. The Phase 18 audit
  already did all the cross-check forward solves.
- Edits to `docs/*.tex` files. Those happen in Phase 20.
- Edits to `results/raman/*.md`. Those are input-only.

### Final audit counts (post-revision)

7 defensible · 7 shaky · 3 wrong · 2 missing-data (after D5 demotion).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning:**

### Audit input artifacts
- `results/SYNTHESIS-2026-04-19.md` — the claims under audit
- `.planning/notes/integration-snapshot-2026-04-19.md` — context
- `results/PHYSICS_AUDIT_2026-04-19.md` — prior partial pass (refine, don't replace)

### Verification cross-references
- `results/validation/REPORT.md` — Phase 18 top-level
- `results/validation/phase13_hessian_smf28.md` — for new §X1
- `results/validation/phase13_hessian_hnlf.md` — for new §X1
- `results/raman/phase17/SUMMARY.md` — D1, D2, D3, W3 citations
- `results/raman/phase16/FINDINGS.md` — S4, S5, W1 citations
- `results/raman/phase15/benchmark.md` — D6 citation
- `results/raman/phase13/FINDINGS.md` — D5 citation

### Project rules
- `CLAUDE.md` — multi-machine sync, GSD strict mode, burst-VM rules
</canonical_refs>

<specifics>
## Specific Refinements to Apply

1. **Update audit counts** in the front-matter Method paragraph:
   "8 defensible · 6 shaky · 3 wrong · 2 missing-data" →
   "7 defensible · 7 shaky · 3 wrong · 2 missing-data
   (D5 demoted post-rev-2 — see §X1)".

2. **Refine W1** wording (in the audit):
   "ratio of noise" → "ratio of two coefficients in a misspecified
   quadratic model where 98.5% of weighted variance is
   non-quadratic residual structure".

3. **Add new §X1** ("Cross-check against Phase 18 reproducibility
   audit") AFTER §"Wrong" and BEFORE §"Missing data":
   - Paragraph 1: state the finding (Phase 13 hessian configs'
     reported J was time-window-affected; eigenstructure verdict
     unchanged).
   - Paragraph 2: source-cite both validation files and the
     stationarity diagnostic (‖g‖ ~ 1e-5).
   - Paragraph 3: actionable consequence: D5 stays in the docs
     but with a "dB anchor was time-window-biased; eigenstructure
     verdict is robust" caveat that Phase 20 must propagate.

4. **Add a brief Literature Anchor** subsection at the end (just
   before "Docs update plan"): note the absence of published prior
   art for spectral-phase-only Raman suppression at -77 dB on
   single-mode fiber. Cite Weiner 2000 (femtosecond pulse shaping)
   and Wright et al. 2020 (multimode nonlinear pulse propagation,
   APL Photonics) as the closest comparison anchors. This is
   useful framing for the advisor talk.

5. **Update the docs update plan** at the bottom of the audit to
   reflect the four .tex changes Phase 20 must make:
   (i) `companion_explainer.tex` W1 wording refinement,
   (ii) `verification_document.tex` §sec:april-hessian gets the
        J-anchoring caveat,
   (iii) `verification_document.tex` W1 wording refinement,
   (iv) `verification_document.tex` adds a brief §"Phase-18
        cross-check" reference under §"Integration Pass".
</specifics>

<deferred>
## Deferred Ideas

- A wider-grid recomputation of the Phase 13 Hessian to pin down
  whether |λmin|/λmax shifts when the optimum is re-found on a
  larger time window. Conjecture: the eigenstructure is robust
  (a saddle is a saddle regardless of dB anchoring), but the
  exact ratios may move ~10-20%. Out of scope for Phase 19.
- A multi-start verification of the 100 m result to test whether
  the warm-start basin is the global minimum at L=100 m. Listed
  in `results/raman/phase16/FINDINGS.md` open questions; would
  require burst-VM time we don't need for the audit refinement.
</deferred>
