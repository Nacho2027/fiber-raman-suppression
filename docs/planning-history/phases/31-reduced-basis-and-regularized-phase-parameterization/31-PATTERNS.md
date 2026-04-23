# Phase 31: Reduced-basis and regularized phase parameterization — Pattern Map

**Mapped:** 2026-04-21
**Files analyzed:** 8 expected new/modified files (inferred — CONTEXT.md defers detail to the research step)
**Analogs found:** 8 / 8 — all patterns already exist in the repo

---

## Pattern-map scope caveat

`31-CONTEXT.md` explicitly locks only four decisions; it DOES NOT list files. `31-RESEARCH.md` is the thin outline the Research Directive says must be expanded before `01-PLAN.md`. The file list below is inferred from:

- **Locked decision 1** — "extends existing basis infrastructure before inventing new basis code" → new driver under an owned `phase31` namespace, consuming `scripts/sweep_simple_param.jl`.
- **Locked decision 2** — "amplitude DCT path is the first reuse target for phase reduction" → phase-side DCT helper parallels `build_dct_basis` in `scripts/amplitude_optimization.jl`.
- **Locked decision 3** — "explicit basis restriction and penalty-based regularization are compared, not conflated" → two driver branches (basis-restricted vs penalty-on-full-grid) plus an analysis/Pareto script.
- **Locked decision 4** — "interpretability, robustness, transferability matter as much as best dB" → simplicity metrics (already in `sweep_simple_param.jl`), transfer/robustness probe (analog: `chirp_sensitivity` + `robustness_test.jl`).
- **Seed** `.planning/seeds/reduced-basis-phase-regularization.md`.

**The planner should confirm this file list during expansion of `31-RESEARCH.md`; if it adds/removes files, re-run the mapper.** Until then, every entry below has a concrete analog in the codebase so the planner can start from copy-with-edits rather than greenfield scaffolding.

---

## File Classification

| New / modified file | Role | Data flow | Closest analog | Match quality |
|---|---|---|---|---|
| `scripts/basis_lib.jl` | library (extension) | transform | `scripts/sweep_simple_param.jl` | exact |
| `scripts/penalty_lib.jl` | library (regularizer) | transform | `scripts/amplitude_optimization.jl` `amplitude_cost` + `scripts/raman_optimization.jl` `λ_gdd` block | exact |
| `scripts/run.jl` | driver / sweep | batch | `scripts/sweep_simple_run.jl` | exact |
| `scripts/analyze.jl` | analysis / figures | transform | `scripts/sweep_simple_analyze.jl` + `scripts/gauge_and_polynomial.jl` | exact |
| `scripts/transfer.jl` | driver (robustness) | batch | `scripts/robustness_test.jl` + `chirp_sensitivity` in `scripts/raman_optimization.jl` | role-match |
| `test/test_phase31_basis.jl` | test | assertion | `test/test_primitives.jl` | exact |
| `.planning/phases/31-.../01-PLAN.md` (expanded) | doc | n/a | `.planning/phases/30-*/01-PLAN.md` (nearest prior phase) | doc-convention |
| `results/raman/phase31/**` (output tree) | data | file-I/O | `results/raman/phase_sweep_simple/` (from Session E) | exact |

Notes:
- `sweep_simple_param.jl` already contains `build_phase_basis(Nt, N_phi; kind=:cubic/:dct/:linear/:identity, bandwidth_mask)`, `cost_and_gradient_lowres`, `optimize_phase_lowres`, `continuation_upsample`, and the simplicity metrics `phase_neff / phase_tv / phase_curvature`. Per locked decision 1, **new basis code for Phase 31 must extend this file (or include it), NOT re-implement basis construction**. `basis_lib.jl` is for Phase-31-specific additions (e.g., polynomial / Hermite / B-spline kinds, or a reduced-chirp-ladder basis if the expanded research motivates it).
- Amplitude DCT in `amplitude_optimization.jl:180 build_dct_basis` is the *reuse target* called out in locked decision 2. The equivalent phase-side path **already exists** as `:dct` kind in `sweep_simple_param.jl:154-170`. Phase 31 should use it directly — the "reuse" is confirming this already-wired path meets the phase-31 requirements, not cloning `build_dct_basis` again.

