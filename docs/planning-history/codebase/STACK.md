# Technology Stack

**Analysis Date:** 2026-04-19

Scientific-computing Julia package (`MultiModeNoise`) for nonlinear
fiber-optic pulse propagation with adjoint-based spectral-phase optimization
(Raman suppression). CPU-only, single-workstation / burst-VM workflow, no
services, no network I/O, no secrets.

## Languages

**Primary:**
- Julia `>= 1.9.3` (declared `[compat]` in `Project.toml:33`); `Manifest.toml`
  currently resolved against Julia `1.12.6` (`Manifest.toml:3`).
- Used for: all physics (`src/simulation/`), optimization drivers
  (`scripts/raman_optimization.jl`, `scripts/multivar_optimization.jl`,
  `scripts/longfiber_optimize_100m.jl`, `scripts/mmf_raman_optimization.jl`,
  etc.), cost-audit analysis, test tiers, image generation.

**Secondary:**
- Python 3.x — invoked implicitly via PyCall / PyPlot as the Matplotlib
  backend for every plotting script. Managed by Julia's `Conda.jl`; not
  directly authored.
- Bash — coordination wrappers in `scripts/burst/` (`run-heavy.sh`,
  `watchdog.sh`, `install.sh`, `spawn-temp.sh`, `list-ephemerals.sh`) plus
  shell drivers like `scripts/cost_audit_run_*.sh` and
  `scripts/longfiber_burst_launcher.sh`.
- GNU Make — convenience targets in `Makefile` (install, test tiers,
  optimize, sweep, report, clean).

**Not present:**
- No TypeScript / JavaScript.
- No C / C++ source authored in the repo (FFTW and BLAS come in as `_jll`
  binaries).

## Runtime

**Environment:**
- Julia runtime: single process, CPU-only, multithreaded via `-t auto`.
  Simulations are launched with `julia -t auto --project=.` (verified in
  `Makefile:37` `test-slow`, `Makefile:40` `test-full`, `Makefile:43`
  `optimize`, `Makefile:58` `sweep`, and every `scripts/burst/run-heavy.sh`
  invocation in `scripts/burst/README.md:19`).
- Python runtime: auto-resolved by PyCall via `Conda.jl` (`Conda v1.10.3`
  in `Manifest.toml`). Matplotlib backend forced to `"Agg"` in plotting
  scripts via `ENV["MPLBACKEND"] = "Agg"` (see
  `scripts/mmf_raman_optimization.jl:28`,
  `scripts/longfiber_regenerate_standard_images.jl:24`,
  `scripts/multivar_demo.jl:25`, `scripts/phase_analysis.jl:35`,
  `scripts/phase13_hessian_figures.jl:32`,
  `scripts/generate_sweep_reports.jl:28`).
- Jupyter (`notebooks/*.ipynb`) used for exploratory work only
  (EDFA/YDFA gain, MMF squeezing, supercontinuum). Not part of the
  primary pipeline.

**Package Manager:**
- Julia built-in `Pkg`. `make install` → `julia --project=. -e 'using Pkg;
  Pkg.instantiate()'` (`Makefile:30-31`).
- Lockfile: `Manifest.toml` present and committed (resolved with Julia
  1.12.6, `project_hash = "20bf3a2b41245eadc0eb6efb98959b5cd878d52f"`).
- Project definition: `Project.toml` — name `MultiModeNoise`, UUID
  `b336628f-8386-4303-a33d-f2bdce4c2a6e`, version `1.0.0-DEV`.
- Local preferences: `LocalPreferences.toml` pins
  `[FFTW] provider = "fftw"` (over MKL). Treat this file as committed and
  authoritative for binary provider.

## Frameworks

**Core numerics:**
- `DifferentialEquations.jl` `7.17.0` — Tsit5 / Vern9 ODE solvers for the
  forward Raman+Kerr propagation (`src/simulation/simulate_disp_mmf.jl`)
  and the adjoint sensitivity solve
  (`src/simulation/sensitivity_disp_mmf.jl`).
- `FFTW.jl` `1.10.0` — pre-planned in-place FFT / IFFT for the spectral /
  temporal transforms inside every ODE RHS call. Planner flag is pinned to
  `FFTW.ESTIMATE` project-wide for determinism (see
  `scripts/determinism.jl` and `src/simulation/*.jl`).
- `Tullio.jl` `0.3.9` — Einstein-summation macro for the 4-D Kerr overlap
  tensor `γ[i,j,k,l]` and MMF mode contractions.
- `LoopVectorization.jl` `0.12.173` — SIMD backend used implicitly by
  Tullio.
- `LinearAlgebra` (stdlib) — BLAS/LAPACK. Thread count pinned to 1 for
  determinism (`scripts/determinism.jl:76` `BLAS.set_num_threads(1)`).
- `SparseArrays` (stdlib) + `Arpack` `0.5.4` — sparse eigenvalue solve for
  the finite-difference GRIN mode solver (`src/simulation/fibers.jl`).
