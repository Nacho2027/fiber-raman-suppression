---
title: Compute Infrastructure Decision — GCP c3-highcpu-8 on $300 Free Trial
date: 2026-04-16
context: Rivera Lab fiber Raman suppression — transition from single-mode to multimode (M=6) with Newton-as-optimizer, 4-week sprint
---

# Compute Infrastructure Decision

## Context

PI directive (April 2026):
1. Extend from single-mode to **multimode** simulations (target M=6).
2. Switch from L-BFGS to **Newton-as-optimizer** (option "b") with full Hessian tracked each iteration "to make sure solutions are stable."

Timeline: **4 weeks remaining** with the Rivera Lab team.

## Final decision (2026-04-16)

**GCP `c3-highcpu-8` (Intel Sapphire Rapids, 8 vCPU, 16 GB RAM, AVX-512) in `us-east1`, funded by the $300 new-account free trial.**

- Running cost: ~$0.33/hour → ~$222 for the full 4-week sprint (24/7)
- Out-of-pocket: **$0** (within $300 free trial, ~$78 buffer)
- Always-on for Claude Code host
- Burst to `c3-highcpu-22` (22 vCPU, ~$0.90/hour) for specific heavy Newton runs, stop when done — a 12-hour burst costs ~$11

Step-by-step in `.planning/todos/pending/provision-gcp-vm.md`.

## Key insight that drove instance sizing

The threading benchmark (`scripts/benchmark_threading.jl`, commit d1c5bd9) measured real speedups on the M3 Max:

| Parallelism opportunity | 8-thread speedup |
|---|---|
| FFTW internal threading | 0.65× (*harmful*) |
| Tullio/LoopVectorization | 1.00× at M=1 |
| Multi-start optimization | 2.13× |
| Parallel forward solves (embarrassingly parallel) | 3.55× |

The dominant parallelism opportunity is **parallel forward+adjoint solves** for Newton Hessian columns. At 8 threads this yields 3.55×; scaling to 32 vCPU would likely give ~8–12× (sub-linear due to BLAS contention). The marginal benefit of going above 8–16 vCPU is real but not dramatic, so **c3-highcpu-8 hits the sweet spot of parallelism benefit vs budget fit**.

If a specific Newton run demonstrably bottlenecks the 8-vCPU machine, burst to c3-highcpu-22 for that run only.

## Evolution of this decision (documented record)

Started with a wrong mental model ("we need bare metal dedicated hardware") and reconverged on the right answer through several revisions:

1. **Hetzner AX52 dedicated** — first instinct based on $/core reputation. Discontinued product.
2. **Hetzner AX102-U dedicated** — current flagship. Rejected: €269 one-time setup fee makes 4-week economics unattractive (€388 total).
3. **Hetzner Cloud CCX43** — 16 dedicated vCPU, €125/month, no setup fee. Intended primary.
4. **Hetzner Cloud CCX53** — 32 dedicated vCPU, €250/month. Intended primary after learning the benchmark justified more cores.
5. **NSF ACCESS Jetstream2** — learned about existing ~200k credit allocation. Would have been $0 primary. User elected not to pursue (scope hesitation on existing MLAOD allocation interpretation).
6. **Back to Hetzner Cloud CCX** — discovered all dedicated-vCPU sizes above CCX23 (4 vCPU) are **sold out at every Hetzner location** as of 2026-04-16. Only 4 vCPU available, smaller than M3 Max.
7. **GCP $300 free trial** — final choice. Instant provisioning, no stock issues, US data center, fits the full sprint within the free-trial budget with ~$78 of buffer.

Lesson: check stock availability before committing to a specific provider. Hetzner's value proposition is real when inventory exists; when it doesn't, hyperscaler free-trial credits become surprisingly competitive.

## Why not the alternatives (final record)

**Hetzner Cloud CCX (primary earlier choice):** sold out. CCX23 is the only option and is worse than the M3 Max. Only revisit if stock returns.

**Hetzner dedicated (AX102-U):** €269 setup fee kills 4-week economics.

**NSF ACCESS Jetstream2:** excellent technically, user declined for scope reasons. Strong option for future longer-horizon work — the Explore tier approves in 1–2 business days with a one-page abstract and easily covers any likely workload. Keep in mind for any post-sprint compute need.

**AWS on-demand:** c7i.4xlarge (16 vCPU, 32 GB) = ~$514/month. 2.3× the cost of GCP c3-highcpu-8 (8 vCPU) for 2× the parallelism — not a winning ratio when the benchmark shows diminishing returns above ~8 threads.

**AWS spot:** good pricing (~$0.20–0.45/hr for 16 vCPU) but interruption risk undermines "always-on Claude Code." Checkpoint/restart overhead not worth it for a 4-week sprint.

**Cornell CAC / G2:** approval takes ~1 month. Dead on arrival.

## Why not GPU

- **M=6 is not big enough to saturate a GPU.** Kerr coupling tensor is M⁴=1296 entries per ω bin; at Nt=2^14 the RHS is ~2×10⁷ FLOPs — trivial on CPU, underutilizes GPU.
- **Bottleneck is embarrassingly parallel ODE solves**, not dense linear algebra. Newton's Hessian needs ~N_φ forward+adjoint solves per iteration. These are independent → scale linearly with CPU cores. GPU wouldn't help without a full CUDA.jl port.
- **Porting to CUDA.jl is weeks of work** — rewriting FFT plans, Tullio CUDA mode, GPU-compatible DE solver selection. Not realistic in a 4-week window.

## Realistic scope de-rating for Newton

Full Newton-as-optimizer with **second-order adjoint** for Hessian-vector products is a 2–3 week math+code project on its own. Fallback ladder (decreasing ambition):

1. Full second-order adjoint Newton (stretch).
2. `Optim.jl` `Newton()` with finite-difference Hessian, parallelized via `Threads.@threads` across CPU cores with `deepcopy(fiber)` per thread (the pattern validated by the threading benchmark). Likely landing point.
3. L-BFGS + diagnostic Hessian at the optimum (positive definite → genuine minimum, negative eigenvalues → saddle point). Satisfies the "make sure solutions are stable" goal.

Worth communicating the scope ladder up front so expectations align if timeline slips.

## Revisit triggers (when to reconsider infrastructure)

- Free-trial credit burn rate outpaces budget (current estimate: ~$222 of $300 over 4 weeks — comfortable)
- Newton runs demonstrably bottleneck 8 vCPU — burst to c3-highcpu-22 for specific runs
- Project continues beyond 4-week window — submit a proper ACCESS Explore allocation or convert to long-term Hetzner dedicated
- `M ≥ 10` modes or `Nt ≥ 2^16` → reconsider GPU via Jetstream2 at that point

## Side benefit

Always-on remote VM means Claude Code is available whenever the user SSHes in, not tied to a particular laptop session. Real value, independent of the compute sizing question.
