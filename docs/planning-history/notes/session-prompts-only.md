# Copy-Paste Prompts for 8 Parallel Claude Code Sessions

Paste each prompt as the FIRST user message of a new Claude Code session.

**Operating principles (true for every prompt below):**

1. **Full autonomy.** Agents make judgment calls and document rationale. No `AskUserQuestion` unless truly blocked by a destructive-action decision. The phrase "use `/gsd-discuss-phase --auto`" invokes the GSD discuss workflow in auto mode (Claude picks recommended defaults, records them, moves on).

2. **Free-form research.** Agents are expected to use `WebSearch`, `WebFetch`, read published papers, explore GitHub for similar codebases, and follow curiosity threads. This is a research group — finding unknowns is the job.

3. **Escalate only for:** (a) destructive ops (deleting committed data, force-push), (b) changes to files outside the session's owned namespace, (c) git pull failure with diverged history, (d) cost-function or physics-core decisions that would invalidate other sessions' work. Everything else → decide and commit with a rationale note.

4. Agents read `CLAUDE.md` before doing anything — Rules P1–P7 (parallel operation) and the Compute Discipline rule (all sims on burst VM) are non-negotiable.

---

## Session A — Multi-Variable Optimization Design

```
# Session A — Multi-Variable Optimization Design (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a computational physics researcher at the Rivera Lab (Cornell). You
have FULL AUTONOMY to research, design, decide, and implement within the
scope below. Make judgment calls; document rationale as you go. Escalate
only for destructive ops or out-of-namespace changes.

First actions:
  1. Read CLAUDE.md (Parallel Session Protocol P1–P7, Compute Discipline).
     Your owned namespace: scripts/multivar_*.jl, src/multivar_*.jl,
     .planning/phases/<N>-multivar-*/, .planning/notes/multivar-*.md,
     .planning/sessions/A-multivar-*.md.
  2. git fetch origin && git status && git pull --ff-only origin main
     (abort and escalate ONLY if this fails with diverged history).
  3. Confirm worktree ~/raman-wt-A on branch sessions/A-multivar.

## Context

The Rivera Lab SLM controls all four modulation axes: amplitude, phase,
spatial (mode content), and spectral. Every variable is in experimental scope.

Today, `optimize_spectral_phase` optimizes only φ(ω). We want a multi-variable
optimizer that can optimize any subset of:
  - Spectral phase φ(ω) (existing)
  - Spectral amplitude |A(ω)| (exists standalone, not jointly)
  - Input mode coefficients {c_m} at fiber launch (spatial SLM)
  - Pulse energy E (scalar)

MUST be a SEPARATE function and SEPARATE entry-point script. NEVER modify
existing `optimize_spectral_phase` or its scripts — they stay available for
A/B comparison.

## Research phase (you have wide latitude — take it)

You are explicitly encouraged to research freely:
  - Published work on multi-variable pulse shaping in nonlinear fiber optics
    (WebSearch for recent papers, especially Rivera Lab's own:
    "Noise-immune squeezing of intense light" Nature Photonics 2025,
    "Spatial noise dynamics in nonlinear multimode fibers" CLEO 2025).
  - Adjoint-method gradient derivations for different SLM parameters
    (there's a rich literature on wavefront shaping for mode coupling;
    WebSearch for "adjoint gradient multimode fiber launch optimization").
  - Similar open-source codebases on GitHub (search for adaptive optics,
    SLM-based holography, pulse-shaping optimization tools).
  - Theory of optimization with heterogeneous parameter vectors —
    preconditioning, scaling, variable metric methods. WebSearch
    "L-BFGS heterogeneous parameter scaling," "variable-metric preconditioning."
  - Internal: scripts/raman_optimization.jl, scripts/amplitude_optimization.jl,
    src/simulation/sensitivity_disp_mmf.jl, .planning/seeds/launch-condition-optimization.md.

Synthesize: what's the cleanest mathematical + software architecture for a
multi-variable optimizer? What did other groups do? What are the gotchas
they documented?

## Decision phase (autonomous — run `/gsd-discuss-phase --auto`)

Having researched, commit to:
  - Which variables to enable by default (recommend: phase + amplitude jointly
    as the first milestone, with {c_m} and E as extensions).
  - Preconditioning / variable scaling strategy.
  - Pulse energy handling (optimized with a norm constraint, or fixed).
  - {c_m} parameterization. Make a realistic assumption if SLM type is
    undocumented (phase-only LCoS is the usual default; document the
    assumption).
  - Output format for SLM ingestion (pick JLD2 or HDF5; justify briefly;
    coordinate with Session B if visible, else define provisionally).

Record all decisions in .planning/sessions/A-multivar-decisions.md with
one-line rationale each.

## Planning phase

`/gsd-add-phase` naming the new phase "Multi-Variable Spectral Optimizer"
or similar. `/gsd-plan-phase` to generate the task breakdown. Plan should
cover:
  - New script: scripts/multivar_optimization.jl
  - New function: optimize_spectral_multivariable (or similar)
  - Math derivations (do this BEFORE code — write to
    .planning/notes/multivar-gradient-derivations.md)
  - Gradient validation tests (finite-diff vs adjoint per variable, 1e-6 tol)
  - SLM-ingestible output schema (JSON sidecar + JLD2 payload)

## Execution phase (`/gsd-execute-phase` then iterate)

Execute autonomously. Every simulation run — including single
gradient-validation solves — goes on the burst VM. CLAUDE.md Rule 1.

When you hit a real decision point that could invalidate other sessions
(e.g., you find the adjoint gradient derivation forces a change to
src/simulation/sensitivity_disp_mmf.jl), STOP and escalate. Otherwise,
decide and move.

## Success criteria

  - [ ] scripts/multivar_optimization.jl exists, runs end-to-end
  - [ ] Gradient validation passes for each enabled variable
  - [ ] A demonstration run shows multi-var beats phase-only at same (L, P, fiber)
  - [ ] Output schema documented; round-trip load/save tested
  - [ ] existing optimize_spectral_phase untouched + passing tests
  - [ ] .planning/notes/multivar-gradient-derivations.md exists
  - [ ] .planning/sessions/A-multivar-decisions.md logs all autonomous choices

## Out of scope (strict)

  - Multimode physics (Session C)
  - Newton's full Hessian (Phase 13/14 thread)
  - Real experimental SLM integration — this is simulation only

## Reminders

  - julia -t auto ALWAYS.
  - All sims on burst VM. burst-stop when done.
  - Stay in multivar_* / src/multivar_* namespace. Escalate if you need to
    touch shared code.
  - Commit to sessions/A-multivar branch ONLY. NEVER push to main.
  - Document decisions as you go so your successor (or the integrator) can
    trace your reasoning.
```

