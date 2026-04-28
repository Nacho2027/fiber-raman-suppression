# Research Closure Report

Date: 2026-04-28

This report freezes the current science state so the project can shift from
exploration to codebase hardening, result presentation, and publication/lab
readiness. It does not propose new science directions.

## Executive Summary

The project now has three main scientific outcomes:

1. Single-mode spectral phase optimization is the stable core capability.
2. Staged multivariable control is useful when amplitude is optimized after a
   phase solution; naive direct joint multivariable optimization is not the
   right promoted path.
3. Long-fiber reoptimization reached a clean 200 m result, while MMF remains a
   qualified simulation candidate rather than a closed paper-grade claim.

The next phase should prioritize packaging:

- make the supported workflows obvious;
- keep exploratory results out of the supported surface;
- write durable summaries with exact result paths;
- reduce the number of half-complete docs and orphaned result folders;
- keep generated results out of git unless intentionally promoted as figures or
  fixtures.

## Lab Rollout Decision

The supported lab rollout should proceed around the single-mode phase-only
front layer. The other research lanes are closed enough to stop blocking
packaging, but they should not become the default workflow:

- Default lab workflow: `research_engine_export_smoke` for real smoke/handoff
  proof, `research_engine_poc` for the configurable single-mode baseline, and
  the approved canonical run/sweep configs for maintained examples.
- Optional experimental workflow: staged `amp_on_phase` refinement, exposed as
  an explicit refinement path rather than the default optimizer.
- Research-result examples: 200 m long-fiber and corrected 4096-grid MMF, both
  with caveats and exact artifact references.
- Deferred methods: direct joint multivariable optimization and
  Newton/preconditioning.

Minimum viable lab-ready state for this repo is therefore not "every research
lane is productionized." It is:

1. the supported single-mode workflow installs, plans, runs, inspects, exports,
   and passes the lab-ready gate;
2. standard images and trust/export artifacts are enforced for supported runs;
3. result and telemetry indexes make completed work discoverable;
4. experimental surfaces are visible but gated;
5. this closure report states what claims are safe and what claims are not.

## Verification Record

This closure report is backed by local artifact inspection and command-level
verification, not only by memory of previous sessions.

Artifact evidence checked:

| Lane | Evidence checked | Status |
|---|---|---|
| Long-fiber | `results/raman/phase16/200m_overngt_opt_resume_result.jld2` and the four files under `results/raman/phase16/standard_images_F_200m_overngt_resume/` | Completed milestone; not optimizer-converged |
| MMF | `results/raman/phase36_window_validation_gdd/mmf_window_validation_summary.md` plus total/per-mode/phase/convergence plots and the standard image set | Qualified 4096-grid simulation claim |
| Multivar | staged ablation summaries under `results/raman/multivar/variable_ablation_overnight_*_20260427/` and representative standard image sets | Direct joint closed as negative; staged refinement positive |
| Supported smoke | latest `results/raman/smoke/smf28_phase_export_smoke_*` bundles with trust report, standard images, and export handoff | Supported lab handoff path |

Validation commands for the lab surface:

```bash
julia -t auto --project=. scripts/canonical/lab_ready.jl --config research_engine_export_smoke
julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run research_engine_export_smoke
julia -t auto --project=. scripts/canonical/run_experiment.jl --artifact-plan research_engine_export_smoke
julia -t auto --project=. scripts/canonical/run_experiment.jl --validate-all
julia -t auto --project=. scripts/canonical/run_experiment_sweep.jl --validate-all
julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 10 results/raman/smoke
julia -t auto --project=. scripts/canonical/index_telemetry.jl --help
TEST_TIER=fast julia -t auto --project=. test/runtests.jl
make lab-ready
make golden-smoke
```

For handoff readiness, `make lab-ready` and `make golden-smoke` are the
decisive local gates. Slow/full tiers remain milestone gates and should run on
appropriate compute when making broader numerical or physics claims.

## Findings By Lane

| Lane | Current status | Main finding | Closure state |
|---|---|---|---|
| Single-mode phase | Supported core | Reliable Raman suppression workflow with standard images, trust reports, front-layer configs, and export smoke coverage | Ready to present as the production baseline |
| Multivariable | Scientifically interpreted; code surface organized | `amp_on_phase` consistently improves over phase-only in tested cases; direct `phase+amplitude+energy` is worse/pathological | Archive direct-joint as negative; keep staged `amp_on_phase` as experimental workflow |
| Long-fiber | Completed latest 200 m run | 200 m resume run reached `J_final = -55.1648 dB`, `converged=false`, `g_residual=0.5649`, `Nt=65536`, `time_window=320 ps` | Needs visual inspection and short result note; no more exploratory runs required before packaging |
| MMF | Qualified, incomplete at high grid | Corrected 4096-grid boundary+GDD candidate reports strong suppression and passes edge diagnostics; 8192-grid attempts hit memory/termination limits | Present only with caveats; paper-grade grid refinement remains incomplete |
| Newton/preconditioning | Research note / negative-to-deferred | Useful analysis, but not a production optimizer path today | Defer; do not promote into main workflow now |

