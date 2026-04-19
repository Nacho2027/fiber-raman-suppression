# Coding Conventions

**Analysis Date:** 2026-04-19

This document refreshes the 2026-04-05 version. It is grounded in the actual source
(`src/**/*.jl`, `scripts/**/*.jl`, `test/**/*.jl`, `Makefile`) as of 2026-04-19 —
post Sessions A–H and the Phase 15/16 determinism work. Where this doc disagrees
with CLAUDE.md, the source wins and the divergence is flagged.

## Naming Patterns

**Functions (snake_case):**
- All functions use `snake_case`: `cost_and_gradient`, `spectral_band_cost`, `setup_raman_problem`, `save_run`, `load_run`, `ensure_deterministic_environment`
- Namespaced variants append a suffix rather than introducing CamelCase: `cost_and_gradient_mmf`, `setup_mmf_raman_problem`
- In-place mutating functions use `!` suffix per Julia convention: `disp_mmf!`, `adjoint_disp_mmf!`, `compute_gain!`, `calc_δs!`, `add_caption!`
- Private/internal helpers use `_` prefix: `_apply_fiber_preset`, `_manual_unwrap`, `_central_diff`, `_auto_time_limits`, `_energy_window`, `_freq_to_wavelength`, `_length_display`, `_add_metadata_block!`, `_spectral_signal_xlim`
- ODE right-hand-side functions follow `{physics_model}!`: `disp_mmf!`, `disp_gain_smf!`, `mmf_u_mu_nu!`
- Parameter constructors follow `get_p_{model}`: `get_p_disp_mmf`, `get_p_adjoint_disp_mmf`, `get_p_disp_gain_smf`
- Setup functions prefixed by problem type: `setup_raman_problem`, `setup_amplitude_problem`, `setup_mmf_raman_problem`

**Variables (Unicode physics symbols allowed and preferred):**
- Physics variables use Unicode that matches mathematical notation: `λ0`, `ω0`, `β2`, `γ`, `φ`, `ũω`, `λ̃ω`, `Δt`, `Δf`, `Δω_raman`
- Greek letters for physical quantities: `σ`, `τ`, `ε`, `ηt`, `δKt`, `φ_NL`, `δω_SPM`, `τ_R`
- Subscripts in variable names use physics domain notation: `uωf` (field in frequency at fiber end), `ut0` (field in time at z=0), `hRω` (Raman response in frequency)
- Preallocated buffers use descriptive physics names, not generic buffer names: `exp_D_p`, `exp_D_m`, `hRω_δRω`, `hR_conv_δR`, `ηKt`, `αK`, `βK`
- Counters and sizes: `Nt` (temporal grid points), `M` (spatial modes), `Nt_φ` (phase grid size), `nz` (saved z-slices)

**Files:**
- Source modules: `snake_case.jl` — `simulate_disp_mmf.jl`, `sensitivity_disp_mmf.jl`, `mmf_cost.jl`
- Scripts: `snake_case.jl`. Session-owned scripts are prefixed by session/topic so parallel sessions don't collide — `mmf_*.jl`, `multivar_*.jl`, `longfiber_*.jl`, `sweep_simple_*.jl`, `cost_audit_*.jl`, `phase13_*.jl`, `phase14_*.jl`, `phase15_*.jl`
- Test files: `test_` prefix — `test_optimization.jl`, `test_phase13_primitives.jl`, `test_phase16_mmf.jl`
- Tier dispatch: `test/tier_{fast,slow,full}.jl` (new — see TESTING.md)
- Shared script library: `scripts/common.jl` (single source of truth for fiber presets and setup)

**Constants:**
- Module-level constants use `UPPER_SNAKE_CASE`: `FIBER_PRESETS`, `C_NM_THZ`, `COLOR_INPUT`, `COLOR_OUTPUT`, `COLOR_RAMAN`, `COLOR_REF`, `OUTPUT_FORMAT_SCHEMA_VERSION`, `DET_VERSION`, `DET_PHASE`
- Script-level constants (avoid REPL collisions): `SMF28_GAMMA`, `SMF28_BETAS`, `HNLF_GAMMA`, `HNLF_BETAS`, `RUN_TAG`
- Include-guard constants: `_COMMON_JL_LOADED`, `_VISUALIZATION_JL_LOADED`, `_DETERMINISM_JL_LOADED`
- Private leading-underscore constants for locals only used inside a file: `_ROOT`, `_VALID_TIERS`, `_CA_NOISE_AWARE_PATH`, `_PHASE16_WISDOM`