- `FiniteDifferences.jl` `0.12.33` — stencils for the β-coefficient
  computation at the carrier frequency.

**Optimization:**
- `Optim.jl` `1.13.3` (`[compat] = "1.13.3"`) — L-BFGS for spectral-phase
  optimization via the `only_fg!()` cost+gradient interface. Used in
  `scripts/raman_optimization.jl`, `scripts/amplitude_optimization.jl`,
  `scripts/multivar_optimization.jl`, `scripts/longfiber_optimize_100m.jl`,
  `scripts/mmf_raman_optimization.jl`.

**Plotting:**
- `PyPlot.jl` `2.11.6` — Matplotlib wrapper. Central plotting library
  (`scripts/visualization.jl`, `scripts/standard_images.jl`, Phase-13 / 14
  figure generators, sweep report renderer).
- `PyCall.jl` `1.96.4` — transitive dependency of PyPlot, drives the
  Python bridge.

**I/O / data:**
- `JLD2.jl` `0.6.4` (`[compat] = "0.6.3"`) — canonical payload format for
  optimization runs. Central entry points `save_run` / `load_run` in
  `scripts/polish_output_format.jl:78-198` (schema version `"1.0"`).
  Every run emits `<path>.jld2` + `<path>.json` pair.
- `JSON3.jl` `1.14.3` (`[compat] = "1.14.3"`) — JSON sidecar writer for
  run metadata. Used alongside JLD2 in `polish_output_format.jl`.
- `NPZ.jl` `0.4.3` — read/write NumPy `.npz`. Used for GRIN fiber
  parameter cache (`fibers/DispersiveFiber_GRIN_*.npz`) and Yb
  cross-section data (`src/gain_simulation/Yb_{absorption,emission}.npz`,
  `data/Yb_{absorption,emission}.npz`).
- `Interpolations.jl` `0.16.2` (`[compat] = "0.16.2"`) — 1-D linear
  interpolation of the Yb cross-section spectra in
  `src/gain_simulation/gain.jl`.
- `CSV.jl` `0.10.16` (`[compat] = "0.10.15"`) + `DataFrames.jl` `1.8.2`
  (`[compat] = "1.8.1"`) — experimental `F_vs_P` data handling in
  `data/plotFvsP.jl`. Not on the simulation hot path.

**Testing:**
- `Test` (stdlib) — used by every tier in `test/tier_{fast,slow,full}.jl`
  and by `test/test_*.jl` suites.
- No external test runner; `test/runtests.jl` dispatches tiers by the
  `TEST_TIER` env var (`fast` / `slow` / `full`).
- No mocking framework, no property-based-test library beyond the
  hand-rolled Taylor-remainder gradient check in
  `test/tier_slow.jl:78-99`.

**Development helpers:**
- `Revise.jl` — optional hot reload, wrapped `try using Revise catch end`
  at the top of scripts. Listed in the Manifest but not a project `[deps]`
  entry.
- `Dates` (stdlib) — UTC timestamps in run IDs and metadata.
- `Printf` / `Logging` (stdlib) — `@info` / `@debug` / `@warn` +
  `@sprintf` throughout scripts.

## Key Dependencies

**Critical (direct, in `Project.toml [deps]`):**
| Package | Installed | Compat pin | Role |
|---|---|---|---|
| DifferentialEquations | 7.17.0 | — | Forward + adjoint ODE integration |
| FFTW | 1.10.0 | — | In-place FFTs on `(Nt, M)` complex matrices |
| Tullio | 0.3.9 | — | 4-D Kerr overlap tensor contraction |
| Optim | 1.13.3 | 1.13.3 | L-BFGS spectral-phase optimization |
| Arpack | 0.5.4 | — | Sparse eigensolver for GRIN modes |
| NPZ | 0.4.3 | — | GRIN cache + Yb cross-section load |
| JLD2 | 0.6.4 | 0.6.3 | Run payload serialization |
| JSON3 | 1.14.3 | 1.14.3 | Sidecar metadata |
| Interpolations | 0.16.2 | 0.16.2 | Yb cross-section interpolation |
| PyPlot | 2.11.6 | — | Matplotlib plotting |
| LoopVectorization | 0.12.173 | — | SIMD backend for Tullio |
| FiniteDifferences | 0.12.33 | — | β-coefficient stencils |
| CSV | 0.10.16 | 0.10.15 | Experimental-data I/O |
| DataFrames | 1.8.2 | 1.8.1 | Tabular handling (data/ scripts only) |
| SparseArrays | stdlib | — | GRIN finite-difference matrix |
| LinearAlgebra | stdlib | — | BLAS/LAPACK, `norm`, `dot` |
| Dates | stdlib | 1.11.0 | Timestamps |

**Transitive infrastructure (from `Manifest.toml`):**
- `FFTW_jll` `3.3.11+0` — the libfftw3 binary.
- `MKL_jll` `2025.2.0+0` — present as transitive dep, but NOT used: the
  active provider is `fftw` per `LocalPreferences.toml`.
