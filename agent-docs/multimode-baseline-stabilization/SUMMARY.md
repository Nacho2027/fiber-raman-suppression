## Summary

- Added MMF-only trust infrastructure:
  - `scripts/research/mmf/mmf_setup.jl`
    - conservative MMF time-window recommendation
    - automatic time-window/Nt upsizing when the requested window is too small
  - `src/mmf_cost.jl`
    - `mmf_mode_band_fractions`
    - `mmf_cost_report`
  - `scripts/research/mmf/mmf_raman_optimization.jl`
    - `mmf_forward_output`
    - `mmf_trust_metrics`
    - baseline runner now returns reference/optimized trust summaries
- Added a dedicated heavy-run driver:
  - `scripts/research/mmf/baseline.jl`
    - regime sweep under `:sum`
    - cost-variant comparison on the strongest candidate regime
    - writes `results/raman/phase36/`
- Tests:
  - `julia -t 4 --project=. test/phases/test_phase16_mmf.jl`
  - passed after replacing the first noisy β₂ inference with a centered second-derivative estimate at zero frequency
- Repo-state follow-up on 2026-04-23:
  - no synced `results/raman/phase36/` directory exists in this workspace
  - no `C-phase36` burst log is present under `results/burst-logs/`
  - the aggressive baseline is therefore still scientifically incomplete in
    the repo snapshot, even though the code path is ready
- Closure recommendation:
  - highest-value next step is still the aggressive rerun at `GRIN_50`,
    `L=2.0 m`, `P=0.5 W`, `:sum` cost
  - the mild `L=1.0 m`, `P=0.05 W` regime should be treated as explicitly
    closed out as a negative / non-meaningful MMF baseline
  - do not reopen joint `{φ, c_m}` or fiber-type comparison until phase36
    exists with trust metrics and inspected standard images

## Campaign 20260424T033354Z Supervision

- Target lane: `mmf`, permanent `fiber-raman-burst`, tag `M-mmfdeep`.
- Initial command: `julia -t auto --project=. scripts/research/mmf/baseline.jl`.
- Launcher log: `results/burst-logs/parallel/20260424T033354Z/mmf.log`.
- First launch at `2026-04-24T03:33:54Z` failed before simulation because burst
  SSH was not ready yet (`connect ... port 22: Connection refused`).
- Relaunch at `2026-04-24T03:35:41Z` reached the burst wrapper but failed during
  Julia startup: clean worktree lacked instantiated dependencies and errored on
  `using JLD2`.
- Follow-up at `2026-04-24T03:40:49Z` repeated the same `JLD2` failure because
  the clean worktree was recreated from `origin/main`.
- Root cause: the clean-worktree launcher patch that runs `Pkg.instantiate()`
  before the lane command was present locally but not yet committed/pushed to
  `origin/main`.
- Required fix before next relaunch: commit and push
  `scripts/ops/parallel_research_lane.sh`, then relaunch the same MMF baseline
  so burst pulls the corrected bootstrap.
- Fix committed and pushed as `b449ae2` (`fix(ops): instantiate clean research
  worktrees`).
- Relaunch at `2026-04-24T03:43:12Z` succeeded past package loading and entered
  the actual Phase 36 driver.
- Active remote wrapper log:
  `results/burst-logs/M-mmfdeep_20260424T034316Z.log`.
- Current stage as of the latest poll: mild `GRIN_50`, `L=1.0 m`, `P=0.05 W`,
  `:sum` objective. Reference `J = 2.8345e-06` (`-55.48 dB`); objective
  evaluations recovered to about `-55.51 dB`, which is consistent with the
  existing expectation that mild is a no-headroom regime. Wait for the accepted
  optimization/trust summary before treating this as final.
- Permanent burst heavy lock is held by `M-mmfdeep`; do not start another heavy
  MMF job on `fiber-raman-burst` until this run completes or is explicitly
  stopped.