**Types:**
- `PascalCase` for struct names: `YDFAParams` in `src/gain_simulation/gain.jl` — still the only typed parameter struct in the core codebase (Dict-of-String remains the dominant pattern)
- Fiber presets live as `NamedTuple`s inside the `FIBER_PRESETS::Dict{Symbol, NamedTuple}` registry in `scripts/common.jl` — preset names are `Symbol`s (`:SMF28`, `:HNLF`, `:GRIN_50`, ...)

**Script constant prefixes (REPL-safety):**
Julia `const` cannot be redefined in a REPL session, so long-lived scripts use a unique uppercase prefix on every top-level constant:
- `RC_` — `scripts/run_comparison.jl`
- `SW_` — `scripts/run_sweep.jl`
- `SR_` — `scripts/generate_sweep_reports.jl`
- Phase-scoped constants use the phase tag: `PHASE16_SEED`, `DET_PHASE`

## Code Style

**Formatting:**
- No linter or formatter is configured. There is no `.editorconfig`, no `.JuliaFormatter.toml`, no pre-commit hook for style.
- Indentation: 4 spaces, consistently
- Line length: no enforced limit; 100–150 chars is normal for `@sprintf` and keyword-argument bodies
- Semicolons separate short assignments on one line: `Nt = sim["Nt"]; M = sim["M"]`
- Trailing `;` on the last expression of interactive scripts where an implicit display would be noisy

**Operators and macros:**
- Use `@.` for vectorized element-wise operations over preallocated buffers: `@. uω = exp_D_p * ũω`, `@. dũω = 1im * exp_D_m * ηt`
- Use `@tullio` for tensor contractions (Einstein summation): `@tullio δKt[t, i, j] = γ[i, j, k, l] * (v[t, k] * v[t, l] + w[t, k] * w[t, l])`
- Prefer `cis(x)` over `exp(im * x)` for pure phase rotations (documented in source — avoids `exp` overhead)
- `fftshift!(dst, src, dim)` for in-place shifts; combined with `FFTW.ESTIMATE` plans (NOT `FFTW.MEASURE`) per Phase 15 determinism fix
- `deepcopy(fiber)` before any multi-threaded loop that runs solves in parallel — `fiber["zsave"]` is mutated inside the ODE solver; sharing `fiber` across threads races

**Sectioning and headers:**
- `# ─────────────────────────────────────────────────────────────────────────────` (em-dash line, 77 wide) between logical sections of a script
- `# ═══════════════════════════════════════════════════════════════════════════════` (double-line) for file-level banners and top-of-file headers in newer tier/test files
- Section headers follow `# N. Section Title` with numbered sections inside scripts
- Run summary boxes use box-drawing characters: `┌──┐`, `├──┤`, `│`, `└──┘`
- Benchmark tables use double-line box drawing: `╔═══╦═══╗`, `║`, `╚═══╩═══╝`
- In `print_fiber_summary` the lines are built in a `String[]` vector and joined before `@info`-ing so the box renders as a single log record

## Common Patterns

**Include guards (files meant for multiple inclusion):**

```julia
# Module-level `using` imports live OUTSIDE the guard so macros are
# visible at compile time — this is a hard rule, violating it breaks
# @info / @sprintf at load time in downstream scripts.
using FFTW
using LinearAlgebra

if !(@isdefined _COMMON_JL_LOADED)
const _COMMON_JL_LOADED = true

# ... rest of the file ...

end  # include guard
```

- Used in: `scripts/common.jl`, `scripts/visualization.jl`, `scripts/determinism.jl`, `scripts/standard_images.jl`
- Do NOT put `using` statements inside the guard — macros (`@sprintf`, `@info`, `@tullio`) resolve at parse time and need their packages visible in the including scope. This is documented in `scripts/determinism.jl` line ~24.

**Design-by-contract with `@assert`:**

```julia
function recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27, ...)
    @assert L_fiber > 0 "fiber length must be positive, got $L_fiber"
    @assert safety_factor > 0 "safety factor must be positive"
    @assert beta2 > 0 "beta2 must be positive (pass absolute value)"
    ...
end
```

