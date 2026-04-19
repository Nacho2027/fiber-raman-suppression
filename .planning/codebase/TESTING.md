# Testing Patterns

**Analysis Date:** 2026-04-19

This refreshes the 2026-04-05 version. The big structural change since then is the
**Session B tiered-test system**: `test/runtests.jl` is now a dispatcher that
selects `test/tier_{fast,slow,full}.jl`, and the `Makefile` exposes three
corresponding targets (`make test`, `make test-slow`, `make test-full`). The
pre-Session-B minimal smoke test is gone.

## Test Framework

**Runner:**
- Julia's built-in `Test.jl` stdlib (`using Test`, `@testset`, `@test`, `@test_throws`, `@test_skip`)
- No external frameworks (no ReTest, no SafeTestsets). `[extras] Test` is the only test dependency in `Project.toml`
- Regression artifacts (Phase 13 vanilla snapshot, FFTW wisdom file under `results/raman/phase14/`) are committed to git and re-used across runs

**Tiered entry points (new — 2026-04-17+):**

| Tier | Wall time | Runs where | Command | What it catches |
|------|-----------|-----------|---------|----------------|
| `fast` | ≤30 s, simulation-free | anywhere (Mac, claude-code-host, burst) | `make test` | Key Bug #2 (SPM time-window formula), output-format round-trip, determinism helper idempotence |
| `slow` | ~5 min | **burst VM only** (Rule 1) | `make test-slow` | Key Bug #1 (dB/linear cost), end-to-end SMF-28 J_final_dB < -40, Taylor-remainder gradient slope ≈ 2, Phase 13 primitives + HVP |
| `full` | ~20 min | burst VM | `make test-full` | Everything in slow + Phase 15 determinism + Phase 14 regression/sharpness + cross-process bit-identity (spawns two Julia subprocesses) |

The dispatcher is `test/runtests.jl`:

```julia
tier = lowercase(get(ENV, "TEST_TIER", "fast"))
if !(tier in ("fast", "slow", "full"))
    throw(ArgumentError("TEST_TIER=$tier unrecognized; ..."))
end
include(joinpath(@__DIR__, "tier_$(tier).jl"))
```

Default tier is `fast` when the env var is unset — so `julia test/runtests.jl` and `make test` both hit the pre-commit gate.

**Run commands (verbatim, from the Makefile):**

```bash
# Fast pre-commit gate — simulation-free, runs anywhere in ~30 s
make test
# Equivalent: TEST_TIER=fast julia --project=. test/runtests.jl

# Slow regression — burst VM
make test-slow
# Equivalent: TEST_TIER=slow julia -t auto --project=. test/runtests.jl

# Full regression including cross-process determinism — burst VM
make test-full
# Equivalent: TEST_TIER=full julia -t auto --project=. test/runtests.jl
```

`-t auto` is mandatory for slow/full because the end-to-end test takes 5 min on one thread and ~1 min on the 22-core burst VM. Never launch bare `julia` for simulation-touching tests (Rule 2).

## Test File Organization

**Location:**
- All regression tests live under `test/` — this is the canonical spot now
- `test/tier_{fast,slow,full}.jl` — the three tiers (own their own `@testset` blocks)
- `test/test_*.jl` — topic-specific suites wired into the tiers via `include`:
  - `test_cost_audit_{unit,analyzer,integration_A}.jl` (Session H)
  - `test_determinism.jl` (Phase 15)
  - `test_phase13_{primitives,hvp}.jl` (Phase 13 geometry)
  - `test_phase14_{regression,sharpness}.jl` (Phase 14 regression)
  - `test_phase16_mmf.jl` (MMF cost/gradient)
- Legacy under `scripts/` (still run-ably standalone, not wired to `make test`):
  - `scripts/test_optimization.jl` — the 978-line original TDD-driven suite for SMF cost/gradient + optimization pipeline
  - `scripts/test_visualization_smoke.jl` — 328-line smoke test for `visualization.jl` (uses a mock `MultiModeNoise` module so it runs without the solver)
  - `scripts/test_multivar_{unit,gradients}.jl` — Session A multivariable-optimization unit tests (`test_multivar_unit.jl` is pure unit and safe to run on claude-code-host; `test_multivar_gradients.jl` calls the solver)
