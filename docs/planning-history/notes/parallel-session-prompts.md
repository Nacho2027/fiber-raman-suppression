---
title: Parallel Claude Code Session Prompts — Multi-Thread Research Sprint
date: 2026-04-16
purpose: Copy-paste-ready prompts for launching up to 8 parallel Claude Code sessions, each pursuing a distinct research thread with autonomous research→discuss→plan→execute workflow.
---

# Parallel Session Prompts

## READ FIRST — Parallel Operation Protocol

**Every prompt below assumes the agent has read `CLAUDE.md` and will follow Rules P1–P7 of the "Parallel Session Operation Protocol" section.** Those rules are non-negotiable safety constraints for running sessions concurrently. Summary:

- **P1 — Owned file namespace.** Each session has a prefix (e.g., `multivar_*`, `mmf_*`). Stay inside it. Escalate to user if a change to shared files is needed.
- **P2 — Branch-per-session.** Each session works on `sessions/<name>` branch. NEVER push to main directly.
- **P3 — Append-only edits to shared docs.** Don't edit existing rows/sections in STATE.md or ROADMAP.md; only append, or write to `.planning/sessions/<name>-status.md` instead.
- **P4 — Sync helpers are now non-destructive** (`--update` not `--delete`). Don't run sync while active editing is happening on both sides.
- **P5 — Burst VM: one heavy run at a time** (lock at `/tmp/burst-heavy-lock`), multiple light runs OK concurrently.
- **P6 — Distribute sessions**: ~4 on Mac, ~3 on claude-code-host. Don't overload either.
- **P7 — User-driven integration checkpoints** every 2–3 hours.

### Concrete host distribution for 8 sessions

| Session | Run on | Why |
|---|---|---|
| A — Multi-Var | claude-code-host | needs burst VM frequently |
| B — Repo Polish | Mac | no compute, heavy editing |
| C — Multimode | claude-code-host | needs burst VM heavily |
| D — Simple Profile | Mac | moderate editing, small compute bursts |
| E — Sweep | Mac | heavy planning, compute on burst VM |
| F — Long Fiber | claude-code-host | monopolizes burst VM for hours |
| G — Synthesis | Mac | pure writing, no compute |
| H — Cost Audit | claude-code-host | needs burst VM for benchmarks |

If claude-code-host gets tight on RAM (`free -h` shows <3 GB available), move one of {A, C, H} to Mac.

### File-ownership table (quick reference — full rules in CLAUDE.md P1)

| Session | OWNED namespace (OK to create/modify) | Shared files (escalate if need change) |
|---|---|---|
| A — Multi-Var | `scripts/multivar_*.jl`, `src/multivar_*.jl`, `.planning/phases/N-multivar-*/`, `.planning/notes/multivar-*.md`, `.planning/sessions/A-multivar-*` | everything else |
| B — Repo Polish | `README.md`, `docs/**`, `Makefile`, `test/**`, `.planning/phases/N-polish-*/`, `.planning/notes/polish-*.md`, `.planning/sessions/B-*` | `src/**`, `scripts/common.jl` |
| C — Multimode | `scripts/mmf_*.jl`, `src/mmf_*.jl`, `.planning/phases/N-mmf-*/`, `.planning/notes/mmf-*.md`, `.planning/sessions/C-*` | `src/simulation/simulate_disp_mmf.jl` core is OFF LIMITS for modifications; wrap it |
| D — Simple Profile | `scripts/simple_profile_*.jl`, `.planning/phases/N-simple-*/`, `.planning/notes/simple-profile-*.md`, `.planning/sessions/D-*` | optimizer core |
| E — Sweep | `scripts/sweep_simple_*.jl`, `.planning/phases/N-sweep-*/`, `.planning/notes/sweep-*.md`, `.planning/sessions/E-*` | `setup_raman_problem` in `scripts/common.jl` — escalate if change needed |
| F — Long Fiber | `scripts/longfiber_*.jl`, `.planning/phases/N-longfiber-*/`, `.planning/notes/longfiber-*.md`, `.planning/sessions/F-*` | `setup_raman_problem` auto-sizing — escalate |
| G — Synthesis | `.planning/notes/physics-findings-synthesis.md`, `.planning/notes/synthesis-*.md`, `.planning/sessions/G-*` | everything else is READ-ONLY |
| H — Cost Audit | `scripts/cost_audit_*.jl`, `.planning/phases/N-cost-audit-*/`, `.planning/notes/cost-audit-*.md`, `.planning/sessions/H-*` | existing optimizer code — create new wrappers, don't modify |

`N` = next-available phase number (agent will determine when adding the phase to ROADMAP).

### Worktree setup (run ONCE on each host before launching sessions)

```bash
cd ~/fiber-raman-suppression
git fetch origin

# One worktree per session, each on its own branch:
git worktree add ../raman-wt-A sessions/A-multivar      -b sessions/A-multivar 2>/dev/null || git worktree add ../raman-wt-A sessions/A-multivar
git worktree add ../raman-wt-B sessions/B-handoff       -b sessions/B-handoff 2>/dev/null || git worktree add ../raman-wt-B sessions/B-handoff
git worktree add ../raman-wt-C sessions/C-multimode     -b sessions/C-multimode 2>/dev/null || git worktree add ../raman-wt-C sessions/C-multimode
git worktree add ../raman-wt-D sessions/D-simple        -b sessions/D-simple 2>/dev/null || git worktree add ../raman-wt-D sessions/D-simple
git worktree add ../raman-wt-E sessions/E-sweep         -b sessions/E-sweep 2>/dev/null || git worktree add ../raman-wt-E sessions/E-sweep
git worktree add ../raman-wt-F sessions/F-longfiber     -b sessions/F-longfiber 2>/dev/null || git worktree add ../raman-wt-F sessions/F-longfiber
git worktree add ../raman-wt-G sessions/G-synthesis     -b sessions/G-synthesis 2>/dev/null || git worktree add ../raman-wt-G sessions/G-synthesis
git worktree add ../raman-wt-H sessions/H-cost          -b sessions/H-cost 2>/dev/null || git worktree add ../raman-wt-H sessions/H-cost

# Verify:
git worktree list
```