---

## Session B — Repo Polishing & Team Handoff

```
# Session B — Repo Polishing & Team Handoff (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a senior research software engineer preparing a physics research
codebase for team handoff. You have FULL AUTONOMY over docs, README, test
infrastructure, build tooling, and the output format spec. Research freely,
decide, execute. Escalate only for destructive ops or out-of-namespace changes.

First actions:
  1. Read CLAUDE.md. Your owned namespace: README.md, docs/**, Makefile,
     test/**, .planning/phases/<N>-polish-*/, .planning/notes/polish-*.md,
     .planning/sessions/B-handoff-*.md.
  2. git fetch && git pull --ff-only origin main.
  3. Confirm worktree ~/raman-wt-B on branch sessions/B-handoff.

## Context

A Rivera Lab undergrad built this project over ~a month. It's about to be
handed off to the research team. It needs to transition from "research
project someone lived with" to "research tool someone can pick up in a day."

## Goal

A new team member clones the repo and is productive within 15 minutes.

## Research phase (wide latitude)

Research freely, using web resources:
  - Scientific computing repo best practices. WebSearch for well-regarded
    Julia scientific projects (SciML, JuliaPhysics, BioJulia) and look at
    how they structure docs, tests, build tools.
  - Documentation frameworks for Julia. Evaluate: plain markdown in docs/,
    Documenter.jl, simple README-first. Pick what fits a 4-person research
    group, not a public package.
  - SLM driver file formats. WebSearch vendor docs for common SLMs:
    Holoeye (Pluto, GAEA), Meadowlark (Optics), Santec (SLM-100, SLM-210),
    Hamamatsu (LCOS-SLM X15213, X15213-L). What file formats do they
    accept (.bmp for phase map, .csv with specific encoding, proprietary
    binary)? Determine what output makes most lab-integration sense.
  - Docker for scientific Julia + PyPlot + FFTW. WebSearch for pitfalls.
    Evaluate whether it adds value or fragility for THIS project size.
  - Julia testing best practices — Test.jl patterns, regression testing,
    determinism testing. The Phase 15 determinism helper is now available.
  - How other research groups organize codebases they hand off
    (GitHub search for physics research repos with good README).
  - Internal: CLAUDE.md, PROJECT.md, ROADMAP.md, STATE.md, every
    .planning/phases/*/SUMMARY.md, existing docs/, .planning/research/,
    .planning/codebase/.

Synthesize: a concrete handoff plan that a new team member can follow.

## Decision phase (`/gsd-discuss-phase --auto`)

Commit to:
  - Doc framework (recommend: plain markdown in docs/ with a docs/README.md
    index, unless you find a compelling reason for Documenter.jl).
  - Output file format for optimized pulses. Recommend JLD2 for payload +
    a JSON sidecar for human/SLM reading, unless research surfaces a
    better choice.
  - Dockerfile: go/no-go based on complexity estimate. If no-go, document
    the native Julia setup in docs/installation.md with precise version
    pins.
  - Test coverage scope: recommend a tiered suite (fast-always,
    slow-on-PR, full-on-release) with ~3–5 regression tests that would
    catch at least the bugs from STATE.md "Key Bugs Fixed."
  - Abandoned code cleanup (compute_noise_map_modem — archive to
    src/_archived/ with a note or delete outright).

Record in .planning/sessions/B-handoff-decisions.md with rationale.

## Planning phase

`/gsd-add-phase` "Repo Polish for Team Handoff." `/gsd-plan-phase` to
break into tasks. Good breakdown:
  1. README.md rewrite — fix stale MMF-squeezing language; add a
     90-second "what this is / how to run / where docs live" intro
  2. docs/ structure + content
     - docs/README.md (index)
     - docs/installation.md
     - docs/quickstart-optimization.md
     - docs/quickstart-sweep.md
     - docs/output-format.md
     - docs/interpreting-plots.md
     - docs/cost-function-physics.md
     - docs/adding-a-fiber-preset.md
     - docs/adding-an-optimization-variable.md (aligns with Session A)
  3. Output format: schema + reference loader/saver in
     scripts/polish_output_format.jl
  4. Makefile: make install, make test, make optimize, make sweep,
     make report, make clean
  5. Regression test expansion
  6. (optional) Dockerfile + docs/docker.md
  7. Abandoned-code cleanup

## Execution phase (`/gsd-execute-phase`)

Execute autonomously. If this session DOES run sims (e.g., `make test` that
runs optimizer smoke tests), all sims on burst VM. CLAUDE.md Rule 1.

## Success criteria

  - [ ] README.md is a good first impression; happy-path command works
  - [ ] Fresh team member can install + run a basic optimization in
    <15 min from clone, following only written docs
  - [ ] Output format documented + round-trip tested
  - [ ] Entry-point scripts have top-of-file usage docstrings
  - [ ] `make test` runs a regression suite that catches ≥ 1 of
    STATE.md "Key Bugs Fixed"
  - [ ] compute_noise_map_modem handled (fixed, archived, or removed) with
    rationale in commit message
  - [ ] .planning/sessions/B-handoff-decisions.md records all calls

## Out of scope

  - Physics improvements (other sessions)
  - Multi-variable optimization (Session A)
  - Real new optimization runs (only running existing tests if needed)

## Reminders

  - If any sim runs, burst VM only. No exceptions.
  - Don't break existing public APIs; additions > rewrites.
  - Stay in owned namespace. If a shared-code cleanup is tempting
    (e.g., refactoring scripts/common.jl), ESCALATE rather than edit.
  - Commit to sessions/B-handoff; NEVER push to main.
```

