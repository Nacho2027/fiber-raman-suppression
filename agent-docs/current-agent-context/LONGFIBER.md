# Long-Fiber Status

This note records the current maintainer-style assessment of the repo's long-fiber capability.

## Bottom line

- The repo has a real long-fiber single-mode path, not just historical notes.
- It is reasonably credible for SMF-style exploratory work around 50–100 m.
- It is not yet robust enough to present as a clean, group-ready long-fiber platform.
- Multimode long-fiber support remains weak and should be treated as experimental.

## What is genuinely in place

- `scripts/research/longfiber/longfiber_setup.jl`
  - explicitly bypasses the old auto-sizing behavior
  - honors the requested `(Nt, time_window)` pair
  - includes interpolation support for warm-start transfer across grids
- `scripts/research/longfiber/longfiber_optimize_100m.jl`
  - dedicated 100 m L-BFGS driver
  - checkpoint/resume support
  - standard-image generation
- `scripts/research/longfiber/longfiber_checkpoint.jl`
  - resume/config-hash guard
  - self-contained unit test when run as a script
- `scripts/research/longfiber/longfiber_validate_100m.jl`
  - post-run validation and reporting path
- `scripts/research/propagation/matched_quadratic_100m.jl`
  - useful reality check showing the 100 m warm-start result is mostly interpretable as pre-chirp rather than a mysterious high-complexity optimum

## What is currently trustworthy

Treat the following as the supported long-fiber research envelope:

- single-mode or effectively single-mode runs
- SMF-style 50 m and 100 m exploratory studies
- continuation / warm-start transfer studies built on the long-fiber setup path

The key existing headline result is the 100 m Phase 16 run:

- `results/raman/phase16/FINDINGS.md`
  - `J_opt@100m = -54.77 dB`
  - `J_warm@2m(L=100 m) = -51.50 dB`
  - `converged = false`
- 2026-04-26 rerun `L-100m1`
  - `J_opt@100m = -55.92 dB`
  - `LF100_MAX_ITER = 25`
  - `converged = false`
  - final gradient norm `7.22e-01`
  - standard images generated under
    `results/raman/phase16/standard_images_F_100m_opt/`

That combination is important: the result is scientifically useful, but it should not be oversold as a tightly converged production benchmark.

Visual inspection note for the 2026-04-26 rerun: the spectral suppression is
real and the standard images are complete, but the optimized phase/group-delay
diagnostic is very rough and the temporal output is split into strong subpulses.
Treat this as a high-value exploratory physics result, not a lab-ready phase
profile.

## What is not yet trustworthy

Do not describe the repo as having mature long-fiber support for:

- generic long-fiber work beyond the specific 50–100 m single-mode path
- multimode long-fiber optimization
- turnkey lab-group usage by new contributors without context
- 200 m scale claims as if they are already validated

`scripts/research/longfiber/longfiber_setup.jl` includes a grid table out to 200 m, but that is not the same thing as a validated 200 m workflow.

## Maintainer verdict

Use these ratings as rough guidance for future agents:

- single-mode long-fiber research capability: `7/10`
- reproducible group-facing long-fiber workflow: `4/10`
- multimode long-fiber capability: `3/10`

In plain terms: promising and usable for ongoing research, but not yet cleaned up enough to be treated as settled infrastructure.

## Practical rule for future agents

When discussing long-fiber capability, use one of these buckets explicitly:

- supported single-mode path
- experimental extension
- open validation gap

For now:

- 50–100 m SMF-style runs: supported single-mode path
- >100 m single-mode extrapolation: open validation gap
- multimode long-fiber optimization: experimental extension

## What would move this from research-grade to group-grade

The next maintainability step would be:

1. one stable long-fiber API and documented entry point
2. one trusted regression suite for 50 m / 100 m
3. one explicit supported-range statement in human docs
4. one clear boundary that multimode long-fiber remains experimental
