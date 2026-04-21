# Phase 31 — FINDINGS

**Question:** does reduced-basis (Branch A) or regularization (Branch B) give a simpler, more transferable, equally-deep Raman-suppression optimum than full-grid L-BFGS from zero init?

**Canonical configuration:** SMF-28, L = 2 m, P = 0.2 W, Nt = 16 384, log-cost + chain-rule-scaled gradient, 80 iters max. Run on Mac (16-core Apple Silicon). All 20 + 21 optima obtained 2026-04-21.

## Headline verdict

**Branch A (cubic basis at N_phi = 128) wins on depth — J = −67.6 dB — but sits in a tight basin (σ_3dB = 0.07 rad) with poor cross-fiber transfer (+21.5 dB on HNLF).** Branch B full-grid zero-init L-BFGS plateaus at −57.75 dB *regardless of penalty family at λ = 0*; it does not reach the cubic basin. For operational use, the pick is one of:

| Goal | Pick | J_dB | σ_3dB | HNLF transfer gap |
|---|---|---|---|---|
| Deepest canonical suppression | A / cubic / N_phi = 128 | −67.60 | 0.07 | +21.5 |
| Robust + still very deep | A / cubic / N_phi = 32 | −60.77 | 0.14 | +16.5 |
| Most cross-fiber transferable with ≥ 20 dB depth | A / polynomial / N_phi = 3 | −26.50 | NaN* | +0.29 |
| Best penalty-side option (if basis restriction is forbidden) | B / tikhonov / λ = 0 | −57.75 | 0.17 | +15.6 |

*σ_3dB crossover past σ = 1 rad — most polynomial optima didn't cross the 3 dB threshold inside the σ ladder, meaning they're very robust (not a failure).

## Branch A (basis restriction) — 20 optima

Five basis families × {3..256} grid. Best per family, canonical J:

| Kind | Best N_phi | J (dB) |
|---|---|---|
| **cubic** | **128** | **−67.60** |
| **linear** | **64** | **−63.94** |
| dct | 128 | −31.12 |
| chirp_ladder | 4 | −29.91 |
| polynomial | 3 | −26.50 (plateau through N_phi = 8) |

Observations:

1. **Polynomial plateau at −26.5 dB** for N_phi ∈ {3..8}. All five polynomial rows converged to J = −26.497 dB in 2–4 iters. Multi-start seeds (flat + ±quadratic chirp) all collapse to the same quadratic-GVD-compensation basin; higher-order polynomials don't escape. This is the "analytical quadratic-chirp baseline".
2. **DCT plateau at −26 dB** for N_phi ≤ 64, jumping to −31.1 dB at N_phi = 128. DCT global modes cannot express the structure that defeats the quadratic basin — only a very high N_phi begins to help.
3. **Cubic basis dramatically outperforms DCT** at identical dimensionality. At N_phi = 128, cubic = −67.6 dB vs DCT = −31.1 dB — a 36 dB gap. The optimal phase has **local** structure: cubic splines' local support captures it; global DCT modes do not.
4. **Linear basis is surprisingly strong** at low N_phi: N_phi = 16 already reaches −60.3 dB, N_phi = 64 reaches −63.9 dB. The optimal phase is "mostly piecewise-smooth" rather than globally smooth.
5. **Cubic continuation warm-start matters.** The cubic ladder uses `continuation_upsample` (next N_phi initialized from the previous optimum), letting it walk out of the quadratic basin. Without that, cubic N_phi=128 from zero init (Branch B with no penalty) only reaches −57.75 dB — 10 dB worse.

## Branch B (penalty on full grid) — 21 optima

Five penalty families × {0, …} λ-ladder. All λ = 0 runs are the same problem → all converge to J = −57.75 dB in 14 iterations (L-BFGS from zero init).