- `scripts/verification.jl` — research-grade physics validation at production grid size (Nt=2^14). Separate from the test tiers because runtime is 10–30 min per VERIF case.

**File size distribution (wc -l):**

| File | Lines | Role |
|------|------:|------|
| `scripts/test_optimization.jl` | 978 | Legacy TDD suite (RED/GREEN/REFACTOR log at top) |
| `scripts/test_visualization_smoke.jl` | 328 | Plot-code assertions |
| `test/test_phase14_sharpness.jl` | 260 | Phase 14 sharpness regression |
| `test/test_phase13_primitives.jl` | 204 | Phase 13 Hessian primitives |
| `test/tier_fast.jl` | 176 | Fast tier |
| `test/test_phase16_mmf.jl` | 167 | MMF cost/gradient |
| `test/test_phase13_hvp.jl` | 158 | Phase 13 HVP |
| `test/test_phase14_regression.jl` | 151 | Phase 14 regression (tolerance-based, NOT byte-identity) |
| `scripts/test_multivar_gradients.jl` | 148 | Multivar gradient FD check |
| `test/test_determinism.jl` | 131 | Same-process bit-identity |
| `test/test_cost_audit_unit.jl` | 123 | Cost-audit unit gates |
| `test/tier_slow.jl` | 109 | Slow tier |
| `scripts/test_multivar_unit.jl` | 101 | Multivar pure unit |
| `test/test_cost_audit_integration_A.jl` | 90 | Cost-audit integration |
| `test/tier_full.jl` | 77 | Full tier (wraps slow + cross-process) |
| `test/test_cost_audit_analyzer.jl` | 71 | Cost-audit analyzer |
| `test/runtests.jl` | 23 | Tier dispatcher |

**Naming:**
- Test files use `test_` prefix
- Test suites use `@testset "Descriptive phrase — more detail"` with an em-dash separator
- Top-level testset banners call out the phase/plan: `"Phase 16 — fast tier"`, `"Phase 16 cost audit — unit"`, `"Key Bug #1 regression — dB/linear cost returns linear J"`

**Structure (AAA pattern):**

```julia
@testset "Category name" begin
    @testset "Specific property — human description" begin
        # Arrange
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
            fiber_preset=:SMF28, Nt=2^10, time_window=10.0,
            L_fiber=0.5, P_cont=0.05, β_order=3)
        φ0 = zeros(sim["Nt"], sim["M"])

        # Act
        result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
                                         φ0=φ0, max_iter=5,
                                         store_trace=true, log_cost=true)

        # Assert
        phi_opt = reshape(Optim.minimizer(result), sim["Nt"], sim["M"])
        J_linear, _ = cost_and_gradient(phi_opt, uω0, fiber, sim, band_mask;
                                        log_cost=false)
        @test 0.0 <= J_linear <= 1.0
        @test isfinite(J_linear)
    end
end
```

## Test Tier Contents

**Tier fast — `test/tier_fast.jl` (≤30 s, simulation-free):**

Three `@testset`s, all simulation-free:

1. **"SPM time window formula (Key Bug #2)"** — pins `recommended_time_window()` to the post-2026-03-31 formula (`δω_SPM = 0.86 × φ_NL / T0`). Checks (a) exact match with the fixed closed-form, (b) SPM correction is observable (≥10 ps after safety×2 in HNLF regime), (c) pre-bug formula is detectably different — regression guard.
2. **"Output format round trip (D2 schema)"** — `save_run` → `load_run` round-trip in a `mktempdir()`, asserts `phi_opt`, `uω0`, `uωf`, `convergence_history`, `schema_version`, JSON-sidecar resolution.
3. **"Determinism helper smoke test (Phase 15)"** — calls `ensure_deterministic_environment()` twice, confirms `fftw_threads == 1`, `blas_threads == 1`, and idempotency.