Each `claude` invocation happens inside ONE of these worktree directories. That worktree's `.planning/` folder is a COPY — sync-planning only propagates between Mac primary and VM, not between worktrees on the same host. Sessions on the same host share the `.planning/` of the PRIMARY checkout via file-ownership prefixing.

## Pre-flight — DO THIS BEFORE STARTING ANY SESSION

### 1. Wait for the in-flight Phase 14 (sharpness-aware) research to complete

Phase 14 introduced a parallel optimizer path (`optimize_spectral_phase_sharp`) that may redefine the cost function baseline for every other session. If that research is mid-flight, DO NOT start new sessions touching the optimizer until it's done, or they'll fork on stale assumptions.

Check status:
```bash
cat .planning/STATE.md | head -40
ls .planning/phases/14-* 2>/dev/null
git log --oneline origin/main~20..origin/main | grep -i "14\|sharp"
```

If Phase 14 is still "in progress" or "planning," wait. If it's complete and has a SUMMARY.md, the rules it established are now in play — sessions below that touch optimization should honor whichever cost function Phase 14 settled on.

### 2. Everybody does git hygiene at session start

Every session, on any machine, begins with:

```bash
git fetch origin
git status
git pull --ff-only origin main    # abort and escalate to user if this fails
```

### 3. Sync gitignored artifacts if needed

On the Mac:
```bash
sync-planning-to-vm        # before starting a remote session if .planning/ changed locally
sync-planning-from-vm      # if a remote Claude Code has updated .planning/
```

### 4. Use git worktrees to prevent file conflicts

Multiple concurrent sessions editing the same files will race. Create a worktree per active session:

```bash
cd ~/fiber-raman-suppression
git worktree add ../raman-wt-multivar sessions/multivar
git worktree add ../raman-wt-multimode sessions/multimode
git worktree add ../raman-wt-longfiber sessions/longfiber
# ... one per session
```

Each Claude Code session operates in its own worktree directory. Merge back to `main` when the session's phase is complete.

### 5. Compute coordination

- **Claude Code sessions** → run on `claude-code-host` (e2-standard-4, 4 vCPU / 16 GB). Comfortable limit: **3 concurrent sessions**. Beyond that, RAM gets tight.
- **Julia simulations** → run on `fiber-raman-burst` (c3-highcpu-22). **Only ONE session at a time owns the burst VM.** If multiple sessions need compute, they queue. Use `burst-status` before starting a run.
- Follow Rules 1–3 in `CLAUDE.md` ("Running Simulations — Compute Discipline") — no exceptions.

---

## The prompts

Each prompt is self-contained. Paste as the FIRST user message in a new Claude Code session. Each prompt assumes it's starting fresh — no prior conversation context.

---

### Session A — Multi-Variable Optimization Design

**Recommended worktree:** `~/raman-wt-multivar` on branch `sessions/multivar`
**Compute profile:** Light (design + prototype) → moderate (small multi-var runs to validate)
**Estimated wall time for autonomous phase:** 1–2 days

```
# Session A — Multi-Variable Optimization Design

## Context

The PI confirmed that the Rivera Lab's SLM is capable of controlling all four
modulation axes: amplitude, phase, spatial (mode content), and spectral. Every
type of variable optimization is in experimental scope.

Today, `optimize_spectral_phase` optimizes only `φ(ω)` (spectral phase vector).
We want to expand to a multi-variable optimizer that can optimize any subset of:
  - Spectral phase `φ(ω)` (existing)
  - Spectral amplitude `|A(ω)|` (has a separate existing script, but not jointly)
  - Input mode coefficients `{c_m}` at fiber launch (novel — enabled by spatial SLM)
  - Pulse energy `E` (scalar)

The new capability must be a SEPARATE function and SEPARATE entry-point script —
do NOT modify `optimize_spectral_phase` or its entry points. The existing
phase-only path must remain untouched and usable for A/B comparison.

## Goal

Produce a design + working prototype for `optimize_multivariable` (name TBD) that:
  1. Takes a list of which variables to optimize (any subset of the 4 above).
  2. Computes adjoint gradients w.r.t. each enabled variable.
  3. Packages them into a joint parameter vector for L-BFGS or Newton.
  4. Returns the optimized parameters plus per-variable diagnostic info.
  5. Has a clear, SLM-compatible output format (see Session B for the format spec).

## Your workflow

PHASE 1 — Research (1–2 hours)
  - Read the existing `scripts/raman_optimization.jl` and
    `scripts/amplitude_optimization.jl`. Understand how each sets up its
    optimizer and passes gradients.
  - Read `src/simulation/sensitivity_disp_mmf.jl` — the adjoint code. Identify
    what would need to change (or be added) to compute gradients w.r.t.
    `|A(ω)|`, `{c_m}`, and `E` alongside the existing `φ(ω)` gradient.
  - Read `.planning/seeds/launch-condition-optimization.md` — this seed
    discusses exactly the `{c_m}` case.
  - Research L-BFGS / Newton with heterogeneous parameter vectors. Key concern:
    different variables have very different magnitudes. Poor scaling kills
    convergence. How do we scale? (A classic answer: per-variable
    preconditioning.)

PHASE 2 — Discuss (AskUserQuestion)
  Surface and resolve:
  - Which variables to enable by default? (Start with phase + amplitude; add
    mode coefficients later?)
  - Preconditioning/scaling strategy
  - Whether pulse energy should be optimized or fixed (it's easy to make J
    trivially "better" by lowering energy into the linear regime — need a
    constraint)
  - How to parameterize `{c_m}` given phase-only vs complex-amplitude SLM
    (the advisor's answer on SLM type feeds this — currently not in docs)

PHASE 3 — Plan (via /gsd-add-phase → /gsd-plan-phase)
  A phase named something like "Multi-Variable Optimizer." The plan should:
  - Define the new script, e.g., `scripts/multivar_optimization.jl`
  - Define the new function, e.g., `optimize_spectral_multivariable(...)`
  - Derive the new gradient components mathematically first, then implement
  - Include unit tests (gradient validation vs finite differences for each
    new variable)
  - Define the SLM-compatible output schema (coordinate with Session B)

PHASE 4 — Execute (via /gsd-execute-phase) autonomously.
  - **Every Julia simulation run — even a single gradient-validation
    solve — goes on the burst VM. No exceptions.** See CLAUDE.md Rule 1.
  - The existing single-mode `E_band/E_total` cost is the starting metric.

## Success criteria

  - [ ] New `scripts/multivar_optimization.jl` exists and runs end-to-end
  - [ ] Gradient validation tests pass (finite-diff matches adjoint within 1e-6)
  - [ ] At least one test case shows multi-var optimization achieves better J
    than phase-only in the SAME conditions (proving the expanded parameter
    space finds a better optimum, or at minimum no worse)
  - [ ] Output format documented (JSON/JLD2 with fields suitable for SLM input)
  - [ ] Existing `optimize_spectral_phase` unchanged and still passing tests

## Out of scope for this session

  - Multimode physics (that's Session C)
  - Newton's method with full Hessian — that's the ongoing Phase 13/14 thread.
    This session uses the existing optimizer infrastructure (L-BFGS).
  - Experimental SLM integration — simulation only.

## Critical reminders

  - `git pull --ff-only origin main` at session start.
  - `julia -t auto` for ALL runs. Never bare `julia`.
  - Any run at Nt >= 2^13 → burst VM. Never on claude-code-host.
  - `burst-stop` when done with any burst usage.
  - Use `/gsd-add-phase` and the GSD workflow; don't skip to direct edits.
```

