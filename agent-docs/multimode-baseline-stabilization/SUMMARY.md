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