---

## Pattern Assignments

### `scripts/basis_lib.jl` (library extension, transform)

**Analog:** `scripts/sweep_simple_param.jl`

**Imports / includes pattern** (`sweep_simple_param.jl:57-63`):
```julia
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "raman_optimization.jl"))

const _SWEEP_SIMPLE_PARAM_JL_LOADED = true
```
Phase 31 equivalent: include `sweep_simple_param.jl` (transitively pulls in `common.jl` + `raman_optimization.jl`), add include-guard `const _PHASE31_BASIS_LIB_JL_LOADED = true`, use the `P31_` constant prefix.

**Basis-construction pattern — the canonical cosine/spline path to extend** (`sweep_simple_param.jl:106-180`):
```julia
function build_phase_basis(Nt::Int, N_phi::Int;
                           kind::Symbol = LR_DEFAULT_KIND,
                           bandwidth_mask::Union{Nothing,AbstractVector{Bool}} = nothing)
    @assert Nt > 0 "Nt must be positive"
    @assert N_phi ≥ 1 "N_phi must be ≥ 1"

    if kind === :identity
        @assert N_phi == Nt ":identity basis requires N_phi == Nt ..."
        return Matrix{Float64}(I, Nt, Nt)
    end
    # ... :cubic / :linear / :dct branches, bandwidth-masked in fftshifted space ...
    _sanity_check_basis(B)
    return B
end
```
For new `:polynomial` / `:hermite` / `:chirp_ladder` kinds, append a branch to `build_phase_basis` (upstream edit to `sweep_simple_param.jl` if owned by this session, otherwise a thin wrapper in `basis_lib.jl` that dispatches on `kind` and falls back to the existing implementation). Reuse `_sanity_check_basis(B)` for condition-number + Gram-matrix checks.

**Cost/gradient wrapper pattern** (`sweep_simple_param.jl:228-246`):
```julia
function cost_and_gradient_lowres(c::AbstractVector{<:Real}, B::AbstractMatrix{<:Real},
                                  uω0::AbstractMatrix{<:Complex}, fiber, sim,
                                  band_mask::AbstractVector{Bool};
                                  kwargs...)
    Nt, M = size(uω0)
    N_phi = size(B, 2)
    @assert size(B, 1) == Nt
    @assert length(c) == N_phi * M

    c_mat = reshape(c, N_phi, M)
    φ = B * c_mat
    J, ∂J_∂φ = cost_and_gradient(φ, uω0, fiber, sim, band_mask; kwargs...)
    ∂J_∂c = B' * ∂J_∂φ
    return J, vec(∂J_∂c)
end
```
This already chains through the full-grid adjoint gradient — no re-derivation needed for any new basis; `φ = B·c`, `∂J/∂c = Bᵀ·∂J/∂φ` is universal.

**Optimizer driver pattern** (`sweep_simple_param.jl:284-367`): copy the `optimize_phase_lowres` `only_fg!` block, including `fiber["zsave"] = nothing`, pre-allocated `uω0_shaped` / `uωf_buffer`, and the NamedTuple return shape `(c_opt, phi_opt, J_final, iterations, converged, B, kind, N_phi, result)`.

---

### `scripts/penalty_lib.jl` (library regularizer, transform)

**Analog 1 — Tikhonov / TV / flatness on a coefficient-space variable:** `scripts/amplitude_optimization.jl:55-155`

