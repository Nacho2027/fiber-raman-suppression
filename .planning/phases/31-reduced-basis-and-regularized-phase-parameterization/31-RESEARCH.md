# Phase 31: Reduced-Basis and Regularized Phase Parameterization — Research

**Researched:** 2026-04-21
**Domain:** numerical analysis (model selection, basis restriction, regularization) applied to nonlinear fiber-optics spectral-phase optimization
**Confidence:** HIGH on codebase reuse and physics anchors, MEDIUM on penalty-family gradient derivations (repo-pattern-verified but not every case coded before), MEDIUM on external model-selection tooling (CS 4220 and standard inverse-problems literature, not always code-verified in this repo).

---

## Summary

Phase 31 is a **model-selection phase**, not a new-algorithm phase. The repo already has:

- a fully working low-resolution phase optimizer with four basis kinds (`:identity`, `:cubic`, `:dct`, `:linear`) in `scripts/sweep_simple_param.jl`,
- an amplitude-side DCT reduced-basis implementation (`build_dct_basis` + `cost_and_gradient_lowdim` in `scripts/amplitude_optimization.jl`) that Phase 27's second-opinion addendum names as the *canonical reuse target*,
- GDD (curvature) penalty and boundary-energy penalty already plumbed through `cost_and_gradient(...)` and transitively through `cost_and_gradient_lowres(...)`,
- gauge-mode theory (Phase 13: cost is invariant under `φ → φ + C + α·ω_shift`, so any sensible basis must either include those modes or live entirely within the gauge-free complement),
- a verdict from Phase 35 that the competitive suppression branch is **saddle-dominated in the full-grid control space**, and that **minima appear only under aggressive dimensional restriction** but at 20+ dB depth loss,
- a sharpness-aware Phase 22 result showing every converged optimum stays **Hessian-indefinite**, so "robustness" is not redundant with "depth" — the Pareto front has real width.

Phase 31 therefore does **four** things, not more:

1. **Catalog** basis families (polynomial chirp ladder, DCT, cubic spline, optional Hermite/B-spline) and penalty families (Tikhonov-on-φ, curvature/GDD, higher-order curvature/TOD, TV, sparsity in DCT, optional elastic-net). Provide gradient forms, Gram/Hessian conditioning checks, and concrete `λ` / `N_phi` ladders.
2. **Run** a coherent head-to-head on a fixed canonical point (SMF-28 L=2 m P=0.2 W) plus at least one off-canonical transfer point (HNLF L=0.5 m P=0.01 W), measuring `J_dB`, `σ_3dB`, simplicity (`N_eff`, `TV`, `phase_curvature`), polynomial-residual fraction, Hessian indefiniteness ratio, condition number of the restricted Hessian, and wall time.
3. **Select** along a Pareto front the "operational" recommended model. The question is not "which gets lowest dB" — Phase 35 says full-grid wins on dB — but "which achieves the best simplicity/robustness/transferability at acceptable depth loss," which is the over-parameterization hypothesis from Phase 27's seed.
4. **Contract** the result back onto the existing infrastructure: no new solver, no new optimization-theory component. Every new file extends or re-uses an existing pattern (see `31-PATTERNS.md` — all 8 inferred files have exact analogs).

**Primary recommendation:** Implement Phase 31 as **2 plans** — Plan 01 `phase31_basis_lib.jl` + `phase31_penalty_lib.jl` + `phase31_run.jl` + unit tests (library + canonical-point sweep); Plan 02 `phase31_transfer.jl` + `phase31_analyze.jl` (transferability probe + figures + Pareto). Both plans run on the burst VM through `burst-run-heavy`. Total burst time budget ~60 min heavy + ~15 min transfer. Every driver that produces a `phi_opt` emits the full standard image set via `save_standard_set(...)`.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

- This phase extends existing basis infrastructure before inventing new basis code.
- The amplitude DCT path is the first reuse target for phase reduction.
- Explicit basis restriction and penalty-based regularization are compared, not conflated.
- Interpretability, robustness, and transferability matter as much as best dB.

### Claude's Discretion

- Choice of specific basis families beyond the four locked ones (polynomial-chirp, DCT, cubic spline, plus optional Hermite / B-spline / Gabor).
- Choice of specific penalty families and their `λ` ladder schedules.
- Which canonical and transfer operating points to include beyond the two already established (SMF-28 L=2 m P=0.2 W canonical; HNLF L=0.5 m P=0.01 W transfer).
- Plan structure (number of plans, waves, task granularity). Recommended: 2 plans as above.
- Whether to include higher-order curvature penalties (TOD = `‖∂³φ/∂ω³‖²`) as a separate family or merge with GDD.
- Whether the Phase 35 saddle-masking risk gets its own mitigation step (recommended: yes — see §Common Pitfalls).

### Deferred Ideas (OUT OF SCOPE)

- Bayesian model selection with full posterior sampling. Only point-estimate model selection (AIC/BIC/L-curve/GCV) is in scope — sampling belongs to a downstream quantum-noise reframing phase.
- Wavelet packets, Gabor frames, and other overcomplete dictionaries. If a candidate can't be expressed as a length-`N_phi` coefficient vector multiplied by a fixed `Nt × N_phi` basis matrix, defer it.
- True multi-task / transfer-learning: sharing coefficients across fiber configs (the "is the phase universal?" PATT-03 question) is a separate phase.
- New optimizer (Newton / truncated-Newton). Phase 31 stays on L-BFGS via the existing `optimize_phase_lowres` path. Second-order work is seeded separately.
- Multimode (M > 1) extension. Phase 31 is single-mode; multimode is Sessions A/C territory.
- Changing the physical cost functional. `spectral_band_cost` stays as-is.

---

## Phase Requirements

Derived from Phase 27 Report §Recommended Future Work, item C (Reduced-basis / regularized phase models), and the second-opinion addendum items 2, 3, 7.

| ID | Description | Research Support |
|----|-------------|------------------|
| P31-A | Deliver a basis-family catalog with dimension count, Gram conditioning, and physics interpretation for at least `{polynomial_chirp, cubic_spline, DCT, linear}` at `N_phi ∈ {4, 8, 16, 32, 64, 128}`. | §Basis Family Catalog |
| P31-B | Deliver a penalty-family catalog with gradient forms and expected scaling behaviour for at least `{tikhonov_φ, curvature_GDD, TV_φ, DCT_sparsity_soft}`, properly placed BEFORE the log-cost rescaling block. | §Penalty Family Catalog + §Log-Cost Scaling Pitfall |
| P31-C | Produce a head-to-head comparison on the canonical SMF-28 point: every basis and every penalty mode evaluated on `(J_dB, σ_3dB, N_eff, TV, curvature, polynomial_R², Hessian_indefiniteness, κ_H_restricted, wall_time)`. | §Evaluation Metrics + §Execution Architecture |
| P31-D | Produce a transferability table: apply each optimum to the HNLF L=0.5 m P=0.01 W point *without re-optimizing* and at least one perturbed pulse (+5% FWHM, +10% energy), and report `ΔJ_dB`. | §Transferability + analog `phase14_robustness_test.jl` |
| P31-E | Use L-curve and AIC-like criteria to recommend a penalty strength / basis size per family. This is the *model-selection* core of the phase. | §Model-Selection Machinery |
| P31-F | Verify no basis / penalty configuration makes the Phase 35 saddle-masking worse. Specifically: record the Hessian-indefiniteness ratio (`|λ_min| / λ_max`) in the coefficient-space Hessian. | §Common Pitfalls §Saddle Masking |
| P31-G | Every driver that produces a `phi_opt` calls `save_standard_set(...)` — no exceptions, including "quick" sweep points. | Project CLAUDE.md mandate |
| P31-H | Phase 31 does NOT mutate any file in `{scripts/common.jl, scripts/visualization.jl, src/**, Project.toml, Manifest.toml}`. It only adds `scripts/phase31_*.jl` under the owned namespace. | Parallel Session Rule P1 |

---

## Architectural Responsibility Map

Phase 31 is a single-tier (Julia simulation + analysis) project. The tier mapping below is specialized to this repo rather than generic web-app tiers.

| Capability | Primary tier | Secondary tier | Rationale |
|------------|-------------|----------------|-----------|
| Basis matrix construction | `scripts/phase31_basis_lib.jl` | — | Adds new `kind` branches to the existing `build_phase_basis` or wraps and dispatches. Extension, not replacement. |
| Penalty gradient assembly | `scripts/phase31_penalty_lib.jl` | `scripts/raman_optimization.jl::cost_and_gradient` (read-only) | New penalties extend the pattern of the existing GDD/boundary blocks. Placed **before** log-cost rescaling. |
| Basis-space optimization driver | `scripts/phase31_run.jl` | `scripts/sweep_simple_param.jl::optimize_phase_lowres` | Existing driver already supports any basis; Phase 31 parameterizes over kinds/penalties/λ and records extended metrics. |
| Analysis and Pareto | `scripts/phase31_analyze.jl` | `scripts/sweep_simple_analyze.jl::pareto_front`, `scripts/phase13_primitives.jl::polynomial_project` | Reuse Pareto utility verbatim; polynomial residual reuses phase13. |
| Transferability probe | `scripts/phase31_transfer.jl` | `scripts/raman_optimization.jl::chirp_sensitivity`, `scripts/phase14_robustness_test.jl` | Outer loop over (basis, N_phi, λ); inner kernel is the existing perturbation+forward pattern. |
| Standard images emission | any driver producing `phi_opt` | `scripts/standard_images.jl::save_standard_set` | Project-mandated contract from CLAUDE.md. |
| Numerical trust reporting | `scripts/numerical_trust.jl` (Phase 28 canonical) | — | Hook in at JLD2 save time. Phase 31 inherits, does not re-invent. |
| Physics model (forward + adjoint solve) | `src/simulation/*.jl` | — | Read-only. No physics change permitted in Phase 31. |

---

## Standard Stack

### Core (already in-repo — no new deps)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Optim.jl` | 1.13.3 (pinned) | L-BFGS via `LBFGS()` + HagerZhang line search. Box-constrained via `Fminbox(LBFGS())` if penalty strength requires bounded `λ`. | Already the production optimizer; Phase 27 second-opinion confirmed globalization (strong Wolfe) is already in place. |
| `FFTW.jl` | pinned via Manifest | DCT-II basis construction + spectral-grid FFTs with deterministic `ESTIMATE` planning. | Project-locked for bit-reproducibility (Phase 15, Phase 28). |
| `Interpolations.jl` | 0.16.2 | Cubic / linear spline bases via `cubic_spline_interpolation` / `linear_interpolation`. | Already used in `sweep_simple_param.jl` for the `:cubic` and `:linear` branches. |
| `JLD2.jl` | pinned | Structured save of results + manifest. | Project convention in every sweep driver. |
| `Arpack.jl` | pinned | Hessian bottom-K eigenvalue extraction for indefiniteness ratio and restricted-`κ`. Reuse `HVPOperator` from `scripts/phase13_hessian_eigspec.jl`. | Phase 13 infrastructure; no re-derivation needed. |
| `LinearAlgebra` (stdlib) | 1.9 | Gram matrix, condition number, pseudoinverse for continuation_upsample. | Stdlib. |
| `Statistics` (stdlib) | 1.9 | Perturbation mean/std for robustness. | Stdlib. |