Import note: `using MultiModeNoise` is pulled in at the top of `tier_fast.jl` because `scripts/common.jl` needs it to resolve, but no ODE solves are triggered.

**Tier slow — `test/tier_slow.jl` (~5 min, burst VM):**

1. **"Key Bug #1 regression — dB/linear cost returns linear J"** — small-grid (Nt=2^11) canonical SMF-28, 3 L-BFGS iterations, verifies that recomputing the cost with `log_cost=false` yields linear `J ∈ [0, 1]`. Catches anyone who accidentally ships the optimizer-internal dB value as if it were linear.
2. **"End-to-end SMF-28 canonical — J_final_dB < -40"** — production-like Nt=2^13, `time_window=12`, `L_fiber=2.0`, `P_cont=0.2`, 30 iters. Asserts `J_final_dB < -40.0` (sanity bound — the canonical run reaches ~-45 dB).
3. **"Taylor-remainder gradient check (smoke)"** — small grid; residuals at `ε ∈ {1e-2, 1e-3, 1e-4}`; log-log slope between 1.7 and 2.3 (the O(ε²) signature of a correct adjoint).
4. Includes `test_phase13_primitives.jl` and `test_phase13_hvp.jl`.

Slow tier pattern to notice: it `include`s `determinism.jl` and calls `ensure_deterministic_environment()` BEFORE `include`ing the pipeline, so FFTW/BLAS threads are pinned before any plan is built.

**Tier full — `test/tier_full.jl` (~20 min, burst VM):**

1. Re-runs the slow tier verbatim.
2. `test_determinism.jl` — same-process bit-identity (two runs in one Julia process, same seed → `max(abs.(Δφ)) == 0.0`).
3. `test_phase14_regression.jl` — loads the pre-Phase-14 vanilla snapshot (`results/raman/phase14/vanilla_snapshot.jld2`) and re-runs the same config. Tolerance-based, NOT byte-identical across processes: `max(|Δφ|) < 0.1 rad`, `|ΔJ_dB| < 0.5 dB`, `|Δiter| ≤ 3`. This tolerance is calibrated ~10× below the Phase 13 observed cross-process drift (1.04 rad, 1.83 dB) and is the deliberate gate.
4. `test_phase14_sharpness.jl` — Phase 14 sharpness regression.
5. **Cross-process bit-identity** — writes a minimal Julia script to a tempfile, `run`s it twice with identical args, compares line-by-line. This is the strongest determinism gate and depends on Phase 15's `FFTW.ESTIMATE` swap.

## Test Patterns

**Contract-violation testing (`@test_throws`):**

```julia
@test_throws AssertionError setup_raman_problem(Nt=100)           # not power of 2
@test_throws ArgumentError  get_disp_fiber_params_user_defined(L_fiber=-1.0)
@test_throws ArgumentError  sanitize_variables(())                # empty
@test_throws ArgumentError  sanitize_variables((:mode_coeffs,))   # nothing left
```

This mirrors the `@assert` / `throw(ArgumentError(...))` split in the source:
`AssertionError` for design-by-contract internal invariants, `ArgumentError` for
user-facing parameter rejection.

**Gradient validation via finite-difference agreement:**

```julia
for trial in 1:5
    φ_pert = randn(Nt)
    ε = 1e-5

    J_ref, ∂J_ref = cost_and_gradient(φ, uω0, fiber, sim, band_mask)

    J_plus, _ = cost_and_gradient(φ .+ ε .* φ_pert, uω0, fiber, sim, band_mask)
    grad_fd       = (J_plus - J_ref) / ε
    grad_analytic = real(dot(φ_pert, ∂J_ref))

    @test abs(grad_fd - grad_analytic) / abs(grad_analytic + 1e-10) < 0.01
end
```

**Taylor-remainder test (O(ε²) convergence — the adjoint-correctness gold standard):**