---

### Session B — Repo Polishing & Team Handoff

**Recommended worktree:** `~/raman-wt-handoff` on branch `sessions/handoff`
**Compute profile:** Zero simulation — all docs + tooling
**Estimated wall time:** 2–3 days

```
# Session B — Repo Polishing & Team Handoff

There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues. Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

## Context

The user (a Rivera Lab undergrad) will hand off this project to their research
team. The repo needs to be immediately usable by someone else who has not
been in the thinking for the past month. Today it's a research project — it
needs to become a research *tool*.

## Goal

Make the repo "drop a new team member in and they can contribute in a day."
Specifically:

  1. README.md at project root — currently stale (references old MMF squeezing
     language, not Raman suppression). Rewrite it completely.
  2. docs/ directory — set up user-facing documentation for:
     - Installation + environment setup (Julia version, PyPlot deps)
     - Running a single optimization (happy path)
     - Running a sweep
     - Interpreting the output plots
     - Understanding the cost function and physics
     - How to add a new fiber preset
     - How to add a new optimization variable (via the output of Session A)
  3. Optional: a Dockerfile for reproducible environments — evaluate
     feasibility given Julia/PyPlot/FFTW complexity. If it's going to be
     fragile, DON'T add it; document the Julia-native path instead.
  4. Output format specification — when the optimizer converges, what file
     does it produce that could be loaded by someone running an SLM? Define
     a schema:
       - Output file type: JLD2 or NPZ or HDF5 (pick one, justify)
       - Fields: optimized parameters, raw SLM pattern (if applicable),
         fiber params, optimization metadata, figure metadata
       - A companion text file / JSON with human-readable summary
     The output should be directly ingestible into an SLM driver. Research
     what SLM drivers typically accept (Holoeye, Meadowlark, etc. — the lab's
     specific model matters; ask user if not documented).
  5. Developer-UX improvements:
     - A `Makefile` or `just` recipes: `make optimize`, `make sweep`,
       `make report`, `make test`
     - Standardize entry-point scripts — many exist (`raman_optimization.jl`,
       `amplitude_optimization.jl`, `run_comparison.jl`,
       `generate_sweep_reports.jl`, etc.) but no clear "start here" guide
     - Expand `test/runtests.jl` which is currently a smoke test into a
       proper regression suite (the Phase 15 determinism helper makes this
       feasible now)
     - Remove or archive abandoned code (`compute_noise_map_modem` is flagged
       broken in STATE.md)

## Your workflow

PHASE 1 — Research (2–4 hours)
  - Read CLAUDE.md, PROJECT.md, ROADMAP.md, STATE.md cover-to-cover.
  - Read every phase's SUMMARY.md to build a mental model of what has been
    done and why.
  - Read `scripts/` to understand the entry points. List them all.
  - Check what documentation already exists in `docs/`, `.planning/research/`,
    and `.planning/codebase/`.
  - Research SLM driver expectations — what do Holoeye / Meadowlark / Santec
    drivers expect as an input file for a phase pattern? Output format decision
    depends on this. Ask user which SLM they have if not clear.

PHASE 2 — Discuss (AskUserQuestion)
  Surface:
  - SLM model / driver (to pick output format)
  - Docker vs native — evaluate and recommend
  - How aggressive to be with removing abandoned code
  - Regression test scope — how much coverage is "enough" for team handoff

PHASE 3 — Plan (/gsd-add-phase → /gsd-plan-phase)
  Break into tasks. Good breakdown:
    1. README rewrite
    2. docs/ directory structure + content
    3. Output format spec + reference implementation (loader/saver)
    4. Makefile / just recipes + entry-point consolidation
    5. Regression test suite expansion
    6. (optional) Dockerfile or reproducibility doc
    7. Cleanup of abandoned code

PHASE 4 — Execute (/gsd-execute-phase) autonomously.

## Success criteria

  - [ ] README at root is a good first impression — explains project, shows
    the happy path with a single copy-pasteable command, points to docs
  - [ ] A new team member can install and run a basic optimization in <15
    minutes from cloning the repo, following only written docs
  - [ ] Optimizer output file is fully documented and has a round-trip
    load/save tested
  - [ ] Entry-point scripts have a clear top-of-file docstring explaining
    purpose and usage
  - [ ] `make test` (or equivalent) runs a meaningful regression suite that
    would have caught at least one of the bugs from STATE.md's "Key Bugs
    Fixed" section
  - [ ] The abandoned `compute_noise_map_modem` is either fixed or removed,
    with a rationale in the commit message

## Out of scope

  - Physics improvements (other sessions)
  - Multi-variable optimization (Session A)
  - Anything that requires new optimization runs

## Critical reminders

  - `git pull` at start.
  - **If this session runs ANY Julia simulation (including `make test` if
    it runs sims), the run goes on the burst VM. No exceptions — not even
    for a single-iteration smoke test.** See CLAUDE.md Rule 1.
  - Don't break existing APIs in the process of polishing; additions > rewrites.
```