| Penalty | λ = 0 | λ = 1 × 10⁻⁶ | λ = 1 × 10⁻⁴ | λ = 1 × 10⁻² | λ = 1 |
|---|---|---|---|---|---|
| tikhonov | −57.75 | −47.02 | −34.14 | −21.66 | −4.34 |
| gdd | −57.75 | −42.90 | −33.39 | −14.97 | — |
| tod (λ=1e-8) | −57.75 | −41.27 | −35.53 | −28.05 | — |
| tv | −57.75 | — | −27.08 | −10.34 | −1.11 |
| dct_l1 | −57.75 | — | −38.03 | −1.11 | — |

Observations:

1. **Penalty/depth trade-off is monotonic and predictable.** As λ grows, each family degrades J_raman in proportion to how strongly it penalizes the optimizer's preferred structure.
2. **Full-grid L-BFGS from zero init never reaches Branch A's cubic basin.** The shared λ = 0 plateau at −57.75 dB is 10 dB shallower than cubic N_phi = 128. This is a **landscape observation**: continuation-through-a-reduced-basis is a better optimizer path than full-grid zero init, even though the full-grid problem nominally has strictly more freedom. Phase 35's saddle-dominated-landscape verdict is consistent with this — zero init hits a saddle and stops.
3. **No penalty family cleanly matches the cubic basis.** The closest is tikhonov λ = 1e-6 → −47.0 dB, still 20 dB shallower than Branch A cubic.
4. **High-λ runs are degenerate** (penalty dominates → φ ≈ 0 → J ≈ −1.1 dB = zero-phase baseline). These rows have large transfer gaps because the "optimum" is essentially the unshaped pulse.

## Transferability (HNLF + 3 perturbed canonicals)

| Source | Median transfer gap J_HNLF − J_canonical | Best cubic N_phi=128 | Best Branch B (λ=0) |
|---|---|---|---|
| HNLF (0.5 m, 0.01 W) | +1.19 dB (A); −8.9 dB (B, misleading) | +21.5 dB | +15.6 dB |
| +5% FWHM | near-zero median | −0.7 dB (improves!) | +1.0 dB |
| +10% P | small positive | +6.1 dB | +2.7 dB |
| +5% β₂ | very small | +0.08 dB | +2.0 dB |

The **Branch B median of −8.9 dB** is misleading — high-λ Branch B rows converge to φ ≈ 0 (J ≈ −1 dB canonical), and their "J_HNLF" is the no-shaping baseline for HNLF (≈ −10 dB), which is numerically a negative gap. These are not real optima.

Real observations:

- **Polynomial N_phi = 3 is the most fiber-transferable** (HNLF gap = +0.29 dB) — the quadratic-chirp analytical phase is roughly fiber-agnostic.
- **Cubic N_phi = 128 is robust to pulse-FWHM** (−0.7 dB — gets *better* when you widen the pulse 5%) and dispersion (+0.08 dB), but **poor on HNLF** (+21.5 dB) and **middling on power** (+6.1 dB). The canonical-specific structure it captured for −67.6 dB doesn't port to a different γ · L product.
- **Branch B λ = 0** has an intermediate profile: wider basin (σ_3dB = 0.17), less fiber-specific (HNLF gap = +15.6), less depth (J = −57.75).

## Robustness (σ_3dB from canonical, 7-σ ladder × 10 trials, early-exit at 3 dB crossover)

- Largest σ_3dB: **0.313 rad** (cubic N_phi = 16, J = −54 dB)
- Smallest σ_3dB: **0.072 rad** (cubic N_phi = 128, J = −67.6 dB)
- σ_3dB degrades monotonically with N_phi within cubic: 0.313 → 0.143 → 0.105 → 0.072 for N_phi ∈ {16, 32, 64, 128}. **Depth trades linearly against basin width.**
- Polynomial and low-N_phi DCT rows frequently have σ_3dB = NaN — they didn't cross the 3 dB threshold inside the σ ladder (ladder top is 1 rad), i.e. their basins are extremely wide because the parameterization is flat to high-order perturbations.

## Saddle-masking caveat (Open Question 5, resolved as "deferred")

