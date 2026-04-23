---
title: Phase 25 verification notes — code-level audit trail
status: working_notes
created: 2026-04-20
---

# Working notes — Phase 25 claim verification

These are the working notes I used while writing the second-opinion addendum.
Every Phase 25 REPORT claim is mapped to a specific file:line check here.

Legend: ✓ verified · ≈ partially verified · ✗ wrong · ? not verified · ! missed

## Phase 25 headline claims vs code

### "Deterministic FFT environment" (REPORT §Assets.1)
- ✓ `scripts/determinism.jl:75-76` — `FFTW.set_num_threads(1)` + `BLAS.set_num_threads(1)` via `ensure_deterministic_environment()`.
- ✓ `src/simulation/simulate_disp_mmf.jl:84-87` — all four FFTW plans use `flags=FFTW.ESTIMATE`.
- ✓ `src/simulation/sensitivity_disp_mmf.jl:229-234` — same for adjoint.
- ✓ Called from `scripts/raman_optimization.jl:48` (`ensure_deterministic_environment()`).
- ! **Not flagged:** ESTIMATE-vs-MEASURE is a real performance tax (MEASURE usually ≥ 2× faster for repeated FFT plans). The determinism seed does not connect to the performance-modeling seed. This is the classic reproducibility-vs-speed tradeoff that CS 4220 / NMDS discuss explicitly.

### "Forward/adjoint validation culture" (REPORT §Assets.2)
- ✓ `scripts/raman_optimization.jl:254-285` — `validate_gradient` uses central differences at ε=1e-5, reports relative error per index.
- ✓ `scripts/amplitude_optimization.jl:553-576` — analogous FD check for amplitude.
- ✓ `scripts/hvp.jl:13-29` — `fd_hvp` uses the same central-difference style for HVP; has `validate_hvp_taylor` in API.
- ! **Not flagged:** None of these use a **Taylor-remainder-2 test** (verifying that `|J(φ+εv) − J(φ) − ε·∇J·v|` shrinks like O(ε²) as ε halves). A ratio-of-errors sanity check is weaker than an order-of-accuracy slope check and can hide a gradient that is "approximately right" but with wrong scaling.
- ≈ `validate_gradient` defaults to `log_cost=true` (line 259 → `cost_and_gradient` default at line 77), so it checks the dB gradient. That is *self-consistent*, but does not test the linear-cost gradient that `hvp.jl` later assumes.

### "Matrix-free Hessian tooling" (REPORT §Assets.3)
- ✓ `scripts/hvp.jl:83-` — `build_oracle` + `fd_hvp` (2 forward + 2 adjoint per HVP).
- ✓ `scripts/hessian_eigspec.jl:104-121` — `HVPOperator` implements the `mul!` contract for `Arpack.eigs` (i.e., Lanczos); extracts top-20 / bottom-20 wings.
- ✓ `hessian_eigspec.jl:30-33` — explicit acknowledgement that shift-invert is impossible matrix-free.
- ! **Not flagged:** `P13_DEFAULT_EPS = 1e-4` in `hvp.jl:48` is a fixed FD step. Optimal step scales as `sqrt(eps_mach · |∇J|) / ‖v‖`. At deep L-BFGS suppression (`‖∇J‖_linear` → 1e-8), a fixed 1e-4 step is way outside the sweet spot — HVP symmetry holds only "up to FD noise" per file docstring, and that noise blows up when the gradient is small. This is the regime where Newton-like curvature matters most.
- ! **Not flagged:** Oracle uses `log_cost=false, λ_gdd=0, λ_boundary=0` (line 74) → probes the **linear physics-only** Hessian. L-BFGS optimizes the **dB cost with regularization**. The eigenspectrum analyzed is therefore NOT the curvature of the objective actually being minimized. Future truncated-Newton built on this infrastructure must decide which Hessian it wants.

### "Raman overflow fix" (REPORT §Context D25-03)
- ✓ `src/helpers/helpers.jl:106-107` (and `:181-182`) — `ts_pos = max.(ts, 0.0)` before `exp.(-ts_pos * 1e15 / τ2)`. Good.

