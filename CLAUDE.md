# Working Style

- Separate agent work docs from human docs. Put internal investigation and implementation notes in `agent-docs/<topic>/CONTEXT.md`, `agent-docs/<topic>/PLAN.md`, and `agent-docs/<topic>/SUMMARY.md`. Put human-facing docs and polished reports in `docs/`. `docs/planning-history/` is the historical archive of the old workflow; do not add new active work there.
- Read `agent-docs/current-agent-context/` before starting substantial technical work that touches numerics, methodology, or compute operations. It is the curated successor to the useful parts of the old `.planning/` state.
- Research heavily before writing code: grep the codebase, read referenced files, use WebFetch on official docs, and WebSearch for known pitfalls. Write findings down before coding.
- Prefer test-driven development for non-trivial changes. When feasible, start red, get to green with the smallest correct change, then refactor with tests still green. When red-first TDD is genuinely awkward for a task, explain that briefly in the agent notes and still land a regression test before calling the work done.
- Test heavily. Add or update tests for every non-trivial change. Never mark work done without running tests.
- Document more rigorously than a typical research repo. Public or reused functions should have docstrings, numerics-heavy code should state units / assumptions / invariants, and behavior or workflow changes should update the relevant human docs as well as the agent summary. Comments should explain intent, physics, or constraints, not narrate syntax.

## Project

**Visualization Overhaul: SMF Gain-Noise Plotting**

A comprehensive fix of all plotting and visualization in the smf-gain-noise project (`MultiModeNoise.jl`). The goal is to produce clean, readable, physically informative plots for nonlinear fiber optics simulations, specifically Raman suppression optimization via spectral phase and amplitude shaping. Plots are for internal research group use (lab meetings, advisor reviews).

**Core Value:** Every plot must clearly communicate the underlying physics so that a reader can understand what happened during propagation and optimization without needing the filename or external context.

### Constraints

- **Tech stack**: Must stay in Julia + PyPlot (matplotlib). No new visualization dependencies.
- **Backward compatibility**: Keep the same function signatures where possible, or provide clear migration.
- **Output format**: PNG at 300 DPI for archival, must look good at both screen and print resolution.
- **Performance**: Plotting should not add significant overhead to optimization runs.

### Standard output images — mandatory for every optimization run

**Every optimization driver that produces a `phi_opt` MUST, before exiting, call `save_standard_set(...)` from `scripts/standard_images.jl`.** This produces the image set the research group expects:

1. `{tag}_phase_profile.png` — 6-panel before/after optimization comparison (wrapped + unwrapped + group delay × input/output)
2. `{tag}_evolution.png` — colorful spectral-evolution waterfall of the optimized field
3. `{tag}_phase_diagnostic.png` — wrapped/unwrapped/group-delay triplet of `phi_opt` alone
4. `{tag}_evolution_unshaped.png` — matching waterfall with `phi ≡ 0` for comparison

Template:

```julia
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "visualization.jl"))
include(joinpath(@__DIR__, "standard_images.jl"))
# ... setup_raman_problem, run optimizer, produce phi_opt ...
save_standard_set(phi_opt, uω0, fiber, sim, band_mask, Δf, raman_threshold;
    tag = "smf28_L2m_P0p2W",
    fiber_name = "SMF28", L_m = 2.0, P_W = 0.2,
    output_dir = "results/raman/my_run/")
```

For runs that produced a `phi_opt` before this rule was in place, run `scripts/regenerate_standard_images.jl` (behind the heavy lock) to generate the standard set for every JLD2 under `results/raman/` that carries a `phi_opt`. Override the scan root via `REGEN_ROOT`.

Drivers that skip this step are incomplete. Do not mark work done without the standard images on disk.

PNG existence is not sufficient verification. Agents must visually inspect the generated figures for obvious plotting failures before calling simulation or optimization work complete.

- **Single run / primary result:** inspect the full standard image set.
- **Sweep / multistart / large batch:** inspect representative best, typical, worst, and any suspicious or outlier cases, then record what was checked in the agent-facing summary.