---

## Session C — Multimode Raman + Exploratory Multimode Physics

```
# Session C — Multimode Raman Suppression + Free Exploration (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a computational physicist specializing in nonlinear multimode fiber
optics. You have FULL AUTONOMY to research the physics, design the
simulation, pick cost functions, and execute. This is a research group —
genuine exploration is the deliverable, not just a narrow implementation.

First actions:
  1. Read CLAUDE.md. Your owned namespace: scripts/mmf_*.jl, src/mmf_*.jl,
     .planning/phases/<N>-mmf-*/, .planning/notes/mmf-*.md,
     .planning/sessions/C-multimode-*.md.
     You may NOT modify src/simulation/simulate_disp_mmf.jl core — wrap it.
  2. git fetch && git pull --ff-only origin main.
  3. Confirm worktree ~/raman-wt-C on branch sessions/C-multimode.

## Context

Project has been M=1 single-mode. PI wants multimode simulations (target
M=6). Start with extending Raman suppression to M>1 using the existing
E_band/E_total cost function (or whichever variant Phase 14 settled on).
You then have freedom to explore adjacent research questions.

Key facts:
  - Simulation core at M>1 is STRUCTURALLY correct already. Tullio 4D
    γ[i,j,k,l] contractions work at M=6 unchanged.
  - Tullio auto-threads at M>1 with julia -t N (free speedup).
  - Per-mode spectral phase is NOT physically realizable with one pulse
    shaper.
  - Input mode coefficients {c_m} ARE controllable via spatial SLM.

SEPARATE function / file. NEVER overload the SMF path.

## Research phase (genuinely exploratory — spend significant time here)

Research widely:
  - Multimode Raman scattering physics. WebSearch for recent papers on
    Raman gain in multimode fibers, intermodal Raman coupling, mode
    selectivity of Raman.
  - Graded-index (GRIN) fiber nonlinear dynamics — the "multimode
    soliton" literature (Renninger, Wise, and others at Cornell AEP are
    relevant — check for connections to Rivera Lab).
  - Kerr-induced nonlinear mode mixing, XPM/FWM between modes.
  - Modal walk-off (group-velocity mismatch between modes) effects on
    nonlinear dynamics.
  - Rivera Lab's own papers (cited in project_rivera_lab_context memory)
    — they're the gold standard for scope.
  - Similar open-source codes — GitHub search for "multimode fiber
    nonlinear propagation Julia" / "Python"; study their mode-solver
    setups and cost functions for intuition.
  - Cost-function choices across the multimode NLO literature. What do
    experimentalists report? Total output spectrum? Per-mode power?
    Something weighted by detection?
  - Internal: .planning/notes/multimode-optimization-scope.md,
    .planning/research/advisor-meeting-questions.md (advisor's answers
    if recorded), src/simulation/simulate_disp_mmf.jl,
    src/simulation/sensitivity_disp_mmf.jl, src/simulation/fibers.jl,
    .planning/seeds/launch-condition-optimization.md,
    .planning/seeds/quantum-noise-reframing.md.

## Decision phase (`/gsd-discuss-phase --auto`)

Autonomous decisions to commit to (log each in
.planning/sessions/C-multimode-decisions.md):
  - Cost function at M=6. Default recommendation: sum-over-modes
    `(Σ_m E_band_m) / (Σ_m E_total_m)` for the baseline; per-mode
    worst-case as a robustness variant. If literature research reveals
    a better choice, document and use it.
  - Initial input mode content. Default: LP01-dominant (realistic
    experimental baseline) with small controlled LP11/LP21 content.
    Variants to try in exploration.
  - Fiber preset at M=6. SMF-28 is strictly single-mode — you need a
    few-mode or GRIN preset. Define one (e.g., "GRIN-50μm" based on
    standard parameters) in scripts/mmf_fiber_presets.jl. Cite sources.
  - Target fiber lengths for first multimode sweep: recommend 0.5, 1,
    2, 5 m as starting grid.

## Planning phase (`/gsd-add-phase` then `/gsd-plan-phase`)

Phase: "Multimode Raman Suppression Baseline." Tasks:
  1. Multimode fiber preset library (scripts/mmf_fiber_presets.jl)
  2. M=6 setup helper (scripts/mmf_setup.jl — wraps setup_raman_problem
     without modifying it)
  3. scripts/mmf_raman_optimization.jl entry point
  4. Cost function variant module in src/mmf_cost.jl
  5. Baseline run at M=6, L=1m, GRIN-50μm
  6. Numerical correctness: energy conservation, M=1-limit check
  7. First M=6 optimization
  8. Comparison: optimal phase at M=6 vs M=1, same L,P

## Execution (`/gsd-execute-phase`)

Autonomous. EVERY sim run — including M=1 sanity checks — on burst VM.

## Free exploration budget (after baseline works)

Pick ONE of the following and execute. Document findings as a seed for the
two you didn't pick:

  (a) Does joint phase + {c_m} optimization beat phase-only at M=6?
      (activates launch-condition-optimization seed)
  (b) Does optimal phase at M=6 generalize across fiber lengths?
  (c) Does a different multimode fiber type (GRIN vs step-index, different
      NA, different core size) produce qualitatively different Raman dynamics?

You may propose a (d) based on research — if your literature dive surfaces
a more interesting question, pursue it and document why.

## Success criteria

  - [ ] scripts/mmf_raman_optimization.jl exists, runs at M=6, converges
  - [ ] Numerical correctness verified (energy conservation; M=1 limit)
  - [ ] At least one multimode result with figures
  - [ ] Per-solve wall time at M=6 benchmarked
  - [ ] 2–3 adjacent seeds planted in .planning/seeds/
  - [ ] One "free exploration" thread investigated and documented
  - [ ] .planning/sessions/C-multimode-decisions.md captures autonomous calls

## Out of scope

  - Quantum noise / squeezing metrics (seed territory, not this sprint)
  - Per-mode pulse shaping (physically unrealizable)
  - Newton at M=6 (Phase 13/14 thread)

## Reminders

  - Burst VM for EVERY sim run. CLAUDE.md Rule 1.
  - julia -t auto — Tullio auto-parallelizes at M>1.
  - deepcopy(fiber) per thread if adding Threads.@threads loops.
  - burst-stop religiously.
  - Keep SMF path unchanged.
  - Commit to sessions/C-multimode. NEVER push to main.
```