---

### Session C — Multimode Raman + Exploratory Multimode Physics

**Recommended worktree:** `~/raman-wt-multimode` on branch `sessions/multimode`
**Compute profile:** Heavy — frequent burst VM usage expected
**Estimated wall time:** 3–5 days

```
# Session C — Multimode Raman Suppression + Free Exploration


There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

## Context

The project has been M=1 (single-mode) so far. PI wants multimode simulations
(target M=6). Start with extending Raman suppression to M>1 using the existing
E_band/E_total cost function, but you have freedom to explore adjacent research
questions that emerge (different fiber types, different optimization parameters,
different cost functions).

Key constraints:
  - The simulation core at M>1 is STRUCTURALLY correct already
    (src/simulation/simulate_disp_mmf.jl, sensitivity_disp_mmf.jl use 4D
    γ[i,j,k,l] tensor contractions — they work at M=6, unchanged).
  - Tullio auto-threads at M>1 with `julia -t N` — this is a free speedup.
  - Per-mode spectral phase is NOT physically realizable (single pulse
    shaper). The spectral phase is ONE profile applied to the total input.
  - Input mode coefficients {c_m} ARE controllable (spatial SLM present).

This session must produce a SEPARATE function / file for multimode
optimization — do NOT overload the SMF path.

## Goal

1. Produce working multimode Raman suppression with M=6 using the existing
   E_band/E_total cost (or whichever cost Phase 14 landed on).
2. Document per-solve cost at M=6 (to calibrate future Newton work).
3. Explore whether the optimal phase profile at M=6 differs from M=1 in
   interesting ways.
4. Identify 2–3 adjacent questions worth follow-up phases (but don't
   execute them in this session).

## Your workflow

PHASE 1 — Research (2–4 hours)
  - Read .planning/notes/multimode-optimization-scope.md — the narrowed
    scope from the 2026-04-16 exploration.
  - Read .planning/research/advisor-meeting-questions.md — the advisor's
    answers (if the user has recorded them) shape the right cost function
    and baseline launch mode content.
  - Read src/simulation/simulate_disp_mmf.jl and sensitivity_disp_mmf.jl
    end-to-end. Confirm what works and what's untested at M>1.
  - Read src/simulation/fibers.jl — the GRIN mode solver that produces the
    multimode γ[i,j,k,l]. Understand how many modes are computed by default
    and how to request M=6 specifically.
  - Read .planning/seeds/launch-condition-optimization.md and
    .planning/seeds/quantum-noise-reframing.md — these are adjacent research
    directions.
  - Search the codebase for existing MMF tests or scripts. List anything found.

PHASE 2 — Discuss (AskUserQuestion)
  - Cost function choice at M=6 (sum over modes vs. per-mode worst-case vs.
    signal-mode-only). Advisor's answer to meeting question Q4 is the input.
  - Initial input mode content (LP01-only vs. tuned superposition). Advisor's
    answer to Q3 is the input.
  - Fiber preset (SMF-28 is single-mode by definition — need a few-mode or
    GRIN fiber preset for M=6; confirm one exists or define one).
  - Target fiber lengths for first multimode sweep.

PHASE 3 — Plan (/gsd-add-phase → /gsd-plan-phase)
  Break into plans:
    1. Multimode fiber preset + M=6 setup helper
    2. `scripts/raman_optimization_mmf.jl` entry point (SEPARATE from SMF)
    3. Cost function variant for M>1 (per user/advisor choice)
    4. Baseline run at M=6, L=1m, SMF28-GRIN (or equivalent) — verify
       numerical stability
    5. First M=6 optimization and comparison vs M=1 at same L,P
  Each plan is ONE phase of multimode work.

PHASE 4 — Execute (/gsd-execute-phase) autonomously.
  All runs at M>=2 MUST go to the burst VM per CLAUDE.md compute discipline.

## Exploration budget

After the baseline is working, you have freedom to investigate ONE of:
  (a) Does joint phase + {c_m} optimization beat phase-only at M=6?
      (this activates the launch-condition seed)
  (b) Does the optimal phase at M=6 generalize across fiber lengths?
  (c) Does a different multimode fiber type (GRIN vs step-index, different
      NA, different core size) produce qualitatively different Raman
      dynamics?
Pick one, document findings, spawn seeds for the other two.

## Success criteria

  - [ ] `scripts/raman_optimization_mmf.jl` exists, runs at M=6, converges
  - [ ] Verified numerical correctness at M=6 (e.g., energy conservation,
    matches M=1 code in the M=1 limit)
  - [ ] One multimode Raman suppression result documented with figures
  - [ ] Per-solve wall time at M=6 benchmarked and reported
  - [ ] 2–3 adjacent seeds planted in .planning/seeds/ for future follow-up

## Out of scope

  - Quantum noise / squeezing metrics (that's the seed, not this sprint)
  - Per-mode pulse shaping (physically unrealizable)
  - Newton optimizer at M=6 (own thread — may emerge from Phase 13/14)

## Critical reminders

  - **burst VM for EVERY simulation run — M=1 sanity checks included.
    No exceptions.** Claude-code-host is ONLY for editing, reading data,
    and running non-simulation scripts. See CLAUDE.md Rule 1.
  - `julia -t auto` — Tullio auto-parallelizes at M>1 and you want that.
  - deepcopy(fiber) per thread if you add Threads.@threads loops
  - `burst-stop` religiously — $0.90/hr bleeds fast.
  - Keep the SMF-path unchanged.
```