Every basis-restricted PSD optimum is flagged `PSD_UNVERIFIED_AMBIENT`. We did not run an ambient-Hessian probe on the full Nt = 16 384 grid because it would require ~N_t matrix-vector Hessian actions per optimum (~hours × 20 rows). Per the resolved Open Question 5 in `CONTEXT.md`, this probe is deferred out of Phase 31.

Implication: the cubic-N_phi=128 basin is PSD in coefficient space, but its ambient Hessian could have soft directions that the Branch A report does not see. Phase 35's verdict ("competitive regimes are saddle-dominated") applies — a low-dim restriction can mask ambient indefiniteness, producing a "basin" that evaporates when you're allowed to move in all 16 384 directions. That is part of what the +21 dB HNLF gap is telling us: the cubic-128 structure is a canonical-specific direction that disappears under fiber change.

## Verdict

1. **Reduced-basis beats regularization on depth.** Branch A cubic N_phi = 128 reaches −67.6 dB; no Branch B penalty family comes within 10 dB. Branch B's shared λ = 0 floor at −57.75 dB reveals a saddle-trap that full-grid zero-init L-BFGS cannot escape — continuation through a reduced basis is the better optimizer path, not just a regularizer.
2. **Depth trades against transferability + basin width.** The cubic-128 optimum is tight (σ_3dB = 0.07 rad) and canonical-specific (HNLF +21.5 dB). Shallower, lower-N_phi cubic/linear optima are proportionally more robust.
3. **Regularization does NOT give a cheaper path to Branch A's best optima.** Even at λ = 0 (no penalty), Branch B's full-grid optimizer is stuck 10 dB above cubic. The win is in the **optimizer trajectory** (continuation warm-start), not in the final search space.
4. **For operational "one phase fits all fibers"** (low robustness to fiber choice), polynomial N_phi = 3 (analytical quadratic chirp) is the right default at −26.5 dB. For canonical-specific deep suppression, cubic N_phi = 128 is best. There is no middle-ground optimum that is both deep and fiber-transferable — the data says these are two different regimes with a ~40 dB wall between them.

## Artifacts

- `results/raman/phase31/sweep_A_basis.jld2` (20 rows)
- `results/raman/phase31/sweep_B_penalty.jld2` (21 rows)
- `results/raman/phase31/transfer_results.jld2` (41 source rows × HNLF + 3 perturbs + σ_3dB)
- `results/raman/phase31/pareto.png` (4-panel depth vs N_eff / σ_3dB / polynomial_R² / HNLF gap)
- `results/raman/phase31/L_curves/*.png` (5 per-penalty L-curves)
- `results/raman/phase31/aic_ranking.csv` (41 rows, AIC = 2·N_eff + 2·J_dB)
- `results/raman/phase31/sweep_A/images/` and `sweep_B/images/` (84 + 84 standard images per optimum)
- `agent-docs/phase31-reduced-basis/candidates.md` (top-10 AIC recommendation)
- `scripts/phase31_{basis,penalty}_lib.jl`, `scripts/phase31_run.jl`, `scripts/phase31_transfer.jl`, `scripts/phase31_analyze.jl`, `test/test_phase31_basis.jl`

## Follow-on questions (for future phases)

1. **Can we close the 10 dB gap between Branch B λ = 0 (−57.75) and Branch A cubic N_phi = 128 (−67.6)?** Hypotheses: (a) multi-start from random perturbations of zero; (b) continuation through an anchored DCT → cubic path with the full-grid fall-back as the final step; (c) second-order (globalized Newton / truncated-Newton with negative-curvature handling — the Phase 33/34 candidates).
2. **Is the HNLF gap a property of the cubic basis or the canonical optimum it found?** Repeat the cubic-N_phi=128 sweep but initialized near the Branch B λ = 0 optimum. If the gap persists, the canonical optimum itself is fiber-specific; if it shrinks, the cubic basis encodes canonical-specific assumptions.
3. **Ambient-Hessian probe on cubic N_phi = 128.** Does the cubic-coefficient-space PSD basin hold up when allowed to move in all 16 384 ambient directions? Phase 33/34 Krylov-preconditioned Newton methods would make this probe tractable.
