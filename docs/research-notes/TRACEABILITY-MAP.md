# Research Note Traceability Map

Evidence snapshot: 2026-04-28

This map links each polished or near-polished note to the local evidence that
supports its claims. It is not a replacement for citations or result manifests.
It is a reviewer aid: if a future agent edits a claim, this file shows which
code and artifacts must be checked first.

## Traceability Rules

- Public notes should cite external research sources for physics and numerical
  methods.
- Internal provenance should point to scripts, result summaries, standard-image
  bundles, and verification docs.
- If a note cannot identify its source artifacts, do not promote it to
  production-ready.
- Figure filenames in public notes should be public-facing even if they were
  copied from older internal result folders.

## `01-baseline-raman-suppression`

Primary purpose: explain the canonical single-mode Raman-suppression objective,
phase-only shaping, adjoint/L-BFGS workflow, and standard-image vocabulary.

Implementation paths:

- `scripts/lib/raman_optimization.jl`
- `scripts/lib/standard_images.jl`
- `scripts/lib/visualization.jl`
- `scripts/lib/common.jl`
- canonical optimization driver referenced in the note's reproduction capsule

Local figure bundle:

- `baseline_before_after_summary.png`
- `baseline_cost_anatomy.png`
- `baseline_trust_snapshot.png`
- `baseline_workflow_clean.png`
- `canonical_smf28_phase_diagnostic.png`
- `canonical_smf28_evolution.png`
- `canonical_smf28_evolution_unshaped.png`
- `no_optimization_phase_diagnostic.png`
- `reference_hnlf_phase_diagnostic.png`
- `reference_hnlf_evolution.png`

Reviewer checks:

- Verify the exact canonical command and result directory before final
  publication use.
- Confirm the cost formula in the note matches the active implementation and
  the current equation-verification document.

## `02-reduced-basis-continuation`

Primary purpose: explain reduced coordinates, continuation, and why a
low-dimensional basis can find basins that are difficult for full-grid
optimization.

Implementation paths:

- reduced-basis and continuation drivers referenced in the note
- basis construction helpers used by the current reduced-basis workflow
- `scripts/lib/standard_images.jl`
- current equation-verification document for `phi = Bc` and
  `grad_c = B^T grad_phi`

Local figure bundle:

- `basis_linear_algebra_diagram.png`
- `basis_family_depth_summary.png`
- `cubic32_reduced_phase_diagnostic.png`
- `cubic32_reduced_evolution.png`
- `cubic128_reduced_phase_diagnostic.png`
- `cubic128_reduced_evolution.png`
- `cubic32_fullgrid_phase_diagnostic.png`
- `cubic32_fullgrid_evolution.png`
- `zero_fullgrid_phase_diagnostic.png`
- `zero_fullgrid_evolution.png`
- `transferable_polynomial_phase_diagnostic.png`
- `transferable_polynomial_evolution.png`
- `no_optimization_phase_diagnostic.png`
- `no_optimization_evolution_unshaped.png`

Reviewer checks:

- Verify every reported depth against a saved artifact or sidecar summary.
- Confirm basis columns, centering, and coefficient gradients match the active
  code path before changing the math section.

## `03-sharpness-robustness`

Primary purpose: explain why robustness/sharpness is a tradeoff axis, not a
replacement objective that automatically wins.

Implementation paths:

- `scripts/research/sharpness/run.jl`
- `scripts/research/sharpness/summarize.jl`
- Hessian-vector or trace-estimation helpers used by the sharpness run
- `scripts/lib/standard_images.jl`

Local figure bundle:

- `sharpness_workflow_diagram.png`
- `robustness_depth_tradeoff.png`
- `robustness_gain_cost_summary.png`
- `hessian_indefinite_summary.png`
- `canonical_plain_phase_diagnostic.png`
- `canonical_plain_evolution.png`
- `canonical_trace_phase_diagnostic.png`
- `canonical_trace_evolution.png`
- `canonical_mc_phase_diagnostic.png`
- `canonical_mc_evolution.png`
- `canonical_unshaped_evolution.png`
- `no_optimization_phase_diagnostic.png`