**Regularizer structure** (`amplitude_optimization.jl:64-105`):
```julia
function amplitude_cost(A, uω0, J_raman, grad_raman;
    λ_energy=1.0, λ_tikhonov=0.001, λ_tv=0.0001, λ_flat=0.0)
    J_total = J_raman
    grad_total = copy(grad_raman)
    breakdown = Dict{String,Float64}(
        "J_raman" => J_raman, "J_energy" => 0.0,
        "J_tikhonov" => 0.0, "J_tv" => 0.0, "J_flat" => 0.0,
    )
    # ...
    if λ_tikhonov > 0
        deviation = A .- 1.0
        N_elem = length(deviation)
        J_T = λ_tikhonov * sum(deviation .^ 2) / N_elem
        grad_T = 2.0 .* λ_tikhonov .* deviation ./ N_elem
        J_total += J_T
        grad_total .+= grad_T
        breakdown["J_tikhonov"] = J_T
    end
    # ... TV with smooth-L1 (sqrt(diff^2 + ε²)), flatness as geo/arith mean ...
    @assert isfinite(J_total); @assert all(isfinite, grad_total)
    return J_total, grad_total, breakdown
end
```
For Phase 31, adapt the TV and Tikhonov branches to act on a phase coefficient vector `c` (or on `φ = B·c` if the penalty is defined on the phase itself). **Critical pattern to preserve**: `breakdown::Dict{String,Float64}` so downstream plots can distinguish `J_raman` from regularizer contributions.

**Analog 2 — GDD penalty directly on spectral phase (second-difference):** `scripts/raman_optimization.jl:123-138`

**GDD block** (`raman_optimization.jl:124-138`):
```julia
if λ_gdd > 0
    Nt_φ = size(φ, 1)
    Δω = 2π / (Nt_φ * sim["Δt"])
    inv_Δω3 = 1.0 / Δω^3
    for m in 1:size(φ, 2)
        for i in 2:(Nt_φ - 1)
            d2 = φ[i+1, m] - 2φ[i, m] + φ[i-1, m]
            J_total += λ_gdd * inv_Δω3 * d2^2
            coeff = 2 * λ_gdd * inv_Δω3 * d2
            grad_total[i-1, m] += coeff
            grad_total[i, m]   -= 2 * coeff
            grad_total[i+1, m] += coeff
        end
    end
end
```
**Already plumbed through to `cost_and_gradient_lowres` via `kwargs...`** — Phase 31 gets GDD penalties in coefficient space for free. Higher-order curvature (`∂³φ/∂ω³` = third-difference) can be added by copying this structure with a fourth-order stencil.

**Boundary-energy penalty pattern** (`raman_optimization.jl:141-162`): the "penalty on the realized pulse" template — use for penalizing energy outside the pulse bandwidth after shaping.

**Log-cost scaling pattern** (`raman_optimization.jl:166-172`):
```julia
if log_cost
    J_clamped = max(J_total, 1e-15)
    log_scale = 10.0 / (J_clamped * log(10.0))
    grad_total .*= log_scale
    J_total = 10.0 * log10(J_clamped)
end
```
Any new regularizer must be added to `J_total` / `grad_total` BEFORE this block so the log-scale applies consistently. This is a documented project convention (see MEMORY: `project_dB_linear_fix.md`).

---

### `scripts/run.jl` (driver, batch)

**Analog:** `scripts/sweep_simple_run.jl`

**Header/imports/determinism pattern** (`sweep_simple_run.jl:31-48`):
```julia
ENV["MPLBACKEND"] = "Agg"

try using Revise catch end

using LinearAlgebra
using FFTW
using Printf
using Random
using Logging
using Statistics
using JLD2
using Dates

include(joinpath(@__DIR__, "sweep_simple_param.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()
```
Add `include("basis_lib.jl")` and `include("penalty_lib.jl")` after `sweep_simple_param.jl` so library order is stable.

**Results-directory and run-tag pattern** (`sweep_simple_run.jl:54-71`):
```julia
const LR_RESULTS_DIR = joinpath(@__DIR__, "..", "results", "raman", "phase_sweep_simple")
const LR_RUN_TAG = Dates.format(now(), "yyyymmdd_HHMMSS")
# ... other LR_ constants ...
mkpath(LR_RESULTS_DIR)
```
Phase 31 equivalent: `const P31_RESULTS_DIR = joinpath(..., "raman", "phase31")` + `const P31_RUN_TAG = ...`. Use `P31_` prefix for all module constants (mirrors `LR_` / `P13_` / `P28_` conventions — see project CLAUDE.md "Script Constant Prefixes" note).

**Multi-start seed pattern** (`sweep_simple_run.jl:80-89`): small flat + ±chirp seed set; reuse verbatim at the coarsest basis level.

