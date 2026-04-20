# Seed: Performance modeling and roofline audit for the FFT/adjoint pipeline

**Planted:** 2026-04-20  
**Source:** Phase 25 NMDS pass

## Why this deserves a phase

The repo already has `scripts/benchmark_threading.jl`, burst-VM conventions,
and repeated discussion of expensive forward/adjoint solves. What it lacks is a
numerical-performance model that explains where time goes and where scaling
stops helping.

The `nmds` performance material makes this phase-sized:
- roofline thinking,
- Amdahl/Gustafson bounds,
- and "time before you tune" as explicit methodology.

## Scope

- Model the forward solve, adjoint solve, FFT planning/execution, and tensor
  contractions as performance kernels
- Identify memory-bound vs compute-bound regions where possible
- Quantify serial fractions that cap parallel speedup
- Connect benchmark results to real decisions about `-t N`, burst VM usage, and
  algorithmic bottlenecks

## Deliverables

- One performance report with modeled bottlenecks, not just raw timings
- A recommendation on where further tuning is worthwhile vs wasted effort
- A small stable benchmark suite tied to those modeled kernels

## Why now

Before spending more effort on hardware scaling or micro-optimization, the
project should know whether its real limit is FFT throughput, solver serial
fractions, memory traffic, or something else.
