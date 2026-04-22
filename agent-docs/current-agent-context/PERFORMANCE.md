# Performance Notes

This file distills the still-actionable conclusions from the remote-only Phase 29 kernel inventory.

Source artifacts:

- `docs/planning-history/phases/29-performance-modeling-and-roofline-audit-for-the-fft-adjoint-/29-KERNEL-INVENTORY.md`
- `docs/planning-history/quick/260415-u4s-benchmark-threading-opportunities-across/*`

## Durable conclusions

### Forward runtime is not "just FFTs"

- At multimode settings like `Nt = 8192, M = 6`, the forward RHS is dominated by the Kerr tensor contractions, not by the scalar FFTs.
- The practical implication is that performance work should focus on the `γ` / `@tullio` contraction path before spending more time micro-tuning the batched `M` FFTs.

### Adjoint cost is materially heavier than forward cost

- The adjoint RHS carries multiple extra Kerr-style contractions plus more FFT traffic.
- For performance reasoning, assume one full cost-and-gradient evaluation is several times the price of a forward solve, especially in multimode regimes.

### FFTW internal threading is still the wrong lever at current grids

- The static kernel inventory and the earlier threading benchmark agree: at `Nt = 2^13`, FFTW internal threading is counterproductive.
- Keep `FFTW.set_num_threads(1)` unless the grid size or workload shape changes enough to justify re-measuring.

### The best parallelism is outside a single solve

- Independent solves, multi-start runs, and sweep points remain the main scaling surface.
- For agent work, prefer task-level parallelism over trying to force more shared-memory speedup out of one forward-adjoint pair.

### Multimode changes the bottleneck story

- At `M = 1`, FFT-heavy reasoning is still a decent mental model.
- At `M >= 3`, the tensor-contraction side becomes important enough that roofline and arithmetic-intensity arguments should be made against the contraction kernels, not only the FFT plans.

## Agent guidance

- When discussing runtime bottlenecks, state whether the claim is for `M = 1` or multimode operation.
- When proposing optimization-speed work, separate per-solve kernel tuning from embarrassingly parallel solve orchestration.
- If a future task needs the full static accounting, read the archived source document in `docs/planning-history/` instead of reconstructing it from memory.