**Continuation warm-start pattern** (`sweep_simple_run.jl:209-214`):
```julia
if lvl == 1
    seeds = multistart_seeds(N_phi, Nt)
else
    c_upsampled = continuation_upsample(c_prev, B_prev, B)
    seeds = [c_upsampled]
end
```
`continuation_upsample` is in `sweep_simple_param.jl:385-394`. Basis-to-basis warm-start is free for any two bases sharing the same Nt grid — reuse across penalty-vs-basis comparison.

**Incremental save pattern** (`sweep_simple_run.jl:242-245`):
```julia
save_path = joinpath(LR_RESULTS_DIR, "sweep1_Nphi.jld2")
JLD2.jldsave(save_path; results, run_tag=LR_RUN_TAG)
@info "  saved $(save_path) ($(length(results)) rows)"
```
Save after each level so an interrupted burst run keeps everything up to the crash.

**Standard-images emission — MANDATORY per project CLAUDE.md** (`sweep_simple_run.jl:253-260, 268-279`): call `save_standard_set(...)` / `finalize_standard_images(...)` for every optimum before exit. Do NOT skip. The project has an explicit "drivers that skip this are incomplete" rule.

**Packaging pattern, including simplicity metrics** (`sweep_simple_run.jl:107-122`):
```julia
function package_result(r, uω0, sim, band_mask, bw_mask; config::NamedTuple)
    phi_vec = vec(r.phi_opt)
    return Dict(
        "config"        => Dict(pairs(config)),
        "N_phi"         => r.N_phi,
        "kind"          => String(r.kind),
        "c_opt"         => vec(r.c_opt),
        "phi_opt"       => phi_vec,
        "J_final"       => r.J_final,
        "iterations"    => r.iterations,
        "converged"     => r.converged,
        "N_eff"         => phase_neff(phi_vec, bw_mask),
        "TV"            => phase_tv(phi_vec, bw_mask),
        "curvature"     => phase_curvature(phi_vec, sim, bw_mask),
    )
end
```
Phase 31 should extend this with fields for regularizer breakdown (`J_raman`, `J_reg_*`), and — critical for locked decision 3 — a `"regularization_mode" => "basis" | "penalty" | "hybrid"` tag so the analysis script can partition runs cleanly.

---

### `scripts/analyze.jl` (analysis / figures)

**Analog 1 — Pareto-front construction:** `scripts/sweep_simple_analyze.jl:39-54`

```julia
function pareto_front(points::Vector{<:NTuple{2,<:Real}})
    n = length(points)
    dominated = falses(n)
    for i in 1:n
        xi, yi = points[i]
        for j in 1:n
            i == j && continue
            xj, yj = points[j]
            if xj ≤ xi && yj ≤ yi && (xj < xi || yj < yi)
                dominated[i] = true
                break
            end
        end
    end
    return findall(.!dominated)
end
```
Reuse verbatim. Phase 31's interesting axes are likely `(J_dB, N_phi)` for the basis branch and `(J_dB, λ_penalty)` for the penalty branch, with the two overlaid on a third figure.

**Analog 2 — JLD2-ingest + record-building + diagnostic figures:** `scripts/gauge_and_polynomial.jl:69-190, 489-567`

**File discovery** (`gauge_and_polynomial.jl:69-80`):
```julia
function find_opt_files(root::AbstractString)
    isdir(root) || return String[]
    paths = String[]
    for (dir, _subdirs, files) in walkdir(root)
        for f in files
            if f == "opt_result.jld2"
                push!(paths, joinpath(dir, f))
            end
        end
    end
    return sort(paths)
end
```
For Phase 31 rename the target filename to match what `run.jl` writes.

**Polynomial-projection post-hoc diagnostic** (`gauge_and_polynomial.jl:228-279` = `polynomial_project` in `primitives.jl`): once Phase 31 has a `phi_opt` from the full-grid penalty branch, project onto a polynomial basis and report `residual_fraction` to measure "how close is the penalty-regularized optimum to a low-order polynomial?". This is the interpretability metric locked decision 4 asks for.

---