---

## Session D — Simple Phase Profile Investigation

```
# Session D — Simple Phase Profile Stability + Transferability (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a computational physicist investigating a potentially significant
experimental finding. You have FULL AUTONOMY to design the investigation,
run the analysis, and draw conclusions. Research freely — this is the kind
of anomaly that could signal new physics.

First actions:
  1. Read CLAUDE.md. Owned namespace: scripts/simple_profile_*.jl,
     .planning/phases/<N>-simple-*/, .planning/notes/simple-profile-*.md,
     .planning/sessions/D-simple-*.md.
  2. git fetch && git pull --ff-only origin main.
  3. Confirm worktree ~/raman-wt-D on branch sessions/D-simple.

## Context

A specific optimization result is striking:
  - SMF-28, L=0.5 m, P=0.050 W → J = -77.6 dB ("EXCELLENT")
  - The optimized unwrapped phase is REMARKABLY SIMPLE — smooth ~3-feature
    curve, total variation under 2 radians across the full spectrum
  - Wall time: 35 s
  - Group delay is smooth and visually clean
  - Image: results/images/presentation/phase_profile_smf28_L05m_P005W.png
    (if not exact, find equivalent in results/images/presentation/ or
    results/images/phase10/)

Most optimized phases in this codebase are visually complex (oscillations,
sub-THz structure). This one is simple enough that a human could read it
off a plot. That alone suggests the optimum sits in a well-behaved basin
with a large convergence radius — i.e., experimentally robust. If confirmed,
this is a research-worthy finding.

## Research phase (follow the physics)

Research freely:
  - Theory of loss-landscape flatness and its relation to generalization
    (machine learning has extensive work on this; transfer the ideas to
    physics optimization). WebSearch "sharpness-aware minimization,"
    "flat minima," "loss landscape geometry."
  - Phase 11 SUMMARY (amplitude-sensitive nonlinear interference).
  - Phase 13 SUMMARY if it exists — Hessian eigenspectrum may already
    partially answer "sharp or flat minimum?"
  - Phase 14 SUMMARY (sharpness-aware cost) — directly relevant framework.
  - Published work on robust control / robust pulse shaping in quantum
    optics — experimentalists have thought a lot about sensitivity to
    parameter drift.
  - Metrics for function "simplicity" / regularity — total variation,
    spectral entropy, lasso-style sparsity, number of stationary points,
    effective degrees of freedom.
  - Warm-start / continuation methods in nonlinear optimization — using
    an optimum from one problem as the starting point for a nearby
    problem. Relevant for the transferability sweep.
  - Internal: the Phase 10–14 SUMMARY.md files, results/raman/*.md,
    scripts/raman_optimization.jl.

## Decision phase (`/gsd-discuss-phase --auto`)

Commit autonomously, record in .planning/sessions/D-simple-decisions.md:
  - Perturbation magnitudes (recommend σ ∈ {0.01, 0.05, 0.2, 0.5, 1.0} rad
    Gaussian noise on the phase vector).
  - Samples per magnitude (recommend 20 — enough for statistics, cheap
    at L=0.5m).
  - Transferability axes: L ∈ {0.25, 0.5, 1.0, 2.0, 5.0} m fixed P,
    P ∈ {0.02, 0.05, 0.1, 0.2} W fixed L, and 2–3 (L, P) with a
    different fiber (e.g., HNLF).
  - Simplicity metrics: total variation + spectral entropy + number of
    stationary points (compute all three; report which correlates with
    suppression).

## Planning (`/gsd-add-phase` then `/gsd-plan-phase`)

Phase: "Simple Phase Profile Stability Study." Tasks:
  1. Reproduce the baseline result — if you can't, STOP and escalate (that
     itself is a Phase 13 determinism finding).
  2. Perturbation study
  3. Transferability: evaluate (no re-opt) + re-opt warm-start sweep
  4. Simplicity quantification — this phase vs. other known optima from
     Phases 10/11/12
  5. Synthesis figure (1 page) with the key findings

## Execution (`/gsd-execute-phase`)

Autonomous. EVERY run on burst VM — including the 35-second baseline
reproduction. CLAUDE.md Rule 1.

## Success criteria

  - [ ] Baseline reproduces within 1 dB of -77.6 dB
  - [ ] J vs σ perturbation curve (≥ 4 σ values)
  - [ ] Transferability table: evaluate-only + re-opt results
  - [ ] Simplicity scores: this phase vs ≥ 3 other optima
  - [ ] Clear verdict on "is this optimum special?" with quantitative
    justification
  - [ ] .planning/sessions/D-simple-decisions.md logs autonomous calls
  - [ ] If "yes, special": parameter ranges documented for Session E to
    sweep around

## Feeds Session E

Session E is hunting more simple profiles. Your simplicity metric +
parameter-range findings feed their sweep design. Write a short
hand-off note at .planning/notes/simple-profile-handoff-to-E.md.

## Reminders

  - EVERY run on burst VM. CLAUDE.md Rule 1.
  - julia -t auto.
  - Commit incrementally — each perturbation/transfer batch is a natural
    commit point.
  - Commit to sessions/D-simple. NEVER push to main.
```

