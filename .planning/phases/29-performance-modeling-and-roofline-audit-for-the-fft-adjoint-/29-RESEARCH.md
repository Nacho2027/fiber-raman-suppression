# Phase 29 Research — Performance modeling

## Core question

Where does time go in the forward/adjoint pipeline, and which parts are
memory-bound, compute-bound, or dominated by serial orchestration?

## Phase outputs

- Stable kernel benchmarks for FFT, forward solve, adjoint solve, and selected
  tensor contractions
- A roofline-style memo tying timings to likely bottlenecks
- Amdahl/Gustafson guidance for thread-count and burst-VM decisions
- A recommendation on where tuning effort is justified