### Supporting (optional, for analysis only)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Polynomials.jl` | already indirectly via `phase13_primitives.jl` | Fit `phi_opt` to a polynomial basis post-hoc for interpretability. | `phase31_analyze.jl` only, for the polynomial R² interpretability metric. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Verdict |
|------------|-----------|----------|---------|
| Explicit DCT matrix multiplication (`B' * φ`) | `FFTW.plan_dct()` (in-place DCT) | ~5× faster at `Nt = 2^14`. | Defer — current wall time is dominated by the forward/adjoint solve, not basis multiplication. Optimize only if profiling shows the basis op >10% of total. Also, the current `:dct` branch constructs an explicit `Nt × N_phi` matrix which is fine at `N_phi ≤ 512`. |
| `Optim.LBFGS()` (unconstrained) | `Fminbox(LBFGS())` with `c ∈ [-C, C]^{N_phi}` | Prevents pathological coefficient blow-up, especially with sparsity penalties. | Only needed if sparsity/elastic-net penalties are included; otherwise the existing unconstrained `LBFGS()` is fine. See §Penalty Family Catalog. |
| Scikit-learn-style cross-validation | Hand-rolled two-point transfer test (canonical SMF-28 → HNLF) | Simpler, interpretable, physics-driven. | Chosen. True CV would require many more optimization runs per fold — prohibitive. |
| Full L-curve computation (a 20-point sweep of `λ`) | Coarse 5-point `λ` ladder with log-spacing | L-curve elbow detection is visually clear at 5–7 points. | Chosen. `λ ∈ {0, 1e-6, 1e-4, 1e-2, 1e0}` per penalty family. |

**Installation:** None — every package is in the pinned `Manifest.toml`. `Pkg.instantiate()` is a no-op if the environment is already resolved.

**Version verification:**

```julia
# On the burst VM:
julia --project=. -e 'import Pkg; Pkg.status(["Optim", "FFTW", "Interpolations", "JLD2", "Arpack"])'
```

Expected output: all packages at the versions pinned in `Manifest.toml` (already verified in prior phases; do not upgrade for Phase 31).

---

## Architecture Patterns

### System Data Flow

```
Canonical setup (once per run)
   setup_raman_problem(:SMF28, L=2.0, P=0.2)
      → (uω0, fiber, sim, band_mask, Δf, raman_threshold)
                               │
                               ▼
                     pulse_bandwidth_mask(uω0)  →  bw_mask
                               │
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
    Branch A: Basis    Branch B: Penalty    Branch C: Hybrid
    (N_phi ladder,     (full Nt grid,        (:dct + Tikhonov
     kind ladder)       λ ladder)             joint sweep)
            │                  │                  │
            └────── cost_and_gradient_lowres ─────┘
                    (existing, takes kwargs:
                     λ_gdd, λ_boundary, log_cost,
                     plus Phase31 extensions:
                     λ_tikhonov, λ_tv, λ_dct_l1)
                               │
                               ▼
                     LBFGS()  (50–100 iter)
                               │
                               ▼
                     phi_opt, c_opt, J_final
                               │
           ┌───────────────────┼──────────────────────┐
           ▼                   ▼                      ▼
   save_standard_set    compute metrics          Hessian probe
   (mandatory)          N_eff, TV, curv,        (phase31_hvp)
                        poly_R², Hess. indef    κ_H_restricted
                               │
                               ▼
                     JLD2 row (Dict{String,Any})
                               │
                               ▼
              phase31_results_{branch}.jld2
                               │
                               ▼
                     phase31_analyze.jl
                     (Pareto, L-curve, AIC plot)
                               │
                               ▼
                     phase31_transfer.jl
                     (apply to HNLF + perturbed
                      pulses, evaluate without
                      re-opt, record ΔJ_dB)
                               │
                               ▼
                     candidates.md, *.png, FINDINGS.md
```

Decision points:

- **Before Branch A/B/C**: build `bw_mask` from the canonical pulse spectrum. All runs share the same `bw_mask` so metrics are comparable.
- **Inside the optimizer**: `cost_and_gradient_lowres` decides whether `φ = B·c` or `φ` is the direct variable (Branch B uses `B = I`, Branch A uses a restricted `B`).
- **After each optimum**: the "save JLD2 row" step is incremental so a crashed burst run loses only the *current* row, not the whole sweep. Already the pattern in `sweep_simple_run.jl:242-245`.

### Recommended Project Structure

```
scripts/
├── phase31_basis_lib.jl     # new bases: :polynomial, :hermite (optional), wrapper
├── phase31_penalty_lib.jl   # Tikhonov, TV, DCT-sparsity, higher-order curvature
├── phase31_run.jl           # Branch A + Branch B + optional Branch C driver
├── phase31_transfer.jl      # transferability probe — ingests Branch A+B+C output
├── phase31_analyze.jl       # Pareto + L-curve + AIC/BIC + candidates.md
└── (existing, untouched)
    ├── sweep_simple_param.jl
    ├── raman_optimization.jl
    ├── amplitude_optimization.jl
    ├── phase13_primitives.jl
    ├── phase13_hvp.jl
    ├── phase14_robustness_test.jl
    ├── standard_images.jl
    ├── visualization.jl
    └── determinism.jl

test/
└── test_phase31_basis.jl    # contract tests (see §Test Plan)

results/raman/phase31/        # owned output tree (gitignored)
├── sweep_basis/
│   ├── smf28_canonical_{kind}_{N_phi}.jld2
│   └── images/
├── sweep_penalty/
│   ├── smf28_canonical_{penalty}_{lambda}.jld2
│   └── images/
├── transfer/
│   └── hnlf_probe_{basis|penalty}.jld2
├── pareto.png
├── l_curve_{penalty}.png
├── candidates.md
└── FINDINGS.md
```

### Pattern 1: Basis matrix as a fixed linear operator

**What:** A real matrix `B ∈ R^{Nt × N_phi}` with `φ = B·c`. Gradient chain rule gives `∂J/∂c = Bᵀ · ∂J/∂φ` exactly — no new adjoint derivation.

**When to use:** Always, for any basis restriction. The matrix is built once outside the optimizer loop and held constant.

**Example (reuse from `sweep_simple_param.jl:228-246`):**

```julia
function cost_and_gradient_lowres(c, B, uω0, fiber, sim, band_mask; kwargs...)
    c_mat = reshape(c, size(B, 2), size(uω0, 2))
    φ = B * c_mat
    J, ∂J_∂φ = cost_and_gradient(φ, uω0, fiber, sim, band_mask; kwargs...)
    ∂J_∂c = B' * ∂J_∂φ
    return J, vec(∂J_∂c)
end
```

### Pattern 2: Penalty as additive gradient contribution BEFORE log-rescale

**What:** A regularizer adds `λ · R(φ)` to the cost and `λ · ∂R/∂φ` to the gradient. This must happen **before** the `log_cost` block — see §Common Pitfalls §Log-Cost Scaling.

**When to use:** Always for penalty-based regularization.

**Example (existing GDD pattern from `raman_optimization.jl:123-138`):**

```julia
if λ_gdd > 0
    Δω = 2π / (Nt_φ * sim["Δt"])
    inv_Δω3 = 1.0 / Δω^3
    for i in 2:(Nt_φ - 1)
        d2 = φ[i+1, m] - 2φ[i, m] + φ[i-1, m]
        J_total += λ_gdd * inv_Δω3 * d2^2
        coeff = 2 * λ_gdd * inv_Δω3 * d2
        grad_total[i-1, m] += coeff
        grad_total[i, m]   -= 2 * coeff
        grad_total[i+1, m] += coeff
    end
end
# (log_cost block comes AFTER this)
```

### Pattern 3: Continuation warm-start across basis levels

**What:** A coarser-basis optimum `c_coarse` is projected into a finer basis via least-squares pseudo-inverse: `c_fine = (B_fine^T B_fine)^{-1} B_fine^T · (B_coarse · c_coarse)`. For orthonormal `B_fine` (e.g. `:dct`), this reduces to `c_fine = B_fine^T · φ_coarse`.

**When to use:** Always for the `N_phi` ladder. A single multi-start at `N_phi = 4` or `N_phi = 8`, then warm-start up the ladder.

**Example (reuse from `sweep_simple_param.jl:385-394`):** `continuation_upsample(c_prev, B_prev, B_new)`.

### Pattern 4: Gauge fix before measuring simplicity metrics

**What:** The cost functional is invariant under `φ → φ + C + α·(ω - ω0)` for arbitrary constant `C` and linear chirp `α` (Phase 13 finding). Metrics like `TV` or `phase_curvature` are NOT gauge-invariant unless computed on the gauge-fixed phase. The gauge-fix operation is `gauge_fix(φ) = φ - C*(φ) - α*(φ)·(ω - ω0)` with `C*, α*` chosen to zero-mean φ and its linear trend on the bandwidth.

**When to use:** Before recording `N_eff`, `TV`, `phase_curvature`, `polynomial_R²`, Hessian-ratio — any quantity that depends on the specific representative in the gauge orbit.

**Example (reuse from `phase13_primitives.jl`):** `gauge_fix(φ, input_band_mask)` (already tested).

### Anti-Patterns to Avoid

- **Writing a new adjoint for a new basis**. The `B^T · ∂J/∂φ` chain rule is universal. Any derivation effort beyond "build B, plug into `cost_and_gradient_lowres`" is wasted.
- **Adding a penalty AFTER the log_cost rescaling**. The regularizer weight then becomes state-dependent; see §Common Pitfalls §Log-Cost Scaling. This is the Phase 27 second-opinion defect 2 and Phase 31 would re-commit it if the pattern is not enforced.
- **Measuring simplicity on a non-gauge-fixed φ**. Comparing `TV(φ_A)` to `TV(φ_B)` is meaningless if the two live in different gauge representatives.
- **Allocating a new `B` matrix inside the optimizer `only_fg!` closure**. Build once outside; pass by reference. The existing `optimize_phase_lowres` already does this correctly.
- **Running Branch A and Branch B on different canonical points**. The whole comparison collapses if the anchor moves. Pin a single canonical and a single transfer point and document.
- **Using `Fminbox(LBFGS())` for unconstrained sparsity penalties**. `Fminbox` forces a barrier; for soft-L1 / smooth-TV the cost is already smooth and unconstrained `LBFGS()` is correct. Reserve `Fminbox` for hard box constraints (e.g. amplitude `A ≥ 1e-6`).

---

## Basis Family Catalog

Six candidate families. Rows ranked by priority for Phase 31 inclusion.