- `@assert` used for both preconditions and postconditions
- Comments `# PRECONDITIONS` and `# POSTCONDITIONS` explicitly mark contract blocks
- Examples in use: `@assert ispow2(Nt)`, `@assert L_fiber > 0`, `@assert all(isfinite, ∂J_∂φ)`, `@assert 0 <= J <= 1`, `@assert size(φ) == size(uω0)`
- Contract failures produce an `AssertionError` tested explicitly via `@test_throws AssertionError ...` in `scripts/test_optimization.jl`

**Dict-based parameter passing:**
- `sim::Dict{String, Any}` — simulation grid: `Nt`, `M`, `Δt`, `ts`, `fs`, `ωs`, `ω0`, `attenuator`, `ε`, `β_order`
- `fiber::Dict{String, Any}` — fiber material: `Dω`, `γ`, `hRω`, `L`, `one_m_fR`, `zsave`, `preset`
- `sol::Dict{String, Any}` — forward-solve output: `uω_z`, `ut_z`, `ode_sol`
- String keys throughout: `sim["Nt"]`, `fiber["Dω"]`, `fiber["L"]`
- Dict entries are mutated during solves (`fiber["zsave"]` gets written). This makes Dict-passing NOT thread-safe — always `deepcopy(fiber)` before parallel use.

**Pre-allocated ODE tuple-packing:**

```julia
function get_p_disp_mmf(ωs, ω0, Dω, γ, hRω, one_m_fR, Nt, M, attenuator)
    exp_D_p = zeros(ComplexF64, Nt, M)
    exp_D_m = zeros(ComplexF64, Nt, M)
    uω       = zeros(ComplexF64, Nt, M)
    ...
    # Plans use FFTW.ESTIMATE (NOT MEASURE) for determinism.
    fft_plan_M!  = plan_fft!(uω,   1; flags=FFTW.ESTIMATE)
    ifft_plan_M! = plan_ifft!(uω,  1; flags=FFTW.ESTIMATE)
    ...
    return (selfsteep, Dω, γ, hRω, one_m_fR, attenuator,
            fft_plan_M!, ifft_plan_M!, ..., ηt)
end
```

Every work array used by the RHS is allocated once here and packed into a single tuple, which is what the ODE solver passes as its `p` argument. This avoids GC pressure during the hundreds of RHS calls `Tsit5`/`Vern9` make per propagation.

**FFT plans use `FFTW.ESTIMATE`, never `FFTW.MEASURE`** (Phase 15 rule):
`FFTW.MEASURE` makes plan selection timing-dependent, which breaks bit-identity across processes. All 16 occurrences in `src/simulation/*.jl` were swapped in Phase 15. Any new FFT plan you add MUST use `flags=FFTW.ESTIMATE`.

**Named tuples for preset registries:**

```julia
const FIBER_PRESETS = Dict(
    :SMF28 => (
        name = "SMF-28",
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        fR = 0.18,
        description = "Corning SMF-28 @ 1550nm (β₂ + β₃)",
    ),
    ...
)
```

Located in `scripts/common.jl`. Access via `get_fiber_preset(:SMF28)`. MMF presets live separately in `scripts/mmf_fiber_presets.jl` and expose `:GRIN_50`, etc.

**Script-as-module idiom:**

```julia
try using Revise catch end
using Printf
using LinearAlgebra
...
include("common.jl")
include("visualization.jl")
include(joinpath(@__DIR__, "determinism.jl"))
ensure_deterministic_environment()

# ... function definitions ...

if abspath(PROGRAM_FILE) == @__FILE__
    # example / CLI entry point
    ...
end
```

- `try using Revise catch end` at the top for optional hot-reload during dev
- `ENV["MPLBACKEND"] = "Agg"` BEFORE any `using PyPlot` for headless execution
- `if abspath(PROGRAM_FILE) == @__FILE__` guard so the file is safe to `include()` from tests without triggering the CLI block
- Always call `ensure_deterministic_environment()` immediately after including `determinism.jl`; the helper is idempotent so repeated calls are free

**Standard-images contract (mandatory for any driver producing `phi_opt`):**
After optimization, before exiting, every driver calls `save_standard_set(...)` from `scripts/standard_images.jl`. Produces the four canonical PNGs the group expects (`{tag}_phase_profile.png`, `{tag}_evolution.png`, `{tag}_phase_diagnostic.png`, `{tag}_evolution_unshaped.png`). Drivers that skip this are considered incomplete — this is enforced by review, not by lint. See `CLAUDE.md` "Standard output images" block.

