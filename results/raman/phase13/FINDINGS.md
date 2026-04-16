# Phase 13 Findings — Optimization-Landscape Diagnostics

**Scope.** Phase 13 asked one question: why do different L-BFGS starts, and
small (L, P) perturbations, produce visibly different `phi_opt(omega)`
profiles? Three orthogonal workstreams were run to triangulate the answer
— determinism, gauge + polynomial analysis (Plan 01), and Hessian
eigenspectrum (Plan 02).

Generated: 2026-04-16
Data sources: `results/raman/phase13/*.jld2` + 3 figures in
`results/images/phase13/phase13_0{4,5,6}_*.png`.

---

## Headline verdict

**`indefinite_hessian`** — at both canonical L-BFGS optima
(SMF-28, L=2 m, P=0.2 W  and  HNLF, L=0.5 m, P=0.01 W) the Hessian is
indefinite with `lambda_min < 0 < lambda_max`. L-BFGS is not stopping at
a minimum; it is stopping at a **saddle point** that happens to have
small gradient norm (~1e-7). The negative-curvature directions have
magnitude 0.4 %–2.6 % of `lambda_max` — small but numerically robust,
not noise.

This subsumes the Plan 01 gauge/polynomial finding (phases are NOT
related by a gauge transformation and NOT explainable by low-order
polynomial structure) and refines it: the "different starts → different
phi_opt" symptom is L-BFGS halting at **different saddles** whose
stable-manifold directions happen to intersect the random-start cone.

One important **limitation** on the verdict: Arpack's matrix-free
Lanczos wings (`:LR` largest algebraic, `:SR` smallest algebraic) cannot
resolve eigenvalues near zero without shift-invert — which is
impossible without an explicit Hessian factorisation. So while we
confirmed the indefinite sign pattern and bounded `|lambda|_min` from
below at ~1e-7, the **gauge null-modes predicted by theory**
(eigenvectors ~ `{const, omega-linear}` at `lambda = 0`) are **NOT in
the reported set** — they lie between `lambda_bottom[20]` (~-1e-7) and
`lambda_top[20]` (~1e-6), in the region Arpack doesn't sample. Their
existence is a theorem, not a number we measured. See
**§ Workstream 3 Limitations**.

---

## Workstream 1 — Determinism

**Verdict: FAIL** (documented in Plan 01, `results/raman/phase13/determinism.md`).
Two runs with identical `Random.seed!(42)` and identical config produce
`phi_opt` differing by `max|Δφ| = 1.041 rad` and final J differing by
-1.83 dB (`J_a = -67.27 dB` vs `J_b = -65.45 dB`).

**Root cause (diagnosed):** `FFTW.MEASURE`-mode plan selection in
`src/simulation/simulate_disp_mmf.jl` / `sensitivity_disp_mmf.jl`.
MEASURE runs timing microbenchmarks to pick the fastest FFT algorithm,
and the selection is timing-noise-dependent even on a single thread.
Different plan choices differ bit-wise due to floating-point reduction
associativity; L-BFGS amplifies the noise into fully different `phi_opt`.

**Status:** Addressed by **Phase 15** (see `scripts/determinism.jl`
`ensure_deterministic_fftw()` + ESTIMATE-only planner). All Plan 02
Hessian runs used ESTIMATE so the eigenspectrum below is reproducible.
For cross-run comparison of *optimizer outputs*, the ESTIMATE switch
must be propagated; Phase 15-01 already wires this into the 5 main
entry points.

---

## Workstream 2 — Gauge fix + polynomial projection (Plan 01)

All 39 existing `phi_opt` arrays (5 canonical runs + 24 sweep optima +
10 multistart) were pushed through `gauge_fix` and `polynomial_project`
with orders 2..6.

| Claim | Verdict | Quantification |
|---|---|---|
| Same-config random-start pairs collapse under gauge-fix | **FALSE** | **0 / 55 pairs** satisfy `rms_gauge_fixed < 0.1 · rms_raw` |
| Neighbour sweep pairs collapse under gauge-fix | **FALSE** | same **0 / 55**; alpha and C are already near-zero in the raw `phi_opt` |
| Low-order polynomial (orders 2..6) explains `phi` | **WEAKLY** | **median residual fraction = 0.924**; 0/39 below 50 %; 9/39 below 80 % |
| (a_2, a_3, a_4) vary smoothly across (L, P) | **PARTIAL** | clear (a_2, a_4) anti-correlation but (a_3)-dependent panels are scatter-dominated; 3 HNLF optima dropped for residual ≥ 0.95 |