| Family | `N_phi` ladder | Basis expression | Dim count | Gram conditioning expectation | Physics interpretation | Repo support today |
|--------|----------------|------------------|-----------|-------------------------------|------------------------|--------------------|
| **`:dct`** | `{4, 8, 16, 32, 64, 128, 256}` | orthonormal DCT-II, first `N_phi` columns, masked to bandwidth | `N_phi` | κ(G) = 1 on masked support (orthonormal) — ideal | Band-limited phase in frequency. Closest analog of a pixelated pulse shaper SLM. | **Yes**, `build_phase_basis(..., kind=:dct, bandwidth_mask=bw_mask)` |
| **`:cubic`** | `{4, 8, 16, 32, 64, 128}` | cubic spline through equally-spaced knots on bandwidth support | `N_phi` | κ(G) scales polynomially with `N_phi` for well-spaced knots; `_sanity_check_basis` warns if > `LR_COND_LIMIT` = 1e12 | Smooth phase with compact knots. Physical analog: phase after PSF smoothing of SLM pixels. **Current default.** | **Yes**, same function, `kind=:cubic` |
| **`:polynomial`** | orders `{2, 3, 4, 5, 6, 8}` → `N_phi ∈ {3, 4, 5, 6, 7, 9}` | Legendre polynomials of `ω - ω0` scaled by bandwidth half-width. Order `k` contains GDD + TOD + ... | `N_phi = order + 1` | Legendre basis on `[-1, 1]` is orthonormal → κ(G) = 1 + mask-induced perturbation | **Physically direct**: coefficients ARE the dispersion orders (β₂-like, β₃-like, β₄-like). Bridges optimization to textbook nonlinear-fiber theory. | **No** — new `kind=:polynomial` branch to add to `build_phase_basis` (or wrapper in `phase31_basis_lib.jl`) |
| **`:linear`** | `{4, 8, 16, 32, 64, 128}` | piecewise-linear tent functions through knots on bandwidth | `N_phi` | similar to `:cubic` but less smooth → slightly worse κ(G) | Ablation / baseline — cheapest smoothness. | **Yes**, `kind=:linear` |
| **`:hermite`** *(optional)* | orders `{3, 5, 7, 9}` → `N_phi` same | Physicist's Hermite polynomials (Gaussian-weighted) — basis orthonormal under Gaussian measure on `ω` | `N_phi = order + 1` | orthonormal under weighted inner product; κ(G_mask) depends on how closely `\|uω0\|²` resembles a Gaussian | Connects to the Gaussian-pulse ansatz; interpretable in terms of Gauss-Hermite mode content of the shaped pulse. | **No** — only add if Plan 01 has budget left. Defer-safe. |
| **`:chirp_ladder`** *(explicit reduced form)* | fixed `N_phi = 4` ≡ `{ω², ω³, ω⁴, ω⁵}` | quadratic + cubic + quartic + quintic chirp, no constant/linear (gauge-fixed by construction) | 4 | κ(G) moderate (< 1e6 typical on bandwidth masked to `ω ∈ [-Δω, +Δω]`) | The "minimum-description-length" ansatz; what the physics textbooks would write by hand. Phase 35's verdict: `N_phi = 4` is the ONLY minimum-like branch → this is the canonical low-dim reference. | **No** — simple wrapper on `:polynomial` with the constant and linear rows zeroed out. |

### Gram-matrix conditioning details

Because the cost functional has a two-dimensional gauge null space (constant + linear phase; Phase 13), any basis that includes constant and/or linear chirp inherits a conditioning pathology: those coefficients are unidentifiable. Two ways to handle it:

1. **Gauge-free basis construction**. `:chirp_ladder` above does this by fiat. `:polynomial` from order 2 (no constant, no linear) does the same. Strongly preferred for **interpretable** analysis.
2. **Gauge-fix post-hoc**. Build the full polynomial basis, optimize in that space, then `gauge_fix(phi_opt, bw_mask)` before reporting. Required for `:dct` and `:cubic` since their low-order columns overlap the gauge directions.

**Metric to record per basis:** `κ(B^T B)` on the bandwidth-masked support. For orthonormal bases this is 1; for `:cubic` and `:linear` it scales with knot spacing. `_sanity_check_basis(B)` in `sweep_simple_param.jl:182-201` already computes this when `N_phi ≤ 512` and warns at `κ > 1e12`. Phase 31 should **promote the warning to a recorded field** in the JLD2 row: `"kappa_B"`, `"kappa_warning_triggered"`.

### Expressivity ordering (empirical expectation)

Expected ranking at large `N_phi` (from Phase 35 findings + CS 4220 approximation-theory heuristics):

1. `:identity` (N_phi = Nt) — full expressivity, baseline for J_dB. Wins on depth.
2. `:dct` at `N_phi = 128–256` — approaches `:identity` depth per Phase 35 result (`N_phi = 128` reaches −68.0 dB, full-resolution −68.X dB).
3. `:cubic` at `N_phi = 64–128` — smoothness-favoured; competitive on depth, better on `TV` / `curvature`.
4. `:polynomial` order 6–8 — **the hypothesis test**: if low-order polynomial can match :dct within 5–10 dB, over-parameterization is confirmed. Phase 35 said order-4 hits −47 dB; order-6 / -8 is the un-tested middle.
5. `:chirp_ladder` — lowest expressivity ceiling (~order-5 polynomial without linear) but cleanest physical interpretation; sets the interpretability floor.
6. `:linear` — ablation only.

### Recommended basis ladder for Phase 31

```julia
BASIS_PROGRAM = [
    (:polynomial, [3, 4, 5, 6, 8]),           # order = N_phi - 1
    (:chirp_ladder, [4]),                      # fixed — always a single run
    (:dct, [4, 8, 16, 32, 64, 128, 256]),
    (:cubic, [4, 8, 16, 32, 64, 128]),
    (:linear, [16, 64]),                       # ablation only
]
```

**Total optimization runs, Branch A (basis) only:** 5 + 1 + 7 + 6 + 2 = **21** runs on the canonical point. Each run ~30–90 s on the burst VM; total ~25 min.

---

## Penalty Family Catalog

Five candidate families. All expressed as `λ · R(φ)` added to the pre-log cost.

### P1. Tikhonov on φ (L₂ on the phase itself)

- **Functional:** `R(φ) = (1/N_bw) · Σ_{i ∈ bw} (φ_i - φ̄)²` (bandwidth-masked variance, gauge-aware)
- **Gradient:** `∂R/∂φ_i = (2/N_bw) · (φ_i - φ̄) · 1_{i ∈ bw}` for `i ∈ bw`, else 0
- **λ ladder:** `{1e-6, 1e-4, 1e-2, 1e0}` (plus `λ = 0` baseline)
- **Expected effect:** penalizes large phase excursions. Pulls optima toward flat. Very weak regularizer at competitive dB.
- **Failure mode:** at large `λ` the optimizer converges to `φ = 0` regardless of the physics — degenerate.
- **Conditioning impact on Hessian:** adds `(2λ/N_bw) · I_bw` to the Hessian restricted to the bandwidth. Shifts bottom spectrum up; at `λ ≫ |λ_min_H|` will make the Hessian PSD by brute force. This is the "regularize-until-convex" knob.

### P2. Curvature / GDD (`‖∂²φ/∂ω²‖²_{2,bw}`)

- **Functional:** `R(φ) = (1/Δω³) · Σ_{i ∈ bw-1} (φ_{i+1} - 2φ_i + φ_{i-1})²` — already implemented in `raman_optimization.jl:123-138`.
- **Gradient:** already implemented (second-difference, dispersed into `grad_total[i-1], grad_total[i], grad_total[i+1]`).
- **λ ladder:** `{0, 1e-6, 1e-4, 1e-2}` — but see §Common Pitfalls §Log-Cost Scaling: current `λ_gdd = 1e-4` is the default but its **effective** weight drops ~50 dB over a 50 dB optimization. This will contaminate any simple sweep unless the penalty gradient is also log-rescaled OR the penalty is applied **before** the log-rescale block (as the code currently does — but the weight-drift side effect remains).
- **Expected effect:** penalizes second derivative of `φ(ω)` — forbids sharp kinks. Physically: discourages high-order dispersion structure, prefers smooth chirp.
- **Failure mode:** at very large `λ` the optimum becomes pure quadratic phase (pure GDD), which gives only modest Raman suppression.
- **Conditioning impact:** adds a discretized Laplacian² to the Hessian — regularizes the phase grid toward smoothness.

### P3. Higher-order curvature / TOD (`‖∂³φ/∂ω³‖²`)

- **Functional:** `R(φ) = (1/Δω⁵) · Σ (φ_{i+2} - 3φ_{i+1} + 3φ_i - φ_{i-1})²` — fourth-order stencil for the third derivative.
- **Gradient:** copy the GDD pattern with 4-point stencil. Stencil coefficients in the gradient: `+1, -3, +3, -1` to be dispersed to `grad[i-1], grad[i], grad[i+1], grad[i+2]` with appropriate signs.
- **λ ladder:** `{0, 1e-8, 1e-6, 1e-4}` (needs Δω⁵ normalization — larger exponent → smaller effective λ).
- **Expected effect:** penalizes third derivative of `φ(ω)` — discourages asymmetric chirp ramps. Leaves GDD alone; only suppresses TOD-like structure.
- **Use case:** decoupling "I want a smooth chirp but allow any GDD" from "penalize all curvature including GDD." Useful if Phase 31 finds that GDD penalty bleeds interpretability but pure curvature smoothing is still desirable.

### P4. Total Variation (`‖∂φ/∂ω‖_{1,smooth}`)

- **Functional:** `R(φ) = Σ_{i ∈ bw-1} √((φ_{i+1} - φ_i)² + ε²)` with `ε = 1e-6` (smooth-L1 approximation of |·|)
- **Gradient:** `∂R/∂φ_i = (φ_i - φ_{i-1}) / √((φ_i - φ_{i-1})² + ε²) - (φ_{i+1} - φ_i) / √((φ_{i+1} - φ_i)² + ε²)` — copy the amplitude TV pattern from `amplitude_optimization.jl:107-128`.
- **λ ladder:** `{0, 1e-4, 1e-2, 1e0}` (TV scales linearly with phase jumps, not their squares).
- **Expected effect:** favors **piecewise-constant** phase with few sharp transitions. Unusual for this problem, BUT: might reveal whether a sparse step-wise phase ansatz competes with smooth bases. Physically speculative but cheap.
- **Failure mode:** non-differentiable at `ε = 0`; `ε = 1e-6` is the smoothed surrogate. Keep `ε` conservative to preserve convergence.

### P5. Sparsity in DCT (`‖B_{dct}^T · φ‖_1`)

- **Functional:** `R(φ) = Σ_k √((B_{dct,k}^T · φ)² + ε²)` — smooth-L1 of DCT coefficients of φ, summed over all DCT modes `k`.
- **Gradient:** `∂R/∂φ_i = Σ_k (B_{dct,k,i}) · (B_{dct,k}^T φ) / √((B_{dct,k}^T φ)² + ε²)`. Equivalently: `∂R/∂φ = B_{dct} · g` where `g_k = c_k / √(c_k² + ε²)` is the subgradient of smooth-L1 applied to `c = B_{dct}^T φ`.
- **λ ladder:** `{0, 1e-4, 1e-2, 1e0}`.
- **Expected effect:** pushes the optimum toward using few DCT coefficients — **soft basis selection**. Bridges Branch A and Branch B: instead of pre-committing to `N_phi`, let the penalty choose. The result should agree with the best `:dct` N_phi found in Branch A.
- **Conditioning impact:** complex — couples all phase points through `B_{dct}`. May slow convergence because L-BFGS sees a less-smooth landscape than pure L₂ regularization.

### Penalty combinations to explicitly NOT include

- **Elastic-net on DCT coefficients** (L₁ + L₂). Possible but redundant with (P5 + P1 active simultaneously). Defer unless Phase 31 analysis finds single-penalty results unclear.
- **Lasso on φ directly** (`‖φ‖_1` on the grid). Physically uninterpretable (a sparse-in-frequency phase is a delta comb, not a shape) and numerically unstable. Skip.

### Recommended penalty program for Phase 31

Run each penalty at each `λ` on the full-grid (`N_phi = Nt = 2^{14}`) canonical point, so Branch B is pure penalty, pure full-grid:

```julia
PENALTY_PROGRAM = [
    (:tikhonov,  [0.0, 1e-6, 1e-4, 1e-2, 1e0]),
    (:gdd,       [0.0, 1e-6, 1e-4, 1e-2]),            # :gdd = curvature; 0 is the current default
    (:tod,       [0.0, 1e-8, 1e-6, 1e-4]),
    (:tv,        [0.0, 1e-4, 1e-2, 1e0]),
    (:dct_l1,    [0.0, 1e-4, 1e-2, 1e0]),
]
```