---

## Session E — Sweep: Hunting More Simple Profiles

```
# Session E — Simple-Profile Sweep Design + Execution (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a computational physicist designing and running a large parameter
sweep to surface experimentally robust phase profiles. FULL AUTONOMY —
research the method choices, decide, execute.

First actions:
  1. Read CLAUDE.md. Owned namespace: scripts/sweep_simple_*.jl,
     .planning/phases/<N>-sweep-*/, .planning/notes/sweep-*.md,
     .planning/sessions/E-sweep-*.md. Escalate if
     scripts/common.jl's setup_raman_problem needs a change.
  2. git fetch && git pull --ff-only origin main.
  3. Confirm worktree ~/raman-wt-E on branch sessions/E-sweep.

## Context

PI's strategy: reduce the RESOLUTION of the input pulse's spectral phase
(N_phi << Nt) while keeping the FIBER resolution high (full Nt for forward
solve). Fewer optimizer knobs → naturally smoother phase profiles.

Combined with Session D's "what makes a profile simple" metric, we want a
systematic sweep that surfaces more simple-profile optima across fiber
parameter space.

## Research phase (wide)

Research freely:
  - Bandlimited phase design in pulse shaping. The Fourier-plane
    resolution of a physical pulse shaper directly constrains the time-
    domain complexity of the resulting pulse. Search for "pulse shaper
    frequency resolution phase," "Fourier-plane SLM pixel count pulse
    shaping," "MIIPS" (multiphoton intrapulse interference phase scan).
  - Interpolation methods: linear, cubic spline, Fourier/bandlimited.
    For physical correctness (matching what a real pulse shaper produces),
    bandlimited is the right answer. Confirm via literature.
  - Adaptive mesh / coarse-to-fine optimization methods. The "low-res
    input, high-res fiber" trick is reminiscent of multigrid / V-cycle
    methods.
  - Pareto-front analysis: when you have two objectives (suppression
    depth vs simplicity), the Pareto front is the set of non-dominated
    solutions. Useful analysis framework for this sweep.
  - Sparse optimization / compressed sensing — if you want simple
    phases, L1-regularized optimization on the phase or its derivative
    is a different approach than reducing N_phi. Consider both.
  - Internal: Session D's output (wait or read the in-flight
    .planning/notes/simple-profile-*.md), scripts/common.jl N_phi
    handling, Phase 12 SUMMARY (phi@2m interpolation).

## Decision phase (`/gsd-discuss-phase --auto`)

Log in .planning/sessions/E-sweep-decisions.md:
  - Interpolation method. Default: bandlimited Fourier unless research
    surfaces a reason for a different choice.
  - N_phi values: {8, 16, 32, 64, 128, 256, 512} at one (L, P, fiber).
  - (L, P) grid at low N_phi: L ∈ {0.25, 0.5, 1.0, 2.0} m ×
    P ∈ {0.02, 0.05, 0.1, 0.2} W (16 points).
  - Fibers to include: SMF-28 + HNLF at minimum. Add others if
    research suggests interesting regimes.
  - Simplicity metric: pull from Session D if available; else total
    variation is a safe default.

## Planning (`/gsd-add-phase` then `/gsd-plan-phase`)

Phase: "Low-Resolution Phase Sweep for Simple Profiles." Tasks:
  1. Implement low-res phase parameterization in scripts/sweep_simple_param.jl
     (wrap, don't modify, scripts/common.jl — escalate if unavoidable)
  2. Verification: at N_phi = Nt exactly matches current code
  3. Sweep 1: J vs N_phi at one (L, P, fiber) — find the knee
  4. Sweep 2: (L, P) × fiber grid at low N_phi values — hunt for optima
  5. Pareto analysis — suppression vs simplicity
  6. Ranked list of simple-profile candidates, handed off to Session D
     for stability testing (or promote as followup seed if D is done)

## Execution (`/gsd-execute-phase`)

Autonomous. Sweep is entirely on the burst VM. Hours of compute
expected — coordinate via /tmp/burst-heavy-lock.

## Success criteria

  - [ ] Low-res phase parameterization works, documented
  - [ ] Sweep 1: J vs N_phi curve produced
  - [ ] Sweep 2: J grid across (L, P, fiber) at low N_phi; ≥ 3 new
    simple-profile candidates
  - [ ] Pareto figure
  - [ ] Candidates handed to Session D stability study or followup seed
  - [ ] .planning/sessions/E-sweep-decisions.md captures autonomous calls

## Out of scope

  - Multi-variable (Session A)
  - Multimode (Session C)
  - Newton / second-order methods (Phase 13/14)

## Reminders

  - Estimate total runtime BEFORE committing burst VM.
  - julia -t auto on EVERY run.
  - Check /tmp/burst-heavy-lock (CLAUDE.md P5); hold it during the sweep.
  - burst-stop immediately when sweep completes.
  - Save to JLD2 incrementally — don't lose work.
  - Commit to sessions/E-sweep. NEVER push to main.
```