### "dB/linear cost fix" (REPORT §Context D25-03)
- ✓ `scripts/raman_optimization.jl:119-129` — `J_phys = 10·log10(J_clamped)`, `log_scale = 10 / (J_clamped · ln 10)`, `∂J_∂φ_scaled = ∂J_∂φ .* log_scale`. Matches Memory `project_dB_linear_fix`.
- ✗ **Latent bug Phase 25 missed:** `cost_and_gradient` defaults to `log_cost=true` (line 77). `chirp_sensitivity` (line 332) calls `cost_and_gradient(...)` with no `log_cost` kwarg → returns dB values → `J_gdd[i]` holds negative dB. Then `plot_chirp_sensitivity` line 361 runs `J_gdd_dB = lin_to_dB.(J_gdd)`, which is `10·log10(-40.0)` → `DomainError`. Either this code path is dead (never exercised) or it has been throwing. `scripts/raman_optimization.jl:776` does invoke it inside the canonical driver. **This needs a regression test.**
- ! **Inconsistency Phase 25 missed:** in `cost_and_gradient`, the log scaling is applied ONLY to the physics gradient (line 125). The GDD and boundary regularizer gradients are added in their linear form (lines 142-147, 171-172). So as `J → 0`, `log_scale` grows without bound and the physics gradient dominates, effectively nulling the regularizer. That may be operationally desirable (let the physics term drive deep suppression) but it is not the optimizer contract the caller sees: the user sets `λ_gdd = 1e-4` expecting a fixed weight, and gets a weight that drops by 50 dB over a 50 dB optimization. CS 4220 conditioning framing would flag this directly.

### "SPM-corrected time window + auto-sizing" (Memory `project_attenuator_time_window`)
- ✓ `scripts/common.jl:191-215` — `recommended_time_window` includes SPM term `δω_SPM = 0.86 · γ P L / T0`.
- ✓ `scripts/common.jl:348-359`, `:427-438` — both setup functions auto-upgrade `time_window` and `Nt` when requested window is too small.
- ≈ `pulse_extent = 0.5` (line 200) is a hardcoded 0.5 ps contingency. Fine for 185 fs sech², wrong for 30 fs pulses; not parameterized on `pulse_fwhm`. Low-impact but fragile.

### "Boundary-condition check" (implicit in "honest-grid thinking")
- ✓ `scripts/common.jl:289-298` — `check_boundary_conditions(ut_z, sim; threshold=1e-6)` returns `(is_ok, edge_fraction)` on the outer 5% of the time grid.
- ! **Structural gap Phase 25 missed:** the attenuator is a **super-Gaussian order-30 hard absorber at 85% window half-width** (`src/helpers/helpers.jl:59-63`). Any energy walking into the absorber is silently attenuated inside the ODE, so the edge-fraction check reports the *surviving* edge energy, not the energy that was already absorbed. There is no running "mass loss at boundary" metric. For long fibers and high powers — exactly the hard regimes Phase 25 cares about — the reported dB is the dB of a *partially-absorbed* field. This is a physics-coupled numerical honesty failure distinct from "the grid was too small"; it is present even when the recommended window formula says the grid is large enough, because the absorber eats energy anywhere outside the 85% soft edge.

### "Dict{String,Any} for sim/fiber state" (REPORT §6)
- ✓ `src/helpers/helpers.jl:65-66` (`sim` dict) and `:129` (`fiber` dict).
- ✓ Mutated in place: `fiber["zsave"]` is set to `nothing` (raman_optimization.jl:203, amplitude_optimization.jl:414, hvp.jl:89) or to a vector in `solve_disp_mmf` variants.
- ! **Also missed by Phase 25:** the unit system carried inside `sim` is hybrid: `time_window` in ps, `Δt` in ps (line 52), `ts` in **seconds** (line 53), `f0` in THz (line 51), `ω0` in rad/ps (line 55), `ε` carries `1e-12 * Δt / (h * 1e12 * f0)` (line 57). `hRt` multiplies `ts * 1e15` to convert to fs (line 107). This is the prototypical CS 4220 "nondimensionalize first" target that Phase 25 invokes abstractly but doesn't pin to the specific code.