## Technology Stack

Julia ≥ 1.9.3 (Manifest pinned to 1.12.4) + Python/Matplotlib via PyCall for plotting. Headless plotting via `ENV["MPLBACKEND"] = "Agg"`. No secrets, no `.env`. Build via `Pkg.instantiate()`.

| Package | Purpose |
|---------|---------|
| DifferentialEquations | ODE suite (`Tsit5()`, `Vern9()`) for pulse propagation |
| FFTW | Pre-planned in-place FFTs (`FFTW.MEASURE`) |
| Tullio | `@tullio` Einstein summation for 4D mode-overlap tensors |
| Optim 1.13.3 | L-BFGS spectral phase/amplitude optimization |
| Arpack | Sparse eigenvalue solver (`eigs`) for GRIN fiber modes |
| NPZ | Read NumPy `.npz` (fiber cache, Yb cross-section data) |
| Interpolations 0.16.2 | 1D linear interpolation for Yb cross-sections |
| PyPlot | Matplotlib wrapper via PyCall |
| Revise | Optional hot-reload (wrapped in `try/catch`) |

## Conventions

### Naming Conventions

- `snake_case` functions; `!` suffix for in-place mutating (`disp_mmf!`, `adjoint_disp_mmf!`); `_` prefix for internal helpers (`_manual_unwrap`, `_central_diff`).
- ODE RHS: `{physics_model}!` (`disp_mmf!`). Parameter constructors: `get_p_{model}`. Setup: `setup_raman_problem`, `setup_amplitude_problem`.
- Physics variables use Unicode matching math notation: `λ0`, `ω0`, `β2`, `γ`, `φ`, `ũω`, `Δt`, `Δf`. Greek letters for physics quantities.
- Counters: `Nt` (temporal grid points), `M` (spatial modes), `Nt_φ` (phase grid).
- `UPPER_SNAKE_CASE` for module constants (`FIBER_PRESETS`, `C_NM_THZ`, `COLOR_INPUT`). Include guards: `_COMMON_JL_LOADED`.
- `PascalCase` for structs (`YDFAParams`). Use `@kwdef mutable struct` for typed parameter containers (only `YDFAParams` currently).

### Code Style

- 4-space indentation; no formatter configured.
- `@.` for vectorized ops: `@. uω = exp_D_p * ũω`.
- `@tullio` for tensor contractions (Einstein summation).
- Prefer `cis(x)` over `exp(im * x)` for phase rotations.

### Common Patterns

- Include guard (`_COMMON_JL_LOADED`) for files meant for multiple inclusion.
- `@assert` for preconditions and postconditions (marked `# PRECONDITIONS` / `# POSTCONDITIONS`).
- Dict-based parameter passing: `sim::Dict{String,Any}`, `fiber::Dict{String,Any}` with string keys (`sim["Nt"]`, `fiber["Dω"]`).
- ODE parameter tuples preallocate all work arrays to avoid GC pressure during integration.
- `abspath(PROGRAM_FILE) == @__FILE__` guard in scripts that should not execute when `include`d.
- `try using Revise catch end` at top of scripts for optional hot-reload.

### Error Handling

- `@assert` for design-by-contract (in/out). `throw(ArgumentError(...))` for user-facing validation in core (`src/helpers/helpers.jl`). `@warn` for recoverable conditions (small time window). No try/catch in numerical code; errors propagate.

### Documentation Style

- Julia `"""..."""` docstrings above functions with `# Arguments`, `# Returns`, `# Example`.
- Physics comments explain the math: `# Chain rule: dJ/dphi(omega) = 2 * Re(lambda_0*(omega) * i * u_0(omega))`.
- Units always stated in comments (`# W^-1 m^-1`, `# s^2/m`, `# THz`).
- Document preconditions, postconditions, and numerical assumptions when they are important to correctness or reproducibility.
- If a change affects outputs, workflows, file formats, CLI/script usage, or interpretation of results, update the relevant human-facing doc in `docs/` or `README.md`, not just inline comments.
- Keep comments high-signal. Prefer documenting intent, invariants, physics, or failure modes over line-by-line narration.

