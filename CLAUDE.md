<!-- GSD:project-start source:PROJECT.md -->
## Project

**Visualization Overhaul: SMF Gain-Noise Plotting**

A comprehensive fix of all plotting and visualization in the smf-gain-noise project (MultiModeNoise.jl). The goal is to produce clean, readable, physically informative plots for nonlinear fiber optics simulations — specifically Raman suppression optimization via spectral phase and amplitude shaping. Plots are for internal research group use (lab meetings, advisor reviews).

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
3. `{tag}_phase_diagnostic.png` — wrapped/unwrapped/group-delay triplet of phi_opt alone
4. `{tag}_evolution_unshaped.png` — matching waterfall with phi ≡ 0 for comparison

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

For runs that produced a `phi_opt` before this rule was in place, run `scripts/regenerate_standard_images.jl` (behind the heavy lock) to generate the standard set for every JLD2 under `results/raman/` that carries a phi_opt. Override the scan root via `REGEN_ROOT`.

Drivers that skip this step are incomplete. Do not mark work "done" without the standard images on disk.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

Julia ≥ 1.9.3 (Manifest pinned to 1.12.4) + Python/Matplotlib via PyCall for plotting. Headless plotting via `ENV["MPLBACKEND"] = "Agg"`. No secrets, no .env. Build via `Pkg.instantiate()`.

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
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Conventions
- `snake_case` functions; `!` suffix for in-place mutating (`disp_mmf!`, `adjoint_disp_mmf!`); `_` prefix for internal helpers (`_manual_unwrap`, `_central_diff`).
- ODE RHS: `{physics_model}!` (`disp_mmf!`). Parameter constructors: `get_p_{model}`. Setup: `setup_raman_problem`, `setup_amplitude_problem`.
- Physics variables use Unicode matching math notation: `λ0`, `ω0`, `β2`, `γ`, `φ`, `ũω`, `Δt`, `Δf`. Greek letters for physics quantities.
- Counters: `Nt` (temporal grid points), `M` (spatial modes), `Nt_φ` (phase grid).
- `UPPER_SNAKE_CASE` for module constants (`FIBER_PRESETS`, `C_NM_THZ`, `COLOR_INPUT`). Include guards: `_COMMON_JL_LOADED`.
- `PascalCase` for structs (`YDFAParams`). Use `@kwdef mutable struct` for typed parameter containers (only `YDFAParams` currently).

## Code Style
- 4-space indentation; no formatter configured.
- `@.` for vectorized ops: `@. uω = exp_D_p * ũω`.
- `@tullio` for tensor contractions (Einstein summation).
- Prefer `cis(x)` over `exp(im * x)` for phase rotations.

## Common Patterns
- Include guard (`_COMMON_JL_LOADED`) for files meant for multiple inclusion.
- `@assert` for preconditions AND postconditions (marked `# PRECONDITIONS` / `# POSTCONDITIONS`).
- Dict-based parameter passing: `sim::Dict{String,Any}`, `fiber::Dict{String,Any}` with string keys (`sim["Nt"]`, `fiber["Dω"]`).
- ODE parameter tuples preallocate all work arrays to avoid GC pressure during integration.
- `abspath(PROGRAM_FILE) == @__FILE__` guard in scripts that should not execute when `include`d.
- `try using Revise catch end` at top of scripts for optional hot-reload.

## Error Handling
- `@assert` for design-by-contract (in/out). `throw(ArgumentError(...))` for user-facing validation in core (`src/helpers/helpers.jl`). `@warn` for recoverable conditions (small time window). No try/catch in numerical code — errors propagate.

## Documentation Style
- Julia `"""..."""` docstrings above functions with `# Arguments`, `# Returns`, `# Example`.
- Physics comments explain the math: `# Chain rule: dJ/dphi(omega) = 2 * Re(lambda_0*(omega) * i * u_0(omega))`.
- Units always stated in comments (`# W^-1 m^-1`, `# s^2/m`, `# THz`).