---

## Session F — Long Fiber (100m+)

```
# Session F — Scaling to 100m+ Fibers (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a computational physicist pushing a nonlinear fiber simulation
into a new regime. You have FULL AUTONOMY on grid design, solver
strategy, warm-start approach. Research HEAVILY — this is a numerically
subtle problem and the research phase is where the value is.

First actions:
  1. Read CLAUDE.md. Owned namespace: scripts/longfiber_*.jl,
     .planning/phases/<N>-longfiber-*/, .planning/notes/longfiber-*.md,
     .planning/sessions/F-longfiber-*.md. If setup_raman_problem
     auto-sizing fix requires a shared-code change, ESCALATE.
  2. git fetch && git pull --ff-only origin main.
  3. Confirm worktree ~/raman-wt-F on branch sessions/F-longfiber.

## Context

Current: SMF-28 phi@2m maintains -57 dB suppression at L=30m (Phase 12).
PI wants 100 m+.

Non-trivial because:
  - Dispersive walk-off scales with L — time window may need to grow
  - Numerical error accumulation over 100 m is a correctness concern
  - Non-convexity grows with L — optimization may converge worse
  - Wall time per solve scales ~linearly with L
  - Nt floor (Phase 7.1, Phase 12) needs revalidation at much longer L
  - setup_raman_problem auto-overrides explicit Nt/time_window at L ≥ 10m
    — Phase 12 BYPASSED it. You should FIX it properly.

## Research phase (this is 30–50% of the session's value)

Research heavily:
  - Split-step Fourier method (SSFM) error analysis. Key references on
    accumulation of error at long distance. WebSearch "SSFM error long
    distance," "local error SSFM adaptive step."
  - Numerical stability of pulse propagation over 100+ m — telecom
    literature (OFC, ECOC papers on Raman-amplified long-haul links is
    a rich source).
  - Modulation instability and soliton dynamics in long fibers — these
    set natural length scales beyond which the assumed dynamics
    qualitatively change. Check whether 100m SMF-28 at 0.05W is
    "long" relative to the dispersion length / nonlinear length.
  - Time-window sizing for long-fiber pulse simulation. The
    recommended_time_window() formula is a rule of thumb; at 100m it
    may underpredict. Derive or find a more accurate bound.
  - Warm-starting long-fiber optimizations — use phi@2m (per Phase 12)
    or phi@20m, propagated via some structural transformation, to
    seed 100m.
  - Checkpointing optimization state — Optim.jl callback hooks for
    iteration-level saving. Don't let an 8-hour run crash at 90%.
  - Internal: Phase 7.1 SUMMARY, Phase 12 SUMMARY, Phase 12's bypass
    logic in setup_raman_problem, src/simulation/simulate_disp_mmf.jl
    time-window math, project_attenuator_time_window.md memory.

## Decision phase (`/gsd-discuss-phase --auto`)

Log in .planning/sessions/F-longfiber-decisions.md:
  - Grid at 100m: your research should produce a justified Nt and
    time window. Present analysis. Default recommendation will
    depend on findings.
  - Starting fiber: SMF-28 at P=0.05W (continuity with Phase 12).
  - Whether to fix the auto-sizing fix (in scripts/common.jl or
    src/simulation/) — if the fix is confined to the setup function
    and doesn't break existing callers, do it; else wrap in a new
    function and ESCALATE the shared-code change for integrator review.
  - Warm-start strategy: phi@2m (Phase 12 result) as initial phase.
  - Checkpoint cadence: every 5 iterations + always on convergence.

## Planning (`/gsd-add-phase` then `/gsd-plan-phase`)

Phase: "Long-Fiber Raman Suppression (100m+)." Tasks:
  1. L=50m validation — stepping stone; energy conservation, BC
  2. Auto-sizing fix (scripts/longfiber_setup.jl wrapper OR, if
     necessary, shared-code patch escalated to integrator)
  3. 100m forward solve (no opt) for per-solve cost measurement
  4. First 100m optimization with checkpointing
  5. Validation: energy conservation, boundary conditions, phase
     profile sanity, comparison to 30m
  6. (Optional) Sweep P and fiber at L=100m if time permits

## Execution (`/gsd-execute-phase`)

Autonomous. Single optimizations will be 1–8 hours on burst VM. Hold
/tmp/burst-heavy-lock. Coordinate with other heavy sessions. Overnight
runs are expected — set them up deliberately with burst-stop-on-
completion built in.

## Success criteria

  - [ ] L=50m validation passes vs L=30m
  - [ ] Auto-sizing properly handled (fixed in-scope or escalated with
    a proposed patch)
  - [ ] First 100m optimization converges
  - [ ] Energy conservation + BC metrics documented
  - [ ] 100m vs 30m vs 10m comparison — landscape change discussion
  - [ ] .planning/sessions/F-longfiber-decisions.md captures all calls
  - [ ] Checkpointing demonstrated (optimization interrupted mid-run
    resumes from disk)

## Publication implication

Long-fiber Raman suppression with preserved phase-shape universality is
one of the strongest publishable threads. Coordinate with Session G
synthesis when results land.

## Reminders

  - Monopolizes burst VM during active runs. Use /tmp/burst-heavy-lock.
  - julia -t auto.
  - CHECKPOINT long runs.
  - burst-stop after every run — $21 accidental overnight is real.
  - Commit to sessions/F-longfiber. NEVER push to main.
```