- `OpenBLAS_jll` `0.3.29+0` — BLAS backend used by `LinearAlgebra`.
- `PyCall` `1.96.4` + `Conda` `1.10.3` — drive the Python bridge, auto-
  install matplotlib on first use.

**No deps on:**
- HTTP / web frameworks (Genie, Oxygen, HTTP.jl-as-server).
- Database drivers (SQLite, Postgres, MongoDB).
- Auth / crypto libraries.
- Cloud SDKs (AWS/GCP/Azure client libs). GCP compute is driven via the
  `gcloud` CLI through the host shell, not via Julia.

## Configuration

**Environment variables (runtime-only, no `.env`):**
- `MPLBACKEND=Agg` — forced in every plotting script for headless
  matplotlib.
- `TEST_TIER=fast|slow|full` — selects the test tier (`test/runtests.jl:16`).
- `JULIA_DEBUG` — standard Julia log-level control (surfaced in `@debug`
  statements).
- `WAIT_TIMEOUT_SEC` — optional knob for `scripts/burst/run-heavy.sh:27`
  (wait-for-lock instead of fail-fast).
- `BURST_AUTO_SHUTDOWN_HOURS` — ephemeral-VM safety net in
  `scripts/burst/spawn-temp.sh`.
- `REGEN_ROOT` — override scan root for
  `scripts/regenerate_standard_images.jl` (see `CLAUDE.md`).

**Julia preferences:**
- `LocalPreferences.toml` pins `[FFTW] provider = "fftw"`. Checked in.

**Build / project config:**
- `Project.toml` — deps and compat.
- `Manifest.toml` — resolved lockfile (Julia 1.12.6).
- No `.env*`, no secrets, no API keys.

**Code-quality config:**
- None configured — no `.JuliaFormatter.toml`, no `.editorconfig`, no
  pre-commit hook config. Style is enforced by convention
  (see `CONVENTIONS.md`).

## Build & Run

**Install deps (one-time, ~2 min):**
```bash
make install
```

**Run tests:**
```bash
make test         # fast tier, ≤30 s, simulation-free; runs anywhere.
make test-slow    # ~5 min; burst VM recommended.
make test-full    # ~20 min; burst VM. Includes cross-process bit-identity.
```

**Run the canonical optimization:**
```bash
make optimize                                          # SMF-28, ~5 min
# or
julia -t auto --project=. scripts/raman_optimization.jl
```

**Run a full (L, P) sweep (heavy — burst VM required):**
```bash
burst-ssh "cd fiber-raman-suppression && \
           ~/bin/burst-run-heavy E-sweep1 \
           'julia -t auto --project=. scripts/run_sweep.jl'"
```

**Regenerate report cards / presentation figures from saved JLD2:**
```bash
make report
```

**Clean regenerable artifacts (keeps JLD2 payloads):**
```bash
make clean
```

## Platform Requirements

**Development:**
- Julia `>= 1.9.3` (the project was last resolved against `1.12.6`).
- Python 3.x with Matplotlib — auto-provisioned by `Conda.jl` on first
  PyPlot use.
- libfftw3 — supplied by `FFTW_jll`; no system install needed.
- OpenBLAS — supplied by `OpenBLAS_jll`.
- No GPU. No CUDA. Tullio has an optional CUDA extension that is not
  activated.
- No containers (no `Dockerfile`, no `docker-compose.yml`).

**Compute infrastructure:**
- Two-tier compute (see `CLAUDE.md` "Running Simulations — Compute
  Discipline"):
  - `claude-code-host` (GCP e2-standard-4, 16 GB) — always-on host for
    Claude Code sessions. Never runs simulations.
  - `fiber-raman-burst` (GCP c3-highcpu-22) — on-demand burst VM. All
    Julia simulation work goes here through the mandatory
    `~/bin/burst-run-heavy` wrapper (Rule P5).
  - Ephemeral clones via `~/bin/burst-spawn-temp` for parallel runs.
- Memory: `Nt = 2^13, M = 1` is the canonical single-mode regime and fits
  comfortably in < 4 GB. `M > 1` multimode runs at larger `Nt` can push
  into multi-GB territory.
- Threading: Julia must be launched with `-t auto` (or `-t N`). Without
  this, all Tullio / parallel-forward-solve speedups are dormant.
  `scripts/benchmark_threading.jl` measured 3.55× parallel-forward and
  2.13× multi-start speedups at 8 threads.
- Determinism: when running regression tests or reproducibility-sensitive
  work, `scripts/determinism.jl::ensure_deterministic_environment()` pins
  FFTW and BLAS to 1 thread. This is already wired into the slow and full
  test tiers.

**Production:**
- Not applicable. This is a research codebase; there is no deployed
  runtime. Outputs are JLD2/JSON files + PNG images consumed in lab
  meetings, notebooks, and the `presentation-*` directory.

---

*Stack analysis: 2026-04-19*