## Logging
- `@info` for run summaries/milestones; `@debug` for iteration-level diagnostics (visible with `JULIA_DEBUG=all`); `@warn` for soft violations. `@sprintf` for formatting.

## SI Units Convention
- Wavelength: meters (e.g., `1550e-9`)
- Time: seconds for physics (`pulse_fwhm = 185e-15`), picoseconds for simulation grids
- Frequency: THz for spectral grids, Hz for repetition rates
- Power: Watts
- Dispersion: `s^2/m` for beta_2, `s^3/m` for beta_3
- Nonlinearity: `W^-1 m^-1`
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- Julia package (`Project.toml` / `Manifest.toml`); core physics as in-place ODE RHS functions (`!` convention).
- Forward-adjoint optimization: forward propagation + backward adjoint for gradient-based optimization.
- Dict-based parameter passing (`sim`, `fiber`); work arrays pre-packed into tuples to avoid GC pressure.
- Scripts use `include()` chains with manual include guards.

## Core Concepts
- **Interaction picture**: ODEs in the interaction picture separate fast linear (dispersive) dynamics from slow nonlinear dynamics. `exp_D_p`/`exp_D_m` phase factors transform between lab and interaction frames.
- **Kerr + Raman nonlinearity**: Instantaneous Kerr (tensor contraction `gamma[i,j,k,l]`) + delayed Raman (convolution with `hRω`), both contributing to `dũω`.
- **Self-steepening**: Frequency-dependent scaling (`ωs/ω0`) on the nonlinear term.
- **Adjoint method**: Backward propagation of adjoint field `λ` computes gradients of a cost functional w.r.t. input spectral phase — exact, efficient, avoids AD through the ODE solver.
- **Spectral band cost**: `J = E_band / E_total` — fractional energy in a Raman-shifted frequency band.
- **GRIN fiber modes**: Spatial modes from graded-index profile via finite-difference eigenvalue solver.
- **YDFA gain model**: Yb3+ rate equations using absorption/emission cross-sections from NPZ.

## Layers
- **Simulation core** (`src/simulation/`): ODE RHS, adjoint RHS, solvers, initial state generators.
- **Fiber setup** (`src/simulation/fibers.jl`, `src/helpers/helpers.jl`): GRIN mode solver, overlap tensor, `get_disp_sim_params`.
- **Gain model** (`src/gain_simulation/gain.jl`): `YDFAParams`, cross-section interpolation.
- **Analysis** (`src/analysis/`): Noise variance decomposition via Tullio contractions.
- **Optimization** (`scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`): cost/gradient, L-BFGS, regularization.
- **Shared library** (`scripts/common.jl`): `FIBER_PRESETS`, `setup_raman_problem`, `spectral_band_cost`, `recommended_time_window`.
- **Visualization** (`scripts/visualization.jl`): spectral/temporal evolution plots, optimization comparison, phase diagnostics.

## Data Flow
- State held in two Dicts: `sim` (grid/physical constants) and `fiber` (material/geometry).
- ODE state is complex matrix `ũω` of shape `(Nt, M)` in the interaction picture.
- Work arrays pre-allocated in tuples (`p` parameter) — zero allocations during integration.

