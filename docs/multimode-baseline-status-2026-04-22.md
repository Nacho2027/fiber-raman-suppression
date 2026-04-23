# Multimode Baseline Status (2026-04-22)

## What changed

This pass did not refactor the shared single-mode optimizer. It added MMF-only
trust infrastructure:

- `scripts/mmf_setup.jl`
  - conservative MMF time-window recommendation
  - automatic MMF time-window / `Nt` upsizing for undersized runs
- `src/mmf_cost.jl`
  - `mmf_mode_band_fractions`
  - `mmf_cost_report`
- `scripts/mmf_raman_optimization.jl`
  - forward-only MMF trust metrics
  - per-run summaries of `sum`, `fundamental`, and `worst_mode`
  - boundary-edge diagnostic attached to each MMF baseline run
- `scripts/mmf_phase36_baseline.jl`
  - focused MMF regime / cost-comparison driver for burst

## Tests

Ran:

```bash
julia -t 4 --project=. test/test_phase16_mmf.jl
```

Passed all testsets after replacing the first noisy MMF β₂ estimator with a
centered second-derivative estimate at zero frequency.

## Physics status

### Non-meaningful regime

`GRIN_50`, `L = 1.0 m`, `P_cont = 0.05 W` is still the wrong baseline to build
future MMF work on.

Evidence:

- historical Session C result at `Nt = 8192`: `J(φ=0) ≈ -55.43 dB` with no
  meaningful optimization gain
- this pass's burst screening at `Nt = 4096` again started at
  `J(φ=0) ≈ -55.48 dB`
- the coarse-grid run showed transient optimizer excursions before drifting back
  near the original no-headroom value, which is exactly the pattern expected for
  an under-informative / numerically sensitive regime rather than a real MMF
  Raman-control baseline

Conclusion: this mild GRIN-50 point is not scientifically useful for reduced-basis
or joint-parameter work.

### Meaningful regime recommendation

The next MMF baseline should use:

- fiber: `GRIN_50`
- length: `2.0 m`
- power: `0.5 W`
- objective: `:sum`
- phase model: shared-across-modes spectral phase
- trust requirements:
  - MMF auto-window sizing enabled
  - standard image set saved
  - report `sum`, `fundamental`, and per-mode fractions together
  - reject runs with boundary-edge fraction above `1e-3`

Rationale:

- Session C already established that the mild point is sub-soliton and uninformative.
- Session C’s aggressive follow-up was chosen precisely because it moves GRIN-50
  into a regime with real Raman headroom.
- This pass added the missing MMF-specific safeguards needed to make that
  aggressive baseline scientifically trustworthy when rerun.

## Cost recommendation

Use `:sum` as the primary MMF cost. Keep `:fundamental` and `:worst_mode` as
diagnostics, not as the headline baseline objective.

Why:

- `:sum` matches the mode-integrating detector physics and is the least brittle
  baseline for later reduced-basis or joint-parameter work.
- `:fundamental` can still be reported because GRIN Raman and self-cleaning can
  load LP01 preferentially.
- `:worst_mode` is useful as a robustness stress metric, but it is too
  pessimistic and optimization-hostile to be the main baseline target.

## Practical next step

Run `scripts/mmf_phase36_baseline.jl` on burst again, but only as a fully
observed heavy session, and treat the `Nt = 4096` path as screening only.
The publishable / durable baseline should come from the aggressive `GRIN_50`,
`L = 2.0 m`, `P = 0.5 W` rerun with the new MMF trust checks enabled.