**Total optimization runs, Branch B only:** 5 + 4 + 4 + 4 + 4 = **21** runs. Each ~30–90 s.

### Optional Branch C: Hybrid basis × penalty grid

If Plan 02 budget allows, run a 2D grid `{:dct at N_phi = 32 or 64} × {λ_tikhonov ∈ {0, 1e-4, 1e-2}}` to test whether small-basis + small-penalty dominates either alone. 3 × 2 = 6 extra runs. Strongly recommended for the Pareto story.

---

## Model-Selection Machinery

Four tools, ranked by implementation simplicity.

### 1. L-curve (simplest, most interpretable)

Per penalty family, plot on log-log axes:

- x-axis: `R(φ_opt(λ))` — the residual regularizer norm
- y-axis: `J_raman(φ_opt(λ))` — the *unregularized* physics cost (record this separately in the breakdown dict!)

The "elbow" is the λ that balances fit against regularization. Detect either visually or by maximum curvature of the log-log L-curve.

Already a standard tool; see Hansen, *The L-curve and its use in the numerical treatment of inverse problems* (1999).

**Implementation cost:** ~30 lines in `phase31_analyze.jl`. Requires recording `J_raman` (NOT `J_total`) in the JLD2 row — achievable by adding `"J_raman"` to the `package_result` Dict from the existing amplitude-optimization `breakdown` dict pattern.

### 2. Generalized Cross-Validation (GCV)

For a linear inverse problem with regularization matrix `L`, GCV chooses `λ` to minimize `‖J(λ)‖² / (trace(I - A(λ)))²` where `A(λ)` is the influence matrix of the regularized fit. For our **nonlinear** problem, GCV is only approximate but the heuristic still applies: plot `J_raman(λ) · (N_phi / (N_phi - trace_proxy))²` as a function of `λ` and take the minimum.

**Implementation cost:** ~50 lines. Lower confidence than L-curve for nonlinear problems. Include only if Plan 02 has budget.

### 3. AIC/BIC (information criteria)

- **AIC:** `AIC(λ) = 2 · k_effective(λ) + N_bw · log(J_raman(λ))` — **lower is better**.
- **BIC:** `BIC(λ) = k_effective(λ) · log(N_bw) + N_bw · log(J_raman(λ))` — penalizes complexity more aggressively at large `N_bw`.

Here `k_effective` is:
- For Branch A (basis restriction): `k = N_phi - 2` (subtract two for gauge null-modes).
- For Branch B (penalty): `k = N_phi - 2 - rank_suppressed_by_penalty`, approximated by `k ≈ N_eff(φ_opt)` from `phase_neff(...)`.

`N_bw = count(bw_mask)` — the effective # of independent data points on the bandwidth.

**Implementation cost:** ~20 lines. Cleanest for **cross-family comparison** (polynomial vs DCT vs spline at different `N_phi`).

### 4. Cross-configuration validation (the "transferability score")

Train on canonical SMF-28 L=2 m P=0.2 W. Evaluate on HNLF L=0.5 m P=0.01 W *and* on canonical-perturbed `{P = 0.21 W, FWHM = 194 fs, β₂ = 1.05 · β₂_{SMF28}}` *without re-optimization*. Record `J_transfer_dB`.

Transferability is a Phase-specific surrogate for out-of-sample validation — we don't have enough operating points for true k-fold CV but we have enough for train-on-one / test-on-two.

**Implementation cost:** already coded in `phase14_robustness_test.jl` + `chirp_sensitivity`. Rewrapping into `phase31_transfer.jl` is copy-paste + JLD2 ingest.

### Recommended set for Phase 31: **L-curve + AIC + transferability**.

GCV skipped (nonlinear approximation too loose). BIC optional if AIC is inconclusive.

---

## Evaluation Metrics — full list

All metrics must be recorded in every JLD2 row.

| Metric | Formula / source | Interpretation | Code location |
|--------|------------------|----------------|---------------|
| `J_dB` | `10 · log10(J_raman)` | depth of Raman-band suppression — the headline | existing, `cost_and_gradient` with `log_cost=true` |
| `J_raman_linear` | `J_raman` (unregularized, linear) | for L-curve y-axis | record from `breakdown["J_raman"]` |
| `sigma_3dB` | from Gaussian-perturbation sweep: smallest σ such that `J_dB(φ + σ·n) - J_dB(φ) ≥ 3 dB`, averaged over `N_trial` realizations | robustness (Phase 22 convention) | port from `scripts/phase14_robustness_test.jl` |
| `N_eff` | `phase_neff(φ_opt, bw_mask)` — entropy of DCT power spectrum | "effective # of active DCT modes" | `scripts/sweep_simple_param.jl:407` |
| `TV` | `phase_tv(φ_opt, bw_mask)` — normalized total variation of unwrapped φ | phase smoothness | `sweep_simple_param.jl:440` |
| `curvature` | `phase_curvature(φ_opt, sim, bw_mask)` — `‖∂²φ/∂ω²‖_2` on bw | how bendy the chirp is | `sweep_simple_param.jl:464` |
| `polynomial_R²` | residual fraction of `φ_opt` projected onto `{ω², ω³, ω⁴}` polynomial basis — **1 - (‖φ_opt - φ_proj‖ / ‖φ_opt‖)** | interpretability — how close is the optimum to a textbook chirp? | `scripts/phase13_primitives.jl::polynomial_project` |
| `hess_indef_ratio` | `|λ_min_bottom_20| / λ_max_top_20` in the **coefficient-space** Hessian | saddle-masking check (Phase 35); **SHOULD** be small (< 0.05) if basis is not artificially flattening | Arpack wrapper on coefficient-space HVP |
| `kappa_B` | `κ(B^T B)` | basis conditioning | `_sanity_check_basis` — promote to JLD2 field |
| `kappa_H_restricted` | `λ_max(H_c) / |λ_min_nonzero(H_c)|` in coefficient space | restricted-Hessian conditioning; ties to Phase 28 |
| `J_transfer_HNLF` | `cost_and_gradient(φ_opt, uω0_HNLF, fiber_HNLF, sim, band_mask_HNLF; log_cost=true)` | is this optimum re-usable? | `phase31_transfer.jl` |
| `J_transfer_perturb` | worst-case `ΔJ_dB` under `±5%` FWHM / `±10%` P perturbations, no re-opt | robustness to pulse drift | `phase31_transfer.jl` |
| `wall_time_s` | from Optim.jl result | cost of the method | `result.time_run` |
| `iterations` | `Optim.iterations(result)` | convergence speed | existing |
| `converged` | `Optim.f_converged(result)` | did it stop on f_tol or on max_iter? | existing |

**Pareto axes for the plots:** choose two or three at a time:
- **(J_dB, N_eff)**: depth vs simplicity. Already used by Session E / `sweep_simple_analyze.jl`. ✓
- **(J_dB, σ_3dB)**: depth vs robustness. Phase 22 style. ✓
- **(J_dB, polynomial_R²)**: depth vs interpretability — this is THE phase 31 novel axis.
- **(J_dB, J_transfer_HNLF - J_canonical)**: depth vs transferability.

Render each as a separate PNG. Scatter with marker shape = basis family, marker color = `log10(λ)` (for Branch B) or `N_phi` (for Branch A), annotate Pareto-optimal points with basis-name/λ labels.

---

## Numerical Conditioning Checks

The Phase 31 run MUST emit the following at every optimum (record into the JLD2 row):

### Check 1: Basis Gram matrix conditioning

```julia
G = Symmetric(B' * B)
kappa_B = cond(G)           # or compute from eigvals at N_phi ≤ 512
# expected:
#   :dct         → 1.0
#   :polynomial  → < 1e3 (Legendre scaling)
#   :cubic       → scales with (Nt/N_phi) at the knots — typically < 1e6
#   :linear      → similar to :cubic, sometimes a bit worse
# Fail if kappa_B > 1e12 (already the LR_COND_LIMIT warning threshold)
```

Already implemented in `_sanity_check_basis`. Promote the warning to a recorded field.

### Check 2: Coefficient-space Hessian conditioning

For each optimum, use the Phase 13 HVP infrastructure:

```julia
# Build oracle in coefficient space
coefficient_oracle = c -> begin
    _, dc = cost_and_gradient_lowres(c, B, uω0, fiber, sim, band_mask; kwargs...)
    dc
end
hvp = make_fd_hvp(coefficient_oracle)  # existing: phase13_hvp.jl::fd_hvp
# Arpack bottom-K and top-K
op = HVPOperator(hvp, N_phi * M)
lam_top = eigs(op, nev=10, which=:LR)[1]
lam_bot = eigs(op, nev=10, which=:SR)[1]
kappa_H = maximum(abs.(lam_top)) / max(abs(lam_bot[1]), eps())
hess_indef_ratio = abs(lam_bot[1]) / maximum(abs.(lam_top))
```

**This is critical for the saddle-masking check (Phase 35 pitfall).** If `hess_indef_ratio` > 0.05 in coefficient space, the restricted basis has NOT converted the saddle into a minimum — the negative curvature persists. Under a reduced basis, we *want* either:

- `hess_indef_ratio` close to 0 — all eigenvalues positive → genuine minimum in the reduced space.
- `hess_indef_ratio` similar to the full-grid value (~2% for SMF-28 canonical, Phase 13) — saddle persists → the reduction didn't mask it.

What Phase 35 warned against is: low `N_phi` (e.g. 4) gives an artificially PSD Hessian at −47 dB. So Phase 31 MUST report `J_dB` alongside `hess_indef_ratio` and alongside `κ_H_restricted` — a minimum that only exists because you can't move in the bad directions is not physics, it's a reporting artifact.

### Check 3: Gradient verification via Taylor-remainder-2

Phase 27 second-opinion defect: current `validate_gradient` in `raman_optimization.jl:252-285` is a ratio check, NOT a Taylor-remainder slope check. For the **new** penalty families in Phase 31, use a slope check:

```julia
# For a direction v, J(c + ε·v) - J(c) - ε · ∇J(c)·v should be O(ε²) as ε halves.
# Plot log(|residual|) vs log(ε); slope should be ≈ 2.
epsilons = [1e-1, 1e-2, 1e-3, 1e-4, 1e-5]
J0, g = cost_and_gradient_lowres(c0, B, uω0, fiber, sim, band_mask; ..., λ_tikhonov=1.0)
v = randn(length(c0)); v ./= norm(v)
residuals = Float64[]
for ε in epsilons
    J_plus, _ = cost_and_gradient_lowres(c0 + ε*v, B, uω0, fiber, sim, band_mask; ..., λ_tikhonov=1.0)
    push!(residuals, abs(J_plus - J0 - ε * dot(g, v)))
end
# log-log slope of residuals vs ε should be ≈ 2.
slope = (log(residuals[end]) - log(residuals[1])) / (log(epsilons[end]) - log(epsilons[1]))
@test abs(slope - 2.0) < 0.3
```

Required test for EACH new penalty in `phase31_penalty_lib.jl`. Enforces the Phase 27 second-opinion recommendation (row 3 of the "What Phase 27 missed" table).

---

## Execution Architecture

### Plan / wave assignment

**Plan 01 — Library + Branch A (basis) sweep at canonical point.** Waves:

- **Wave 1** (library): `phase31_basis_lib.jl`, `phase31_penalty_lib.jl`, `test/test_phase31_basis.jl`. No optimization yet. Unit tests + gradient finite-difference tests + basis conditioning tests. Runs on `claude-code-host`, not burst.
- **Wave 2** (Branch A run): `phase31_run.jl` invoked with `--branch=A`. Runs on burst VM through `burst-run-heavy A-phase31 'julia -t auto --project=. scripts/phase31_run.jl --branch=A'`. Outputs 21 JLD2 rows (see basis program) + 21 × 4 standard images per optimum.