## Key Abstractions
| Abstraction | Location | Purpose |
|-------------|----------|---------|
| `sim` Dict | `src/helpers/helpers.jl :: get_disp_sim_params()` | Grid params: `Nt`, `Δt`, `ts`, `fs`, `ωs`, `ω0`, `attenuator`, `ε`, `β_order` |
| `fiber` Dict | `src/helpers/helpers.jl :: get_disp_fiber_params_user_defined()` | Fiber params: `Dω`, `γ`, `hRω`, `L`, `one_m_fR`, `zsave` |
| `p` tuple (forward) | `src/simulation/simulate_disp_mmf.jl :: get_p_disp_mmf()` | Pre-allocated work arrays + FFT plans for forward ODE RHS |
| `p` tuple (adjoint) | `src/simulation/sensitivity_disp_mmf.jl :: get_p_adjoint_disp_mmf()` | Pre-allocated work arrays + FFT plans for adjoint ODE RHS |
| `YDFAParams` struct | `src/gain_simulation/gain.jl` | Typed parameter container for Yb-doped fiber amplifier |
| `FIBER_PRESETS` Dict | `scripts/common.jl` | Named fiber parameter presets (SMF28, HNLF variants) |
| `band_mask` Bool vector | `scripts/common.jl :: setup_raman_problem()` | Boolean mask selecting Raman-shifted frequency bins |

## Entry Points
- `src/MultiModeNoise.jl` — module root, loaded via `using MultiModeNoise`.
- `scripts/raman_optimization.jl` — runs 5 predefined optimization configs (SMF-28, HNLF) + chirp sensitivity.
- `scripts/amplitude_optimization.jl` — spectral amplitude optimization with multiple regularizations.
- `scripts/run_benchmarks.jl` — grid size, time window, continuation, multi-start, parallel gradient validation.
- `scripts/test_optimization.jl` — unit / contract / property / integration tests.
- `test/runtests.jl` — minimal smoke test (module loads).
- `notebooks/*.ipynb` — interactive MMF squeezing / EDFA-YDFA gain / supercontinuum exploration.

## Design Decisions
- **Dict-based parameters over structs**: flexible key addition (`fiber["zsave"]` is mutated by optimization code) at the cost of type safety.
- **Pre-allocated tuple packing**: all ODE work arrays packed into one `p` tuple — performance-critical for `DifferentialEquations.jl`.
- **Include-based composition (scripts)**: `include()` + manual include guards rather than proper module imports — pragmatic for research code, fragile for dependency tracking.
- **Interaction picture formulation**: separating linear dispersion from nonlinear effects lets the ODE solver use larger step sizes.
- **Adjoint method for gradients**: hand-derived adjoint method / adjoint ODE — exact and efficient, avoids AD through the ODE solver.
- **Single live gain implementation**: `simulate_disp_gain_mmf.jl` is the active gain-enabled path. The stale placeholder `src/simulation/simulate_disp_gain_smf.jl` was removed in Phase 25 after confirmed dead.
- **L-BFGS optimization**: `Optim.jl` with L-BFGS; `only_fg!()` computes cost+gradient simultaneously from a single forward-adjoint pass.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

**Strict mode is ON in this project.** `hooks.workflow_guard_strict: true` is set in `.planning/config.json`, so the `PreToolUse` guard at `~/.claude/hooks/gsd-workflow-guard.js` will **hard-deny** `Write`/`Edit` tool calls that target source files outside a GSD workflow context (no active `/gsd-*` skill and no Task subagent).

Allow-list (always permitted, even outside GSD): `.planning/**`, `.gitignore`, `.env*`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `settings.json`.

When starting any edit on a tracked source file, route through:
- `/gsd-fast` — trivial one-shot edits, no planning overhead
- `/gsd-quick` — small fixes, doc updates, ad-hoc tasks with state tracking
- `/gsd-debug` — investigation and bug fixing
- `/gsd-execute-phase` — planned phase work

If the user explicitly says "bypass GSD for this one" (or similar), flip `hooks.workflow_guard_strict` to `false` in `.planning/config.json` for the duration of the task, then flip it back. Do NOT silently work around the block any other way.
<!-- GSD:workflow-end -->

## Codex Runtime Constraints

**Context:** Codex's skill adapter translates Claude's `Task(...)` → `spawn_agent(...)`, but sometimes silently falls back to inline execution. Heavy orchestrators (`plan-phase`, `execute-phase`, `autonomous`) lose their plan-check / verifier / atomic-commit protocol when this happens, leaving phases uninauditable (see the Phase 28 `integrate(phase28-34)` single-commit incident).