### Logging

- `@info` for run summaries and milestones; `@debug` for iteration-level diagnostics (visible with `JULIA_DEBUG=all`); `@warn` for soft violations. Use `@sprintf` for formatting.

### SI Units Convention

- Wavelength: meters (for example `1550e-9`)
- Time: seconds for physics (`pulse_fwhm = 185e-15`), picoseconds for simulation grids
- Frequency: THz for spectral grids, Hz for repetition rates
- Power: Watts
- Dispersion: `s^2/m` for beta_2, `s^3/m` for beta_3
- Nonlinearity: `W^-1 m^-1`

## Architecture

### Pattern Overview

- Julia package (`Project.toml` / `Manifest.toml`); core physics as in-place ODE RHS functions (`!` convention).
- Forward-adjoint optimization: forward propagation + backward adjoint for gradient-based optimization.
- Dict-based parameter passing (`sim`, `fiber`); work arrays pre-packed into tuples to avoid GC pressure.
- Scripts use `include()` chains with manual include guards.

### Core Concepts

- **Interaction picture**: ODEs in the interaction picture separate fast linear (dispersive) dynamics from slow nonlinear dynamics. `exp_D_p` / `exp_D_m` phase factors transform between lab and interaction frames.
- **Kerr + Raman nonlinearity**: Instantaneous Kerr (tensor contraction `gamma[i,j,k,l]`) + delayed Raman (convolution with `hRω`), both contributing to `dũω`.
- **Self-steepening**: Frequency-dependent scaling (`ωs / ω0`) on the nonlinear term.
- **Adjoint method**: Backward propagation of adjoint field `λ` computes gradients of a cost functional w.r.t. input spectral phase. This is exact, efficient, and avoids AD through the ODE solver.
- **Spectral band cost**: `J = E_band / E_total`, the fractional energy in a Raman-shifted frequency band.
- **GRIN fiber modes**: Spatial modes from a graded-index profile via a finite-difference eigenvalue solver.
- **YDFA gain model**: Yb3+ rate equations using absorption and emission cross-sections from NPZ.

### Layers

- **Simulation core** (`src/simulation/`): ODE RHS, adjoint RHS, solvers, initial state generators.
- **Fiber setup** (`src/simulation/fibers.jl`, `src/helpers/helpers.jl`): GRIN mode solver, overlap tensor, `get_disp_sim_params`.
- **Gain model** (`src/gain_simulation/gain.jl`): `YDFAParams`, cross-section interpolation.
- **Analysis** (`src/analysis/`): noise variance decomposition via Tullio contractions.
- **Optimization** (`scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`): cost and gradient, L-BFGS, regularization.
- **Shared library** (`scripts/common.jl`): `FIBER_PRESETS`, `setup_raman_problem`, `spectral_band_cost`, `recommended_time_window`.
- **Visualization** (`scripts/visualization.jl`): spectral and temporal evolution plots, optimization comparison, phase diagnostics.

### Data Flow

- State is held in two Dicts: `sim` (grid and physical constants) and `fiber` (material and geometry).
- ODE state is a complex matrix `ũω` of shape `(Nt, M)` in the interaction picture.
- Work arrays are pre-allocated in tuples (`p` parameter) to avoid allocations during integration.

### Key Abstractions