```julia
ε_values  = [1e-2, 1e-3, 1e-4]
residuals = Float64[]
for ε in ε_values
    Jp, _ = cost_and_gradient(φ .+ ε .* δφ, uω0, fiber, sim, band_mask;
                              log_cost=false)
    push!(residuals, abs(Jp - J0 - ε * dot(∇J, δφ)))
end
slope = (log(residuals[1]) - log(residuals[end])) /
        (log(ε_values[1])  - log(ε_values[end]))
@test 1.7 < slope < 2.3   # expected slope = 2.0 for an exact gradient
```

Appears in `tier_slow.jl` (smoke), `test_phase16_mmf.jl` (MMF M=6), and
`scripts/verification.jl` (production Nt=2^14). Slope ≈ 2 is the signature
of a correct first-order adjoint gradient.

**Same-process bit-identity (Phase 15 determinism):**

```julia
ensure_deterministic_environment(verbose=true)
Random.seed!(42)
result_a = optimize_spectral_phase(...)
Random.seed!(42)
result_b = optimize_spectral_phase(...)   # same process, second call
phi_a = Optim.minimizer(result_a)
phi_b = Optim.minimizer(result_b)
@test maximum(abs.(phi_a .- phi_b)) == 0.0   # BYTE-IDENTICAL
```

**Cross-process bit-identity (full tier only):**
Writes a short Julia script, `run`s it in two fresh subprocesses via `Base.julia_cmd()`, compares output files line-by-line. Depends on `FFTW.ESTIMATE` (deterministic plan selection) and single-threaded FFTW/BLAS (deterministic reduction order).

**Skip guards for work-in-progress gates:**

```julia
if !_CA_READY
    @test_skip "cost_audit_noise_aware.jl not yet present (Task 2)"
else
    # actual assertions
end
```

Used in `test_cost_audit_unit.jl` to gracefully degrade when a planned companion
script is not yet on disk, without failing the tier.

**Legacy TDD log (historical context):**
`scripts/test_optimization.jl` lines 15–57 document 13 RED/GREEN/REFACTOR cycles
that drove the contract-programming conversion of `common.jl`. Read it when
adding new contracts — it explains why certain `@assert`s exist.

## Mocking

**Framework:** none. Julia's duck typing and a handful of hand-written mocks.

**Mock patterns in use:**
- `scripts/test_visualization_smoke.jl` defines an inline `module MultiModeNoise` stub with just `meshgrid`, `lin_to_dB`, and a `solve_disp_mmf` that returns `randn`-populated arrays. This lets the visualization smoke test exercise all plotting code without the ODE solver — critical for the "safe on claude-code-host" posture.
- Tiny test problems via `make_test_problem(; Nt=2^8, L=0.1, P=0.05, tw=5.0)` in `scripts/test_optimization.jl` — reproducible defaults, small grids.
- `mktempdir() do dir ... end` for scratch JLD2/JSON paths; no filesystem side-effects leak between tests.

**What NOT to mock (explicit policy):**
- ODE solver (`DifferentialEquations.jl`) — verified library, trust it
- FFT (`FFTW.jl`) — verified library; pin threads/flags instead
- BLAS/LAPACK — same; pin threads for determinism
- Gradient computation — validate via finite-difference agreement and Taylor remainder, not by mocking

## Fixtures and Factories

**Test-problem factories (defined in `scripts/test_optimization.jl`):**

```julia
function make_test_problem(; Nt=2^8, L=0.1, P=0.05, tw=5.0)
    return setup_raman_problem(
        Nt=Nt, L_fiber=L, P_cont=P, time_window=tw,
        β_order=2, gamma_user=0.0013, betas_user=[-2.6e-26],
    )
end

function measure_fwhm(t_arr, intensity)
    peak      = maximum(intensity)
    half_max  = peak / 2.0
    above     = findall(intensity .> half_max)
    isempty(above) && return 0.0
    return t_arr[above[end]] - t_arr[above[1]]
end

function significant_spectral_indices(uω0; frac=0.01)
    power = vec(sum(abs2.(uω0), dims=2))
    return findall(power .> frac * maximum(power))
end
```