---

### Session D — Simple Phase Profile Stability Study

**Recommended worktree:** `~/raman-wt-simple` on branch `sessions/simple-profile`
**Compute profile:** Moderate — many small runs, no big sweeps
**Estimated wall time:** 1–2 days

```
# Session D — Simple Phase Profile Stability + Transferability


There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

## Context

The user noticed a striking result:
  - SMF-28, L=0.5 m, P=0.050 W → J = -77.6 dB ("EXCELLENT")
  - The optimized unwrapped phase is REMARKABLY SIMPLE — essentially a
    smooth ~3-feature curve with total variation under 2 radians across
    the full spectrum
  - Wall time: 35 s (fast convergence)
  - The group delay profile is also smooth and visually clean
  - Image: results/images/presentation/phase_profile_smf28_L05m_P005W.png
    (if this filename isn't exact, find the equivalent in
    results/images/presentation/ or results/images/phase10/ or similar)

This is suspicious in a good way. Most optimized phases from this codebase
are visually complex (many oscillations, structure at sub-THz scales).
This one is simple enough that a human could plausibly read it off a plot.
That suggests the optimum sits in a well-behaved basin with a large
convergence radius — potentially experimentally robust.

## Goal

Determine whether this specific optimum is:
  1. Stable under perturbation of the phase (test the basin width)
  2. Transferable to nearby fiber parameters (different L, different P,
     different fiber)
  3. Actually simpler than typical optima (quantify "simplicity" —
     e.g., low total variation, low spectral complexity, smooth group
     delay)
  4. Worth hunting for more of its kind (outputs to Session E's sweep design)

## Your workflow

PHASE 1 — Reproduce the result (30 min)
  Find the exact config that produced the image. Likely candidates:
    - scripts/raman_optimization.jl with fiber=SMF-28, L=0.5m, P=0.050W
    - May be the SMF-28 entry in scripts/common.jl's FIBER_PRESETS
    - Check recent phase SUMMARY.md files for matching config
  Re-run the optimization. Confirm you get ~-77.6 dB and a visually
  similar phase profile. If you can't reproduce, STOP and escalate —
  non-reproducibility is itself a finding (and a Phase 13 concern
  about determinism).

PHASE 2 — Research (1–2 hours)
  - Read the Phase 11 SUMMARY ("amplitude-sensitive nonlinear
    interference") — the physics explanation for why some configs
    work better than others
  - Read the Phase 13 SUMMARY if it exists — Hessian eigenspectrum
    analysis might already partially answer "is this a sharp or flat
    minimum?"
  - Read the Phase 14 SUMMARY (sharpness-aware cost) — this is the
    exact framework for answering "is this optimum experimentally
    robust?"
  - Research: metrics for phase profile "simplicity" (total variation,
    number of stationary points, spectral entropy)

PHASE 3 — Discuss (AskUserQuestion)
  - What perturbation magnitudes to test? (e.g., Gaussian noise on
    phase with σ ∈ {0.01, 0.1, 0.5, 1.0} rad)
  - How many perturbation samples per magnitude?
  - Which transferability axes to sweep? (L, P, fiber type — suggest
    3 at low density first)
  - Which simplicity metric(s) to use?

PHASE 4 — Plan (/gsd-add-phase → /gsd-plan-phase)
  Tasks:
    1. Reproduce baseline run, confirm numerical match
    2. Perturbation study: for each σ, run N perturbations, measure
       J degradation
    3. Transferability sweep: evaluate this phase at (L, P) pairs
       near the optimum (without re-optimizing) and at (L, P, fiber)
       triples (re-optimizing from THIS phase as warm start)
    4. Simplicity quantification: compute TV, #stationary points,
       spectral complexity for this phase vs. phases from other
       known optima (Phase 10/11/12 results)
    5. Figure: compile findings into a 1-page visual summary

PHASE 5 — Execute (/gsd-execute-phase) autonomously.

## Success criteria

  - [ ] Baseline reproduces within 1 dB of -77.6 dB
  - [ ] Perturbation curve: J vs σ plotted for at least 4 σ values
  - [ ] Transferability table: J at 4–6 (L, P) pairs without
    re-optimization, and 2–3 pairs with re-optimization
  - [ ] Simplicity score: this phase vs. at least 3 other optima
    from prior phases, same metric
  - [ ] Clear yes/no verdict on "is this optimum special?" with
    quantitative justification

## Feeds into Session E

If "yes, this is special," Session E's sweep should target similar
low-amplitude, simple-structure regimes. Document which parameter
ranges produced this optimum so Session E can expand around them.

## Critical reminders

  - **Every run — the baseline reproduction, every perturbation, every
    transferability sweep point — goes on the burst VM. No exceptions, even
    for a single 35-second check.** See CLAUDE.md Rule 1.
  - `julia -t auto`.
  - Commit incrementally; each perturbation/transfer batch is a
    natural commit point.
```