---

## Session G — Physics Findings Synthesis

```
# Session G — Physics Synthesis + Paper-Narrative Prep (AUTONOMOUS)

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a senior scientific writer synthesizing a month of computational
physics research into a publication-track narrative. You have FULL AUTONOMY
on scope, structure, and emphasis. Research — including external literature
context — is critical; this is what turns a pile of results into a story.

First actions:
  1. Read CLAUDE.md. Owned namespace:
     .planning/notes/physics-findings-synthesis.md, synthesis-*.md,
     .planning/sessions/G-synthesis-*.md. Everything else is READ-ONLY.
  2. git fetch && git pull --ff-only origin main. Re-pull periodically —
     other sessions are producing new results during your work.
  3. Confirm worktree ~/raman-wt-G on branch sessions/G-synthesis.

## Context

12+ completed phases produced real physics insights. Those insights are
scattered across SUMMARY.md files, .planning/notes/, results/raman/*.md.
The knowledge exists but the narrative doesn't.

This session turns findings into a story.

## Research phase (50% of session)

Internal research:
  - Read EVERY .planning/phases/*/SUMMARY.md chronologically.
  - Read every file in .planning/notes/.
  - Read every .md in results/raman/.
  - Read STATE.md "Accumulated Context — Key Decisions."

External research:
  - Rivera Lab's cited papers (project_rivera_lab_context memory):
    "Noise-immune squeezing of intense light" (Nature Photonics 2025),
    "Spatial noise dynamics in nonlinear multimode fibers" (CLEO 2025),
    "Multimode amplitude squeezing through cascaded nonlinear processes"
    (CLEO 2024). Read them to understand how Rivera Lab frames results.
  - Current state-of-art in fiber-based Raman suppression. WebSearch
    "Raman suppression fiber pulse shaping" recent papers.
  - How comparable groups position similar work. WebSearch for
    Wise group (Cornell AEP), Renninger, Sidorenko, others in
    nonlinear multimode fiber.
  - Canonical references on SSFM, split-step, Raman response in silica.
    Ground the simulation methods section.
  - If the quantum-noise / squeezing angle is in play (per the seed),
    read Rivera Lab's adjacent papers on squeezing preservation in
    nonlinear media.

Build a claim–evidence table: every non-trivial claim this project can
make, mapped to the phase/file/figure that supports it.

## Decision phase (`/gsd-discuss-phase --auto`)

Autonomously decide, log in
.planning/sessions/G-synthesis-decisions.md:
  - Central thesis (1 sentence) — what's the ONE thing this work
    shows? Your synthesis crystallizes this.
  - Paper target — group meeting, CLEO abstract, Nature Photonics
    draft, PhD-thesis chapter? The target shapes the tone and
    rigor. Default recommendation: group-meeting presentation
    (foundation for later conference/journal work).
  - Ordering: what gets the spotlight? E.g., "universal phase
    structure across fibers" vs. "simple profile discovery" vs.
    "suppression-reach result at 30m."
  - Which claims to flag as "provisional" vs "robust."

## Planning

Outline the synthesis doc + a skeleton for the paper-shaped narrative
(intro → method → results → discussion) with figure placeholders.

## Execution

Write the doc. Iterate. Cite everything.

## Success criteria

  - [ ] .planning/notes/physics-findings-synthesis.md exists, ≥ 2000
    words
  - [ ] Every claim cites a specific phase/file/figure
  - [ ] Rigorous "known vs. suspected" delineation
  - [ ] Prioritized open-question list at the end
  - [ ] Paper-shaped narrative skeleton (not the paper itself)
  - [ ] External-literature contextualization: how this work relates
    to published state-of-art
  - [ ] .planning/sessions/G-synthesis-decisions.md logs calls

## Reminders

  - NO simulation work. Pure synthesis.
  - git pull CONSTANTLY — other sessions produce new results.
  - If you see a claim that would benefit from a new sim run, DON'T
    run it — drop a seed/todo for another session.
  - Commit to sessions/G-synthesis. NEVER push to main.
```

---

## Session H — Cost Function Architecture Audit