### "L-BFGS globalization weakness" (REPORT §3 + globalization seed)
- ≈ `scripts/raman_optimization.jl:235` uses `LBFGS()` from Optim.jl — the default line search is **HagerZhang**, which already has strong Wolfe conditions + backtracking. Phase 25 framing that the project has "weak globalization" overstates the gap for 1st-order work; it is accurate only for hypothetical Newton-style work.
- ≈ `scripts/amplitude_optimization.jl:273` uses `Fminbox(LBFGS(m=10))` with true box constraints (δ_bound). Again, this is a real globalization layer, not a bare local method.
- ! **The real globalization gap** is for the indefinite-Hessian / truncated-Newton regime (when the Hessian has negative eigenvalues — which `hessian_eigspec.jl`'s bottom-K analysis is set up to detect). That is a trust-region vs. Wolfe-line-search distinction, not a "need to add line search" one.

### "Tsit5 reltol=1e-8 for both forward and adjoint"
- ✓ `src/simulation/simulate_disp_mmf.jl:182`, `:186`.
- ✓ `src/simulation/sensitivity_disp_mmf.jl:301`.
- ! **Not flagged:** no `abstol` is supplied, so the default (`1e-6`) is in force. The optimized-field Raman-shifted components at -60 dB are `|ũω| ~ 1e-3` on a baseline of `~1`; at -80 dB (Session D), `|ũω| ~ 1e-4`. A 1e-6 abstol starts to be comparable to the signal being optimized. Whether this biases gradients is an open empirical question the audit should pose.
- ! **Not flagged:** the ODE is in the interaction picture, which is an ETD-style pre-conditioning. But the "slow" interaction-picture variable still has rapid nonlinear oscillations. `Vern9()` is mentioned in the project docs (CLAUDE.md) but not used. CS 4220 / NMDS would suggest experimenting with an **exponential integrator** (ETDRK4, Magnus) directly — that is the "interaction-picture-done-right" family and may give the same accuracy at larger steps.
- ≈ `scripts/sensitivity_disp_mmf.jl:289-293` explicitly caps accuracy at Tsit5's 4th-order interpolant. That is a real and thoughtful choice, and Phase 25 does not credit it.

### "Reduced-basis / regularization seed as future work"
- ✗ **Phase 25 misframing:** a DCT reduced-basis parameterization is **already implemented** for amplitude optimization: `scripts/amplitude_optimization.jl:180-192` (`build_dct_basis`) and `:201-209` (`cost_and_gradient_lowdim`), wired through `Fminbox(LBFGS(m=10))` with bandwidth masking and gradient-validation. The reduced-basis seed should say "extend this basis machinery from amplitude to phase" rather than reading as greenfield work.

### "Planning drift as trust blocker" (REPORT §4)
- ✓ `.planning/STATE.md` references several checkpoints; a quick skim confirms cross-file drift. Not re-audited in detail here — Phase 25's claim holds.

## Additional numerical items surfaced in this pass

| # | Area | File:line | Severity | What | Missed by P25? |
|---|------|-----------|----------|------|----------------|
| A1 | Cost-surface coherence | `raman_optimization.jl:121-172` | HIGH | log_cost scales physics gradient but not regularizer gradient; at deep suppression the regularizer effectively vanishes. | Yes |
| A2 | Chirp sensitivity bug | `raman_optimization.jl:332, 361` | MEDIUM | `lin_to_dB` applied to already-dB values (domain error on negative log10). | Yes |
| A3 | Hessian / cost mismatch | `hvp.jl:74`, `raman_optimization.jl:77` | MEDIUM | HVPs probe linear physics cost; L-BFGS minimizes dB cost + regularizers. | Yes |
| A4 | FD-HVP step size | `hvp.jl:48` | MEDIUM | Fixed ε=1e-4 is wrong at convergence where ‖∇J‖ is small; need adaptive ε. | Yes |
| A5 | Absorbing boundary | `helpers.jl:59-63` | HIGH | Super-Gaussian attenuator silently absorbs edge energy; no mass-loss metric. Edge-fraction check is post-absorption. | Yes |
| A6 | ODE abstol | `simulate_disp_mmf.jl:182`, `sensitivity_disp_mmf.jl:301` | MEDIUM | Default abstol=1e-6 becomes comparable to signal at -60…-80 dB. | Yes |
| A7 | ETD vs Tsit5 | `simulate_disp_mmf.jl:182` | LOW-MEDIUM | Interaction picture is a partial ETD; full exponential integrator may outperform Tsit5 at equal accuracy. | Yes |
| A8 | Unit heterogeneity | `helpers.jl:51-57` | MEDIUM | ps / sec / THz / rad·ps⁻¹ mixed in `sim` dict; classic nondimensionalization target. | Partially (framing abstract) |
| A9 | Reduced basis exists | `amplitude_optimization.jl:180-209` | LOW (framing) | DCT machinery already available; seed should extend not greenfield. | Yes |
| A10 | Taylor remainder 2 | `raman_optimization.jl:254-285` | LOW | Ratio check only; no O(ε²) slope verification. | Yes |
| A11 | Globalization framing | `raman_optimization.jl:235`, `amplitude_optimization.jl:273` | FRAMING | L-BFGS+HagerZhang and Fminbox already provide globalization for 1st-order; real gap is trust-region for indefinite 2nd-order. | Yes |
| A12 | `clamp!(A, 1e-6, Inf)` | `amplitude_optimization.jl:206` | LOW | Non-smooth barrier can stall gradient methods if hit. | Yes |
| A13 | `factorial(n)` in Dω | `helpers.jl:187` | LOW | Julia `factorial(Int)` overflows at n=21; current β_order ≤ 12 is safe; docs don't note the cliff. | Yes |
| A14 | Condition-number probe | (missing) | LOW-MED | Arpack already extracts top-K and bottom-K eigenvalues; a κ = λ_max / λ_min_nonzero per run would be cheap and a trust-report metric. | Yes |
| A15 | Regularizer λ on dB scale | `raman_optimization.jl:443-447` | MED | `λ_gdd=1e-4` is hardcoded; per A1 its effective weight is state-dependent, not fixed. | Yes |
| A16 | `analysis.jl` status | `src/analysis/analysis.jl` | LOW (not a numerics bug) | Phase 25 says "marked broken". Code itself parses and is used by at least one notebook. "Broken in planning" is a planning-drift symptom, not a live numerical defect. | Partially |

## Seeds status

Existing (`.planning/seeds/`):
1. `numerics-conditioning-and-backward-error-framework.md`
2. `globalized-second-order-optimization.md`
3. `truncated-newton-krylov-preconditioning.md`
4. `reduced-basis-phase-regularization.md`
5. `continuation-and-homotopy-schedules.md`
6. `performance-modeling-and-roofline-audit.md`
7. `extrapolation-and-acceleration-for-parameter-studies.md`

Candidate new seeds worth writing:
- **`cost-surface-coherence-and-log-scale-audit.md`** — unify log_cost / linear cost / HVP-oracle / regularizer-gradient conventions. Fixes A1–A3, A15 together. Not covered by existing seeds because each existing seed scopes a *method*; this seed scopes an *interface contract across methods*. Phase-sized because it touches raman_optimization, amplitude_optimization, phase13_hvp, chirp_sensitivity, and the trust-report convention simultaneously.
- **`absorbing-boundary-and-honest-edge-energy.md`** — replace super-Gaussian attenuator with a tracked absorber or PML-style layer; expose edge-absorption as a running trust metric. Fixes A5. Not covered by existing seeds.

Candidate rejected:
- Adjoint tolerance / ETD experiment → subsumed by conditioning seed.
- Adaptive FD-HVP ε (A4) → subsumed by truncated-Newton-Krylov seed.
- Taylor-remainder test (A10) → subsumed by conditioning seed.

## Second-opinion rankings (used to draft the addendum)

### Top 5 numerical risks (by blast radius × likelihood)
1. **Cost-surface incoherence** (A1 + A3 + A15): dB vs linear scale is not one convention; regularizer weights are state-dependent in practice; Hessian is probed on a different cost than the one L-BFGS minimizes. Contaminates any future Newton/Hessian-aware work.
2. **Absorbing boundary silently eats energy** (A5): dB improvements in long-fiber / high-power regimes are partly artifacts of which edge energy got absorbed. Not caught by edge-fraction check.
3. **Chirp sensitivity latent bug** (A2): canonical driver calls `plot_chirp_sensitivity` with dB values passed to `lin_to_dB`; domain error. Either dead code or throws on every full run.
4. **Planning drift** (Phase 25 original): stays on the list, unchanged.
5. **Scaling / conditioning of φ variable** (Phase 25 original + A8): mixed SI ↔ ps ↔ THz units in `sim` dict are the specific nondimensionalization target.

### Top 5 highest-leverage improvements
1. Cost-surface coherence audit (A1+A2+A3+A15) — small scope, catches a real bug and a conceptual error.
2. Extend DCT reduced-basis machinery from amplitude → phase (A9) — cheap, reuses existing code, directly tests Phase 25's "over-parameterized full grid" hypothesis.
3. Trust-report bundle with edge-absorption metric (A5 + Phase 25 original) — turns existing diagnostics into a standing acceptance gate.
4. Adaptive FD-HVP step (A4) — unlocks meaningful curvature probes near convergence, the exact regime where truncated-Newton is supposed to help.
5. Taylor-remainder-2 tests for all gradient validation paths (A10) — a few dozen lines, catches the kind of bugs that hide behind self-consistent FD ratios.

### Single most important next numerics phase
**Conditioning + cost-surface coherence + trust-report bundle — one phase, not three.**
The existing `numerics-conditioning-and-backward-error-framework` seed is the right *direction* but too narrow. Promote it to a bundle that explicitly includes (a) log/linear cost convention unification across cost_and_gradient, phase13_hvp oracle, regularizers, and diagnostics; (b) adaptive FD-HVP ε; (c) running edge-absorption metric; (d) per-run condition-number probe (cheap, given Arpack infra); (e) Taylor-remainder-2 tests. Only after this does a truncated-Newton / sharpness / globalization phase make sense — otherwise the comparison is on an unstable footing.
