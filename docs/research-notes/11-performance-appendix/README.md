# Performance Model and Compute Strategy

- status: `production-ready appendix`
- evidence snapshot: `2026-04-26`
- PDF: `11-performance-appendix.pdf`

## Purpose

This note explains how to reason about runtime for the Raman-suppression
project. It is a compute-methodology appendix, not an optical-result note, so
its figures are benchmark diagrams and timing charts rather than paired
phase-diagnostic / heat-map result pages.

## Main Claims

- Full-grid finite-difference gradients are not practical at canonical grid
  sizes; adjoint gradients are the right optimization primitive.
- For the canonical single-mode workload, internal FFTW threading is the wrong
  lever at the current grid size.
- The best parallelism is outside one solve: sweeps, multistarts, basis ladders,
  and validation batches.
- Multimode and long-fiber workloads need their own benchmarks before reusing
  the same compute rule.

## Primary Sources

- `agent-docs/current-agent-context/PERFORMANCE.md`
- archived roofline report, Amdahl-fit JSON, and hardware-profile JSON
- archived deterministic FFT-planning benchmark
- `scripts/research/benchmarks/benchmark_threading.jl`
- `scripts/workflows/run_benchmarks.jl`

The exact archived result paths are intentionally not named in this outward-facing
README. They are recoverable from the agent context if a future maintainer needs
to audit provenance.

## Figures

- `figures/performance_cost_model.png`
- `figures/single_solve_thread_speedup.png`
- `figures/kernel_timing_summary.png`
- `figures/determinism_speed_tradeoff.png`

## Verification

After editing, compile from this directory with:

```bash
pdflatex -interaction=nonstopmode 11-performance-appendix.tex
pdflatex -interaction=nonstopmode 11-performance-appendix.tex
```

Then render and inspect the PDF pages. This note must remain free of placeholder
text, internal milestone labels, overfull layout problems, and unreadable chart
text.