Wall time estimate: Wave 1 ~5 min (tests), Wave 2 ~25 min on burst (21 runs × ~70 s each, some parallelism via `Threads.@threads` with `deepcopy(fiber)`).

**Plan 02 — Branch B (penalty) sweep + transfer + analyze.** Waves:

- **Wave 1** (Branch B run): `phase31_run.jl --branch=B`. 21 more JLD2 rows on the penalty ladder. ~25 min on burst.
- **Wave 2** (transfer + optional Branch C): `phase31_transfer.jl`. Reads Branch A + B results, applies each `phi_opt` to HNLF + perturbed configs, records `J_transfer`. No optimization — just forward solves. ~10 min on burst.
- **Wave 3** (analysis): `phase31_analyze.jl` — Pareto, L-curve, AIC, candidates.md, FINDINGS.md. Runs locally (no burst). ~5 min.

**Total phase budget:** ~70 min burst compute + ~15 min local + ~30 min test/plumbing = well under the 2 hr natural session limit.

### Parallelism plan

Inside `phase31_run.jl`:

- **Branch A**: parallelize over `(kind, N_phi)` pairs via `Threads.@threads`. Each thread does `deepcopy(fiber)` (Rule 1 from CLAUDE.md Compute Discipline). Expected speedup ~3.5× at 8 threads (documented in the threading benchmarks).
- **Branch B**: same — parallelize over `(penalty_name, lambda)` pairs.
- **Continuation ladder within a kind**: stay sequential (one thread walks `N_phi = 4 → 8 → ... → 256` using warm-start). Don't try to parallelize the ladder itself.

Inside `phase31_transfer.jl`:

- Parallelize over `(result_row × transfer_config)`. Each task is a single forward solve — cheap and perfectly parallel. Expected speedup ~8× at full burst threads.

### Output JLD2 schema

One `Dict{String,Any}` per run. Required keys (union of Branch A + Branch B requirements):

```julia
Dict(
    # ─── Provenance ───
    "run_tag"          => P31_RUN_TAG,
    "branch"           => "A" | "B" | "C",
    "regularization_mode" => "basis" | "penalty" | "hybrid",
    "commit_sha"       => "<git rev-parse HEAD>",

    # ─── Config ───
    "config"           => Dict("fiber_preset"=>"SMF28", "L_m"=>2.0, "P_W"=>0.2, ...),

    # ─── Basis ───
    "kind"             => "dct" | "cubic" | "polynomial" | "chirp_ladder" | "linear" | "identity",
    "N_phi"            => 64,
    "kappa_B"          => 1.0,  # Gram conditioning
    "kappa_B_warned"   => false,

    # ─── Penalty (0 for Branch A, filled for Branch B/C) ───
    "penalties"        => Dict("tikhonov"=>0.0, "gdd"=>0.0, "tod"=>0.0, "tv"=>0.0, "dct_l1"=>0.0),

    # ─── Optimum ───
    "c_opt"            => vec(c_opt),
    "phi_opt"          => vec(phi_opt),         # full Nt grid, post-reconstruction
    "phi_opt_gauged"   => vec(gauge_fix(phi_opt, bw_mask)),  # for metrics
    "J_final"          => J_final_dB,
    "J_raman_linear"   => J_raman,              # unregularized physics cost
    "iterations"       => Optim.iterations(result),
    "converged"        => Optim.f_converged(result),
    "wall_time_s"      => wall_time,

    # ─── Simplicity metrics (on gauge-fixed phi) ───
    "N_eff"            => phase_neff(phi_gauged, bw_mask),
    "TV"               => phase_tv(phi_gauged, bw_mask),
    "curvature"        => phase_curvature(phi_gauged, sim, bw_mask),

    # ─── Interpretability ───
    "polynomial_R2"    => polynomial_project_r2(phi_gauged, [2, 3, 4], bw_mask),
    "polynomial_coeffs"=> poly_coeffs_234,       # for reporting

    # ─── Conditioning ───
    "hess_indef_ratio" => |lambda_min_bot| / lambda_max_top,  # in coefficient space
    "kappa_H_restricted" => lambda_max_top / |lambda_min_nonzero|,
    "hess_probe_wall_s"=> wall_time_arpack,

    # ─── Trust (Phase 28 bundle) ───
    "trust_report"     => Dict(...),  # reuse scripts/numerical_trust.jl

    # ─── Transferability (filled by phase31_transfer.jl, nullable in phase31_run.jl) ───
    "J_transfer_HNLF"  => J_transfer_HNLF,
    "J_transfer_perturb" => Dict("+5pct_FWHM"=>ΔJ, "+10pct_P"=>ΔJ, ...),

    # ─── Robustness ───
    "sigma_3dB"        => sigma_3dB,
    "sigma_3dB_n_trials" => 20,
)
```

Save incrementally as rows complete:

```julia
const P31_RESULTS_PATH = joinpath(P31_RESULTS_DIR, "phase31_runs.jld2")
rows = Dict{String,Any}[]
# ... inside each branch loop:
push!(rows, row_dict)
JLD2.jldsave(P31_RESULTS_PATH; rows=rows, run_tag=P31_RUN_TAG)
```

### Standard images emission (MANDATORY)

Every row above has a `phi_opt`. Therefore every row triggers:

```julia
save_standard_set(phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold;
    tag = "p31_$(branch)_$(kind)_Nphi$(N_phi)_$(penalty_tag)",
    fiber_name = "SMF28",
    L_m = 2.0, P_W = 0.2,
    output_dir = joinpath(P31_RESULTS_DIR, "sweep_$(branch)", "images"))
```

No exceptions. CLAUDE.md rule is absolute. Skipping this makes the work "incomplete" regardless of dB.

### Manifest

`phase31_run.jl` writes a `manifest.json` alongside the JLD2 with:

- `run_tag`, `git_commit`, `julia_version`, `threads`
- `fftw_wisdom_sha256`
- `basis_program`, `penalty_program`, `canonical_config`, `transfer_config`
- paths of all emitted JLD2 + image files
- total wall time

Pattern: see `scripts/determinism.jl::ensure_deterministic_environment()` output + the `trust_report` JSON convention in Phase 28.

---

## Test Plan (for `test/test_phase31_basis.jl`)

Eight required testsets, all against the existing Test.jl harness (`test_phase13_primitives.jl` is the template):

1. **`:identity` reproduces full-res cost.** At `N_phi = Nt`, `cost_and_gradient_lowres(vec(φ), I, uω0, fiber, sim, band_mask)` = `cost_and_gradient(φ, uω0, fiber, sim, band_mask)` byte-exact.
2. **New `:polynomial` basis builds without warnings at orders 2–8.** `kappa_B` < 1e4 for each order on the canonical bandwidth.
3. **New `:chirp_ladder` basis has exactly 4 columns and zero overlap with gauge null modes.** `cos_similarity(B[:,k], const) < 1e-10` and `cos_similarity(B[:,k], ω_linear) < 1e-10` for all k.
4. **Coefficient-space gradient finite-difference test** for each new kind. For each `kind ∈ {:polynomial, :chirp_ladder, :hermite}`: random c, compute gradient, verify `|grad_FD - grad_adjoint| / |grad_adjoint| < 1e-4` at 5 random coefficient indices.
5. **Taylor-remainder-2 slope test** for each penalty in `phase31_penalty_lib.jl`. Set `λ_raman = 0` (impossible via kwargs — instead set `uω0` such that `J_raman ≈ 0`), enable one `λ_penalty` at a time, verify slope ≈ 2.
6. **Continuation upsample preservation** across kind boundaries: `continuation_upsample(c_polynomial_order4, B_polynomial_order4, B_dct_64)` produces a `c_dct` such that `B_dct * c_dct ≈ B_polynomial * c_polynomial` to machine precision on the bandwidth.
7. **Orthonormal-basis fast path**: for `:dct`, `continuation_upsample` reduces to `B_fine' * φ_prev` bit-exact.
8. **Hessian indefiniteness check is non-trivial**: at the Phase 35 known-minimum `:chirp_ladder` optimum, `hess_indef_ratio < 0.01` (PSD). At full-grid `:identity` optimum, `hess_indef_ratio > 0.005` (indefinite). Both results from Phase 35 must be reproduced.

Test wall time target: < 90 s locally, no burst needed.

---

## Common Pitfalls

### Pitfall 1: Log-Cost Scaling Breaks Regularizer Weight Comparability

**What goes wrong:** Phase 27 second-opinion defect #2. The physics cost gradient is multiplied by `10 / (J · ln 10)` as `J` decreases from −0 dB to −80 dB, effectively scaling the physics gradient up by ~50 dB. The GDD / boundary / new Phase 31 penalties' gradients are added **before** the log-rescale, so they get multiplied by the same factor. Net effect on effective weight of a regularizer term as a function of `J`:

- At `J = 1` (0 dB): effective λ is as set.
- At `J = 1e-8` (−80 dB): effective λ is ~1e8 times as set.

The regularizer's effective strength GROWS as the optimizer succeeds at Raman suppression. So `λ_gdd = 1e-4` at start of optimization becomes effectively `λ_gdd = 1e4` at −80 dB, which is catastrophically strong.

**Why it happens:** The log-rescale was introduced to keep the physics cost and gradient on a common scale for L-BFGS line search. Re-scaling the penalties the same way was NOT intentional — it's a side effect of adding penalty contributions to `grad_total` before the log block applies to everything.

**How to avoid for Phase 31:**

**Option A (recommended, cheapest):** Add Phase 31 penalties *after* the log-rescale, so the penalty gradient is NOT multiplied by `log_scale`. This gives state-independent `λ` but requires the penalty functional to produce a cost contribution on the **dB scale**, i.e. `J_penalty_dB = 10·log10(1 + λ·R/J_raman)` or similar. Complicates the functional form.

**Option B (cleaner, more work):** Keep penalties before the log-rescale, but **explicitly record J_raman_linear separately** in the breakdown dict and document in FINDINGS.md that "`λ = X`" refers to the linear-cost effective weight at the *initial* iterate, and that penalties get implicitly annealed as `J` decreases. This is what `amplitude_optimization.jl` does — the `breakdown` dict carries `J_tikhonov`, `J_tv`, `J_flat` individually so post-hoc analysis can back out the per-component costs.

**Phase 31 decision (recommended, based on Phase 27 seed `cost-surface-coherence-and-log-scale-audit.md`):** Option B. Record `J_raman` and `J_{penalty_name}` individually in the breakdown. Document the annealing side-effect. Do NOT try to "fix" the log-scaling in Phase 31 — that's a separate seed's concern. But DO verify the Taylor-remainder slope still holds (it does, because both cost and gradient are log-rescaled consistently).

**Warning signs at execution:** penalty weight ladders showing no visible effect at small `λ`, and catastrophic regularization (J → 0 phase) at medium `λ`. If `λ = 1e-6` behaves like `λ = 0` and `λ = 1e-4` produces `φ ≡ 0`, the log-scaling pitfall is biting.

### Pitfall 2: Saddle Masking by Basis Restriction (Phase 35 Verdict)

**What goes wrong:** The competitive-depth branch (`J_dB < −65 dB`) is saddle-dominated in the full-grid control space. Phase 35 showed that `N_phi = 4` restricts to a subspace where the negative-curvature directions are *not representable*, so the restricted Hessian is PSD — a "minimum" by construction, at −47 dB. Restricting further reduces depth further; the competitive branch remains saddle-dominated.

