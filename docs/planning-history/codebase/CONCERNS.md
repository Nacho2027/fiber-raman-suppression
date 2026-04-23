# Codebase Concerns

**Analysis Date:** 2026-04-19
**Supersedes:** 2026-04-05 audit. Several items fixed; new parallel-session risks surfaced.

This is a research codebase (quantum-noise / Raman-suppression simulation, Rivera Lab @ Cornell). Not user-facing. No secrets, no network exposure except GCP SSH. The dominant risk axes are (in order of real impact): **scientific correctness of the adjoint/optimization stack**, **reproducibility across the 8-session parallel workflow**, **compute-cost runaway on `fiber-raman-burst`**, **thread-safety of the mutating `fiber` Dict**, and **repo hygiene** (large binary results, untracked LaTeX artifacts, gitignored `.planning/` vs. force-added session docs).

## Severity legend

- **CRITICAL**: silently corrupts results or can halt the project (VM lockup, data loss)
- **HIGH**: a specific bug a contributor is likely to trip over in normal work
- **MEDIUM**: tech debt that slows work / makes physics harder to interpret
- **LOW**: cosmetic or easily-patched

## Resolved since 2026-04-05

These no longer need tracking:

| Item | Resolution | Commit / location |
|---|---|---|
| Broken `compute_noise_map_modem` shipped in module | Moved to `src/_archived/analysis_modem.jl` with archival header; `src/MultiModeNoise.jl` no longer includes it. Notebook reference parked. | `src/_archived/README.md`; commit `a28ba45`, `12cea85` |
| Missing `.gitignore` | Present at repo root. Ignores `Manifest.toml`, `*.jld2`, `results/raman/sweeps/`, `results/raman/phase1[012]/`, `results/images/`, `.planning/`, `__pycache__`, LaTeX intermediates | `.gitignore` |
| Minimal test suite (1 `@test true`) | Tiered suite added: `test/tier_fast.jl` (176), `tier_slow.jl` (109), `tier_full.jl` (77); 11 test files total ~1740 LoC covering Phase 13 primitives/HVP, Phase 14 sharpness, Phase 16 MMF (13 assertions), determinism, cost-audit. Dispatched via `TEST_TIER` env var in `test/runtests.jl`. | `test/`, commit `eb691df` (Session B) |
| Non-deterministic FFTW planner | Pinned to `ESTIMATE` for reproducibility via `scripts/determinism.jl::ensure_deterministic_environment()`; validated bit-identical cross-process (Phase 15). Cost: +21.4% runtime. | `scripts/determinism.jl`, Phase 15 merge |
| Standard-image set not produced by drivers | Project-level rule in `CLAUDE.md` mandates `save_standard_set(...)` at the end of every driver producing `phi_opt`. Most drivers wired (see Partial Wiring below). Legacy drivers patched in commit `12cea85`. | `scripts/standard_images.jl` (158 LoC) |
| README minimal (7 lines, Windows paths) | Session B docs suite replaced it along with 9 supporting docs + Makefile | commit `eb691df` |
| Duplicate `simulate_disp_gain_smf.jl` placeholder | Deleted in Phase 25. `scripts/benchmark.jl` now swaps FFTW planner flags only in the three live simulation files, and codebase docs were updated to stop advertising the dead SMF gain file. | Phase 25 |
| `pulse_form` silent fallthrough | Fixed in Phase 25. `get_initial_state` and `get_initial_state_gain_smf` now throw `ArgumentError` for unsupported pulse shapes, and `test/tier_fast.jl` covers the regression. | Phase 25 |

## Critical Issues

### The `fiber` Dict is mutated during solves — per-thread `deepcopy(fiber)` is a footgun