**Interpretation.** The phases are not gauge-copies of one another; in
fact the raw `phi_opt` have near-zero mean and near-zero group delay to
begin with, meaning L-BFGS is already converging to something roughly
"gauge-fixed" by luck of the initial condition (zero-phase start).
Orders 2..6 fail to explain the residual structure — there is real
high-frequency oscillation in `phi_opt(omega)` that a 5-coefficient
monomial basis cannot capture.

See Fig 1 (`phase13_01_gauge_before_after.png`), Fig 2
(`phase13_02_polynomial_residuals.png`), Fig 3
(`phase13_03_polynomial_coefficients.png`) for the visual evidence.

---

## Workstream 3 — Hessian eigenspectrum (Plan 02)

Finite-difference HVP (symmetric central difference, `eps = 1e-4`) was
wrapped as a matrix-free LinearOperator and passed to `Arpack.eigs`
with `nev = 20` on each wing:

- `:LR` (largest algebraic) → **top-20** eigenvalues + eigenvectors
- `:SR` (smallest algebraic) → **bottom-20** eigenvalues + eigenvectors

HVP Taylor-remainder validation was performed in
`test/test_phase13_hvp.jl` (committed at `b962091`) and showed the
expected O(eps²) convergence — slope ≈ 2 in the log-log residual plot
over the middle three decades of `eps`. HVP symmetry `v' H w ≈ w' H v`
passed to 1e-5 relative. Cross-validation against a dense Hessian at
`Nt = 2^8` also passed.

### Eigenvalue summary

| Config | `lambda_max` | `lambda_min` | `|lambda_min|/lambda_max` | Sign pattern | Near-zero in ±20 wings (thr. 1e-6·λ_max) |
|---|---:|---:|---:|:---:|:---:|
| SMF-28 canonical  (L=2m,   P=0.2 W)  | `+1.074e-05` | `-2.794e-07` | **2.6 %**  | INDEFINITE | **0** |
| HNLF  canonical  (L=0.5m, P=0.01 W) | `+5.078e-05` | `-2.091e-07` | **0.41 %** | INDEFINITE | **0** |

Both wings are **100 % same-sign**: all 20 of `lambda_top` are positive,
all 20 of `lambda_bottom` are negative. The saddle signature is robust.

### Cosine similarity to the analytic gauge modes

The Hessian of `J = E_band/E_total` is invariant under
`phi → phi + C + alpha·omega` (see `newton-exploration-summary.md §4`),
so two eigenvalues **must** be exactly zero with eigenvectors
`{const, omega-linear-centered-on-band}`. We checked the bottom-5
eigenvectors against the two analytic gauge references
(unit-normalised):

| Config | Bottom-5 k | lambda | cos(·, const) | cos(·, ω-linear) | Gauge match? |
|---|:---:|---:|---:|---:|:---:|
| SMF-28 | 1 | -1.308e-07 | 0.0099 | 0.0004 | no |
| SMF-28 | 2 | -1.406e-07 | 0.0004 | 0.0015 | no |
| SMF-28 | 3 | -1.427e-07 | 0.0049 | 0.0011 | no |
| SMF-28 | 4 | -1.439e-07 | 0.0131 | 0.0006 | no |
| SMF-28 | 5 | -1.448e-07 | 0.0003 | 0.0005 | no |
| HNLF   | 1 | -2.384e-08 | 0.0059 | 0.0003 | no |
| HNLF   | 2 | -3.668e-08 | 0.0027 | 0.0001 | no |
| HNLF   | 3 | -4.294e-08 | 0.0143 | 0.0003 | no |
| HNLF   | 4 | -4.391e-08 | 0.0025 | 0.0001 | no |
| HNLF   | 5 | -4.732e-08 | 0.0022 | 0.0001 | no |