---

### Session E — Sweep Design: Hunting Simple Phase Profiles

**Recommended worktree:** `~/raman-wt-sweep` on branch `sessions/sweep-simple-hunt`
**Compute profile:** Heavy — large parameter sweep on burst VM
**Estimated wall time:** 2–4 days (burst VM heavy)

```
# Session E — Hunting for More Simple Phase Profiles


There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

## Context

The PI proposed a specific strategy: reduce the RESOLUTION of the input
pulse (fewer degrees of freedom in the spectral phase) while keeping the
RESOLUTION OF THE FIBER high (full Nt for the forward solve). This should
naturally find simple phase profiles because the optimizer has fewer
knobs to twist — it can only produce smooth shapes.

Combined with Session D's findings on what makes a profile "simple," we
want a systematic sweep that surfaces more simple-profile optima.

## Goal

1. Implement the "low-res input, high-res fiber" mode: N_phi << N_t,
   interpolate the low-res phase onto the high-res frequency grid
   before applying to the input pulse.
2. Sweep N_phi across a range (e.g., 8, 16, 32, 64, 128, 256) at
   fixed (L, P, fiber).
3. Sweep (L, P) at fixed low N_phi to find multiple simple optima.
4. Rank results by suppression depth AND simplicity (metric from
   Session D).
5. Identify the "Pareto front" — best suppression for each simplicity
   level.

## Your workflow

PHASE 1 — Wait for Session D output (1–2 days if running in parallel)
  Session D defines the simplicity metric. If you start before Session
  D is done, either:
    (a) Wait and read .planning/phases/<D's phase>/SUMMARY.md
    (b) Define a provisional metric (total variation is safe) and
        revisit after D converges.

PHASE 2 — Research (1–2 hours)
  - Read scripts/common.jl — look for an existing N_phi parameter.
    If not present, determine the cleanest place to add one.
  - Read scripts/raman_optimization.jl — understand how N_phi currently
    maps to the input phase parameterization.
  - Research interpolation strategies — linear, cubic, spline, Fourier
    (bandlimited). Pick one based on physics (Fourier/bandlimited is
    the "right" answer for pulse shaping — matches how a real pulse
    shaper's Fourier-plane resolution maps to time-domain shape).
  - Read Phase 12 SUMMARY — the long-fiber work already plays with
    phase interpolation (phi@2m applied to L=30m). This is similar
    machinery.

PHASE 3 — Discuss (AskUserQuestion)
  - Interpolation method
  - N_phi values to sweep
  - (L, P) grid for the sweep (dense or sparse, range)
  - How to define "simple" quantitatively (pulls from Session D)

PHASE 4 — Plan (/gsd-add-phase → /gsd-plan-phase)
  Tasks:
    1. Implement low-res phase parameterization (probably a variant of
       setup_raman_problem that takes N_phi < Nt)
    2. Verify the new setup: at N_phi = Nt it should exactly match the
       current setup; at N_phi < Nt it should produce smooth phases
    3. Sweep 1: N_phi ∈ {8, 16, 32, 64, 128, 256} at one (L, P, fiber)
    4. Sweep 2: (L, P) grid at low N_phi ∈ {16, 32}
    5. Pareto analysis + figure
    6. Promote best candidates to Session D's stability test

PHASE 5 — Execute (/gsd-execute-phase) autonomously.
  Sweep runs ENTIRELY on the burst VM. Expect hours of compute.

## Success criteria

  - [ ] Low-res phase parameterization works and is documented
  - [ ] Sweep 1 completes, produces the J vs N_phi curve — should
    show when reducing N_phi costs suppression depth
  - [ ] Sweep 2 produces a grid of J across (L, P) at low N_phi —
    find at least 3 new simple-profile candidates
  - [ ] Pareto figure: suppression vs. simplicity, showing the simple
    profile from Session D and any new candidates
  - [ ] Candidates handed off to Session D-style stability study
    (either in this session or as a followup seed)

## Out of scope

  - Multi-variable optimization (Session A)
  - Multimode physics (Session C)
  - Newton / second-order methods (existing Phase 13/14 thread)

## Critical reminders

  - Sweeps are expensive — plan carefully before launching. Estimate
    total runtime before committing the burst VM.
  - `julia -t auto` on EVERY run.
  - `burst-stop` immediately when sweep completes.
  - Save results to JLD2 files incrementally so you don't lose work
    if the VM is preempted.
```

---

### Session F — Long Fiber Support (100m+)

**Recommended worktree:** `~/raman-wt-longfiber` on branch `sessions/long-fiber`
**Compute profile:** Very heavy — long optimization runs, biggest burst VM usage
**Estimated wall time:** 3–7 days (mostly compute)