No shared fixtures module. Each top-level test file defines the helpers it needs locally.

**Committed regression artifacts:**
- `results/raman/phase14/vanilla_snapshot.jld2` — pre-Phase-14 reference for `test_phase14_regression.jl`
- `results/raman/phase14/fftw_wisdom.txt` — FFTW wisdom cache imported by `test_cost_audit_unit.jl` and `test_phase14_regression.jl` for plan-selection stability

**Seeds:**
Constants are used when reproducibility is required, all defined at file top:
- `PHASE16_SEED = 20260417` — `test/test_phase16_mmf.jl`
- `Random.seed!(42)` — the slow-tier canonical-run convention (matches `test_determinism.jl`)
- `Random.seed!(0)` — the Taylor-remainder gradient smoke test

## Coverage

**Requirements:** none enforced. Coverage is empirical and documented per-file in
test-file docstrings and CLAUDE.md.

**What IS covered (post-Session-B):**

| Component | Location | Tier | Method |
|-----------|----------|------|--------|
| `spectral_band_cost` | `scripts/common.jl` | fast (implicit) + `test_optimization.jl` | 6 unit tests |
| `recommended_time_window` | `scripts/common.jl` | fast | exact-formula check + bug-regression guard |
| `save_run`/`load_run` (D2 schema) | `scripts/polish_output_format.jl` | fast | round-trip |
| `ensure_deterministic_environment` | `scripts/determinism.jl` | fast | idempotence smoke |
| `cost_and_gradient` log/linear interface | `scripts/raman_optimization.jl` | slow | Key Bug #1 regression |
| End-to-end SMF-28 optimization | canonical stack | slow | `J_final_dB < -40` |
| Adjoint gradient correctness (SMF) | `src/simulation/sensitivity_disp_mmf.jl` | slow | Taylor-remainder slope ≈ 2 |
| Adjoint gradient correctness (MMF) | `src/mmf_cost.jl` | `test_phase16_mmf.jl` | Taylor + FD at M=6 |
| Phase 13 Hessian primitives | `scripts/phase13_primitives.jl` | slow | unit tests |
| HVP correctness | `scripts/phase13_hvp.jl` | slow | unit tests |
| Same-process determinism | full stack | full | byte-identity |
| Cross-process determinism | full stack | full | spawn 2 subprocesses, compare |
| Phase 14 vanilla regression | committed snapshot | full | tolerance-based (documented) |
| Multivar pack/unpack/sanitize | `scripts/multivar_optimization.jl` | none (run manually) | `test_multivar_unit.jl` |
| Multivar gradients | same | none (run manually) | `test_multivar_gradients.jl` |
| Visualization functions | `scripts/visualization.jl` | none (run manually) | `test_visualization_smoke.jl` (25 tests, mock `MultiModeNoise`) |
| Physics soliton / photon conservation | full stack | separate | `scripts/verification.jl` @ Nt=2^14 |

**What is NOT covered:**
- Notebooks under `notebooks/` — not auto-tested
- `src/gain_simulation/gain.jl` YDFA model — no regression tests; exercised only by notebook runs
- Session-specific drivers (`longfiber_*`, `sweep_simple_*`) have no dedicated tests; relied on for producing artifacts, with correctness checked via the standard-images review and sweep-report diffs

## Test Types

**Unit tests (fast):** single function, synthetic inputs, direct assertions. Nt=2^8 or pure-algebra (e.g., `sanitize_variables`). <1 s each.

**Contract tests (fast):** `@test_throws AssertionError` / `@test_throws ArgumentError` for invalid inputs — enforces the design-by-contract style.

**Property-based tests (fast):** invariants over random inputs. `J ∈ [0, 1]` across 20 random `uωf`. Gradient-FD agreement across 5 random φ perturbations.