### Whitelist — Codex MAY invoke these skills

Single-scope, inline-safe, no named subagents required:

- `$gsd-fast`, `$gsd-quick`, `$gsd-note`, `$gsd-add-todo`, `$gsd-add-backlog`
- `$gsd-progress`, `$gsd-stats`, `$gsd-check-todos`, `$gsd-help`, `$gsd-status`
- `$gsd-explore`, `$gsd-spike`, `$gsd-sketch`, `$gsd-plant-seed`
- `$gsd-research-phase` (standalone research only — DO NOT chain to plan or execute)

### Blacklist — Codex MUST NOT invoke these skills

Require subagent orchestration (`gsd-planner`, `gsd-phase-researcher`, `gsd-executor`, `gsd-plan-checker`, `gsd-verifier`, etc.):

- `$gsd-plan-phase`, `$gsd-execute-phase`, `$gsd-execute-plan`
- `$gsd-autonomous`, `$gsd-plan-review-convergence`
- `$gsd-verify-work`, `$gsd-review`, `$gsd-ship`, `$gsd-debug`
- `$gsd-audit-fix`, `$gsd-audit-milestone`, `$gsd-audit-uat`, `$gsd-code-review`
- `$gsd-ingest-docs`, `$gsd-new-milestone`, `$gsd-new-project`

If a Codex session determines it needs a blacklisted skill, it MUST stop and return this exact phrase:

> "This task requires the `[name]` skill, which depends on named subagent orchestration. Codex's adapter is unreliable for this. Please re-run in Claude Code."

**Do NOT** silently execute inline. **Do NOT** manually replicate the skill's workflow (no hand-writing `PHASE-SUMMARY.md`, no fabricating `manifest.json`, no batch-committing multiple plans). Return control to the user.

### Verification after any Codex session touching `.planning/phases/`

```bash
bash scripts/check-phase-integrity.sh <phase-number>
```

Exits 0 if protocol was followed, 1 if violations detected. Run before ending any Codex session that touched phase artifacts; run on any phase you suspect was commit-bombed.

## Multi-Machine Workflow

This project runs on **multiple machines** (local Mac + GCP claude-code-host + occasional bursts on fiber-raman-burst). The same repo is cloned on each machine. Without discipline, divergent commits on different machines produce merge conflicts.

### Session hygiene — always do these

**At the START of any Claude Code session (regardless of machine):**

```bash
git fetch origin
git status                        # check for divergence / uncommitted changes
git pull --ff-only origin main    # apply remote changes if local is behind
```

If `git pull --ff-only` fails (diverged histories), the other machine has committed work that isn't in this checkout. Do NOT proceed with edits before reconciling — merging or rebasing blindly after a long session can lose work. Surface it to the user for a decision.

**At the END of any session (or any logical stopping point):**

```bash
git status                        # confirm what's about to be committed
git add <specific files>          # prefer explicit over "git add -A"
git commit -m "<type>(<scope>): <description>"
git push origin main              # so the other machines can pull
```

### Gitignored state: `.planning/` and memory

The `.planning/` directory and `~/.claude/projects/.../memory/` files are **not** tracked in git. Changes there only propagate via the local sync helpers on the Mac:

- `sync-planning-to-vm` — Mac → VM (push planning + memory)
- `sync-planning-from-vm` — VM → Mac (pull planning + memory)

Run these explicitly whenever `.planning/` or memory has been edited on one side. After running `sync-planning-from-vm`, re-read any `.planning/` file you had open — the on-disk content may have changed.

### Machine inventory