**Output-format contract (D2 schema):**
Optimization results are persisted via `save_run` / `load_run` in `scripts/polish_output_format.jl`. Each call writes a paired JLD2 payload + JSON sidecar with a `schema_version` tag (`OUTPUT_FORMAT_SCHEMA_VERSION`). `tier_fast.jl` includes a round-trip test that guards this schema.

## Error Handling

- `@assert` is the primary tool for design-by-contract validation of numerical inputs and outputs (preconditions/postconditions)
- `throw(ArgumentError(...))` for user-facing parameter validation in core library code:
  - `src/helpers/helpers.jl` — rejects negative fiber length, non-power-of-2 grids
  - `scripts/multivar_optimization.jl` — `sanitize_variables` throws `ArgumentError` for unknown variable names, empty tuples, and `(:mode_coeffs,)` alone
  - `test/runtests.jl` — throws `ArgumentError` for unrecognized `TEST_TIER`
- `@warn` for recoverable conditions: time window smaller than `recommended_time_window(L)`, boundary energy above threshold, degraded path selections
- No `try/catch` blocks in numerical code. Errors propagate to the caller. The only exceptions are:
  - `try using Revise catch end` — optional dev dependency
  - `isfile(wisdom) && try; FFTW.import_wisdom(wisdom); catch; end` — best-effort FFTW wisdom import in tests
- No custom exception types are defined. Use `AssertionError` for internal invariants and `ArgumentError` for user-facing parameter rejection.

## Documentation Style

**Module and script headers:**
- Every `src/` module and every `scripts/` driver opens with a triple-quoted docstring describing purpose, inputs, outputs, runtime, and cross-references. See `scripts/raman_optimization.jl` lines 1–30 for the canonical template.

**Function docstrings (Julia-standard):**

```julia
"""
    recommended_time_window(L_fiber; safety_factor=2.0, beta2=20e-27,
                              gamma=0.0, P_peak=0.0, pulse_fwhm=185e-15)

Compute safe time window [ps] from dispersive walk-off plus SPM spectral
broadening for single-mode fibers. [...physics explanation with units...]

# Keyword arguments
- `safety_factor`: multiplicative safety margin (default 2.0)
- `beta2`: absolute value of β₂ in s²/m (default 20e-27, approximately SMF-28)
- `gamma`: nonlinear coefficient in W⁻¹m⁻¹ (default 0.0 = no SPM correction)
- `P_peak`: peak pulse power in W (default 0.0 = no SPM correction)
- `pulse_fwhm`: pulse FWHM duration in seconds (default 185e-15 for 185 fs sech²)
"""
```

- Use `# Arguments`, `# Keyword arguments`, `# Returns`, `# Example`, `# Run` sections
- Physics comments explain the mathematical operation alongside the code: `# Chain rule: dJ/dphi(omega) = 2 * Re(lambda_0*(omega) * i * u_0(omega))`
- Units always stated in comments: `# W⁻¹ m⁻¹`, `# s²/m`, `# THz`, `# rad/s`
- `# --- Section Title ---` or `# N. Section Title` for subsections inside functions

**Known documentation gaps:**
- Some older code in `src/simulation/` still has incomplete argument descriptions in docstrings — backfill when editing
- `README.md` was refreshed in Session B (2026-04-17+) and now reflects Raman suppression rather than the pre-fork MMF-squeezing focus

**Domain docs (`docs/`):**
- `docs/README.md` — doc index
- `docs/quickstart-optimization.md` — canonical SMF-28 run walkthrough
- `docs/quickstart-sweep.md` — (L, P) parameter sweep on the burst VM
- `docs/cost-function-physics.md`, `docs/interpreting-plots.md`, `docs/output-format.md` — research-group-level explainers
- `docs/adding-a-fiber-preset.md`, `docs/adding-an-optimization-variable.md` — extension guides
- `docs/installation.md`, `docs/physics_verification.pdf`, `docs/verification_document.pdf` — reference artifacts

## Import Organization

Observed convention (bottom-up, before any include()):