- **Issue:** `fiber["zsave"]` is set to `nothing` (or to a `LinRange`) inside many drivers and library callers as a *side effect* of running a forward solve. See `scripts/raman_optimization.jl:203`, `scripts/longfiber_optimize_100m.jl:193`, `scripts/sweep_simple_param.jl:318`, `scripts/simple_profile_driver.jl:325,610`, `scripts/robustness_test.jl:129`, `scripts/multivar_optimization.jl:561`, `scripts/hvp.jl:89`, `scripts/test_multivar_gradients.jl:55`, `scripts/cost_audit_driver.jl:273`, `scripts/sharpness_optimization.jl:476`. Any `Threads.@threads` loop sharing one `fiber` instance across threads will race on this assignment.
- **Status:** The `deepcopy(fiber)` pattern is documented in `CLAUDE.md` (§"When the `deepcopy(fiber)` pattern is required", lines 593–608) and is followed in the major parallel drivers: `scripts/sweep_simple_run.jl:447` (the 64-config `Threads.@threads` in `run_sweep2`), `scripts/benchmark_optimization.jl:635,725`, `scripts/benchmark_threading.jl:298,313,367,381`. There are 40+ call sites using `deepcopy(fiber)` across the scripts (grep confirms).
- **Risk surface for new code:** There is no mechanical enforcement. A new `Threads.@threads` or `@spawn` loop that forgets `deepcopy` will hit a silent race — not a crash — because the mutations are consistent types. Results would be wrong but look plausible. MMF `Threads.@threads` (Phase 16/18) is a likely next introduction point.
- **Severity:** CRITICAL (silent-correctness risk)
- **Fix approach (true fix):** Stop mutating `fiber` from callers. Either (a) refactor `setup_raman_problem` and solve entry points to consume `zsave` as a keyword arg that never writes back, or (b) make `fiber` immutable (convert to a `NamedTuple` or typed struct). Option (b) also lets the type checker catch `fiber["Dw"]` typos at parse time (see MEDIUM issue below).
- **Fix approach (stopgap):** Add a `@test` in `test/tier_fast.jl` that asserts `fiber` is unmutated after a representative optimize / propagate call (Session C's Phase 16 test set has something close — extend to all solve entry points). Catches the specific regression "someone removed the deepcopy."

### Resolved 2026-04-20 — dead `simulate_disp_gain_smf.jl` placeholder removed

- **What changed:** The unused placeholder file was deleted, the Phase 15 benchmark stopped editing it, and the codebase docs no longer advertise it as a live module.
- **Why this mattered:** It was a future-contributor trap: one extra `include(...)` would have produced method redefinition conflicts and two competing stories about where gain propagation really lived.

### Burst-VM lockup risk — wrapper is mandatory but not fully machine-enforced

- **Issue:** On 2026-04-17, 7+ concurrent heavy Julia processes on the 22-core `fiber-raman-burst` VM caused a hard kernel lockup (requires console reset). Post-incident fix deployed:
  - `~/bin/burst-run-heavy` wrapper (`scripts/burst/run-heavy.sh`, 129 lines): enforces `^[A-Za-z]-[A-Za-z0-9_-]+$` session tag, acquires `/tmp/burst-heavy-lock`, releases on trap.
  - `~/bin/burst-watchdog` systemd-user service (`scripts/burst/watchdog.sh`, 82 lines): kills youngest heavy julia if 1-min load > 35 OR available mem < 4 GB AND ≥ 2 heavy julias active.
- **Remaining risk:** Enforcement is policy + honor system, not guaranteed.
  1. `burst-run-heavy` is only invoked if the caller explicitly runs it. Nothing on the VM prevents a bare `tmux new -d -s X 'julia ...'`. CLAUDE.md Rule P5 calls this out (`Never tmux new -d 'julia ...' directly`), and the BIG_WARNING for Session G (`.planning/phases/18-sharp-ab-execution/BIG_WARNING.md`) reiterates. But agents forget.
  2. The lock is file-based with PID liveness check (`run-heavy.sh:45-56`). If the VM is rebooted and a stale `/tmp/burst-heavy-lock` survives, the stale-detection logic only looks at the pid; `/tmp` is tmpfs so reboot clears it, but a crashed wrapper that doesn't trap cleanly (e.g., SIGKILL from OOM killer) could leave an orphan lock file with a dead pid. The stale-check handles this, but only *detects* staleness on the next `burst-run-heavy` attempt — a half-running Julia job with its wrapper SIGKILLed would still be holding memory/CPU while the lock is declared stale. Next job then piles on.
  3. The watchdog only kills when ≥ 2 heavy julias are running (`watchdog.sh:70`). A single runaway job (e.g., OOM-spiraling Newton Hessian) won't trigger it. Intentional choice (so a legitimate 100%-CPU job isn't killed) but means single-job pathologies need manual intervention.
  4. The ephemeral-VM spawner (`burst-spawn-temp`) has a trap + 6-hour auto-shutdown backup. Orphans possible if claude-code-host dies mid-spawn (trap never fires). Mitigation: `~/bin/burst-list-ephemerals` manual check.
- **Severity:** CRITICAL (incident recurrence would cost a workday and budget)
- **Fix approach:**
  - Add a read-only pre-flight check in every MMF/heavy driver: `error()` out if `hostname` matches burst-VM pattern AND `ps -ef | grep -c '[j]ulia.*simulate'` > 1 AND `$BURST_HEAVY_LOCK_BYPASS` is unset. Forces discipline.
  - Tighten watchdog to trigger on single-process memory pressure (e.g., 1 julia using > 80% RAM) — separate rule from the multi-job load path.
  - Add a cron job on claude-code-host that greps `~/bin/burst-list-ephemerals` once an hour and pings if non-empty for > 2 h.