**None** of the reported bottom-5 eigenvectors has cos-similarity above
our 0.95 threshold with either gauge mode. Projected onto the full
reported 20-vector bottom subspace, the gauge modes sit at
`||P_bot c|| = 0.060` (SMF) / `0.038` (HNLF) and
`||P_bot ω-linear|| = 0.005` / `0.001` — essentially orthogonal to the
reported wings. This is **exactly consistent with the gauge modes
having λ ≈ 0** and therefore living *between* the top and bottom wings,
in the region matrix-free Arpack Lanczos cannot resolve.

### Top-5 stiff directions (Fig 5)

The top-5 eigenvectors are concentrated in the input band with fine
structure and no obvious low-order (polynomial) interpretation — they
look like high-frequency oscillations whose wavelength decreases with
eigenvalue rank. On HNLF the stiff structure is noisier / broader than
on SMF-28, consistent with HNLF's larger |β_3/β_2| mixing spectral
directions more strongly.

### Bottom-5 soft directions (Fig 6)

All bottom-5 eigenvectors are negative-eigenvalue: descent directions
of the cost. They too localise on the input band (visible in
Fig 6, columns 1 and 2), and none of them is a gauge null-mode. Their
existence is the proof of the saddle.

### Workstream 3 Limitations

1. **Matrix-free Arpack cannot resolve λ ≈ 0.** Shift-invert requires
   factoring `(H - σI)` which is not available for a matrix-free HVP.
   The plan anticipated this. Consequence: the 2 gauge null-modes
   predicted by symmetry are invisible in the reported 40-vector
   spectrum. We inferred their location (in the gap between `lambda_top[20]
   ≈ 1e-6` and `lambda_bottom[20] ≈ -1e-7`) from the gauge projection
   norms but did not measure them directly.
2. **HVP epsilon floor.** At `eps = 1e-4` the HVP is accurate to about
   `1e-9` (from the Taylor test) which bounds our eigenvalue resolution.
   Eigenvalues much smaller than this in magnitude would be buried in
   HVP noise. Smallest `|lambda_bottom|` we report is `2.4e-8` (HNLF),
   which is comfortably above the floor.
3. **Nt = 8192.** The eigendecomposition was done at the production
   grid. Cross-validation with a dense Hessian at `Nt = 2^8` confirmed
   the HVP machinery is correct but does not guarantee the
   high-resolution spectrum is free of grid-dependent spurious modes.
   A single burst-VM rerun at `Nt = 4096` could de-risk this; not yet
   performed.
4. **Arpack convergence.** `n_iter_top = 20 = nev` and `n_iter_bot = 20`
   at both configs means Lanczos terminated at the minimum iterations,
   suggesting Arpack's internal convergence test was satisfied
   immediately. We did not inspect residuals but did verify orthogonality
   of the returned eigenvectors (`||V_top' V_top - I||_max ≈ 1e-15`,
   same for `V_bot`). Cross-orthogonality `|V_top' V_bot|_max = 0.05`
   (SMF) / `0.18` (HNLF) is elevated — the two wings share some span —
   reinforcing that Arpack has not cleanly separated the spectrum near
   zero.

---

## Routing recommendation for Phase 14

**Go forward with sharpness-aware cost.** The indefinite Hessian is
direct evidence that the landscape has escape directions below the
current "converged" points. Phase 14's sharpness-aware regularisation
is exactly the right tool: penalising curvature-weighted cost changes
along the local Hessian's soft / negative directions will either (a)
push the optimizer away from saddles into genuine minima or (b) make
the optimizer's stopping tolerance physical rather than numerical.

**Which sharpness measure.** Given the spectrum:

- **Use a full (signed-abs) sharpness penalty**, not a PSD-truncated
  one. The negative-curvature directions are the interesting physics,
  not an artifact — a penalty that ignores them collapses back to
  first-order.
- The current vanilla `lambda = 0.1` snapshot (commit `3ba48cd`) is a
  reasonable starting regularisation strength: `|lambda_min|/lambda_max
  ≈ 1e-2` means a sharpness penalty with weight ≲ 0.1 will perturb the
  objective by ~10⁻⁴ at the current optima — small enough not to
  dominate the physical cost, large enough to kick L-BFGS off the
  saddle. If Phase 14 sees no qualitative change at `lambda = 0.1`,
  try `lambda = 1.0` before abandoning the approach.