| Abstraction | Location | Purpose |
|-------------|----------|---------|
| `sim` Dict | `src/helpers/helpers.jl :: get_disp_sim_params()` | Grid params: `Nt`, `Δt`, `ts`, `fs`, `ωs`, `ω0`, `attenuator`, `ε`, `β_order` |
| `fiber` Dict | `src/helpers/helpers.jl :: get_disp_fiber_params_user_defined()` | Fiber params: `Dω`, `γ`, `hRω`, `L`, `one_m_fR`, `zsave` |
| `p` tuple (forward) | `src/simulation/simulate_disp_mmf.jl :: get_p_disp_mmf()` | Pre-allocated work arrays + FFT plans for forward ODE RHS |
| `p` tuple (adjoint) | `src/simulation/sensitivity_disp_mmf.jl :: get_p_adjoint_disp_mmf()` | Pre-allocated work arrays + FFT plans for adjoint ODE RHS |
| `YDFAParams` struct | `src/gain_simulation/gain.jl` | Typed parameter container for Yb-doped fiber amplifier |
| `FIBER_PRESETS` Dict | `scripts/common.jl` | Named fiber parameter presets (SMF28, HNLF variants) |
| `band_mask` Bool vector | `scripts/common.jl :: setup_raman_problem()` | Boolean mask selecting Raman-shifted frequency bins |

### Entry Points

- `src/MultiModeNoise.jl` — module root, loaded via `using MultiModeNoise`.
- `scripts/raman_optimization.jl` — runs 5 predefined optimization configs (SMF-28, HNLF) + chirp sensitivity.
- `scripts/amplitude_optimization.jl` — spectral amplitude optimization with multiple regularizations.
- `scripts/run_benchmarks.jl` — grid size, time window, continuation, multi-start, parallel gradient validation.
- `scripts/test_optimization.jl` — unit, contract, property, and integration tests.
- `test/runtests.jl` — minimal smoke test (module loads).
- `notebooks/*.ipynb` — interactive MMF squeezing, EDFA-YDFA gain, and supercontinuum exploration.

### Design Decisions

- **Dict-based parameters over structs**: flexible key addition (`fiber["zsave"]` is mutated by optimization code) at the cost of type safety.
- **Pre-allocated tuple packing**: all ODE work arrays are packed into one `p` tuple, which is performance-critical for `DifferentialEquations.jl`.
- **Include-based composition (scripts)**: `include()` + manual include guards rather than proper module imports; pragmatic for research code, fragile for dependency tracking.
- **Interaction picture formulation**: separating linear dispersion from nonlinear effects lets the ODE solver use larger step sizes.
- **Adjoint method for gradients**: hand-derived adjoint ODE, exact and efficient, avoids AD through the ODE solver.
- **Single live gain implementation**: `simulate_disp_gain_mmf.jl` is the active gain-enabled path. The stale placeholder `src/simulation/simulate_disp_gain_smf.jl` was removed in Phase 25 after confirmed dead.
- **L-BFGS optimization**: `Optim.jl` with L-BFGS; `only_fg!()` computes cost and gradient simultaneously from a single forward-adjoint pass.

## Multi-Machine Workflow

This project runs on multiple machines (local Mac + GCP `claude-code-host` + occasional bursts on `fiber-raman-burst`).

The live working-tree model is:

- **Syncthing** keeps the Mac repo and the `claude-code-host` repo continuously synced.
- **Git** is for history, rollback, and GitHub pushes.
- **Burst** is not part of Syncthing. Stage code to burst explicitly and pull results back explicitly.

### Session hygiene — always do these

**At the START of any session on the Mac or `claude-code-host`:**

```bash
git status
```

Also verify Syncthing is healthy before trusting the shared workspace:

- Mac: `syncthing cli show connections`
- `claude-code-host`: `systemctl --user status syncthing --no-pager`

If Syncthing is down, fix that first. Do not reflexively `git pull` just because a session started. Syncthing handles Mac ↔ host file sync. Use git reconciliation only when you actually need updated remote history before a push or after another session lands commits.

**At the END of any session (or any logical stopping point):**

```bash
git status
git fetch origin
git add <specific files>
git commit -m "<type>(<scope>): <description>"
git push origin main
```

If `git push origin main` is rejected:

```bash
git fetch origin
git rebase origin/main
git push origin main
```

Syncthing moves file changes between the Mac and `claude-code-host`. Git records the checkpoint on `origin/main`.

### Documentation and history