**Why it happens:** The negative eigenvectors of the full Hessian are high-frequency oscillatory patterns in `φ(ω)`. A small-`N_phi` basis cannot span those directions, so the restricted Hessian misses them. The ratio `hess_indef_ratio` drops not because the physics got more convex but because the basis can't see the non-convex directions.

**How to avoid / mitigate:** Phase 31 MUST record **both** `hess_indef_ratio_coefficient_space` AND `hess_indef_ratio_ambient_space` for every optimum. The first is the restricted Hessian (uses `phase31_hvp_coefficient`); the second is the full-grid Hessian evaluated at `φ_opt = B · c_opt` using the existing `phase13_hvp`. A *genuine* minimum has both small.

**Warning signs:** `hess_indef_ratio_coefficient < 0.01` but `hess_indef_ratio_ambient > 0.02` at the same optimum → saddle-masking is happening. The basis is hiding the saddle, not resolving it.

**Phase 31 contract:** For any recommended "operational" basis emerging from Pareto analysis, both ratios must be reported, and the FINDINGS.md must call out which optima are genuinely PSD vs. basis-restricted PSD.

### Pitfall 3: Gauge Mode Leakage Confuses Interpretability Metrics

**What goes wrong:** A polynomial basis including order 0 and 1 (constant and linear) has 2 gauge null-directions. L-BFGS will randomly populate those coefficients on convergence — random constants and linear chirps that don't affect J. Reporting `TV(φ_opt)` or `curvature(φ_opt)` without gauge-fixing gives random offsets.

**How to avoid:** Gauge-fix `φ_opt` before computing any simplicity / interpretability metric:

```julia
phi_opt_gauged = gauge_fix(phi_opt, bandwidth_mask)  # from phase13_primitives.jl
# then
N_eff = phase_neff(phi_opt_gauged, bw_mask)
TV = phase_tv(phi_opt_gauged, bw_mask)
poly_R2 = polynomial_project(phi_opt_gauged, [2, 3, 4], bw_mask).r2
```

Better still: pick gauge-free bases by construction (`:chirp_ladder`, `:polynomial` starting at order 2). Then no post-hoc gauge fix is needed and the coefficients are directly interpretable as `(β₂_shaper, β₃_shaper, β₄_shaper, ...)`.

**Warning signs:** Two optima with `J_dB` differing by 0.01 dB but `TV` differing by 2× → almost certainly a gauge artifact. If gauge-fixing collapses them, confirmed.

### Pitfall 4: Over-Fitting a Basis to One Operating Point

**What goes wrong:** `:dct` at `N_phi = 256` on SMF-28 canonical might reach −68 dB. On HNLF L=0.5 m P=0.01 W the same `phi_opt` evaluated (no re-opt) might be −12 dB — degraded by 56 dB. That's not a bad basis, it's a natural result: the optimum is specific to the canonical point.

**How to avoid for Phase 31:** Always report `J_transfer_HNLF` alongside `J_canonical`. The operational recommendation should emphasize **transferability + depth**, not raw depth. If every high-depth optimum transfers poorly, the Pareto story is "low-N_phi polynomials transfer well at moderate depth; high-N_phi DCT transfers poorly at deep depth." Both are valid results.