## Multivariable Result

The multivariable result should be presented as a staged-policy finding, not as
a general claim that every extra variable helps.

Canonical ablation at SMF-28, `L=2.0 m`, `P=0.30 W`:

| Case | Result | Interpretation |
|---|---:|---|
| phase-only reference | `-40.79 dB` | baseline |
| amplitude on fixed phase | `-46.91 dB`, `-6.12 dB` vs phase | positive |
| energy on fixed phase | `-44.89 dB`, `-4.10 dB` vs phase | positive but less rich |
| amplitude+energy on fixed phase | `-43.99 dB`, `-3.19 dB` vs phase | positive but weaker than amplitude-only |
| warm direct `phase+amplitude+energy` | `-31.04 dB`, `+9.75 dB` vs phase | negative |
| amplitude+energy from unshaped input | `-1.54 dB` | reject |

Robustness at `delta_bound=0.15`:

| Point | Phase-only | Amp-on-phase | Gain vs phase |
|---|---:|---:|---:|
| `L=1.8 m`, `P=0.30 W` | `-39.67 dB` | `-48.96 dB` | `9.28 dB` |
| `L=2.2 m`, `P=0.30 W` | `-35.25 dB` | `-46.08 dB` | `10.84 dB` |
| `L=2.0 m`, `P=0.27 W` | `-42.74 dB` | `-51.15 dB` | `8.41 dB` |
| `L=2.0 m`, `P=0.33 W` | `-43.56 dB` | `-54.24 dB` | `10.68 dB` |

Codebase action:

- Keep `controls.policy = "amp_on_phase"` as the experimental multivar path.
- Keep `controls.policy = "direct"` available for research, but do not present
  it as the recommended workflow.
- Do not start Bayesian/CMA-ES/alternating campaigns until the codebase and
  findings are packaged.

## Long-Fiber Result

Latest accepted artifact:

- `results/raman/phase16/200m_overngt_opt_resume_result.jld2`
- `results/raman/phase16/standard_images_F_200m_overngt_resume/`
- Detailed status note:
  `docs/status/longfiber-200m-closure-2026-04-28.md`

Key metadata:

- `L_m = 200.0`
- `P_cont_W = 0.05`
- `Nt = 65536`
- `time_window_ps = 320.0`
- `J_final = -55.16482931639846 dB`
- `converged = false`
- `g_residual = 0.5648841056107406`
- `n_iter = 69` in the resume call
- `resume_iter = 381`
- `wall_s = 75997.0`

Interpretation:

The 200 m result is a real completed run with standard images and a final
payload. The standard image set was visually inspected and renders coherently.
It is not a mathematically converged optimizer solution, but it is good enough
to summarize as a long-fiber reoptimization milestone. Additional runs are not
the immediate priority.

## MMF Result

The strongest current accepted candidate is the corrected 4096-grid,
boundary+GDD regularized run:

- `results/raman/phase36_window_validation_gdd/mmf_window_validation_summary.md`
- `J_ref = -17.96 dB`
- `J_opt = -49.69 dB`
- `Delta = 31.73 dB`
- `lambda_boundary = 5.00e-02`
- `lambda_gdd = 1.00e-04`
- `boundary_ok = true`
- max edge fraction `2.07e-11`

Interpretation:

This is presentation-ready only as a qualified simulation finding. The
high-resolution 8192-grid reruns did not complete cleanly and did not produce
accepted standard images. MMF should therefore be documented with explicit
caveats: promising constrained candidate, not broad launch/coupling-robust MMF
physics.

## Codebase Packaging Priorities

1. Stabilize the public workflow around the front-layer CLI, supported configs,
   smoke runs, standard images, result inspection, and lab-readiness checks.
2. Move durable scientific summaries into `docs/reports/` or
   `docs/research-notes/`; keep agent operational notes in `agent-docs/`.
3. Do not commit routine result folders. Promote only selected figures,
   summaries, or fixtures.
4. Make the README point to a small number of entry points instead of the full
   research history.
5. Keep MMF and multivar marked experimental until their remaining acceptance
   gates are explicitly closed.

## Recommended Presentation Claims

Safe claims:

- Spectral phase optimization is the codebase's validated core workflow.
- Staged amplitude-on-phase refinement can outperform phase-only at nearby
  single-mode operating points.
- A 200 m long-fiber reoptimization produced a completed, image-backed result
  near `-55.16 dB`.
- A corrected, regularized six-mode GRIN-50 MMF simulation shows strong Raman
  suppression at the accepted 4096-grid setting.

Claims to avoid for now:

- Direct joint multivariable optimization is generally better.
- MMF suppression is grid-refined, launch-robust, or experimentally validated.
- The long-fiber 200 m solution is optimizer-converged.
- Newton/preconditioning is production-ready.

## Immediate Next Tasks

1. Update the top-level README so new users land on supported workflows and
   closure reports, not the whole exploratory history.
2. Run the lab-readiness/acceptance checks once after the documentation pass.
3. Decide which selected figures should be copied into `docs/reports/` for
   presentation use.