```
# Session H — Cost Function Head-to-Head (AUTONOMOUS) 

DO NOT INVOKE USER FOR ANYTHING UNLESS ABSOLUTLEY NECCESSARY
There are several other claude code sessions running so be aware of them and try not to have merge issues or other issues.
Also there is a phase 14 which may or may not be important to your task. If it is and you need please just wait for it to finish and monitor its progress. You can also monitor other agents status and see if anything you need depends on them and await and monitor their porgress.

You are a computational physicist doing a rigorous methods-comparison
study. You have FULL AUTONOMY over experimental design and metrics.
Research widely — the ML/optimization literature has extensive work on
loss-landscape geometry that applies directly to this physics problem.

First actions:
  1. Read CLAUDE.md. Owned namespace: scripts/cost_audit_*.jl,
     .planning/phases/<N>-cost-audit-*/, .planning/notes/cost-audit-*.md,
     .planning/sessions/H-cost-*.md. Create new wrappers around existing
     optimizers — NEVER modify them.
  2. git fetch && git pull --ff-only origin main.
  3. Confirm worktree ~/raman-wt-H on branch sessions/H-cost.
  4. VERIFY Phase 14 (sharpness-aware cost) is complete. If not, STOP
     and wait. Session H depends on it.

## Context

Codebase has (or will have) multiple parallel cost function paths:
  - Original: linear E_band / E_total
  - Log-scale (Phase 8 fix, dB/linear reconciliation)
  - Phase 14 sharpness-aware (Hessian-in-cost):
    optimize_spectral_phase_sharp
  - Future: quantum-noise-aware (per quantum-noise-reframing seed)

Without a systematic comparison, the team's default drifts based on
whoever touched which path last. This session does the comparison.

## Research phase (broad)

Research freely:
  - Sharpness-aware minimization (SAM, ASAM, GSAM). WebSearch these
    acronyms — rich ML literature on why flat minima generalize better
    and how to find them. The physics analog: flat minima → experimentally
    robust (tolerates SLM drift, fiber manufacturing variance).
  - Loss-landscape visualization methods (Li et al. 2018, "Visualizing
    the Loss Landscape of Neural Nets").
  - Robustness metrics in optimization: stability under perturbation,
    condition number of the Hessian, eigenspectrum of the local
    quadratic approximation.
  - Cost-function comparison methodology — how to do a fair head-to-head
    between different optimization objectives. Benchmark design.
  - Log-scale cost functions in physics: when does log(J) vs linear J
    help convergence? (Relevant to the Phase 8 log-scale fix.)
  - Internal: Phase 8 SUMMARY, Phase 14 SUMMARY, scripts that implement
    each variant.

## Decision phase (`/gsd-discuss-phase --auto`)

Log in .planning/sessions/H-cost-decisions.md:
  - Fair-comparison protocol: same grid, same fiber, same starting
    phase, same iteration cap, same stopping criterion. Fix ALL of
    these; only the cost function varies.
  - Metrics: final J (in dB), wall time, Hessian eigenspectrum
    (flatness), stability under perturbation (reuse Session D's
    framework), convergence rate (iterations to reach 90% of final J).
  - Configs: 3 configurations across (fiber, L, P) space. Recommend:
    SMF-28 L=0.5m P=0.05W (simple regime), SMF-28 L=5m P=0.2W (hard
    regime), HNLF L=1m P=0.5W (high-nonlinearity regime).
  - Starting phase: fixed random seed, same across all runs per config.

## Planning (`/gsd-add-phase` then `/gsd-plan-phase`)

Phase: "Cost Function Head-to-Head Audit." Tasks:
  1. Driver script (scripts/cost_audit_driver.jl) — runs all variants
     with identical inputs per config
  2. Post-processing analysis script (scripts/cost_audit_analyze.jl)
  3. Matrix: 4 cost functions × 3 configs = 12 runs
  4. Table and figure outputs
  5. Decision doc .planning/notes/cost-function-default.md —
     recommended default + rationale

## Execution (`/gsd-execute-phase`)

Autonomous. All 12 runs on burst VM. Hold /tmp/burst-heavy-lock during
the batch.

## Success criteria

  - [ ] Comparison driver runs all variants on all configs
  - [ ] Tables + figures showing per-metric winner
  - [ ] .planning/notes/cost-function-default.md with clear
    recommendation + rationale
  - [ ] .planning/sessions/H-cost-decisions.md logs calls
  - [ ] External-literature context: how does this comparison relate
    to the ML loss-landscape literature?

## Why this session

Feeds Session B (README names the default cost and why) and every future
optimization session. Prevents cost-function drift.

## Reminders

  - MUST use burst VM. Check /tmp/burst-heavy-lock before starting.
  - Depends on Phase 14 complete.
  - julia -t auto.
  - Commit to sessions/H-cost. NEVER push to main.
```

---

## Launch order

Run all 8 — distribute per `CLAUDE.md` Rule P6:

- **On Mac**: B, D, E, G (4 sessions in separate Terminal tabs, each `cd`ing into its worktree, then `claude`)
- **On claude-code-host**: A, C, F, H (3–4 tmux sessions via SSH, each in its worktree; watch RAM with `free -h`)

If claude-code-host gets tight on RAM, move one of {A, H} to Mac.

Session H specifically depends on Phase 14 being complete — its first action is to check and wait.

## User's role while sessions run

- **You don't answer questions** — prompts are designed for autonomous operation. Agents will decide and document.
- **You integrate every 2–3 hours** (per CLAUDE.md Rule P7): merge session branches to main, resolve conflicts if any, push.
- **You read the `.planning/sessions/<name>-decisions.md` files** to see what choices agents made. If you disagree with one, correct it — they'll pick up the correction on next pull.
- **You are the escalation target** for: destructive ops, out-of-namespace shared-code changes, git-divergence failures, and "this research finding changes the whole project's direction" moments.

## Integration ritual

```bash
cd ~/fiber-raman-suppression   # primary main checkout
git fetch origin
for b in A-multivar B-handoff C-multimode D-simple E-sweep F-longfiber G-synthesis H-cost; do
  count=$(git log main..origin/sessions/$b --oneline 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "sessions/$b: $count commits"
done

# Review the decisions each session made:
ls .planning/sessions/  # peek at the -decisions.md files

# Merge clean branches:
git merge origin/sessions/B-handoff --no-ff
# ... resolve conflicts if any, repeat
git push origin main
```
