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
| E3 | burst `M-mmfbnd` constrained attempt | same threshold case, `λ_boundary=0.05`, `SAVE_DIR=results/raman/phase36_window_validation_boundary` | did not start Julia output | permanent burst VM entered `STOPPING` immediately after wrapper acquired lock on two launch attempts | infrastructure-blocked follow-up |

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

### Current Decision

Do not accept the MMF threshold result as physical Raman suppression. The prior
`edge_frac≈1` diagnosis was partly a diagnostic bug, but the corrected trust
metric still fails by about 50x against the `1e-3` edge threshold.

MMF status: **needs reformulated/constrained objective or larger/healthier
compute for constrained reruns**, not accepted physics.

Recommended next step when burst is stable:

```bash
MMF_VALIDATION_SAVE_DIR=results/raman/phase36_window_validation_boundary \
MMF_VALIDATION_CASES=threshold \
MMF_VALIDATION_MAX_ITER=4 \
MMF_VALIDATION_THRESHOLD_TW=96 \
MMF_VALIDATION_THRESHOLD_NT=4096 \
MMF_VALIDATION_LAMBDA_BOUNDARY=0.05 \
julia -t auto --project=. scripts/research/mmf/mmf_window_validation.jl
```

If that still fails, move to a reduced/smoothed phase basis or explicit
trust-constrained objective before mode-coefficient optimization.