- Next poll command:
  `burst-ssh 'tail -n 420 /home/ignaciojlizama/fiber-raman-suppression/results/burst-logs/M-mmfdeep_20260424T034316Z.log; find /home/ignaciojlizama/fiber-raman-suppression/results/raman/phase36 -maxdepth 2 -type f | head -80'`

## 2026-04-27 MMF Window/Trust Revisit

### Code Findings

- Fixed a real MMF trust diagnostic bug in
  `scripts/research/mmf/mmf_raman_optimization.jl`:
  - old path used `ifft(uωf, 1)` for output-time diagnostics
  - repo convention is `uω = ifft(ut)` and `ut = fft(uω, 1)`
  - old path also used legacy `check_boundary_conditions`, which divides by the
    attenuator and can amplify edge roundoff
- New MMF trust behavior:
  - `mmf_output_time_field(uωf) = fft(uωf, 1)`
  - uses `check_raw_temporal_edges`
  - checks both shaped input and propagated output
  - reports input and output edge fractions separately
- Added a focused transform-convention regression to
  `test/phases/test_phase16_mmf.jl`.
- Exposed `λ_gdd` and `λ_boundary` through `run_mmf_baseline` and
  `mmf_window_validation.jl`; validation output can now be redirected with
  `MMF_VALIDATION_SAVE_DIR`.
- Online research notes were added in
  `agent-docs/multimode-baseline-stabilization/ONLINE-RESEARCH.md`.

### Experiments

| ID | Run | Settings | Result | Trust/Diagnostics | Decision |
|---|---|---|---|---|---|
| E1 | local focused regression | no propagation; synthetic centered `ut`, `uω=ifft(ut)` | passed | `fft(uω)` recovers centered pulse; raw edge `2.25e-35`; `ifft(uω)` is not the time field | diagnostic fix covered |
| E2 | burst `M-mmffix` | `GRIN_50`, `L=2 m`, `P=0.20 W`, `Nt=4096`, `TW=96 ps`, `max_iter=4`, `λ_boundary=0` | `J_sum -17.96 -> -45.07 dB`, `Δ=27.12 dB` | `max_edge=5.02e-02`, input `4.92e-02`, output `5.02e-02`, `boundary_ok=false`; phase diagnostics show extreme noisy group delay/GDD | not accepted; real temporal-edge artifact remains |
| E3 | burst `M-mmfbnd` constrained attempt on permanent VM | same threshold case, `λ_boundary=0.05`, `SAVE_DIR=results/raman/phase36_window_validation_boundary` | did not start Julia output | permanent burst VM entered `STOPPING` immediately after wrapper acquired lock on two launch attempts | superseded by ephemeral rerun |
| E4 | ephemeral `M-mmfbnd` boundary-constrained rerun | same threshold case, `λ_boundary=0.05`, `λ_gdd=0`, `SAVE_DIR=results/raman/phase36_window_validation_boundary` | `J_sum -17.96 -> -45.04 dB`, `Δ=27.09 dB` | `max_edge=2.74e-07`, input `2.74e-07`, output `2.64e-07`, `boundary_ok=true`; per-mode plot shows suppression across launched modes | window artifact no longer explains the gain, but phase still visually aggressive |
| E5 | ephemeral `M-mmfgdd` boundary+GDD constrained rerun | same threshold case, `λ_boundary=0.05`, `λ_gdd=1e-4`, `SAVE_DIR=results/raman/phase36_window_validation_gdd` | raw Raman `J_sum -17.96 -> -49.69 dB`, `Δ=31.73 dB`; penalized objective ended at `-29.53 dB` | `max_edge=2.07e-11`, input `2.07e-11`, output `1.98e-11`, `boundary_ok=true`; `J_fund=-49.65 dB`, `J_worst=-45.35 dB` | accepted as current MMF candidate; needs robustness, not window rescue |
| E6 | ephemeral `M-mmfg8192` grid-refinement attempt | same as E5 but `Nt=8192`, `TW=96 ps`, `SAVE_DIR=results/raman/phase36_window_validation_gdd_nt8192` | inconclusive; best observed penalized objective plateaued near `-30.38 dB` after ~5.5 h | no final summary/standard images; manual termination caused result archive not to sync | not accepted evidence; rerun with explicit evaluation/time limits |