```
# Session F — Scaling the System to 100m+ Fibers

## Context


There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

Current results show SMF-28 phi@2m maintains -57 dB Raman suppression at
L=30m (Phase 12). The PI wants to push further: 100 m, maybe beyond.

This is a non-trivial extension because:
  - Dispersive walk-off scales with L, so the time window may need to grow
  - Numerical accumulation of error over 100 m of propagation is a
    correctness concern
  - Optimization convergence may be worse (non-convexity grows with L)
  - Wall time per solve scales roughly linearly with L
  - Nt floor requirements from Phase 7.1 / 12 need re-validation at
    much longer lengths

The Phase 12 "suppression-reach" work already hit one snag: the setup_raman_problem
wrapper auto-overrides explicit Nt / time_window at L >= 10m, and Phase 12
had to bypass it. This problem amplifies at 100m.

## Goal

Establish a correct, efficient simulation + optimization pipeline for
L ≥ 100 m. Produce at least one 100m optimization result with documented
numerical validation.

## Your workflow

PHASE 1 — Research (3–5 hours — this is the slow, careful phase)
  Rigorously. This is where the value lives for this session.

  - Read Phase 7.1 SUMMARY (Nt floor, max_iter, L=10m dropped) — understand
    why the previous grid bumped and how it was sized.
  - Read Phase 12 SUMMARY carefully — identify the bypass logic for the
    auto-sizing wrapper and why it was needed.
  - Read src/simulation/simulate_disp_mmf.jl — understand the time-window
    math. Specifically the boundary-condition check and the SPM formula
    corrected 2026-03-31 (see project_attenuator_time_window.md memory).
  - Read recommended_time_window() carefully. At L=100m with P=0.05W,
    what does the formula predict? Is that grid feasible? Estimate memory.
  - Research: how does pulse-based Raman simulation typically scale? Look
    for published work on long-fiber nonlinear propagation. Key references
    on SSFM (split-step Fourier method) and error control at long
    distances.
  - Verify the solver tolerances (do NOT change them — per user directive
    in memory, they're already tuned) are appropriate at 100m. If not,
    surface this to user.

PHASE 2 — Discuss (AskUserQuestion)
  - Grid sizing at 100m: what Nt and time window does physics demand?
    Present your analysis and have user confirm before committing compute.
  - Which fiber (SMF-28, HNLF, others): start with SMF-28, but ask.
  - Power level: low-power (linear-ish regime) easier; user may want
    nonlinear regime specifically.
  - Time budget for a single 100m optimization: hours? a day? Be upfront.

PHASE 3 — Plan (/gsd-add-phase → /gsd-plan-phase)
  Tasks:
    1. Validate the simulation at L=50m first — an intermediate stepping
       stone. Establish correctness (energy conservation, boundary
       conditions).
    2. Fix any auto-sizing issues in setup_raman_problem — don't bypass,
       fix properly. Coordinate with Session B (if it's also doing cleanup).
    3. Run a 100m validation forward solve (no optimization yet) to measure
       per-solve cost.
    4. Run the first 100m optimization. Start from phi@2m (per Phase 12)
       as warm start to reduce iterations.
    5. Validate the result: energy conservation, boundary conditions,
       visual sanity of the phase profile and convergence curve.
    6. (Optional) Sweep: fix L=100m, sweep P and fiber.

PHASE 4 — Execute (/gsd-execute-phase) autonomously.
  THIS ONE IS HEAVY. Expect single optimizations to run 1–8 hours on
  the burst VM. Plan for overnight runs. Set the VM to auto-stop
  after the job if possible.

## Success criteria

  - [ ] Numerical validation at L=50m shows no new issues vs L=30m
  - [ ] Auto-sizing logic properly fixed (not bypassed) for L ≥ 100m
  - [ ] First 100m optimization completes and converges
  - [ ] Energy conservation and boundary-condition metrics verified
  - [ ] Comparison: 100m result vs. 30m result vs. 10m result —
    does the optimization landscape change qualitatively?

## Feeds into Session G (if spawned) / paper narrative

  - This is one of the most publishable threads. Long-fiber Raman
    suppression with preserved phase-shape universality would be a
    strong result.

## Critical reminders

  - This session WILL monopolize the burst VM during active runs.
    Coordinate with other sessions before starting a long optimization
    (check who else needs compute).
  - `julia -t auto`. At M=1 this gives modest speedup but every bit
    helps for multi-hour runs.
  - Save checkpoints! Long runs that crash at 80% without
    intermediate state are the worst. Use Optim.jl callbacks to save
    iteration history to disk.
  - `burst-stop` after each 100m run — even an overnight cost of $21
    accidentally.
```

---

### Session G (Suggested) — Physics Synthesis & Paper Narrative Prep

**Recommended worktree:** `~/raman-wt-synthesis` on branch `sessions/synthesis`
**Compute profile:** Zero compute — writing + reading
**Estimated wall time:** 2–3 days

```
# Session G — Physics Findings Synthesis

## Context


There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

The project has 12+ completed phases producing real physics insights.
Those insights are scattered across SUMMARY.md files, .planning/notes/,
and results/raman/*.md. Before the sprint ends, consolidate what is
ACTUALLY KNOWN about Raman suppression via spectral-phase shaping in
this codebase, in a form suitable for a paper draft or at minimum a
group-meeting presentation.

## Goal

A single authoritative document `.planning/notes/physics-findings-synthesis.md`
that:
  1. States the central physics discovery(ies)
  2. Lists the evidence for each claim, with pointers to phase SUMMARYs
     and figures
  3. Identifies which claims are robust vs. provisional
  4. Identifies the top 3–5 open questions the remaining sprint time
     could address
  5. Outlines a paper-shaped narrative: intro → method → results →
     discussion, with placeholders for figures

## Your workflow

PHASE 1 — Research (fully 50% of this session's time)
  - Read EVERY phase SUMMARY.md in .planning/phases/*/
  - Read all files in .planning/notes/
  - Read all .md files in results/raman/
  - Read STATE.md's "Accumulated Context — Key Decisions" section
  - Read the Rivera Lab papers cited in project_rivera_lab_context.md
  - Build a claim/evidence table

PHASE 2 — Discuss
  Surface your claim/evidence table to the user. Get alignment on which
  claims are strongest, which need more evidence, which to prioritize.

PHASE 3 — Plan
  Outline the synthesis doc and the paper-narrative skeleton.

PHASE 4 — Execute (write the doc)

## Success criteria

  - [ ] physics-findings-synthesis.md exists and is ≥ 2000 words
  - [ ] Every claim cites a specific phase/file/figure
  - [ ] Has a rigorous "known vs. suspected" delineation
  - [ ] Ends with prioritized open-question list
  - [ ] User confirms it captures the project's physics story accurately

## Why this session

The other sessions produce new findings. This session converts findings
into a narrative. Without it, publication-readiness lives in scattered
files and no one (including the user) will easily reconstruct the
arc of what was learned.

## Critical reminders

  - No simulation work in this session. Pure synthesis.
  - `git pull` constantly — other sessions are producing new results
    that should be incorporated.
```