- Active agent work lives in tracked `agent-docs/<topic>/` directories.
- Human-facing docs and polished reports live in `docs/`.
- Historical GSD material has been archived under `docs/planning-history/`.
- Do not revive `.planning/` for new work. If a historical note is still useful, reference it from `docs/planning-history/` and create new material in either `agent-docs/` or `docs/` as appropriate.
- `.git` is intentionally excluded from Syncthing. The working tree syncs; commit history does not.

### Machine inventory

| Machine | Role | Always on? |
|---|---|---|
| Local Mac (`/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression`) | Primary editing, exploration, advisor context | Yes (whenever laptop is on) |
| `claude-code-host` (GCP e2-standard-4, 34.152.124.66) | Remote Claude Code sessions, long-running tasks | Yes, 24/7 |
| `fiber-raman-burst` (GCP c3-highcpu-22) | Heavy Newton / multimode runs | On-demand (stopped by default) |

See `docs/planning-history/notes/compute-infrastructure-decision.md` for the full setup and rationale.

### Common pitfalls

- **Assuming Syncthing solves simultaneous edits**: it does not. If two machines edit the same file before syncing, Syncthing creates `.sync-conflict-*` files. Avoid overlapping edits to the same path.
- **Assuming Syncthing updates git history**: it does not. Syncthing moves files, not commits. Fetch or rebase when you actually need to reconcile with `origin/main`.
- **Forgetting to push at session end**: the other machine may have the file contents via Syncthing, but `origin/main` still needs the commit history.
- **Editing the same files from multiple machines or sessions**: keep concurrent sessions on non-overlapping files whenever possible. If a push is rejected, rebase on `origin/main` immediately before doing more work.
- **Mixing agent notes with human docs**: keep internal work products in `agent-docs/` and polished outputs in `docs/`.
- **Treating archived planning docs as active workflow state**: `docs/planning-history/` is historical context, not a live planning database.

## Parallel Session Operation Protocol

This project runs up to 8 concurrent Claude Code sessions on multiple machines (Mac + `claude-code-host` + sometimes `fiber-raman-burst`). Silent conflicts would destroy hours of work. Every agent in every session must follow this protocol.

### Rule P1: Session has an owned file namespace. Stay inside it.

When launched with a prompt from `docs/planning-history/notes/parallel-session-prompts.md`, the session owns a specific namespace. The agent must not write outside it. If it needs a change to shared code (for example, a utility in `scripts/common.jl`), it stops and escalates.

Session namespaces:

- New scripts or src files prefixed by session topic: `multivar_*.jl`, `mmf_*.jl`, `longfiber_*.jl`, `sweep_simple_*.jl`, `cost_audit_*.jl`, in `src/<session_topic>/`.
- `agent-docs/<session-topic>/` — entire work doc directory owned by one session.
- Human-facing deliverables in `docs/<session-topic>/` only when that session was explicitly tasked with producing user-facing docs or reports.