**Warning signs:** Transferability scatter plot has a clear negative correlation between `J_canonical` and `J_transfer` — expected. Flag any operating point where a basis transfers *better* than it fits (implausible; suggests canonical optimization didn't converge).

### Pitfall 5: `λ = 0` Baseline Not Identical Across Branches

**What goes wrong:** Branch A at `kind = :identity, N_phi = Nt` with no penalties should equal Branch B at `kind = :identity` with `λ_all = 0`, which should equal the baseline `optimize_spectral_phase` run. If any of these disagree, a plumbing bug is hiding.

**How to avoid:** Unit test this equivalence. `test_phase31_basis.jl` testset 1 already covers `:identity` == `cost_and_gradient`. Add a testset 9: "Branch B with all `λ = 0` equals Branch A `:identity`."

**Warning signs:** `J_dB` at the same canonical point varies across runs with `penalties = 0` — then a bug exists somewhere.

### Pitfall 6: Multi-Thread Fiber State Race

**What goes wrong:** `fiber["zsave"]` is mutated by the solver during forward / adjoint propagation. Two threads sharing `fiber` will race, producing non-reproducible results.

**How to avoid:** Every `Threads.@threads` block does `fiber_local = deepcopy(fiber)` and uses `fiber_local` exclusively. Exact pattern is documented in CLAUDE.md Rule 1 and used in `scripts/benchmark_optimization.jl:635`.

**Warning signs:** Runs are individually reproducible but collectively non-reproducible across re-launches. Single-threaded run agrees with one particular thread-count run but not another.

### Pitfall 7: FD-HVP Step Size at Deep Optima (Phase 27 Addendum Defect #5)

**What goes wrong:** `phase13_hvp.jl:48` uses fixed `ε = 1e-4`. At −80 dB, `‖∇J‖_linear ~ 1e-8`, so the optimal `ε_fd ≈ √(eps_mach · ‖∇J‖) / ‖v‖ ≈ 1e-8 / ‖v‖`. A fixed `1e-4` is 4 orders of magnitude too large — the HVP is dominated by truncation error, not roundoff.

**How to avoid for Phase 31:** When computing `hess_indef_ratio` and `κ_H_restricted` for any competitive optimum, use an adaptive `ε` in the coefficient-space HVP. This is small wrapper-level code in `phase31_run.jl`:

```julia
g_norm = norm(dc)  # coefficient gradient at optimum
ε_adaptive = sqrt(eps(Float64) * g_norm)  # tuned for coefficient space
# then pass ε_adaptive into the coefficient-space HVP
```

**Warning signs:** `hess_indef_ratio` fluctuates by > 20% across repeated Arpack runs on the same optimum → FD step is dominated by noise. Lower `ε` and retry.

### Pitfall 8: Absorbing Boundary at Long Fiber (Phase 27 Addendum Defect #4)

**What goes wrong:** Super-Gaussian attenuator (`helpers.jl:59-63`) silently absorbs energy in outer 15% of time window. At L = 2 m SMF-28 with P = 0.2 W, most energy stays within the window — usually fine. But if Phase 31 transfers an optimum to a long-fiber regime, the attenuator eats real signal.

**How to avoid:** The canonical and transfer points listed in this research (SMF-28 L=2 m, HNLF L=0.5 m) are both safe. Don't extend Phase 31 to L > 5 m without first running the edge-energy probe from `scripts/common.jl::check_boundary_conditions`. Record edge_fraction in the trust_report for every run.

---

## Runtime State Inventory

Phase 31 is a code-addition phase, not a rename/refactor phase. No runtime-state inventory is required beyond the code paths listed below.

| Category | Items | Action |
|----------|-------|--------|
| Stored data | No existing JLD2 files embed the string "phase31". New results go under `results/raman/phase31/`. | None (greenfield output tree) |
| Live service config | None. | None |
| OS-registered state | None. | None |
| Secrets/env vars | None. | None |
| Build artifacts | Julia precompilation cache for `scripts/phase31_*.jl` will be re-created on first include. | None (automatic) |

---

## Environment Availability

Verified on `claude-code-host` (primary dev) and required on `fiber-raman-burst` (heavy compute):

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Julia | All | ✓ (both hosts) | 1.9.3+ (pinned at 1.12.4 via Manifest) | none |
| Julia `-t auto` | Phase 31 `Threads.@threads` loops | ✓ | — | single-thread, 8× slower |
| `burst-ssh`, `burst-run-heavy`, `burst-status` | Plans 01 Wave 2 / Plan 02 Waves 1-2 | ✓ on claude-code-host only | — | SSH direct + manual tmux (DEPRECATED per CLAUDE.md Rule P5) |
| FFTW wisdom | deterministic runs | ✓ via `scripts/determinism.jl` | — | skip (already the case in prior runs) |
| `Arpack.jl` | Hessian eigenspectrum probe | ✓ | pinned | skip indefiniteness check (not acceptable for P31-F) |
| `Optim.jl` | L-BFGS | ✓ | 1.13.3 pinned | none |
| `PyPlot` / matplotlib | figures | ✓ | — | skip image emission (unacceptable per P31-G) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none relevant — all required infrastructure is present.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `@testset` harness, invocation via `julia --project=. test/test_phase31_basis.jl` |
| Config file | none — test file self-contained |
| Quick run command | `julia --project=. test/test_phase31_basis.jl` (no `-t auto`; tests are single-thread) |
| Full suite command | `julia --project=. -e 'include("test/runtests.jl")'` — but note that `runtests.jl` is currently a minimal smoke test; the Phase 31 test file is invoked directly. |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| P31-A | Basis catalog populated with correct dimensions and conditioning | unit | `julia --project=. test/test_phase31_basis.jl` → testsets 2, 3, 6, 7 | ❌ Wave 0 |
| P31-B | Penalty catalog with correct gradient forms | unit | testset 5 (Taylor-remainder slope) | ❌ Wave 0 |
| P31-C | Canonical-point head-to-head runs | integration | manual inspection of `results/raman/phase31/phase31_runs.jld2` row count == 21 + 21 = 42 | ❌ Wave 0 |
| P31-D | Transferability table present | integration | `results/raman/phase31/phase31_runs.jld2` rows all have `J_transfer_HNLF` populated after `phase31_transfer.jl` runs | ❌ Wave 0 |
| P31-E | L-curve / AIC recommendations in candidates.md | manual | visual: L-curve elbow and AIC minimum annotated | ❌ Wave 0 |
| P31-F | No saddle-masking artifacts | automated | testset 8 (Phase 35 reproduction); + post-hoc script compares ambient vs coefficient Hessian ratios | ❌ Wave 0 |
| P31-G | Standard images emitted | integration | `ls results/raman/phase31/sweep_*/images/*_phase_profile.png | wc -l` ≥ 42 | ❌ Wave 0 |
| P31-H | No mutation of protected files | automated | `git diff --stat scripts/common.jl scripts/visualization.jl src/ Project.toml Manifest.toml` shows empty output after Plan 01 + Plan 02 | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project=. test/test_phase31_basis.jl` (30–90 s locally)
- **Per wave merge:** full test suite invocation + visual inspection of emitted images
- **Phase gate:** `bash scripts/check-phase-integrity.sh 31` (project-wide integrity check) + trust-report summary check + git diff confirms P31-H

### Wave 0 Gaps

All test files are new:

- [ ] `test/test_phase31_basis.jl` — 9 testsets covering P31-A/B/F and the Phase 35 reproduction
- [ ] `scripts/phase31_basis_lib.jl` — adds `:polynomial`, optional `:hermite`, `:chirp_ladder` kinds
- [ ] `scripts/phase31_penalty_lib.jl` — adds `:tikhonov`, `:tod`, `:tv_phi`, `:dct_l1` penalties
- [ ] `scripts/phase31_run.jl` — driver
- [ ] `scripts/phase31_transfer.jl` — transfer probe
- [ ] `scripts/phase31_analyze.jl` — Pareto + L-curve + AIC

Framework install: no new packages needed. `Pkg.instantiate()` is a no-op.

---

## Code Examples

### Example 1: Polynomial basis construction (new code)

```julia
# In scripts/phase31_basis_lib.jl

"""
    build_polynomial_basis(Nt, order; ω_grid, ω0, Δω_band, start_order=2) -> Matrix{Float64}

Legendre polynomial basis of orders `{start_order, ..., order}` in the centered,
scaled frequency variable x = (ω - ω0) / Δω_band.

Gauge-free by construction when start_order ≥ 2 (skips constant and linear).
"""
function build_polynomial_basis(Nt::Int, order::Int;
                                ω_grid::AbstractVector{<:Real},
                                ω0::Real,
                                Δω_band::Real,
                                start_order::Int = 2)
    @assert length(ω_grid) == Nt
    @assert order ≥ start_order ≥ 0
    x = (ω_grid .- ω0) ./ Δω_band            # scaled coordinate
    @assert all(abs.(x) .≤ 2.0) "scaled coordinate out of expected [-2, 2] range"

    N_phi = order - start_order + 1
    B = zeros(Float64, Nt, N_phi)

    # Generate Legendre via recurrence:  P_{n+1}(x) = ((2n+1)·x·P_n - n·P_{n-1}) / (n+1)
    Pnm1 = ones(Nt)
    Pn = copy(x)
    if start_order == 0
        B[:, 1] = Pnm1 ./ sqrt(sum(Pnm1.^2))
    end
    k = 1  # current order that has been computed
    col = (start_order == 0) ? 2 : (start_order == 1 ? 1 : 0)
    if start_order ≤ 1
        B[:, col] = Pn ./ sqrt(sum(Pn.^2))
        col += 1
    end
    for n in 1:order
        Pnp1 = ((2n + 1) .* x .* Pn .- n .* Pnm1) ./ (n + 1)
        if n + 1 ≥ start_order
            B[:, col] = Pnp1 ./ sqrt(sum(Pnp1.^2))
            col += 1
        end
        Pnm1, Pn = Pn, Pnp1
    end

    _sanity_check_basis(B)
    return B
end
```

### Example 2: Tikhonov-on-φ penalty (new code)

```julia
# In scripts/phase31_penalty_lib.jl

"""
    apply_tikhonov_phi!(J_total, grad_total, φ, bw_mask; λ)

Add λ · variance(φ on bandwidth) to J_total and its gradient to grad_total, in place.
Gauge-aware: subtracts bandwidth mean of φ first.

Returns the penalty cost contribution (for the breakdown dict).
"""
function apply_tikhonov_phi!(J_total::Ref{Float64},
                              grad_total::AbstractMatrix{<:Real},
                              φ::AbstractMatrix{<:Real},
                              bw_mask::AbstractVector{Bool};
                              λ::Real)
    # PRECONDITIONS
    @assert λ ≥ 0
    @assert size(grad_total) == size(φ)
    @assert length(bw_mask) == size(φ, 1)
    λ == 0 && return 0.0

    J_tikh = 0.0
    for m in 1:size(φ, 2)
        idx = findall(bw_mask)
        Nbw = length(idx)
        Nbw == 0 && continue
        φ̄ = mean(φ[idx, m])
        for i in idx
            dev = φ[i, m] - φ̄
            J_tikh += dev^2 / Nbw
            # ∂/∂φ_i (sum_j (φ_j - φ̄)^2 / N) = (2/N)(φ_i - φ̄) · (1 - 1/N)
            # but with large N this is approximately (2/N)(φ_i - φ̄)
            grad_total[i, m] += 2λ * (1 - 1/Nbw) * dev / Nbw
        end
    end
    J_tikh *= λ
    J_total[] += J_tikh

    # POSTCONDITIONS
    @assert isfinite(J_tikh)
    return J_tikh
end
```

### Example 3: Driver skeleton for Branch A (new code)

```julia
# In scripts/phase31_run.jl (shortened excerpt)

function run_branch_A(; canonical=:smf28_L2_P02, dry_run=false)
    uω0, fiber, sim, band_mask, Δf, raman_threshold = setup_raman_problem(;
        fiber_preset=:SMF28, L_fiber=2.0, P_cont=0.2,
        Nt=2^14, time_window=10.0)
    bw_mask = pulse_bandwidth_mask(uω0)
    rows = Dict{String,Any}[]
    save_path = joinpath(P31_RESULTS_DIR, "sweep_A_basis.jld2")

    for (kind, Nphi_list) in BASIS_PROGRAM
        # Continuation warm-start within this kind
        c_prev = nothing; B_prev = nothing
        for N_phi in Nphi_list
            B = build_basis_dispatch(kind, sim["Nt"], N_phi, bw_mask, sim)
            seeds = (c_prev === nothing) ?
                multistart_seeds(N_phi, sim["Nt"]) :
                [continuation_upsample(c_prev, B_prev, B)]

            best = nothing
            for seed in seeds
                fiber_local = deepcopy(fiber)
                r = optimize_phase_lowres(uω0, fiber_local, sim, band_mask;
                                          N_phi=N_phi, kind=kind, bandwidth_mask=bw_mask,
                                          c0=collect(seed), B_precomputed=B,
                                          max_iter=P31_MAX_ITER, log_cost=true)
                if best === nothing || r.J_final < best.J_final
                    best = r
                end
            end
            c_prev, B_prev = best.c_opt, best.B

            row = package_phase31_row(best, uω0, sim, band_mask, bw_mask;
                                       config=canonical_config,
                                       branch="A", kind=kind, penalties=Dict())
            push!(rows, row)
            JLD2.jldsave(save_path; rows=rows, run_tag=P31_RUN_TAG)

            save_standard_set(best.phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold;
                              tag=@sprintf("p31A_%s_N%d", kind, N_phi),
                              fiber_name="SMF28", L_m=2.0, P_W=0.2,
                              output_dir=joinpath(P31_RESULTS_DIR, "sweep_A", "images"))
        end
    end
end
```

### Example 4: Transferability (new code)

```julia
# In scripts/phase31_transfer.jl (excerpt)

function transfer_probe(phi_opt, kind, N_phi, source_config)
    # Transfer target 1: HNLF canonical
    uω0_h, fiber_h, sim_h, band_mask_h, _, _ = setup_raman_problem(;
        fiber_preset=:HNLF, L_fiber=0.5, P_cont=0.01,
        Nt=2^14, time_window=10.0)
    # Build a basis in HNLF's bandwidth if the source was basis-restricted
    bw_mask_h = pulse_bandwidth_mask(uω0_h)
    # Directly evaluate phi_opt (Nt grid) on the HNLF problem
    J_h, _ = cost_and_gradient(phi_opt, uω0_h, fiber_h, sim_h, band_mask_h; log_cost=true)

    # Transfer target 2: perturbed canonical
    transfers = Dict("HNLF_canonical" => J_h)
    for (delta_tag, modifier) in [
        ("+5pct_FWHM", Dict(:fwhm_scale=>1.05)),
        ("+10pct_P", Dict(:P_scale=>1.10)),
        ("+5pct_beta2", Dict(:β2_scale=>1.05)),
    ]
        uω0_p, fiber_p, sim_p, band_mask_p, _, _ = setup_raman_problem_perturbed(;
            fiber_preset=:SMF28, L_fiber=2.0, P_cont=0.2,
            perturbation=modifier, Nt=2^14, time_window=10.0)
        J_p, _ = cost_and_gradient(phi_opt, uω0_p, fiber_p, sim_p, band_mask_p; log_cost=true)
        transfers[delta_tag] = J_p
    end
    return transfers
end
```

---

## State of the Art

| Old approach | Current approach | When changed | Impact |
|--------------|------------------|--------------|--------|
| Full-grid φ optimization as the only path | Low-res parametric (`sweep_simple_*`) coexists | Session E / Phase 26 | Phase 35 used this; Phase 31 extends. |
| `λ_gdd = 1e-4` default in `optimize_spectral_phase` | Same default, but Phase 27 flagged its effective-weight drift | Phase 27 addendum | Phase 31 documents but does not fix; points to future seed. |
| Amplitude shaping used `build_dct_basis` with `δ · B · c` wrapping | Same, still the reuse target | Phase ~15 | Phase 31 parallels the DCT path for phase. |
| `cost_and_gradient` had linear cost/gradient | Switched to `log_cost=true` default (dB) | Phase 16 | All Phase 31 runs inherit — `f_tol = 0.01 dB`. |
| Gauge directions not measured | `gauge_fix` + `polynomial_project` in `phase13_primitives.jl` | Phase 13 | Phase 31 metrics use gauge-fixed φ. |
| Hessian analyzed only at one canonical | Phase 22 extended to 26 (config × flavor × λ) optima | Phase 22 | All indefinite — Phase 31 must not claim to produce minima without measurement. |
| Phase 31 planned as greenfield reduced-basis | Seed reframes as extension of existing DCT code | Phase 27 second-opinion defect #7 | This research honors the reframe. |

### Deprecated / outdated

- **Raw `tmux new` launches on burst VM**: replaced by `burst-run-heavy` wrapper (CLAUDE.md Rule P5, enforced since 2026-04-17). Plan 01 / 02 driver invocations MUST use the wrapper.
- **Linear-cost L-BFGS default**: `log_cost=false` is a legacy setting. All Phase 31 runs use `log_cost=true`.
- **`validate_gradient` ratio check**: works but not Taylor-remainder-grade. Phase 31 unit tests use slope checks (Phase 27 second-opinion recommendation #5 adopted).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Polynomial-chirp ladder with `order ≥ 6` can reach within ~10 dB of the full-grid optimum | §Basis Family Catalog Expressivity ordering | [ASSUMED] — extrapolated from Phase 35's `N_phi=4 → -47 dB, N_phi=128 → -68 dB` knee; order-6 / -8 are untested middle. If assumption is wrong, the interpretability story is weaker but the phase still produces a valid Pareto. |
| A2 | Tikhonov penalty at `λ = 1e-6` is a measurable but not dominating regularizer on the log-rescaled cost | §Penalty Family Catalog P1 | [ASSUMED] — based on the Phase 27 addendum analysis that the effective λ drifts ~8 orders. If the drift is larger, the `{1e-6, 1e-4, 1e-2, 1e0}` ladder may need shifting. Empirical calibration in Plan 01 Wave 1. |
| A3 | The `hess_indef_ratio` metric from Arpack `:SR` wing correctly captures saddle-masking | §Pitfall 2 | [VERIFIED: Phase 13 + Phase 35] — both phases used this metric; behavior reproducible. |
| A4 | HVP with adaptive `ε_fd = √(eps·‖∇J‖)` gives slope-2 Taylor remainder at deep (−80 dB) optima | §Pitfall 7 | [CITED: Phase 27 second-opinion defect #5] — this is the standard result from Nocedal & Wright §8.1, but not verified on the specific oracle here. Add a test in Plan 01. |
| A5 | Wall time per run ~30–90 s on burst VM at Nt=2^14 with `max_iter = 50` | §Plan / wave assignment | [VERIFIED: Session E benchmark] — `sweep_simple_run.jl` Sweep 2 measured this. |
| A6 | `save_standard_set` does not add more than ~3 s per call | §Standard images emission | [ASSUMED] — not directly benchmarked but implied by image-generation patterns in prior phases. Low risk. |
| A7 | HNLF L=0.5 m P=0.01 W is a meaningfully different transfer target from SMF-28 canonical | §Transferability | [VERIFIED: Phase 13 FINDINGS, Phase 22] — both points behave qualitatively differently (HNLF has much higher gamma / shorter nonlinear length). |
| A8 | AIC with `k ≈ N_phi - 2` correctly penalizes complexity for gauge-reduced bases | §Model-Selection Machinery §3 | [ASSUMED] — standard inverse-problems heuristic but not rigorously derived for nonlinear objectives. Interpret AIC ranking as a sorting tool, not a hypothesis test. |
| A9 | Polynomial R² metric on orders `{2, 3, 4}` gives a useful interpretability score | §Evaluation Metrics | [VERIFIED: `phase13_primitives.jl::polynomial_project` already exists and was used in Phase 13 FINDINGS] |

---

## Open Questions (RESOLVED)

All seven questions are resolved before planning. Decisions below bind Plan 01 / Plan 02.

1. **Should Phase 31 include an elastic-net (L₁+L₂ on DCT coeffs)?**
   - RESOLVED: **NO — deferred out of Phase 31.** Single-penalty variants (Tikhonov, TOD, TV, DCT-L1, GDD) cover the extremes and already fill the 21-row Branch B budget. Elastic-net is recorded as a follow-on seed in `.planning/seeds/` if Plan 02 findings motivate it.

2. **What `N_phi` values should the polynomial ladder include?**
   - RESOLVED: **Keep `{3, 4, 5, 6, 8}` (orders `{2, 3, 4, 5, 7}`) in Plan 01 Branch A.** Orders 7 and 8 overlap enough with the DCT ladder at `N_phi=8` to let the Pareto analysis detect redundancy — that is itself a useful finding. No trimming at Plan 02.

3. **Should the transferability probe re-optimize or stay forward-only?**
   - RESOLVED: **Forward-only in Plan 02.** `scripts/phase31_transfer.jl` evaluates each `phi_opt` on HNLF and perturbed canonical configs without re-running the optimizer. Measures raw transferability. Fine-tuning-transfer is deferred to a follow-on seed.

4. **Should Plan 01 or Plan 02 own the numerical trust report integration?**
   - RESOLVED: **DEFERRED out of Phase 31.** No `trust_report` field is required in the JLD2 rows. `scripts/numerical_trust.jl` was designed for `optimize_spectral_phase` (full-grid) and its schema does not match `optimize_phase_lowres` output. Integration is out of scope for this phase and is recorded as a follow-on seed. Plan 01 / Plan 02 JLD2 schemas drop `trust_report` from the required key list.

5. **Does the `hess_indef_ratio_ambient` probe work on a basis-restricted optimum?**
   - RESOLVED: **DEFERRED out of Phase 31 — coefficient-space only.** Plan 01 records `hess_indef_ratio` (coefficient-space) and `kappa_H_restricted` only. Ambient-Hessian probe (full-Nt HVP at `φ_opt = B · c_opt`) is NOT computed. Plan 02's `phase31_analyze.jl` flags every basis-restricted PSD optimum as `PSD_UNVERIFIED_AMBIENT` and explicitly surfaces this limitation in `FINDINGS.md` as an open follow-on. The ambient probe becomes a seed if any row lands with `hess_indef_ratio < 0.01`.

6. **Should we include the `TV_φ` penalty despite the physics being unusual?**
   - RESOLVED: **YES — keep `TV` in Branch B.** Low cost-to-include; a positive finding would be novel. Removal at analysis time is trivial if results are uninterpretable.

7. **Is Hermite basis worth including?**
   - RESOLVED: **NO — deferred out of Phase 31.** Phase 31 ships with 5 basis kinds (`:polynomial`, `:chirp_ladder`, `:dct`, `:cubic`, `:linear`). Hermite is a follow-on seed if Pareto analysis leaves a Gaussian-pulse-specific gap.

---

## Architectural Responsibility Check (cross-ref with `31-PATTERNS.md`)

Every proposed file matches an existing analog with "exact" or "role-match" quality:

| Proposed file | Analog | Responsibility | Quality |
|---------------|--------|----------------|---------|
| `scripts/phase31_basis_lib.jl` | `scripts/sweep_simple_param.jl` | basis construction | exact |
| `scripts/phase31_penalty_lib.jl` | `scripts/amplitude_optimization.jl::amplitude_cost` + `scripts/raman_optimization.jl::cost_and_gradient` (GDD block) | penalty functionals + gradients | exact |
| `scripts/phase31_run.jl` | `scripts/sweep_simple_run.jl` | optimization sweep driver | exact |
| `scripts/phase31_transfer.jl` | `scripts/phase14_robustness_test.jl` + `scripts/raman_optimization.jl::chirp_sensitivity` | no-reopt forward evaluation for robustness / transfer | role-match |
| `scripts/phase31_analyze.jl` | `scripts/sweep_simple_analyze.jl::pareto_front` + `scripts/phase13_gauge_and_polynomial.jl` | analysis + figures | exact |
| `test/test_phase31_basis.jl` | `test/test_phase13_primitives.jl` | contract tests | exact |

Phase 31 is strictly **recombination + benchmarking** on top of existing infrastructure. No new optimizer, no new solver, no new physics. This is the locked-decision-1 alignment.

---

## Project Constraints (from CLAUDE.md)

| Constraint | How Phase 31 honors it |
|------------|------------------------|
| `save_standard_set(...)` for every `phi_opt` | P31-G requires it; §Standard images emission makes it explicit. |
| Log-cost convention (`log_cost=true`) | All drivers use it; penalty gradients go BEFORE the rescale block. |
| `deepcopy(fiber)` per thread | §Parallelism plan mandates it. |
| Nt floor = 8192 (recommended 2^14 = 16384 for production) | `LR_BASELINE_NT = 2^14` already the Session-E default; Phase 31 inherits. |
| Burst-VM wrapper for any simulation | Plans 01 Wave 2, Plan 02 Waves 1-2 use `burst-run-heavy <TAG> 'julia -t auto ...'`. |
| Session tag format `^[A-Za-z]-[A-Za-z0-9_-]+$` | Suggested tag: `A-phase31` (or session-letter assigned in `parallel-session-prompts.md`). |
| `burst-stop` when done | Explicit in driver epilog + documented in Plan 01/02 SUMMARY checklist. |
| No edits to `scripts/common.jl`, `scripts/visualization.jl`, `src/**`, `Project.toml`, `Manifest.toml` | P31-H; verified by `git diff --stat` check at phase gate. |
| SI units everywhere | Inherited from existing functions; Phase 31 adds no new units. |
| `snake_case` + `!` for mutating + Unicode physics vars | Code-style convention; `apply_tikhonov_phi!` pattern above follows it. |
| GSD strict mode | All edits route through `/gsd-execute-phase`. |
| Phase-integrity hook | `bash scripts/check-phase-integrity.sh 31` at phase gate. |
| No secrets / env vars | None in scope. |

---

## Sources

### Primary (HIGH confidence)

- **In-repo source files** (read in full or in depth for this research):
  - `scripts/sweep_simple_param.jl` (basis machinery, simplicity metrics, continuation)
  - `scripts/sweep_simple_run.jl` (driver pattern, multistart seeds, package_result)
  - `scripts/sweep_simple_analyze.jl` (Pareto utility)
  - `scripts/amplitude_optimization.jl` (DCT basis, penalty breakdown dict, `cost_and_gradient_lowdim`)
  - `scripts/raman_optimization.jl` (cost/gradient, GDD + boundary penalties, `chirp_sensitivity`, log-cost block)
  - `scripts/phase14_robustness_test.jl` (perturbation-without-reopt pattern)
- **In-repo planning artifacts:**
  - `.planning/phases/27-numerical-analysis-audit-and-cs-4220-application-roadmap/27-REPORT.md` — full + second-opinion addendum
  - `.planning/phases/22-sharpness-research/SUMMARY.md` — 26-row Hessian-indefinite table
  - `.planning/phases/35-saddle-escape/35-SUMMARY.md` — reduced-basis verdict
  - `.planning/phases/13-optimization-landscape-diagnostics-.../13-02-SUMMARY.md` — HVP + Arpack infrastructure + gauge-mode theory
  - `.planning/phases/28-conditioning-and-backward-error-framework-for-raman-optimiza/28-SUMMARY.md` — trust-report schema
  - `.planning/phases/31-.../31-CONTEXT.md` (locked decisions)
  - `.planning/phases/31-.../31-PATTERNS.md` (pattern map)
  - `.planning/seeds/reduced-basis-phase-regularization.md`
  - `.planning/seeds/cost-surface-coherence-and-log-scale-audit.md`
- **Project root:** `CLAUDE.md` (all compute discipline, session protocol, standard image mandate, GSD strict mode)
- **Memory notes:** `project_dB_linear_fix.md` (log-cost gradient rescale)

### Secondary (MEDIUM confidence — verified via cross-reference)

- **Cornell CS 4220 S26** (https://github.com/dbindel/cs4220-s26/) — the course material referenced by Phase 27 as the framing for "regularization as model selection," "L-curve," "conditioning," "Krylov," "globalization." Specific lectures/notes not individually cited here; the framing is inherited from Phase 27's direct read of the course.
- **Bindel, *Numerical Methods for Data Science*** (https://www.cs.cornell.edu/~bindel/nmds/) — same author; adds performance-modeling discussion that Phase 27 draws on.
- **Hansen, P.C. (1999), "The L-curve and its use in the numerical treatment of inverse problems"** — standard reference for L-curve model selection.
- **Nocedal & Wright, *Numerical Optimization* (2nd ed.)** — §8.1 finite-difference Hessian step size `ε = √(eps_mach · ‖∇J‖) / ‖v‖`, referenced in Phase 27 second-opinion defect #5.
- **Hansen, P.C., *Discrete Inverse Problems: Insight and Algorithms* (SIAM 2010)** — canonical for Tikhonov / TSVD regularization. Referenced for §Penalty Family Catalog framing.
- **Akaike (1974), "A new look at the statistical model identification"** — AIC definition.
- **Schwarz (1978), "Estimating the dimension of a model"** — BIC definition.

### Tertiary (LOW confidence — framing support, not load-bearing)

- General Julia / Optim.jl / FFTW.jl documentation — used implicitly for API confirmation but not a specific citation.
- General fiber-optics references (Agrawal *Nonlinear Fiber Optics*) — for "GDD / TOD / higher-order dispersion" framing in §Basis Family Catalog physics interpretation. Standard textbook knowledge.

### Unverified-but-reasonable external claims

- The L-curve has a unique elbow for typical inverse problems (claimed in §Model-Selection Machinery §1) — Hansen documents pathological no-elbow cases; Phase 31 will accept that fallback and note in FINDINGS if an elbow isn't clean.

---

## Metadata

**Confidence breakdown:**
- Standard stack and infrastructure: HIGH — every item verified in the current repo.
- Architecture patterns: HIGH — every pattern has a cited `file:line` analog in `31-PATTERNS.md`.
- Basis family catalog: HIGH on `:dct / :cubic / :linear / :identity` (implemented); MEDIUM on `:polynomial / :chirp_ladder` (standard math but not in-repo); LOW-MEDIUM on `:hermite` (optional, less certain).
- Penalty family catalog: HIGH on `:gdd` (implemented); HIGH on `:tikhonov / :tv` (direct amplitude analog); MEDIUM on `:tod` (extends GDD pattern, gradient derivation straightforward); MEDIUM on `:dct_l1` (composition of existing pieces, smooth-L1 safety margin documented).
- Model-selection machinery: MEDIUM — L-curve and AIC are standard; their application to the nonlinear log-rescaled cost inherits the Phase 27 cost-coherence caveats.
- Pitfalls catalog: HIGH — each pitfall has a specific Phase / code reference.
- Evaluation metrics: HIGH — all metrics either exist or extend existing ones.
- Execution architecture: HIGH — mirrors `sweep_simple_run.jl` closely.
- Wall-time estimates: MEDIUM — based on Session E empirical data at similar `Nt, max_iter`.

**Research date:** 2026-04-21
**Valid until:** 2026-05-21 (30 days for stable project; extend if new Phases 36+ change the canonical-point or log-cost regime).

---

## RESEARCH COMPLETE