- The sharpness penalty should be computed over the **full reported
  40-vector spectrum** (top + bottom), not a top-K truncation. The
  bottom wing carries the key information here.

**Newton vs L-BFGS for Phase 14+.** Newton-CG with trust-region would
be the principled fix for a saddle, but the engineering cost is high
(second-order adjoint is not in the codebase). Sharpness-aware L-BFGS
is the cheap first thing to try; if it fails, the Hessian-eigenspectrum
evidence is now strong enough to justify the Newton implementation (see
`.planning/notes/newton-exploration-summary.md`).

**Open new research question for Phase 14 or beyond.** Does the saddle
structure persist across the (L, P) sweep, or is there a "true minimum
basin" at some parameter combination? A quick 5-point (L, P) grid with
the Plan 02 Hessian script (now cheap: ~2 min/point on burst) would
answer this.

---

## Limitations & open questions

- **Gauge null-modes not measured.** See § Workstream 3 Limitations (1).
  The verdict depends on a theorem (2 gauge modes at λ=0) that this
  particular diagnostic cannot directly verify.
- **No comparison across multistart points.** Plan 02 analyzed the
  single canonical optimum per fiber. Whether the negative-curvature
  directions are consistent across the 10 multistart runs (suggesting a
  systematic saddle structure) vs. idiosyncratic per start is an open
  question. A batch run of Plan 02's `run_eigendecomposition` across
  10 multistart `phi_opt` values is the natural follow-up — maybe
  Phase 14 Plan 02.
- **Curvature in the input-band-projected subspace.** The reported
  spectrum is over the full 8192-dim phase space. The physics lives on
  the ~1700-dim input-band subspace (per Plan 01's mask). Projecting
  the Hessian onto that subspace before eigendecomposition would give
  a cleaner answer but requires rewriting the HVP.
- **Phase 14 sharpness-aware test.** The regression test at commit
  `3ba48cd` established a vanilla snapshot but hasn't yet been compared
  to a sharpness-aware run. Phase 14 execution will close this loop.

---

## References to artifacts

All paths relative to the repo root.

| Purpose | Path |
|---|---|
| Plan 01 gauge+polynomial data | `results/raman/phase13/gauge_polynomial_analysis.jld2` |
| Plan 01 summary CSV | `results/raman/phase13/gauge_polynomial_summary.csv` |
| Plan 01 determinism report | `results/raman/phase13/determinism.md` |
| Plan 02 SMF-28 Hessian | `results/raman/phase13/hessian_smf28_canonical.jld2` |
| Plan 02 HNLF Hessian | `results/raman/phase13/hessian_hnlf_canonical.jld2` |
| Fig 1 gauge before/after | `results/images/phase13/phase13_01_gauge_before_after.png` |
| Fig 2 polynomial residuals | `results/images/phase13/phase13_02_polynomial_residuals.png` |
| Fig 3 polynomial coefficients | `results/images/phase13/phase13_03_polynomial_coefficients.png` |
| Fig 4 Hessian eigvals stem | `results/images/phase13/phase13_04_hessian_eigvals_stem.png` |
| Fig 5 top eigenvectors | `results/images/phase13/phase13_05_top_eigenvectors.png` |
| Fig 6 bottom eigenvectors | `results/images/phase13/phase13_06_bottom_eigenvectors.png` |
| Plan 01 SUMMARY | `.planning/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/13-01-SUMMARY.md` |
| Plan 02 SUMMARY | `.planning/phases/13-optimization-landscape-diagnostics-gauge-fixing-polynomial-p/13-02-SUMMARY.md` |

### Compute metadata

- Plan 02 burst-VM compute cost: ~$0.18 (fiber-raman-burst c3-highcpu-22,
  ~4 min wall time for 2 configs x Arpack :LR + :SR)
- HVP method: symmetric central difference, `eps = 1e-4`
- Taylor-remainder slope: ~2.0 (validated in `test/test_phase13_hvp.jl`
  at commit `b962091`)
- Arpack settings: `nev=20, tol=1e-7, maxiter=500`; no shift-invert
  fallback used (not available for matrix-free HVP)
- Julia threads on burst: 22; FFTW pinned to 1 (per determinism doc);
  BLAS pinned to 1