### `scripts/transfer.jl` (robustness/transfer probe)

**Analog 1 — chirp/TOD sensitivity:** `scripts/raman_optimization.jl:309-` (`chirp_sensitivity`)

**Analog 2 — robustness framework:** `scripts/robustness_test.jl`

Transfer / robustness structure: take one optimum `phi_opt` (from a reduced basis OR a penalty), perturb the input conditions (pulse FWHM, energy, `β₂`, `γ`), re-evaluate cost without re-optimizing, and record the degradation. `chirp_sensitivity(φ_opt, uω0, fiber, sim, band_mask; gdd_range, tod_range)` already returns the J vs (GDD, TOD) map in the standard shape — use it as the inner kernel and loop over (basis-kind, N_phi) on the outside.

---

### `test/test_phase31_basis.jl` (test, assertion)

**Analog:** `test/test_primitives.jl`

**Test harness pattern** (`test_primitives.jl:17-50`):
```julia
using Test
using LinearAlgebra
using Statistics
using Random
using FFTW

include(joinpath(@__DIR__, "..", "scripts", "primitives.jl"))

const TEST_Nt = 1024
# ... fixtures ...

@testset "Phase 13 primitives" begin
    @testset "1. gauge_fix idempotence" begin
        # ...
    end
    # ... numbered, named testsets ...
end
```