## High-Severity Tech Debt

### Session A: joint-space L-BFGS stuck at -16.78 dB vs phase-only -55.42 dB

- **Issue:** Phase 18-multivar-convergence-fix. Session A's joint `{φ(ω), A(ω), E_in}` L-BFGS optimizer (`scripts/multivar_optimization.jl` 1080 LoC, `scripts/multivar_demo.jl`, plus unit/gradient tests) is infrastructure-complete but physics-broken. On SMF-28 L=2m P=0.30W, joint cold-start reaches -16.78 dB while phase-only (which is a feasible point in joint space!) reaches -55.42 dB. **38-dB gap. Pathological preconditioning/scaling**, not missing local minima.
- **Files:** `.planning/phases/18-multivar-convergence-fix/CONTEXT.md`, `scripts/multivar_optimization.jl`, `scripts/multivar_demo.jl`, `.planning/phases/16-multivar-optimizer/16-01-SUMMARY.md`
- **Impact:** The "joint optimization" claim currently has no evidence behind it. Any paper/thesis draft citing this infrastructure as functional would be making an overstatement.
- **Severity:** HIGH
- **Fix approach (Session A's own recommendations in CONTEXT.md §Candidate fixes):**
  1. Amplitude-only warm-start (freeze φ at 0, optimize A, then unfreeze).
  2. Two-stage freeze-φ-then-unfreeze from phase-only optimum.
  3. Diagonal Hessian preconditioner (Phase 13 tooling). L-BFGS's implicit Hessian is poorly scaled across φ-radians, A-fractions, E-Joules.
  4. Trust-region Newton if indefinite curvature (Phase 13 already found indefinite Hessians on canonical optima).

### Session G: sharp-ab drivers committed but never executed

- **Issue:** Phase 18-sharp-ab-execution. Three drivers (`scripts/sharp_ab_slim.jl`, `scripts/sharp_robustness_slim.jl`, `scripts/sharp_ab_figures.jl`, total ~589 LoC) sit on main *with zero JLD2 results and no FINDINGS.md*. Per user, Session G hit "Opus 4.7-side issues" mid-Phase 16 and the agent never launched the runs. No verification the scripts even compile against current main (BIG_WARNING.md lists "compile-check" as a mandatory first step).
- **Files:** `scripts/sharp_ab_slim.jl` (wires `save_standard_set` at line 194 — good), `scripts/sharp_robustness_slim.jl` (no `save_standard_set`), `scripts/sharp_ab_figures.jl` (no `save_standard_set`), `.planning/phases/18-sharp-ab-execution/BIG_WARNING.md`, `.planning/phases/18-sharp-ab-execution/CONTEXT.md`
- **Impact:** Phase 14's central question (does sharpness-aware beat vanilla on σ_3dB?) remains unanswered on main's code. Session D's SHARP_LUCKY verdict gives a cheap prior but doesn't close it.
- **Severity:** HIGH (blocks synthesis conclusion)
- **Fix approach:** Listed in `BIG_WARNING.md` — compile-check, patch any stale-API references (post-Phase-15 determinism, post-Session-B `src/_archived`), run the three burst-VM jobs in sequence, write `results/raman/phase14-sharp-ab/FINDINGS.md`. Also wire `save_standard_set` into `sharp_robustness_slim.jl` and `sharp_ab_figures.jl`.

### Session H Config C (HNLF L=1m P=0.5W): 0/4 variants, both attempts hung > 1 h

- **Issue:** Phase 18-cost-config-c. Cost-function audit hung twice on the HNLF high-power configuration under default `max_iter`. Tells us either the HNLF-high-P cost landscape is much harder than SMF-28 (multiple basins, Raman-threshold crossed), or one variant has an interior-loop pathology (noise-aware scaffold suspected). Blocked pending different compute strategy.
- **Files:** `.planning/phases/18-cost-config-c/CONTEXT.md`, `scripts/cost_audit_driver.jl`, burst logs `results/burst-logs/H-auditF_*.log`, `H-audit_*.log`
- **Impact:** Config C is a row of `TBD` in the audit summary. The `log_dB` winner claim from Config A (`-75.8 dB` in `10.6 s`) is only validated at SMF-28 canonical.
- **Severity:** HIGH
- **Fix approach:** Single-variant pilot (`log_dB` only on Config C), shorter `max_iter=30`, early-stop on `|grad| < 1e-4 OR ΔJ < 0.1 dB over 5 iter`, live log-tail with 30-min kill rule. Skip noise-aware (unvalidated scaffold). See CONTEXT.md §"Recommended strategy for re-attempt".

### Phase 18 MMF baseline: aggressive run never confirmed

- **Issue:** Phase 18-mmf-baseline-execute. Session C built the M=6 scaffolding (13/13 tests pass on burst VM), but only the *sub-soliton* config (L=1m, P=0.05W, N_sol ≈ 0.9) ran to completion — with a correct zero-improvement result (no Raman to suppress). The **aggressive config** (L=2m, P=0.5W, N_sol ≈ 2–3, firmly Raman-active) was queued on the burst VM as `C-phase16-agg` (pid 16617 at handoff) but the VM became unreachable before the run confirmed. Queued job may still be alive or may have completed unseen.
- **Files:** `scripts/run_aggressive.jl`, `scripts/mmf_raman_optimization.jl`, `scripts/mmf_m1_limit_run.jl`, `test/test_phase16_mmf.jl`, `.planning/phases/18-mmf-baseline-execute/CONTEXT.md`, `.planning/phases/16-multimode-raman-suppression-baseline/16-01-SUMMARY.md` (has `_TBD_` rows waiting)
- **Impact:** Zero real multimode Raman-suppression numbers exist on main. The Phase 16 summary is a placeholder.
- **Severity:** HIGH (blocks the whole multimode direction)
- **Fix approach:** CONTEXT.md is explicit — re-verify tests, run smoke, launch `run_aggressive.jl` through `burst-run-heavy C2-agg`. Expected wall 30–90 min. Check `burst-status` first for the stale pid 16617. Inspect `results/burst-logs/C-phase16-agg_*.log` if present.

### Massive untracked results and presentation artifacts — single-machine-only

- **Issue:** `results/` is 82 MB total on disk. `results/raman` alone is 75 MB. `presentation-2026-04-17/` is 7.5 MB (untracked, contains 17 PNG walkthrough figures + `README-walkthrough.md` + pedagogical explainer — but not in git). `reports/` is untracked and contains LaTeX intermediates (`*.aux`, `*.log`, `*.toc`) *and* the final PDF `overnight-synthesis-2026-04-17.pdf` + `professor-briefing-2026-04-17.pdf`. `.gitignore` catches `results/raman/phase1[012]/` and `results/raman/sweeps/` but the newer dirs (`phase14-sharp-ab/`, `phase16/`, `phase16-cost-audit/`, `phase_sweep_simple/`) are uncovered — though `*.jld2` catches files by type.
- **Current state:** 193 PNGs + 19 JLD2 + 2 NPZ tracked in git (per `git ls-files`). `.git` is 527 MB — ~15× the actual code size. Large portion is historical PNGs and notebooks.
- **Impact:**
  - Presentation materials and LaTeX-compiled briefings **exist only on the machine that built them**. If Mac loses them before `git add -f` + push, they're gone.
  - Other machines (burst VM, ephemeral VMs, claude-code-host) have no way to reach the presentation figures. Sync helpers (`sync-planning-to-vm`, `sync-planning-from-vm`) only cover `.planning/` + memory, not `presentation-*/` or `reports/`.
  - `.git` size will grow unboundedly each time a result PNG lands accidentally.
- **Severity:** HIGH (data-loss risk for the advisor-meeting artifacts)
- **Fix approach:**
  - Decide policy for `presentation-*/` and `reports/`: either `git add -f` + push (text artifacts small, PNGs ~7.5 MB total — reasonable), or move to a separate data repo / cloud bucket.
  - Add `reports/**/*.aux`, `reports/**/*.log`, `reports/**/*.out`, `reports/**/*.toc`, `reports/**/*.fls`, `reports/**/*.fdb_latexmk`, `reports/**/*.synctex.gz` to `.gitignore` (the generic `*.log` et al. already there, but `reports/` not excluded wholesale).
  - Audit: which tracked PNGs in git can be regenerated? If regenerable from JLD2 + `save_standard_set`, remove from git, rely on `results/images/` regeneration scripts.
  - Consider `git lfs` for `data/*.npz` (Yb cross-section data) if LFS infrastructure is an option.

## Parallel-Session / Multi-Machine Risks

### `.planning/` is gitignored but some phases need it in git

- **Issue:** `.gitignore:2` excludes `.planning/` wholesale. Yet Session C force-added 10 MMF planning docs (`git add -f`) on `sessions/C-multimode` because they are canonically linked from scripts (see commit `ee7e73c`). The MMF baseline CONTEXT.md explicitly calls this out as Landmine 1: *"If you create new planning files, you must `git add -f` them."*
- **Impact:** Any new phase docs written by a future session will not make it to other machines unless (a) force-added, or (b) manually rsync'd via `sync-planning-to-vm`/`-from-vm`. The rsync path uses `--update` (timestamp-based) and excludes git-tracked `.planning/STATE.md`, `ROADMAP.md` — so STATE.md changes go through git, but most other files go through rsync. A session that edits `STATE.md` and assumes rsync picked it up will find other machines have stale state.
- **Severity:** HIGH (silent divergence across 8 parallel sessions)
- **Fix approach:**
  - Decide once: is `.planning/` tracked or not? Current split-brain (mostly ignored + selectively force-added) is the worst of both worlds.
  - If tracked: remove `.gitignore:2` line, commit the existing tree, update CLAUDE.md.
  - If not tracked: document the rsync protocol in CLAUDE.md with explicit "these files need force-add" list (currently scattered across CONTEXT.md landmines).

### Sync helpers use `rsync --update` (timestamp-based) — clock skew between Mac and VM can lose edits

- **Issue:** `sync-planning-to-vm` and `sync-planning-from-vm` use `rsync --update` (per CLAUDE.md:409, 553-555). If the Mac and a GCP VM have slightly different clocks *or* if the VM was suspended (so its clock is ahead of wall time), the "more recent" edit wins — silently. Concurrent edits on both sides to the same `.planning/` file are possible with 8 sessions.
- **Impact:** Edits can disappear without error.
- **Severity:** MEDIUM (bounded by how often both sides edit the same file — less likely with owned-namespace Rule P1)
- **Fix approach:** Add `--dry-run` preview mode to sync helpers with conflict listing. Long term: move to a git-based flow (see above).

### `tracked .planning/` git files cross a git-ignored path — commits don't work the way users expect

- **Issue:** CLAUDE.md tells sessions to `git add <specific files>` at session end. But `.planning/STATE.md` is both gitignored (via `.planning/`) AND force-tracked. `git status` on a stock install will not show `.planning/STATE.md` in any section, so contributors may miss that it needs staging. `git add .planning/STATE.md` works (forced), but the path is invisible in `git status -s`.
- **Impact:** Confusion. I've seen similar traps lose hours on other repos.
- **Severity:** MEDIUM
- **Fix approach:** Use `!` negation in `.gitignore`: after `.planning/`, add `!.planning/STATE.md`, `!.planning/ROADMAP.md`, `!.planning/REQUIREMENTS.md`, `!.planning/MILESTONES.md`, `!.planning/PROJECT.md`. Then `git status` shows them naturally.

### `burst-run-heavy` log path assumes `~/fiber-raman-suppression/` home-directory checkout

- **Issue:** `scripts/burst/run-heavy.sh:112` hard-codes `LOGDIR="$HOME/fiber-raman-suppression/results/burst-logs"`. If a session sets up the worktree pattern from CLAUDE.md (`~/raman-wt-<session-name>`) on the burst VM, the wrapper writes logs into the main checkout's `results/`, not the worktree's. `rsync` / `git pull` back to Mac may miss them depending on which worktree is "the" checkout.
- **Impact:** Log spread across worktrees. `burst-status` also assumes the main-checkout path.
- **Severity:** LOW (session tags still prefix logs; just confusing)
- **Fix approach:** Either (a) standardize on one checkout path on the VM (don't use worktrees on the burst VM — it's ephemeral anyway), or (b) parameterize `LOGDIR` from the caller via env var.

## Scientific-Correctness Risks

### `include`-based composition — fragile dependency chain

- **Issue:** `scripts/` uses `include()` with manual guards (`_COMMON_JL_LOADED`, `_VISUALIZATION_JL_LOADED`) rather than proper Julia modules. Dependency chains exist like `raman_optimization.jl` → `common.jl` + `visualization.jl`; `benchmark_optimization.jl` → `raman_optimization.jl`; `mmf_raman_optimization.jl` → `visualization.jl` (read-only, per Landmine 5 in MMF CONTEXT.md); `sweep_simple_run.jl` → `sweep_simple_param.jl` + `visualization.jl` + `standard_images.jl` + `determinism.jl`; `sharp_ab_slim.jl` → `common.jl` + `raman_optimization.jl` + `determinism.jl` + `sharpness_optimization.jl`.
- **Impact:**
  - Moving a function from `common.jl` to `src/` requires touching every include chain.
  - `include("visualization.jl")` evaluates the entire file — you can't import just one function. `plot_optimization_result_v2` signature change (an MMF CONTEXT.md landmine) breaks every downstream driver.
  - The guard pattern `if !(@isdefined _X_LOADED)` is easy to break (typo in the flag).
  - No static dependency graph — hard to reason about what `include`ing one file actually pulls in.
- **Severity:** MEDIUM
- **Fix approach:** Convert `common.jl`, `visualization.jl`, `standard_images.jl`, `determinism.jl` into proper submodules of `MultiModeNoise` (or a new sibling package `MultiModeNoiseScripts`). Drivers `using MultiModeNoise, MultiModeNoiseScripts: setup_raman_problem, save_standard_set`. This also lets `Pkg.test()` + CI compile-check them.

### Large drivers (1.5k–2k LoC) mix physics, orchestration, plotting, and CLI

- **Issue:** `scripts/visualization.jl` (2069 LoC), `scripts/phase_analysis.jl` (1989), `scripts/physics_completion.jl` (1856), `scripts/propagation_reach.jl` (1750), `scripts/phase_ablation.jl` (1116), `scripts/multivar_optimization.jl` (1080), `scripts/amplitude_optimization.jl` (928), `scripts/raman_optimization.jl` (793). Each one tends to define the cost, the driver, the plotting, the JLD2 I/O, and a `__main__`-style `if abspath(PROGRAM_FILE) == @__FILE__` block at the bottom.
- **Impact:** Hard to unit-test the cost in isolation (pulls in plotting, plotting pulls in PyPlot, PyPlot fails to load ⇒ no tests). Hard to review diffs. Hard for a new agent to find the ~50 lines they actually need.
- **Severity:** MEDIUM
- **Fix approach:** Split by responsibility: a `src/costs/*.jl` module family, `src/drivers/*.jl` family, `src/plotting/*.jl` family. Each driver script becomes a thin `main` that assembles library pieces.

### `@assert` disabled under `--check-bounds=no` or `-O3 --optimize=3`

- **Issue:** CLAUDE.md convention section and the code widely use `@assert` for preconditions/postconditions — "design by contract" rather than user-input validation. Under `--check-bounds=no` or custom build flags, `@assert` can be elided. Production runs on the burst VM use `julia -t auto --project=.` (no such flags today, per the burst-run-heavy README examples), so current risk is zero — but nothing prevents a future "let's speed up MMF" flag change from silently disabling correctness checks.
- **Impact:** Silent loss of gradient/adjoint sanity checks in production.
- **Severity:** MEDIUM
- **Fix approach:** For assertions that guard correctness (not just debugging), use `if !cond; throw(ArgumentError(...)) end` per CLAUDE.md's existing "user-facing validation" style. Reserve `@assert` for dev-only invariants. Audit `src/simulation/*.jl` and `src/helpers/helpers.jl` for which assertions are which.

### ODE-solver stiffness at high soliton number (still unresolved)

- **Issue:** From 2026-04-05 audit; **still present**. `Tsit5()` in `src/simulation/simulate_disp_mmf.jl:128` fails with NaN for `N_sol > ~7`. Code comment documents "N~9.8 (L=5m, P=0.10W) causes NaN in the ODE solver -- too stiff." Aggressive MMF config at `N_sol ≈ 2–3` is safely below this; but long-fiber 100-m runs (Session F) and future N_sol-scan experiments will hit it.
- **Severity:** MEDIUM (triggered by specific configurations, not core path today)
- **Fix approach:** `AutoTsit5(Rosenbrock23())` for automatic stiffness detection. Or switch-when-needed based on peak-power heuristic at `z=0`.

### FFTW `MEASURE` flag in hot-loop plan creation

- **Issue:** From 2026-04-05. `plan_fft!(... FFTW.MEASURE)` is called inside `get_p_disp_mmf` (`src/simulation/simulate_disp_mmf.jl:62-65`) and `get_p_adjoint_disp_mmf` (`src/simulation/sensitivity_disp_mmf.jl:125-130`). Each MEASURE benchmarks algorithms (~100 ms per plan). Per-optimization-run overhead; compounds in multi-start or sweep loops.
- **Status:** Partially addressed by Phase 15 determinism work — `scripts/determinism.jl::ensure_deterministic_environment()` pins planner to `ESTIMATE` (bit-exact determinism at +21.4% runtime cost). But this is set globally at driver entry, not inside `get_p_*`; if a script forgets to call `ensure_deterministic_environment()`, MEASURE is still used.
- **Severity:** LOW (performance only, and Phase 15 path is available)
- **Fix approach:** Drop the explicit `FFTW.MEASURE` in `get_p_*` — inherit from the global planner pref. Tests in `test_determinism.jl` already validate the bit-exact path.

### Manual `GC.gc()` calls between optimization runs

- **Issue:** From 2026-04-05. `scripts/raman_optimization.jl:503,515,527,541,555` call `GC.gc()` manually — a symptom of memory pressure from persistent ODE solutions.
- **Severity:** MEDIUM
- **Fix approach:** Release intermediate ODE `sol` objects after extracting needed data. Stop storing `sol.u[:]` when only `sol.u[end]` is needed.

## Medium-Severity Concerns (continuing from 2026-04-05)

| Area | Issue | Files | Status since 2026-04-05 |
|------|-------|-------|-------------------------|
| Parameter typing | `fiber` and `sim` are `Dict{String,Any}`. `fiber["Dw"]` typo → runtime `KeyError`. | All `src/simulation/*.jl` | Unchanged |
| ODE parameter tuples | `get_p_disp_mmf` returns a 28+-element unnamed tuple; destructured positionally in every RHS. One reordering breaks everything. | `src/simulation/simulate_disp_mmf.jl:13,85` | Unchanged |
| `get_initial_state` duplication | Copy-pasted across `simulate_disp_mmf.jl`, `simulate_disp_gain_mmf.jl`. | `src/simulation/` | Still duplicated, but reduced to the 2 live implementations |
| `pulse_form` silent fallthrough | Unsupported pulse forms now throw `ArgumentError` in both live pulse constructors. | `src/simulation/simulate_disp_mmf.jl`, `src/simulation/simulate_disp_gain_mmf.jl` | Fixed 2026-04-20 |
| Fiber preset duplication | `scripts/raman_optimization.jl:486-491` redefines `SMF28_GAMMA`, `SMF28_BETAS` as `const`, duplicating `FIBER_PRESETS` dict in `scripts/common.jl`. | `scripts/raman_optimization.jl` | Unchanged |
| Hardcoded physical constants | `2.99792458e8`, Planck constant in 4+ locations with precision differences (`6.62607e-34` vs `6.62607015e-34`) | `src/helpers/helpers.jl`, `src/gain_simulation/gain.jl` | Unchanged |
| Duplicate `using FiniteDifferences` | `src/MultiModeNoise.jl` lines 6 and 13 — `using FiniteDifferences` appears twice. | `src/MultiModeNoise.jl` | **Still present** (verified: lines appear once each at lines 28 and 25 of current file — looks like it's been cleaned; re-verify) |
| `println` in library code | `src/helpers/helpers.jl` uses `println` (lines 46, 55, 60, 67, 91) for status messages. | `src/helpers/helpers.jl` | Unchanged |
| `@debug`-level logging | Gradient-validation results hidden by default in `scripts/raman_optimization.jl:173,242`, `scripts/common.jl:92` | scripts/ | Unchanged |
| `PyPlot` at module level | `using PyPlot` in `src/MultiModeNoise.jl:32` — any matplotlib install issue breaks the whole module, including non-plotting code paths. | `src/MultiModeNoise.jl` | Unchanged |
| `LoopVectorization.jl` risk | Deprecated in favor of Julia 1.11+ SIMD. Listed in `src/MultiModeNoise.jl:31` but unclear how much `@tullio` actually uses it. | `src/MultiModeNoise.jl` | Unchanged |
| Incomplete docstrings | `disp_mmf!`, `adjoint_disp_mmf!` have placeholder arg descriptions. | `src/simulation/simulate_disp_mmf.jl:2-10`, `src/simulation/sensitivity_disp_mmf.jl:1-13` | Unchanged |

## Partial-Wiring: drivers missing `save_standard_set`

The project rule (CLAUDE.md top section) is: *"Every optimization driver that produces a `phi_opt` MUST, before exiting, call `save_standard_set(...)`"*. Most drivers comply. Verified grep:

- **Wired:** `amplitude_optimization.jl`, `cost_audit_driver.jl`, `longfiber_optimize_100m.jl`, `longfiber_validate_50m.jl`, `mmf_joint_optimization.jl`, `mmf_m1_limit_run.jl`, `mmf_raman_optimization.jl`, `run_aggressive.jl`, `multivar_demo.jl`, `sharp_ab_slim.jl`, `sharpness_optimization.jl`, `raman_optimization.jl`, `sweep_simple_*.jl`.
- **Audit correction:** `scripts/sharp_robustness_slim.jl` and `scripts/sharp_ab_figures.jl` were previously misclassified here. They are post-processing scripts that consume existing optima; they do not themselves produce a fresh `phi_opt`, so the mandatory `save_standard_set(...)` rule does not apply to them.
- **Severity:** MEDIUM (non-compliant drivers ship phi_opt without the standard PNG set; advisor won't have the expected visuals)
- **Fix approach:** Add `save_standard_set(...)` call at the end of each non-wired driver. For `multivar_optimization.jl`, also handle the joint-space `(φ, A, E)` result correctly — the standard set is phase-centric; amplitude rendering may need an extension.

## Test Coverage Gaps (updated)

Good news: tiered tests now cover Phase 13 (HVP, primitives), Phase 14 (sharpness, regression), Phase 16 (MMF, 13 assertions), cost-audit (unit + integration + analyzer), determinism. ~1740 LoC of test code.

**Remaining gaps:**

- `src/simulation/simulate_disp_mmf.jl` (`disp_mmf!`, `solve_disp_mmf`) — still no direct unit test of the forward RHS against a known analytical solution (e.g., linear dispersion only, or Kerr-only with soliton conservation). Adjoint gradient is FD-validated in Phase 16 tests but the forward is only tested transitively via optimization outcomes.
- `src/simulation/fibers.jl` (GRIN mode solver, overlap tensor) — tested only implicitly by Phase 16 M=1-limit equivalence. A direct test against analytical GRIN modes for a small case would catch regressions.
- `src/gain_simulation/gain.jl` (YDFA) — unchanged from 2026-04-05 audit: untested.
- `src/analysis/analysis.jl` — `compute_noise_map_modem` archived, but `compute_noise_map`, `compute_noise_map_modek`, `compute_noise_map_modem_fsum` remain untested.
- Thread-safety: no test asserts that a `Threads.@threads` loop over `deepcopy(fiber)` produces results identical to a serial loop. Would catch silent-race regressions.
- `fiber["zsave"]` mutation: add one test per solve-entry function that asserts `original_fiber` is byte-identical after the call. Existing `test_optimization.jl:338,346` has this spirit for `optimize_spectral_phase` — extend to all entry points.

## Known Physics Limitations (from Phase 12, still relevant)

- **Suppression reach finite for long fibers.** Optimal phase from L=0.5m or L=2m loses effectiveness at L=30m. SMF-28 φ@2m maintains -57 dB at L=30m but HNLF collapses to < 3 dB by z=15m. See `results/raman/CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md`. Session F confirmed phase-universality holds 50× (2m→100m warm-start reaches -51.50 dB) but full reoptimization at 100m only gains +3.26 dB.
- **φ(ω) is NOT polynomial at long fibers.** Session F phase fit: R²=0.015-0.037 for quadratic fit on 100m optimum. `a₂(100m)/a₂(2m) = −3.30` vs GVD-predicted `+50`. Publishable finding, but invalidates any spectral-shaping assumption that "polynomial is enough."
- **Pixel-count question open.** Hardware feasibility depends on whether an SLM with 1280 pixels maintains > 40 dB suppression when optimization uses Nt=8192 bins. Session E's N_φ sweep (N_φ=57 → -82.33 dB at L=0.25m P=0.10W SMF-28) is encouraging but needs the 1280-pixel test explicitly.
- **Phase 13 indefinite Hessian.** L-BFGS halts at saddles, not minima. `|λ_min|/λ_max` = 2.6% (SMF) / 0.41% (HNLF). This likely couples to the Session A joint-space convergence failure above.

## Dependencies at Risk

### PyPlot (matplotlib wrapper)

- **Risk:** Unchanged from 2026-04-05. PyPlot imports at `src/MultiModeNoise.jl:32` module level; any Python/matplotlib install failure breaks the entire module.
- **Mitigation in place:** `ENV["MPLBACKEND"] = "Agg"` set at top of every driver (headless); `try using Revise catch end` pattern for optional deps — but PyPlot is not wrapped the same way.
- **Severity:** MEDIUM
- **Fix approach:** Move `using PyPlot` into `scripts/visualization.jl` only. Core `MultiModeNoise` should not depend on Python.

### LoopVectorization.jl

- **Risk:** Deprecated in favor of Julia 1.11+ native SIMD. Still in `src/MultiModeNoise.jl:31`. Complex LLVM-level dependencies historically break on Julia upgrades.
- **Severity:** MEDIUM
- **Fix approach:** Benchmark whether `@tullio` is actually faster than plain broadcasting for the specific 4D contractions. If not, remove `LoopVectorization` and let Tullio fall back.

## Infrastructure / Ops

- **No CI/CD pipeline.** Test suite exists and is tiered — but it's only run manually. A GitHub Actions workflow running `TEST_TIER=fast make test` on every PR would catch regressions before they land on main.
- **`.git` is 527 MB for ~35k LoC of Julia.** 193 tracked PNGs and 19 JLD2 dominate. Consider `git filter-repo` pass to audit history and drop binary artifacts that are regeneratable.
- **Burst-VM log hygiene.** `results/burst-logs/` on the VM accumulates one file per `burst-run-heavy` invocation. 9 files present in the committed `results/burst-logs/` on main. No rotation / cleanup policy. Not urgent but will add up across 8-session weeks.
- **Ephemeral-VM orphan detection** is manual (`~/bin/burst-list-ephemerals`). A session that forgets to check at shutdown leaves billing running up to the 6-hour auto-shutdown. Add an automated hourly check (see Burst-VM lockup item above).

---

*Concerns audit: 2026-04-19. Reflects state after 2026-04-17 burst-VM incident, 2026-04-19 7-session integration, and Phase 18 follow-up framing.*