**Shared files — never modify without explicit user go-ahead:** `scripts/common.jl`, `scripts/visualization.jl`, `src/simulation/*.jl`, `src/sensitivity_*.jl`, `Project.toml`, `Manifest.toml`, `.gitignore`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/README.md`.

### Rule P2: All sessions work on `main` and push to `main`.

This repo no longer uses session branches as the default coordination model.
Every session stays on `main`.

Session hygiene for direct-to-`main` work:

```bash
git status
# ... do work ...
git fetch origin
git add <files>
git commit -m "..."
git push origin main
```

If `git push origin main` is rejected because another session landed first:

```bash
git fetch origin
git rebase origin/main
git push origin main
```

Do not create ad hoc `sessions/*` branches unless the user explicitly asks for an exception.

### Rule P3: Append-only edits to shared coordination docs

If a session must touch a shared coordination document, append a new dated entry rather than rewriting someone else’s notes. Better: write a session-local `agent-docs/<session-topic>/SUMMARY.md` and let the user integrate later.

### Rule P4: Git, not rsync, is the source of truth for tracked docs

`agent-docs/`, `docs/`, and the rest of the Mac/host working tree move through Syncthing. Git remains the source of truth for history. Do not use ad hoc rsync between the Mac and `claude-code-host`.

### Rule P5: Burst VM coordination — mandatory wrapper

A 2026-04-17 lockup from 7+ concurrent heavy Julia processes motivates the wrapper + watchdog. Pre-2026-04-17 manual lock pattern (`touch /tmp/burst-heavy-lock`) is deprecated. Full mechanism is in `scripts/burst/README.md`.

**Heavy runs** (>8 cores, >5 min, any simulation): never launch directly. Use the wrapper:

```bash
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy <SESSION-TAG> \
          'julia -t auto --project=. scripts/your_script.jl'"
```

The wrapper enforces session-tag format `^[A-Za-z]-[A-Za-z0-9_-]+$` (for example `A-multivar`, `E-sweep2`), acquires `/tmp/burst-heavy-lock` with stale-lock detection, launches in a named tmux, releases on exit (even on crash via `trap`), and tees stdout and stderr to `results/burst-logs/<tag>_<timestamp>.log`.

If another session holds the lock, `burst-run-heavy` fails immediately by default. To wait, set `WAIT_TIMEOUT_SEC=<seconds>`.

**Before any work on the burst VM, check state:** `burst-ssh "~/bin/burst-status"` (shows lock holder, tmux sessions, heavy processes, load and memory, watchdog).

**Light runs** (≤ 4 cores, quick validation): wrapper optional, but `<Letter>-<name>` tmux naming is still mandatory for `burst-status` attribution.

**Watchdog:** `~/bin/burst-watchdog` (as `raman-watchdog.service`) kills the youngest heavy Julia if 1-minute load > 35 or available memory < 4 GB, and at least 2 heavy Julia processes are active. A single job at 100% CPU is fine; the watchdog only fires on contention.

**If in doubt, treat as heavy**. Being blocked by the lock is cheaper than freezing the VM.

**On-demand second burst VM:** `~/bin/burst-spawn-temp <tag> '<command>'` creates an ephemeral VM from a machine image of `fiber-raman-burst`, runs the command, destroys the VM on exit via trap (plus 6-hour auto-shutdown). Keep concurrent ephemerals ≤ 2 (~$0.90/hr each). Run `~/bin/burst-list-ephemerals` to catch orphans.

### Rule P6: Session host distribution

The `claude-code-host` VM (e2-standard-4, 16 GB RAM) hosts about 3 concurrent Claude Code sessions before OOM. Distribute work accordingly:

- **Mac**: sessions doing heavy editing, lots of context, or light compute.
- **claude-code-host**: sessions needing the burst VM frequently (the `burst-*` helpers are only on `claude-code-host`).

Before a 4th session on `claude-code-host`, check `free -h`. If `available` < 3 GB, do not add more. See `docs/planning-history/notes/parallel-session-prompts.md` for prior session assignments and patterns.

### Rule P7: Remote-history checkpoints

Every 2–3 hours, or at natural breakpoints, each session should check whether `origin/main` has moved before starting another substantial edit block:

```bash
git fetch origin
git status
git rev-list --left-right --count main...origin/main
```

If `origin/main` is ahead, rebase before continuing:

```bash
git rebase origin/main
```

If the rebase surfaces conflicts, resolve them immediately or stop and escalate. Do not continue coding on a stale local base.

## Running Simulations — Compute Discipline

This project has dedicated compute infrastructure. Use it correctly. These rules apply to all agents running Julia simulations in this project.

### Rule 1: Always run simulations on the burst VM, never on `claude-code-host`

This rule has no exceptions. Any Julia execution that does nonlinear fiber propagation, forward solve, adjoint solve, optimization iteration, sweep point, sanity check, or simulation unit test goes on `fiber-raman-burst`.

`claude-code-host` is a small always-on VM (4 vCPU, 16 GB RAM) sized to host Claude Code, not to run compute. Even small sims on it will OOM, starve Claude Code of CPU, and make benchmarks unreproducible. If you think your run is small enough to skip the burst VM, use the burst VM anyway.

The only Julia work permitted on `claude-code-host`:

- `julia --version` and similar single-command checks
- `Pkg.status()`, `Pkg.instantiate()`, dependency resolution
- REPL help and doc lookups (no simulation calls)
- Reading saved JLD2 results for inspection (loading data, not re-running)

Everything else goes to the burst VM.

### How to use the burst VM (current pattern)

From `claude-code-host` (helpers in `~/bin/` on `PATH`):

```bash
# 1. Ensure Syncthing has brought the latest Mac/host workspace into this checkout.
syncthing cli show connections
# 2. Start the burst VM (~30s to boot).
burst-start
# 3. Stage a fresh workspace snapshot to burst (.git excluded on purpose).
rsync -az --delete \
      --exclude='.git' --exclude='.DS_Store' --exclude='.stfolder' \
      ~/fiber-raman-suppression/ \
      -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/
# 4. Check the VM is free before claiming the lock.
burst-ssh "~/bin/burst-status"
# 5. Run through the mandatory heavy-lock wrapper (Rule P5).
burst-ssh "cd fiber-raman-suppression && \
           ~/bin/burst-run-heavy E-sweep2 \
           'julia -t auto --project=. scripts/your_script.jl'"
# 6. Monitor (path printed by the wrapper).
burst-ssh "tail -f fiber-raman-suppression/results/burst-logs/E-sweep2_*.log"
# 7. Pull results back to claude-code-host; Syncthing moves them to the Mac.
rsync -az -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/results/ \
      ~/fiber-raman-suppression/results/
# 8. Always stop the VM when done (~$0.90/hr while running).
burst-stop
```

Raw `tmux new -d -s run 'julia ...'` is deprecated because it bypasses the heavy lock. Use `~/bin/burst-run-heavy`. Helpers: `burst-start`, `burst-stop`, `burst-ssh`, `burst-status`.

### Rule 2: Always launch Julia with threading enabled

The simulation core is single-threaded by default. Enable threading explicitly.

```bash
julia -t auto --project=. <script>      # all available threads (preferred)
julia -t 22 --project=. <script>        # or explicit count for burst VM
```

Never launch bare `julia` for simulation work. Verify with `Threads.nthreads() > 1`.

Threading speedups: parallel forward solves 3.55× at 8 threads; multi-start 2.13×. Do not enable FFTW threading at `Nt = 2^13` (counterproductive at this grid size); Tullio threading at `M = 1` is a no-op.

### Rule 3: Always stop the burst VM when simulations complete

The burst VM bills about $0.90/hr while running and $0 stopped. Leaving it running overnight or over a weekend wastes the free-trial budget quickly.

Before ending any session that touched the burst VM:

```bash
burst-status            # verify: TERMINATED means stopped
burst-stop              # if RUNNING, stop it now
```

### When the `deepcopy(fiber)` pattern is required

Multi-threaded Julia code sharing the `fiber` dict across threads will race because `fiber["zsave"]` and other fields are mutated inside solvers. Any `Threads.@threads` loop over independent solves must do:

```julia
Threads.@threads for i in 1:n_tasks
    fiber_local = deepcopy(fiber)      # per-thread copy
    # ... use fiber_local, never the shared fiber
end
```

Already used in `scripts/benchmark_optimization.jl:635` (multi-start) and `scripts/benchmark_optimization.jl:704` (parallel gradient validation). Copy this pattern when adding new parallel solve blocks (Newton Hessian, parameter sweeps).

### Summary — quick checklist before running any simulation

- [ ] Is this non-trivial per Rule 1? If yes, use the burst VM.
- [ ] Did I stage a fresh workspace snapshot to burst with `rsync` before running?
- [ ] Am I launching Julia with `-t auto` (or `-t N`)?
- [ ] If adding new parallel loops, am I `deepcopy(fiber)` per thread?
- [ ] When done, have I run `burst-stop`?