**Required test cases for Phase 31 basis code (minimum set):**
1. `:identity` + `N_phi == Nt` reproduces full-res `cost_and_gradient` byte-exact (already in `sweep_simple_param.jl` self-test; port to Test.jl).
2. For each new `kind`, `B' * B` is well-conditioned (`_sanity_check_basis` already warns; promote to an `@test` with `κ < LR_COND_LIMIT`).
3. Coefficient-space gradient `∂J/∂c` matches finite differences to < 1e-4 rel err (pattern from `amplitude_optimization.jl:324-338` and `raman_optimization.jl:252-291`).
4. `continuation_upsample(c, B_coarse, B_fine)` preserves `φ = B·c` up to basis expressiveness (test that the fine-basis reconstruction's `J` is within 0.5 dB of the coarse-basis `J` at seed time).
5. For an orthonormal basis (`:dct`), `continuation_upsample` reduces to `B_fineᵀ · φ_prev` bit-exact.
6. Regularizer gradient finite-diff check: each penalty added in `penalty_lib.jl` passes the same FD test in isolation (set `λ_raman=0`, enable one `λ_*` at a time).

---

## Shared Patterns (apply to all Phase 31 files)

### Script preamble (headless Julia + Revise + determinism)

**Source:** `scripts/sweep_simple_run.jl:31-48`, `scripts/raman_optimization.jl:32-49`
**Apply to:** every new `scripts/phase31_*.jl`

```julia
ENV["MPLBACKEND"] = "Agg"
try using Revise catch end
using Printf, LinearAlgebra, FFTW, Logging, Random, Statistics, JLD2, Dates
using MultiModeNoise
using Optim

include(joinpath(@__DIR__, "common.jl"))              # FIBER_PRESETS, setup_raman_problem
include(joinpath(@__DIR__, "sweep_simple_param.jl"))  # build_phase_basis, optimize_phase_lowres
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()
```

### Constant prefix convention

**Source:** project CLAUDE.md "Script Constant Prefixes"; examples in `gauge_and_polynomial.jl:42-57` (`P13_*`), `saddle_run.jl:32-43` (`P28_*`), `sweep_simple_run.jl:54-69` (`LR_*`).
**Apply to:** all module constants in Phase 31 — use `P31_` prefix. Example: `const P31_RESULTS_DIR`, `const P31_MAX_ITER`, `const P31_NPHI_LADDER`.

### `@assert` design-by-contract

**Source:** pervasive — `sweep_simple_param.jl:108-125` (preconditions), `amplitude_optimization.jl:66-70, 150-152` (pre + post marked).
**Apply to:** every new function. Start with `# PRECONDITIONS` block, end with `# POSTCONDITIONS` block, both enforced by `@assert`. Errors propagate — no try/catch in numerical code (project convention).

### Standard-images emission (MANDATORY per project CLAUDE.md)

**Source:** CLAUDE.md "Standard output images — mandatory for every optimization run"; implementation in `scripts/standard_images.jl`; caller example in `sweep_simple_run.jl:253-260` plus `finalize_standard_images` at :268-`.
**Apply to:** `run.jl` and `transfer.jl` — any script that produces a `phi_opt` must call `save_standard_set(phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold; tag=..., fiber_name=..., L_m=..., P_W=..., output_dir=...)` before exit. Do NOT skip even for "quick" sweep points.

### JLD2 save layout

**Source:** `sweep_simple_run.jl:107-122` (per-row Dict) + `:242-245` (incremental `JLD2.jldsave`).
**Apply to:** all drivers. One `Dict{String, Any}` per optimum; all results collected in a `Vector{Dict{String, Any}}`; `JLD2.jldsave(path; results, run_tag=P31_RUN_TAG)` after every row so an interrupted burst run doesn't lose progress. Include `"regularization_mode"` tag so locked-decision-3 partitioning is possible post-hoc.

### Log-cost + gradient scaling

**Source:** `raman_optimization.jl:165-172`; memory note `project_dB_linear_fix.md`.
**Apply to:** `penalty_lib.jl`. If you extend `cost_and_gradient` (or write a parallel one), the log-scale application MUST be the last thing before returning, and BOTH `J_total` and `grad_total` must be scaled consistently. The f_tol then changes from `1e-10` (linear) to `0.01` (dB).

### Multi-thread fiber safety

**Source:** project CLAUDE.md "Running Simulations — Compute Discipline" + `scripts/benchmark_optimization.jl:635, 704`.
**Apply to:** any `Threads.@threads` block in `run.jl` / `transfer.jl`:
```julia
Threads.@threads for i in 1:n_tasks
    fiber_local = deepcopy(fiber)
    # ... use fiber_local only, never the shared fiber ...
end
```
`fiber["zsave"]` is mutated during solves and will race if shared.

### Burst-VM execution

**Source:** project CLAUDE.md "Running Simulations" + `scripts/burst/README.md` + Rule P5.
**Apply to:** the planner's run recipe for Phase 31. Any driver that actually runs optimizations must be launched on `fiber-raman-burst` through `burst-run-heavy <TAG> 'julia -t auto --project=. scripts/run.jl'`, not on `claude-code-host`. The session tag format is `^[A-Za-z]-[A-Za-z0-9_-]+$` — suggested tag for this phase's session: `A-phase31` (or whichever session letter the user assigns in `.planning/notes/parallel-session-prompts.md`).

---

## No analog found

None — every file in the inferred list maps onto an existing pattern. If the expanded `31-RESEARCH.md` introduces a file role not covered here (e.g., a symbolic/KKT-based regularizer solver, a Bayesian model-selection driver, a phase-diagram figure with no precedent), re-run this mapper on the updated list. As it stands, Phase 31 is largely a **recombination and benchmarking phase on top of Session E's (Phase 26-ish) Low-Res / Sweep Simple infrastructure**, not a greenfield introduction of new numerical machinery.

---

## Metadata

**Analog search scope:** `scripts/` (all `.jl`), `src/`, `test/`, `.planning/seeds/`, `.planning/phases/13*, 22*, 26*, 28*, 35*` (READ of headers only, no full-file reads beyond those referenced above).
**Files scanned (Grep / Glob):** ~95 Julia files under `scripts/`; 5 test files; 17 seed files.
**Files read in depth:** `scripts/sweep_simple_param.jl`, `scripts/sweep_simple_run.jl`, `scripts/sweep_simple_analyze.jl` (partial), `scripts/amplitude_optimization.jl` (lines 1-360, 850-928), `scripts/raman_optimization.jl` (lines 1-320), `scripts/common.jl` (lines 300-470), `scripts/primitives.jl` (lines 120-400), `scripts/gauge_and_polynomial.jl` (lines 1-200), `scripts/saddle_run.jl` (lines 1-80), `test/test_primitives.jl` (lines 1-80).
**Pattern extraction date:** 2026-04-21.