### Visual Inspection

Inspected regenerated standard image set and MMF plots under
`results/raman/phase36_window_validation/`:

- `mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution.png`
- `mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution_unshaped.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_total_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_per_mode_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_phase.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_convergence.png`

The figures render, but the optimized phase is not physically credible for
acceptance: group delay reaches tens of ps with noisy GDD, the spectral output
mostly reproduces a shaped input spectrum, and raw edge diagnostics show about
5% energy in temporal edges.

Inspected boundary-constrained images under
`results/raman/phase36_window_validation_boundary/`:

- `mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution.png`
- `mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution_unshaped.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_total_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_per_mode_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_phase.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_convergence.png`

The plots render and the raw temporal-edge metric is clean. The per-mode
spectrum shows suppression in the launched modes, not only in the summed
objective. The remaining concern is phase realism: the group delay/GDD are much
less pathological than E2 but still visibly aggressive.

Inspected boundary+GDD-constrained images under
`results/raman/phase36_window_validation_gdd/`:

- `mmf_grin_50_l2m_p0p2w_seed42_phase_profile.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution.png`
- `mmf_grin_50_l2m_p0p2w_seed42_phase_diagnostic.png`
- `mmf_grin_50_l2m_p0p2w_seed42_evolution_unshaped.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_total_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_per_mode_spectrum.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_phase.png`
- `mmf_baseline_window_valid_threshold_l2m_p0.2w_nt4096_tw96_convergence.png`

The standard image set is present and renders. The optimized temporal pulse is
contained well inside the 96 ps window, and raw edge fractions are near
machine-clean levels. The phase is no longer the original tens-of-ps
window-filling object; the diagnostic shows roughly sub-ps to 1.2 ps group-delay
structure with oscillatory GDD. This is still an engineered phase candidate, so
do not overclaim experimental generality until seed/window/regularization and
launch-coefficient sensitivity are checked.

### Current Decision

MMF status: **accepted as a current physical candidate, not an invalid-window
result**.

The unregularized E2 optimum is still rejected, but the same threshold regime
survived both the raw-edge boundary penalty and a GDD penalty. E5 is the best
current candidate: `GRIN_50`, `L=2 m`, `P=0.20 W`, `Nt=4096`, `TW=96 ps`,
`λ_boundary=0.05`, `λ_gdd=1e-4`, with `J_sum -17.96 -> -49.69 dB`,
`Δ=31.73 dB`, `boundary_ok=true`, and standard images visually inspected.

Remaining scientific todos before treating this as robust or publication-grade:

- Do not rely on `seed` repeats in `mmf_window_validation.jl` until the driver
  supports a nonzero/random `φ0`; the current validation path warm-starts from
  zeros.
- Rerun the `Nt=8192`, `TW=96 ps` refinement with explicit function-evaluation
  or wall-time limits so it exits cleanly and writes standard images.
  `mmf_window_validation.jl` now exposes
  `MMF_VALIDATION_F_CALLS_LIMIT` and `MMF_VALIDATION_TIME_LIMIT_SECONDS`, and
  `optimize_mmf_phase` enforces the evaluation limit before each expensive MMF
  propagation call.
- Run a small time-window/Nt ladder around the E5 settings, for example
  `TW=72/96/128 ps` with bounded optimizer settings as quota allows.
- Reopen the mode-coefficient follow-up now that window trust passes: test
  launch coefficient sensitivity and verify that suppression is not an artifact
  of the default LP01-heavy launch.
- Add a first-class validation/report script for `:fundamental` and
  `:worst_mode` objective variants, although E5's diagnostic report already
  shows strong `J_fund` and `J_worst` at the `:sum` optimum.