| Machine | Role | Always on? |
|---|---|---|
| Local Mac (`/Users/ignaciojlizama/RiveraLab/fiber-raman-suppression`) | Primary editing, exploration, advisor context | Yes (whenever laptop is on) |
| `claude-code-host` (GCP e2-standard-4, 34.152.124.66) | Remote Claude Code sessions, long-running tasks | Yes, 24/7 |
| `fiber-raman-burst` (GCP c3-highcpu-22) | Heavy Newton / multimode runs | On-demand (stopped by default) |

See `.planning/notes/compute-infrastructure-decision.md` for the full setup and rationale.

### Common pitfalls

- **Forgetting to pull at session start** → diverged commits, merge conflicts later. Always fetch+pull first.
- **Forgetting to push at session end** → other machines can't see the work. Always push before closing out.
- **Editing `.planning/` on one machine without syncing** → stale state on the other. Run `sync-planning-{to,from}-vm` explicitly.
- **Multiple parallel Claude Code sessions editing the same files** → use git worktrees or enforce non-overlapping directory scope per session.

## Parallel Session Operation Protocol

**This project runs up to 8 concurrent Claude Code sessions on multiple machines (Mac + claude-code-host + sometimes fiber-raman-burst). Silent conflicts would destroy hours of work. Every agent in every session MUST follow this protocol.**

### Rule P1: Session has an OWNED FILE NAMESPACE. Stay inside it.

When launched with a prompt from `.planning/notes/parallel-session-prompts.md`, the session owns a specific namespace. The agent MUST NOT write outside it. If it needs a change to shared code (e.g., a utility in `scripts/common.jl`), it STOPS and escalates — no silent edits to shared files.

Session namespaces:
- New scripts/src prefixed by session topic: `multivar_*.jl`, `mmf_*.jl`, `longfiber_*.jl`, `sweep_simple_*.jl`, `cost_audit_*.jl`, in `src/<session_topic>/`.
- `.planning/phases/<N>-<session-topic>/` — entire phase dir owned by one session.
- `.planning/notes/<session-topic>-*.md`, `.planning/seeds/<session-topic>-*.md`.

**Shared files — NEVER modify without explicit user go-ahead:** `scripts/common.jl`, `scripts/visualization.jl`, `src/simulation/*.jl`, `src/sensitivity_*.jl`, `Project.toml`, `Manifest.toml`, `.gitignore`, `CLAUDE.md`, `README.md`, `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `.planning/PROJECT.md`, `.planning/MILESTONES.md`.

### Rule P2: Branch-per-session. Never push directly to `main`.

Each session works in a git worktree on its own branch:

```bash
git worktree add ../raman-wt-<session-name> sessions/<session-name>
cd ../raman-wt-<session-name>
# ... session work ...
git commit -m "..."
git push origin sessions/<session-name>
```

**The session NEVER runs `git push origin main`.** Only the user (or a single integrator session) merges session branches into main at coordination checkpoints. This eliminates the push race.

### Rule P3: Append-only edits to shared `.planning/` files

If a session MUST touch `STATE.md` / `ROADMAP.md`, append a new row — never edit existing rows. Better: write to `.planning/sessions/<session-name>-status.md`; the user aggregates at checkpoints.

### Rule P4: Sync helpers are non-destructive

`sync-planning-to-vm` / `sync-planning-from-vm` use `rsync --update` (not `--delete`) and exclude git-tracked files (`STATE.md`, `ROADMAP.md`):
- Files on only one side are preserved.
- On conflict, more recently modified version wins (per `--update`).
- `STATE.md` / `ROADMAP.md` go through git, not rsync — run `git pull` for those.

Do NOT run sync-planning-* while another session is actively editing `.planning/` on either side.

### Rule P5: Burst VM coordination — MANDATORY WRAPPER

A 2026-04-17 lockup from 7+ concurrent heavy Julia processes motivates the wrapper + watchdog. Pre-Apr-17 manual lock pattern (`touch /tmp/burst-heavy-lock`) is DEPRECATED. Full mechanism in `scripts/burst/README.md`.

**Heavy runs** (>8 cores, >5 min, any simulation): never launch directly. Use the wrapper:

```bash
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy <SESSION-TAG> \
          'julia -t auto --project=. scripts/your_script.jl'"