Reviewer checks:

- Confirm whether trace/Monte-Carlo sharpness results use the same scalar
  objective as the plotted Raman depth.
- Check Hessian/trace diagnostics for sample count, random seed, and
  finite-difference step before changing quantitative claims.

## `04-trust-region-newton`

Primary purpose: explain the trust-region/Newton attempts, saddle-dominated
geometry, radius collapse, and why this is not yet the default optimizer.

Implementation paths:

- `scripts/research/trust_region/`
- trust-region experiment summaries referenced in the note
- Hessian or HVP helpers used by the trust-region lane

Local figure bundle:

- `trust_region_workflow_diagram.png`
- `hessian_saddle_spectrum_clean.png`
- `continuation_ladder_summary.png`
- `delta0_radius_collapse_summary.png`
- `power_validation_regime_summary.png`
- `control_no_optimization_phase_diagnostic.png`
- `control_no_optimization_evolution.png`
- `continuation_seed_phase_diagnostic.png`
- `continuation_seed_evolution.png`
- `cold_radius_collapse_phase_diagnostic.png`
- `cold_radius_collapse_evolution.png`
- `ladder_dispersion_phase_diagnostic.png`
- `ladder_dispersion_evolution.png`
- `ladder_no_preconditioner_phase_diagnostic.png`
- `ladder_no_preconditioner_evolution.png`

Reviewer checks:

- Verify predicted-vs-actual reduction formula and sign conventions against
  the current equation-verification document.
- Confirm the note distinguishes finite-difference HVPs from analytic
  second-adjoint HVPs.

## `05-cost-numerics-trust`

Primary purpose: define cost conventions, numerical trust gates, gauge
projection, dB/log scaling, and standard diagnostic requirements.

Implementation paths:

- `scripts/lib/objective_surface.jl`
- `scripts/lib/raman_optimization.jl`
- `scripts/lib/standard_images.jl`
- `scripts/research/analysis/numerical_trust.jl`
- `scripts/research/cost_audit/cost_audit_driver.jl`
- `docs/reference/current-equation-verification.tex`

Local figure bundle:

- `objective_surface_pipeline.png`
- `gauge_projection_clean.png`
- `trust_gate_checklist.png`
- `cost_audit_depth_summary.png`
- `cost_audit_iteration_tradeoff.png`
- `control_no_optimization_phase_diagnostic.png`
- `control_no_optimization_evolution.png`
- `canonical_result_phase_diagnostic.png`
- `canonical_result_evolution.png`

Reviewer checks:

- Confirm the note states whether regularizers are inside or outside the dB
  transform for each discussed objective.
- Re-run or refresh the equation-verification document before using this as a
  publication-grade methods reference.

## `06-long-fiber`

Primary purpose: summarize the 100--200 m single-mode long-fiber milestones,
including why the evidence is strong but not a converged-optimum claim.

Implementation paths:

- `scripts/research/longfiber/longfiber_setup.jl`
- `scripts/research/longfiber/longfiber_optimize_100m.jl`
- `scripts/research/longfiber/longfiber_optimize_200m.jl`
- `scripts/research/longfiber/longfiber_checkpoint.jl`
- `scripts/research/longfiber/longfiber_regenerate_standard_images.jl`
- `scripts/lib/standard_images.jl`

Local figure bundle:

- `longfiber_workflow.png`
- `longfiber_grid_ladder.png`
- `longfiber_result_summary.png`
- `longfiber_100m_phase_diagnostic.png`
- `longfiber_100m_evolution.png`
- `longfiber_100m_evolution_unshaped.png`
- `longfiber_100m_phase_profile.png`
- `longfiber_200m_phase_diagnostic.png`
- `longfiber_200m_evolution.png`
- `longfiber_200m_evolution_unshaped.png`
- `longfiber_200m_phase_profile.png`