---

### Session H (Suggested) — Cost Function Architecture Audit

**Recommended worktree:** `~/raman-wt-cost-audit` on branch `sessions/cost-audit`
**Compute profile:** Moderate — benchmark runs on burst VM
**Estimated wall time:** 2–3 days

```
# Session H — Cost Function Architecture Audit

## Context


There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. Also both claude code with gsd and gsd-2 are running so not only check and update .planning but also .gsd

The codebase now has (or is about to have) multiple parallel cost function
paths:
  - Original: linear E_band / E_total
  - Log-scale (Phase 8 fix, dB/linear reconciliation)
  - Phase 14 sharpness-aware (Hessian-in-cost) path: optimize_spectral_phase_sharp
  - Possible future: quantum-noise-aware (per .planning/seeds/quantum-noise-reframing.md)

Without a systematic comparison, the team's default choice drifts based on
whichever path someone touched most recently. This session does the
comparison properly.

## Goal

A controlled, head-to-head comparison of all cost function variants under
identical conditions, producing a recommendation for which to use as the
default going forward.

## Your workflow

PHASE 1 — Research + inventory
  - List every cost function variant in the codebase
  - Read Phase 8 SUMMARY (log-scale fix)
  - Read Phase 14 SUMMARY (sharpness-aware — if complete)
  - Read docs on sharpness-aware minimization in the literature (SAM, Entropy-SGD)

PHASE 2 — Discuss
  - What's the "fair comparison"? Same grid, same fiber, same starting phase,
    same iteration cap, same stopping criterion.
  - Metrics: final J, wall time, Hessian eigenspectrum (flatness), stability
    under perturbation (reuse Session D's simplicity + stability framework).

PHASE 3 — Plan
  Tasks:
    1. Design the comparison matrix (4 cost functions × 3 configs = 12 runs)
    2. Implement a driver script that runs all variants with identical inputs
    3. Analysis: winner per metric, runner-up, tradeoff narrative
    4. Decision doc recommending a default

PHASE 4 — Execute

## Success criteria

  - [ ] Comparison driver runs all variants
  - [ ] A decision doc lives in .planning/notes/cost-function-default.md
    with a clear recommendation and rationale

## Why this session

Feeds into Session B (documentation — the README should mention the default
cost and why) and every future optimization session. Prevents cost-function
drift.

## Critical reminders

  - MUST use the burst VM (runs at Nt=2^13)
  - This depends on Phase 14 being complete. If not, wait.
```

---

## How to launch in parallel — practical recipe

1. **First: verify Phase 14 is complete or near complete.** Sessions A, C, D,
   E, F, H can drift into stale territory if the cost function changes mid-flight.
   Sessions B and G are safe to run now regardless.

2. **Spawn sessions in waves, not all at once:**

   **Wave 1 (now, 2–3 sessions):**
   - Session B (Repo Polishing) — no compute dependency, pure win
   - Session G (Physics Synthesis) — no compute, reads existing state
   - Session D (Simple Profile Stability) — small compute, quick result

   **Wave 2 (after Phase 14 done, 2–3 sessions):**
   - Session A (Multi-Variable Optimization)
   - Session C (Multimode)
   - Session E (Sweep Design) — can start planning before D finishes

   **Wave 3 (when burst VM is free, serialize):**
   - Session F (Long Fiber) — monopolizes burst VM for hours/days
   - Session H (Cost Function Audit) — benchmarks need exclusive burst time

3. **Git worktrees per session.** Use the `git worktree add` commands in each
   prompt's header. This prevents cross-session file conflicts.

4. **Burst VM coordination.** Per CLAUDE.md Rule 1, ALL simulation work —
   regardless of size — runs on the burst VM. The burst VM is ONE machine,
   so only one session at a time can actively run sims on it. Before
   starting any compute work:
   ```bash
   burst-status        # if RUNNING, check what's on it; if TERMINATED, safe to start
   burst-ssh "tmux ls" # list tmux sessions — see who else's jobs are alive
   ```
   Sessions parallelize their *research, planning, and editing* work
   (which runs on `claude-code-host`), but serialize their *simulation runs*
   on the burst VM. If your session's plan calls for a long sweep, flag
   it to the user so other sessions can plan around the burst VM being
   occupied.

5. **Claude-code-host has 3 concurrent sessions comfortably.** Don't spawn
   4+ simultaneously or you'll OOM.

6. **Check in with the user between waves.** After Wave 1 finishes, the user
   should review findings before committing compute to Wave 2.

---

## Prompt engineering notes (for reference)

These prompts follow Opus best practices:
  - Clear role/goal statement up front
  - Structured phase-based workflow (research → discuss → plan → execute)
  - Explicit "use /gsd-* commands" workflow anchoring
  - Explicit "out of scope" to prevent drift
  - Quantitative success criteria
  - Negative constraints ("don't modify X," "never bare julia")
  - Escalation triggers ("if X, STOP and escalate to user")
  - References to specific files/paths so the agent doesn't hallucinate
  - Compute discipline reminders tied to CLAUDE.md

When in doubt, agents should prefer asking via AskUserQuestion over guessing.
