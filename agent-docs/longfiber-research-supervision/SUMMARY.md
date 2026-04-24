# Long-Fiber Research Supervision

Campaign: `20260424T033354Z`

## Scope

This note tracks the long-fiber lane only. The active scientific objective is
to harden the 100 m single-mode result first, then decide whether a controlled
continuation ladder toward 200 m is trustworthy.

## Startup Incidents

- `L-longfiber` failed at VM startup because multivar and long-fiber raced to
  refresh/create `fiber-raman-burst-template`.
- The helper-level image race cleared; no result from this attempt is
  scientifically accepted.
- `L-longfiber2` used the fixed result-archive helper but failed at Julia
  package load because the clean remote worktree environment was not
  instantiated. The archived run log shows missing `FFTW`.
- The ops launcher fix `b449ae2` adds `Pkg.instantiate()` before executing the
  lane command in the clean remote worktree.
- `L-longfiber3` failed before simulation because the initial instantiate fix
  used single quotes inside the single-quoted `burst-spawn-temp` command path.
  Commit `cc4089a` corrected the launcher bootstrap to use double quotes.
- Rapid `L-longfiber4` and `L-longfiber5` relaunch attempts hit GCE source
  machine-image operation-rate limits. Treat these as operational failures
  only; no long-fiber science was run.

## Active Run

- No accepted long-fiber run is active as of this note update.
- Back off materially before the next ephemeral launch to avoid GCE
  operation-rate failures; the short cooldown before `L-longfiber5` was not
  enough.
- Next command shape should be a single shell-wrapped command:
  `bash -lc 'julia --project=. -e "using Pkg; Pkg.instantiate()" && exec env LF100_MODE=fresh LF100_MAX_ITER=25 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl'`
- Use the fixed local `~/bin/burst-spawn-temp`, which archives modified
  results before VM destruction.

## Verification Requirements

- Confirm `results/raman/phase16/100m_opt_full_result.jld2` is updated by the
  accepted run.
- Confirm canonical standard images under
  `results/raman/phase16/standard_images_F_100m_opt/`.
- Confirm long-fiber human plots exist or regenerate them:
  `physics_16_03_optimization_trace_100m.png`,
  `physics_16_04_phi_profile_2m_vs_100m.png`,
  `physics_16_05_Jz_comparison.png`.
- Record `J_final`, iteration count, convergence flag, gradient residual,
  energy drift, boundary fraction, and whether this strengthens or merely
  reproduces the existing 100 m claim.

## Next Decision

If `L-longfiber3` reproduces or improves the 100 m result cleanly, run one
validation pass before any 200 m extension. If it fails for a code or workflow
reason, patch the smallest longfiber-owned or ops fix and relaunch only after
the fix is committed/pushed.