Reviewer checks:

- Keep the convergence caveat attached to every 100--200 m headline value.
- Check that any future rerun still produces the complete standard image set:
  phase profile, phase diagnostic, optimized evolution, and unshaped evolution.
- The lightweight checkpoint self-test passed on 2026-04-28 after fixing a
  soft-scope issue in the test harness.

## `07-simple-profiles-transferability`

Primary purpose: separate deep native suppression from simplicity,
robustness, and transferability.

Implementation paths:

- simple-profile driver and metric scripts referenced in the note
- stability probe driver referenced in the note
- standard-image builder used for candidate figure bundles

Local figure bundle:

- `simple_transferability_workflow.png`
- `native_depth_comparison.png`
- `depth_transfer_tradeoff.png`
- `hardware_robustness_loss_matrix.png`
- `no_optimization_phase_diagnostic.png`
- `no_optimization_evolution.png`
- `transferable_polynomial_phase_diagnostic.png`
- `transferable_polynomial_evolution.png`
- `deep_simple_profile_phase_diagnostic.png`
- `deep_simple_profile_evolution.png`
- `deep_structured_profile_phase_diagnostic.png`
- `deep_structured_profile_evolution.png`

Reviewer checks:

- Verify transfer gaps and robustness-loss numbers against the stability table
  before changing the headline interpretation.
- Keep the conclusion split into mechanism, performance, and cautionary
  hardware-readiness story; do not collapse it into one "best mask" claim.

## `08-multimode-baselines`

Primary purpose: document the qualified idealized GRIN-50 MMF result and the
diagnostic correction that rejected the first unregularized candidate.

Implementation paths:

- `scripts/research/mmf/`
- `scripts/canonical/run_experiment.jl`
- `configs/experiments/grin50_mmf_phase_sum_poc.toml`
- `scripts/lib/standard_images.jl`
- MMF validation summaries in the local result tree

Local figure bundle:

- `mmf_claim_boundary.png`
- `mmf_validation_ladder.png`
- `mmf_edge_trust.png`
- `mmf_control_evolution.png`
- `mmf_rejected_unregularized_phase_diagnostic.png`
- `mmf_rejected_unregularized_evolution.png`
- `mmf_boundary_phase_diagnostic.png`
- `mmf_boundary_evolution.png`
- `mmf_accepted_phase_diagnostic.png`
- `mmf_accepted_evolution.png`
- `mmf_accepted_evolution_unshaped.png`
- `mmf_accepted_phase_profile.png`
- `mmf_accepted_total_spectrum.png`
- `mmf_accepted_per_mode_spectrum.png`
- `mmf_accepted_convergence.png`

Reviewer checks:

- Keep the claim limited to an idealized six-mode GRIN-50 shared-phase
  simulation unless grid refinement, launch sensitivity, and random coupling
  gates are later closed.
- Do not use the rejected unregularized result as a positive claim; it is only
  evidence that the edge diagnostic mattered.
- The canonical front-layer dry-run passed on 2026-04-28, but accepted MMF
  evidence still comes from the dedicated validation artifacts.

## `09-multi-parameter-optimization`

Primary purpose: explain why broad joint phase/amplitude/energy optimization
was not the useful path, and why staged amplitude refinement after a strong
phase-only solution is the supported positive result.

Implementation paths:

- `scripts/research/multivar/multivar_optimization.jl`
- `scripts/canonical/refine_amp_on_phase.jl`
- `scripts/dev/smoke/test_multivar_unit.jl`
- `scripts/dev/smoke/test_multivar_gradients.jl`
- `scripts/lib/multivar_artifacts.jl`
- `scripts/lib/standard_images.jl`

Local figure bundle:

- `multivar_control_workflow.png`
- `multivar_strategy_ladder.png`
- `multivar_control_phase_diagnostic.png`
- `multivar_control_evolution.png`
- `multivar_phase_only_phase_diagnostic.png`
- `multivar_phase_only_evolution.png`
- `multivar_amp_refined_phase_diagnostic.png`
- `multivar_amp_refined_evolution.png`
- `multivar_energy_refined_phase_diagnostic.png`
- `multivar_energy_refined_evolution.png`
- `multivar_ablation_summary.png`
- `multivar_convergence_and_spectra.png`
- `multivar_bound_sweep.png`
- `multivar_local_robustness.png`

Reviewer checks:

- Keep the positive claim staged: phase-only first, then amplitude refinement.
- Keep broad joint optimization framed as a negative/cautionary result.
- The multivariable unit and gradient smoke checks passed on 2026-04-28.

## `10-recovery-validation`

Primary purpose: explain honest-grid recovery, retired claims, and
saddle/negative-curvature follow-up.

Implementation paths:

- `scripts/research/recovery/`
- recovery and saddle diagnostics referenced in the note
- long-fiber validation artifact if the validated long-fiber example remains
  in this note

Local figure bundle:

- `recovery_validation_workflow.png`
- `recovery_anchor_summary_clean.png`
- `retired_sweep_recovery_summary.png`
- `saddle_escape_summary_clean.png`
- `saddle_ladder_summary_clean.png`
- `hessian_saddle_spectrum_clean.png`
- `control_smf28_no_shaping_phase_diagnostic.png`
- `control_smf28_no_shaping_evolution.png`
- `recovered_smf28_phase_diagnostic.png`
- `recovered_smf28_evolution.png`
- `recovered_hnlf_phase_diagnostic.png`
- `recovered_hnlf_evolution.png`
- `retired_sweep_fullgrid_phase_diagnostic.png`
- `retired_sweep_fullgrid_evolution.png`
- `validated_longfiber_phase_diagnostic.png`
- `validated_longfiber_evolution.png`

Reviewer checks:

- Verify which recovered cases are exact reruns, which are honest-grid
  validations, and which are retired claims.
- Keep negative-curvature and saddle-escape interpretation tied to actual HVP
  or spectrum evidence.

## `11-performance-appendix`

Primary purpose: explain cost model, adjoint value, threading, determinism, and
compute discipline.

Implementation paths:

- `scripts/research/benchmarks/benchmark_threading.jl`
- `scripts/workflows/run_benchmarks.jl`
- benchmark workflow paths referenced in the note
- burst-machine workflow in `AGENTS.md` and `CLAUDE.md`

Local figure bundle:

- `performance_cost_model.png`
- `kernel_timing_summary.png`
- `single_solve_thread_speedup.png`
- `determinism_speed_tradeoff.png`

Reviewer checks:

- Verify benchmark hardware, thread count, and command before quoting speedups.
- This note does not need phase/heat-map pages unless it starts making optical
  result claims.

## `12-long-fiber-reoptimization`

Primary purpose: document the warm-start strategy where a short-fiber phase is
transferred and then re-optimized for a long-fiber target.

Implementation paths:

- `scripts/research/longfiber/longfiber_setup.jl`
- `scripts/research/longfiber/longfiber_optimize_100m.jl`
- `scripts/research/longfiber/longfiber_validate_100m.jl`
- `scripts/research/longfiber/longfiber_regenerate_standard_images.jl`
- `results/raman/.../FINDINGS.md` or the current public replacement summary

Local figure bundle:

- `warm_start_reoptimization_workflow.png`
- `longfiber100m_unshaped_evolution.png`
- `longfiber100m_reoptimized_phase_diagnostic.png`
- `longfiber100m_reoptimized_evolution.png`
- `longfiber100m_reoptimized_phase_profile.png`

Reviewer checks:

- Keep this note framed as computational warm-start re-optimization unless a
  physical segmented-shaper experiment is actually performed.
- Keep the 100 m convergence caveat visible until a converged rerun or
  deliberate benchmark status exists.