**Stateless-design tests (fast):** verify that `cost_and_gradient` does not mutate the `fiber` Dict (the "deepcopy safety" check — regression guard for a real bug that bit the project earlier).

**Integration tests (slow):** full `setup_raman_problem` → `optimize_spectral_phase` → result validation. Nt=2^11 or 2^13, 3–30 L-BFGS iters.

**Gradient-correctness tests (slow):** Taylor-remainder slope ≈ 2 + finite-difference agreement. The adjoint-correctness gold standard.

**Determinism tests (full):** same-process byte-identity and cross-process byte-identity. Phase 15 gates.

**Physics-validation tests (separate — `scripts/verification.jl`):** Nt=2^14 at production fidelity. VERIF-01 soliton shape (N=1 period), VERIF-02 photon-number conservation across 5 configs, VERIF-03 adjoint Taylor-remainder slope, VERIF-04 direct-integration vs `spectral_band_cost`. Not wired to `make test-full` because runtime is 10–30 min per case — the group runs these manually at milestones.

## Running tests — practical recipes

**Local Mac / claude-code-host (no burst VM):**

```bash
make test                           # fast tier; default when TEST_TIER unset
julia --project=. scripts/test_multivar_unit.jl         # pure-unit multivar
julia --project=. scripts/test_visualization_smoke.jl   # plotting smoke
```

Do NOT run `make test-slow` or `make test-full` on claude-code-host — they call
the solver and violate Rule 1 (and they will noticeably slow down any other
Claude Code session sharing the VM).

**Burst VM (heavy regression):**

Follow Rule P5 — always go through `~/bin/burst-run-heavy`, never launch
`tmux new` raw:

```bash
# From claude-code-host:
burst-start
burst-ssh "~/bin/burst-status"                            # verify lock is free

burst-ssh "cd fiber-raman-suppression && git pull && \
           ~/bin/burst-run-heavy B-tests \
           'make test-slow'"

burst-ssh "tail -f fiber-raman-suppression/results/burst-logs/B-tests_*.log"
# ... when done ...
burst-stop
```

Use `make test-full` instead of `make test-slow` at milestone checkpoints (pre-merge, pre-release), because the cross-process bit-identity test is the strongest determinism gate and takes an extra ~15 min to spawn the subprocess pair.

**Physics verification (manual milestone run):**

```bash
burst-ssh "cd fiber-raman-suppression && git pull && \
           ~/bin/burst-run-heavy B-verif \
           'julia -t auto --project=. scripts/verification.jl'"
```

Runtime 30–60 min. Produces VERIF-01..04 reports under `results/verification/`.

---

## Divergence notes (versus 2026-04-05 doc)

- The 2026-04-05 doc listed `test/runtests.jl` as a 1-assertion smoke test. It is now a 23-line tier dispatcher. The old smoke test is gone.
- The 2026-04-05 doc did not mention `Makefile` targets (there was no Makefile). Session B added the `install / test / test-slow / test-full / optimize / sweep / report / clean` target set.
- The 2026-04-05 doc treated `scripts/test_optimization.jl` as the primary test entry. It is still valuable as reference (and the TDD log is historically significant) but is NO LONGER wired into `make test`. New tests go under `test/`, not under `scripts/`.
- Phase 15 determinism infrastructure (`scripts/determinism.jl`, `FFTW.ESTIMATE` swap, single-threaded FFTW/BLAS) is entirely post-2026-04-05 and is now a precondition for both slow and full tiers.
- Tolerance-based regression in `test_phase14_regression.jl` (`max|Δφ| < 0.1 rad`, `|ΔJ_dB| < 0.5 dB`) is a deliberate compromise documented in the test docstring — do not "tighten" it without first checking `results/raman/phase13/determinism.md`, which explains why byte-identity is impossible across processes under the original `FFTW.MEASURE` path. The full tier's cross-process subprocess test is what actually nails bit-identity end-to-end.

---

*Testing analysis: 2026-04-19. Reflects Session B tiered-test restructure, Phase 15 determinism, and Phase 16 cost-audit / MMF work.*
