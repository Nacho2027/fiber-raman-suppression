# Methodology Notes

This file captures durable experimental-method facts migrated from the old quick-task artifacts.

## Sweep window sizing

Source artifacts:

- `.planning/quick/260331-gh0-fix-sweep-methodology-time-window-formul/*`

### What remains important

- `recommended_time_window(...)` was corrected on 2026-03-31 to convert nonlinear phase into an SPM bandwidth using `δω_SPM ≈ 0.86 * φ_NL / T0`, with `T0 = pulse_fwhm / 1.763` for sech² pulses.
- The important implication is not the exact derivation, but the operational consequence: **longer fibers and higher powers need much larger windows than the early sweep code assumed**.
- Pre-fix sweep results are not trustworthy in regimes where SPM broadening matters. The high-risk regime called out in the original note was roughly `L >= 2 m` or high-power points where the old window estimate badly under-shot.
- Current fast tests already cover the corrected windowing logic; see `test/tier_fast.jl`.

### Agent guidance

- When evaluating or extending sweep-style scripts, assume time-window sizing is a first-order numerical risk, not a cosmetic parameter.
- If a run looks physically suspicious at longer length or higher power, inspect `recommended_time_window(...)` inputs before interpreting the result.
- Be cautious about comparing results across runs generated before and after the 2026-03-31 windowing fix.

## Threading and parallelism

Source artifacts:

- `.planning/quick/260415-u4s-benchmark-threading-opportunities-across/*`

### Durable findings

- At `Nt = 8192`, FFTW internal threading was measured to be counterproductive. Keep `FFTW.set_num_threads(1)` for this grid size.
- At `M = 1`, Tullio threading is effectively irrelevant because the contraction collapses to trivial scalar work.
- The useful parallelism is at the task level:
  - independent forward solves
  - multi-start optimization runs
  - sweep points
- The critical implementation pattern is **`deepcopy(fiber)` per thread** because the `fiber` dict carries mutable solver state such as `zsave`.

### Agent guidance

- Launch Julia with threads enabled for sweep or multi-start workloads.
- Do not spend time tuning FFTW threading for current single-mode `Nt = 2^13` workloads unless the grid size changes materially.
- If parallelizing independent solves, copy `fiber` per thread and treat that as non-negotiable.
- Revisit Tullio-thread conclusions only for multimode (`M > 1`) workloads.

### Already reflected elsewhere

The most important operational conclusions from this benchmark are already encoded in `CLAUDE.md`. This file exists so agents can see the rationale and historical provenance without reading old GSD quick-task files.
