# Artifact Provenance Ledger

Evidence snapshot: 2026-04-28

This ledger separates three levels of evidence:

- **PDF evidence:** the compiled note and copied local figure bundle exist.
- **Local result evidence:** a result directory, summary, standard-image bundle,
  or saved payload exists in `results/`.
- **Publication evidence:** the note has a clean table tying every quoted number
  to an exact artifact, command, code path, and verification status.

The current notes are presentation-ready, but not all are publication-frozen.

## Series-Level Inventory

| Note | PDF pages | Local figure files | PDF evidence | Publication provenance |
|---|---:|---:|---|---|
| `01-baseline-raman-suppression` | 13 | 11 | Present and visually audited | Needs exact canonical result table. |
| `02-reduced-basis-continuation` | 18 | 24 | Present and visually audited | Needs exact basis/result artifact table. |
| `03-sharpness-robustness` | 16 | 15 | Present and visually audited | Needs sharpness-objective source/result table. |
| `04-trust-region-newton` | 17 | 16 | Present and visually audited | Needs HVP/trust-run provenance table. |
| `05-cost-numerics-trust` | 12 | 10 | Present and visually audited | Audit matrix is intentionally incomplete. |
| `06-long-fiber` | 9 | 12 | Present and visually audited | Strong local artifact evidence; caveat remains non-convergence. |
| `07-simple-profiles-transferability` | 14 | 13 | Present and visually audited | Needs transfer/robustness artifact table. |
| `08-multimode-baselines` | 11 | 17 | Present and visually audited | Strong local artifact evidence for accepted GRIN-50 case; high-grid gate open. |
| `09-multi-parameter-optimization` | 14 | 20 | Present and visually audited | Strong local artifact evidence for staged amplitude result; lab handoff open. |
| `10-recovery-validation` | 17 | 17 | Present and visually audited | Needs exact saved-state table for each recovered/retired case. |
| `11-performance-appendix` | 9 | 5 | Present and visually audited | Needs benchmark environment table before quoting speedups externally. |
| `12-long-fiber-reoptimization` | 8 | 5 | Present and visually audited as provisional | Needs fresh rerun/provenance before promotion. |

## Strongest Pinned Result Lanes

### Long Fiber: `06-long-fiber`

Supported public claim: phase-only long-fiber optimization reached deep
image-backed 100--200 m single-mode suppression values, but these are achieved
milestones rather than converged global optima.

Local artifacts checked:

- `results/raman/phase16/100m_opt_full_result.jld2`
- `results/raman/phase16/200m_overngt_opt_resume_result.jld2`
- `results/raman/phase16/standard_images_F_100m_opt/`
- `results/raman/phase16/standard_images_F_200m_overngt_resume/`
- `docs/status/longfiber-200m-closure-2026-04-28.md`

Pinned metrics:

| Case | Length | Power | Grid | Result | Convergence status | Artifact status |
|---|---:|---:|---:|---:|---|---|
| 100 m optimized | 100 m | 0.20 W | `Nt=65536` | about `-55.9 dB` | not converged | Result payload and four standard images exist. |
| 200 m resumed | 200 m | 0.05 W | `Nt=65536` | `-55.16482931639846 dB` | `converged=false`, `g_residual=0.5648841056107406` | Result payload, checkpoint, status note, and four standard images exist. |

Publication caveat: keep the non-convergence sentence beside every headline
long-fiber value.

### Multimode: `08-multimode-baselines`

Supported public claim: a shared spectral phase suppresses Raman-band output in
one idealized six-mode GRIN-50 simulation under strict temporal-edge
diagnostics.

Local artifacts checked:

- `results/raman/phase36_window_validation/mmf_window_validation_summary.md`
- `results/raman/phase36_window_validation_boundary/mmf_window_validation_summary.md`
- `results/raman/phase36_window_validation_gdd/mmf_window_validation_summary.md`
- `results/raman/phase36_window_validation_gdd/` standard plot files

Accepted pinned metrics from the boundary+GDD summary:

| Case | L | P | Nt | Time window | Regularization | Reference | Optimized | Gain | Edge status |
|---|---:|---:|---:|---:|---|---:|---:|---:|---|
| GRIN-50 threshold | 2.0 m | 0.20 W | 4096 | 96 ps | `lambda_boundary=0.05`, `lambda_gdd=1e-4` | `-17.96 dB` | `-49.69 dB` | `31.73 dB` | `boundary_ok=true`, max edge `2.07e-11` |

Publication caveat: this is not a generic experimental MMF claim. High-grid
refinement, launch sensitivity, and random/degenerated coupling remain open.

### Multi-Parameter Optimization: `09-multi-parameter-optimization`

Supported public claim: broad joint optimization was not the useful path; the
supported positive lane is staged amplitude refinement after a strong
phase-only solution.

Local artifacts checked:

- canonical amplitude-on-phase closure summary under `results/raman/multivar/`
- robust repeat summary under `results/raman/multivar/`
- variable-ablation summary under `results/raman/multivar/`
- `results/raman/multivar/...` standard phase diagnostic, evolution, and
  unshaped evolution images for the staged runs

Pinned metrics:

| Case | Operating point | Bound | Phase-only | Refined | Improvement | Iterations | Status |
|---|---|---:|---:|---:|---:|---:|---|
| canonical amplitude-on-phase | SMF-28, L=2.0 m, P=0.30 W | `delta=0.15` | `-40.79 dB` | `-45.94 dB` | `5.15 dB` | 8 | PASS |
| robust repeat | SMF-28, L=2.0 m, P=0.33 W | `delta=0.15` | `-43.56 dB` | `-54.24 dB` | `10.68 dB` | 50 | PASS, hit iteration cap |
| ablation | SMF-28, L=2.0 m, P=0.30 W | `delta=0.10` | `-40.79 dB` | `-46.91 dB` | `6.12 dB` | 50 | PASS, hit iteration cap |

Publication caveat: amplitude masks need calibration and lab interpretation;
iteration caps mean the best numbers are achieved values, not proven optima.

## Notes Requiring Provenance Tables Before Publication

| Note | Missing provenance work |
|---|---|
| `01` | Tie the canonical baseline number and figures to exact result directory, command, trust report, and code version. |
| `02` | Tie each reduced-basis table value to saved artifacts and the exact basis construction path. |
| `03` | Tie each sharpness/robustness curve to the objective variant, perturbation radius, estimator settings, and source script. |
| `04` | Tie each trust-region result to the exact HVP method, objective surface, trust-ratio convention, and run summary. |
| `05` | Keep incomplete audit cells explicit; add exact source paths for the completed cost-audit cases. |
| `07` | Tie transferability and robustness-loss values to the stability/universality source tables. |
| `10` | Tie recovered, validated, and retired cases to exact saved states and recovery commands. |
| `11` | Tie benchmark plots to hardware, thread counts, Julia/FFTW settings, and command output. |
| `12` | Re-run or re-confirm warm-start artifacts before promoting beyond provisional strategy. |

## Verification Commands Already Run In This Closure Pass

- `julia -t auto --project=. scripts/research/longfiber/longfiber_checkpoint.jl`
  passed after a test-harness soft-scope fix.
- `julia -t auto --project=. scripts/dev/smoke/test_multivar_unit.jl`
  passed in the multivariable note-polish pass.
- `julia -t auto --project=. scripts/dev/smoke/test_multivar_gradients.jl`
  passed in the multivariable note-polish pass.
- `julia -t auto --project=. scripts/canonical/run_experiment.jl --dry-run grin50_mmf_phase_sum_poc`
  passed as a front-layer planning check; it does not replace the dedicated
  MMF validation artifacts.

## Current Burst-Dependent Gap

An MMF high-resolution validation job is running through the burst wrapper and
should be treated separately from this local documentation closure. Do not
rewrite the MMF claim around that run until the pulled-back result artifacts
and standard images have been inspected.