```

The wrapper enforces session-tag format `^[A-Za-z]-[A-Za-z0-9_-]+$` (e.g., `A-multivar`, `E-sweep2`), acquires `/tmp/burst-heavy-lock` with stale-lock detection, launches in a named tmux, releases on exit (even on crash via `trap`), and tees stdout/stderr to `results/burst-logs/<tag>_<timestamp>.log`.

If another session holds the lock, `burst-run-heavy` fails immediately by default. To wait: `WAIT_TIMEOUT_SEC=<seconds>`.

**Before any work on the burst VM, check state:** `burst-ssh "~/bin/burst-status"` (shows lock holder, tmux sessions, heavy procs, load/memory, watchdog).

**Light runs** (≤ 4 cores, quick validation): wrapper optional, but `<Letter>-<name>` tmux naming is still mandatory for `burst-status` attribution.

**Watchdog:** `~/bin/burst-watchdog` (as `raman-watchdog.service`) kills the youngest heavy Julia if 1-min load > 35 OR available memory < 4 GB, AND ≥ 2 heavy Julia processes are active. Single job at 100% CPU is fine — the watchdog only fires on contention.

**If in doubt, treat as heavy** — being blocked by the lock is cheaper than freezing the VM.

**On-demand second burst VM:** `~/bin/burst-spawn-temp <tag> '<command>'` creates an ephemeral VM from a machine image of `fiber-raman-burst`, runs the command, destroys the VM on exit via trap (plus 6-hour auto-shutdown). Keep concurrent ephemerals ≤ 2 (~$0.90/hr each). Run `~/bin/burst-list-ephemerals` to catch orphans.

### Rule P6: Session host distribution

The `claude-code-host` VM (e2-standard-4, 16 GB RAM) hosts ~3 concurrent Claude Code sessions before OOM. Distribute:
- **Mac**: sessions doing heavy editing / lots of context / light compute. Each in its own `~/raman-wt-<name>` worktree.
- **claude-code-host**: sessions needing the burst VM frequently (the `burst-*` helpers are only on claude-code-host).

Before a 4th session on claude-code-host, check `free -h` — if `available` < 3 GB, don't add more. See `.planning/notes/parallel-session-prompts.md` for per-session assignments.

### Rule P7: Integration checkpoints

Every 2–3 hours (or at natural breakpoints), the USER (not a session) does an integration pass:

```bash
git fetch origin
git branch -r | grep sessions/     # see which session branches have new work
for branch in sessions/B-handoff sessions/D-simple ... ; do
  git log main..origin/$branch --oneline
done
git checkout main
git merge origin/sessions/B-handoff --no-ff
git push origin main
```

Sessions pull from main at the start of their next work block to incorporate the integrations.

## Running Simulations — Compute Discipline

**This project has dedicated compute infrastructure. Use it correctly. These rules apply to ALL agents (Claude Code, sub-agents, planners, executors) running Julia simulations in this project.**

### Rule 1: ALWAYS run simulations on the burst VM, never on `claude-code-host`

**This rule has NO exceptions.** Any Julia execution that does nonlinear fiber propagation — forward solve, adjoint solve, optimization iteration, sweep point, sanity check, unit test of the simulation code — goes on `fiber-raman-burst`.

`claude-code-host` is a small always-on VM (4 vCPU, 16 GB RAM) sized to host Claude Code, not to run compute. Even "small" sims on it will OOM (each Claude Code session uses 1–4 GB), starve Claude Code of CPU, and make benchmarks unreproducible. If you think your run is "small enough to skip the burst VM," use the burst VM anyway — the 30s VM-start overhead is trivial.

**The ONLY Julia work permitted on `claude-code-host`:**
- `julia --version` and similar single-command checks
- `Pkg.status()`, `Pkg.instantiate()`, dependency resolution
- REPL help / doc lookups (no simulation calls)
- Reading saved JLD2 results for inspection (loading data, not re-running)

Everything else → burst VM.

### How to use the burst VM (current pattern)

From `claude-code-host` (helpers in `~/bin/` on PATH):

```bash
# 1. Commit and push code first (burst VM pulls from git).
git add <files> && git commit -m "..." && git push
# 2. Start the burst VM (~30s to boot).
burst-start
# 3. Check the VM is free before claiming the lock.
burst-ssh "~/bin/burst-status"
# 4. Run through the MANDATORY heavy-lock wrapper (Rule P5).
burst-ssh "cd fiber-raman-suppression && git pull && \
           ~/bin/burst-run-heavy E-sweep2 \
           'julia -t auto --project=. scripts/your_script.jl'"