1. `try using Revise catch end` (scripts only, optional)
2. `ENV["MPLBACKEND"] = "Agg"` (scripts that touch PyPlot)
3. Standard-library `using` lines alphabetical-ish: `using Printf`, `using LinearAlgebra`, `using FFTW`, `using Logging`, `using Random`, `using Statistics`, `using Dates`
4. Third-party `using` lines: `using PyPlot`, `using Optim`, `using JLD2`, `using JSON3`
5. Project module: `using MultiModeNoise`
6. `include(...)` of sibling scripts (guarded): `include("common.jl")`, `include("visualization.jl")`, `include(joinpath(@__DIR__, "determinism.jl"))`, `include(joinpath(@__DIR__, "standard_images.jl"))`
7. `ensure_deterministic_environment()` call (before any randomness or FFT planning)

All `using` lines go OUTSIDE any include guard. This is a hard rule — see Include Guards above.

Tests follow the same order but skip the PyPlot/Revise lines unless the test specifically exercises plotting.

## Logging

- `@info` for run summaries, progress messages, major milestones, tier banners
- `@debug` for detailed diagnostics (iteration counts, parameter values, gradient norms) — only visible with `JULIA_DEBUG=all`
- `@warn` for non-fatal but concerning conditions (time window smaller than recommended, boundary energy above threshold, fallback path chosen)
- `@sprintf("...", args...)` used inside logging macros for formatted output. Do not build the string separately and then pass it in; `@sprintf` keeps the format string and args at the call site for grep-ability.
- Run summaries use the box-drawing idiom (see `print_fiber_summary` in `scripts/common.jl`): build lines in `String[]`, `join(lines, "\n")`, pass the single multi-line string to `@info`
- Legacy code in `src/` uses `println(...)` and `flush(stdout)` — tolerated, but new code in `src/` and ALL code in `scripts/` MUST use the `Logging` macros

## SI Units Convention

**Core physics (always SI for on-disk and function-boundary values):**
- Wavelength: meters (e.g., `1550e-9`)
- Time: seconds for physics (`pulse_fwhm = 185e-15`), picoseconds for simulation grids (`time_window = 10.0`)
- Frequency: THz for spectral grids, Hz for repetition rates
- Power: Watts
- Dispersion: `β₂` in `s²/m`, `β₃` in `s³/m`
- Nonlinearity: `γ` in `W⁻¹ m⁻¹`

**JLD2 file format (critical non-SI exceptions):**
- `sim_omega0` — stored in **rad/ps**, NOT rad/s. Convert to THz via `f0 = ω0 / (2π)`.
- `sim_Dt` — stored in **picoseconds**
- `P_cont_W` — **average** continuum power, not peak. Peak power is derived as `P_peak = P_cont / (pulse_fwhm * pulse_rep_rate)`.
- `convergence_history` — stored in **dB**, post-optimization via `lin_to_dB` (Phase 7 fix)
- `band_mask` — Boolean vector in **FFT order**, not `fftshift`ed. Plotting helpers fftshift when rendering.

**Cost conventions:**
- Linear `J ∈ [0, 1]` is the fractional in-band energy (precondition / postcondition on `spectral_band_cost`)
- Logarithmic cost is `10 * log10(J)` (dB). When `log_cost=true` is passed to `cost_and_gradient`, the optimizer sees the dB value and its gradient is scaled by `10 / (J * ln10)`. This is the "Key Bug #1" fix — the optimizer-returned minimum is in dB, so callers MUST recompute J with `log_cost=false` to get the linear-space check asserted by `tier_slow`.

---

## Divergence notes (versus CLAUDE.md claims)

CLAUDE.md asserts a handful of things that are worth grounding against source:

- CLAUDE.md says "FFTW threading at Nt=2^13: counterproductive — do NOT call `FFTW.set_num_threads(n > 1)` at this grid size". This is consistent with `scripts/determinism.jl`, which unconditionally pins FFTW threads to 1 for determinism reasons as well as performance. Both motivations apply.
- CLAUDE.md lists "no try/catch blocks in numerical code". Source check confirms this, with the two documented exceptions above (Revise import; FFTW wisdom import in tests).
- CLAUDE.md claims `scripts/test_optimization.jl` is the comprehensive test suite. Source shows this is still true but is NO LONGER the primary regression path — `test/tier_{fast,slow,full}.jl` (Session B, post-2026-04-05) are the new canonical entry points. See TESTING.md.
- CLAUDE.md does not mention the `save_run`/`load_run` D2 schema or `OUTPUT_FORMAT_SCHEMA_VERSION`. These are current and enforced by `tier_fast`.

---

*Convention analysis: 2026-04-19. Reflects current state after Phase 15 determinism fix and Session B tiered-test restructure.*