# 5. Monitor (path printed by the wrapper).
burst-ssh "tail -f fiber-raman-suppression/results/burst-logs/E-sweep2_*.log"
# 6. Pull results back.
rsync -az -e "gcloud compute ssh --zone=us-east5-a --project=riveralab --" \
      fiber-raman-burst:~/fiber-raman-suppression/results/ \
      ~/fiber-raman-suppression/results/
# 7. ALWAYS STOP THE VM WHEN DONE (~$0.90/hr while running).
burst-stop
```

Raw `tmux new -d -s run 'julia ...'` is DEPRECATED — bypasses the heavy-lock. Use `~/bin/burst-run-heavy`. Helpers: `burst-start`, `burst-stop`, `burst-ssh`, `burst-status`.

### Rule 2: ALWAYS launch Julia with threading enabled

**The simulation core is single-threaded by default — enable threading explicitly.** Without it, you use 1 core out of 4 (or 22 on the burst VM).

```bash
julia -t auto --project=. <script>      # all available threads (PREFERRED)
julia -t 22 --project=. <script>        # or explicit count for burst VM
```

**Never launch bare `julia` for simulation work.** Verify with `Threads.nthreads()` > 1.

Threading speedups: parallel forward solves 3.55× at 8 threads; multi-start 2.13×. Do NOT enable FFTW threading at Nt=2^13 (counterproductive at this grid size); Tullio threading at M=1 is a no-op (tensor contractions trivial). These numbers require `-t N` at launch.

### Rule 3: ALWAYS stop the burst VM when simulations complete

The burst VM bills ~$0.90/hr while running, $0 stopped. Leaving it running overnight costs ~$21; over a weekend, ~$65. The 4-week $300 free trial evaporates fast.

Before ending any session that touched the burst VM:

```bash
burst-status            # verify: TERMINATED means stopped
burst-stop              # if RUNNING, stop it now
```

### When the `deepcopy(fiber)` pattern is required

Multi-threaded Julia code sharing the `fiber` dict across threads **will race** because `fiber["zsave"]` and other fields are mutated inside solvers. Any `Threads.@threads` loop over independent solves must do:

```julia
Threads.@threads for i in 1:n_tasks
    fiber_local = deepcopy(fiber)      # per-thread copy
    # ... use fiber_local, never the shared fiber
end
```

Already used in `scripts/benchmark_optimization.jl:635` (multi-start) and `:704` (parallel gradient validation). Copy this pattern when adding new parallel solve blocks (Newton Hessian, parameter sweeps).

### Summary — quick checklist before running any simulation

- [ ] Is this "non-trivial" per Rule 1? → YES: use burst VM. NO: may run on `claude-code-host`.
- [ ] Did I commit and push my code so the burst VM's `git pull` gets them?
- [ ] Am I launching Julia with `-t auto` (or `-t N`)?
- [ ] If adding new parallel loops: am I `deepcopy(fiber)` per thread?
- [ ] When done: have I run `burst-stop`?

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
