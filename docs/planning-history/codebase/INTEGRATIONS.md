# External Integrations

**Analysis Date:** 2026-04-19

This is a research codebase with **no network services, no databases, no
authentication, no webhooks, and no third-party SaaS integrations.**
"Integrations" here means:
1. Native / foreign libraries linked into the Julia runtime.
2. The Python / Matplotlib bridge used for plotting.
3. On-disk file formats used as the de-facto data contract between
   optimization drivers, report generators, and downstream analysis.
4. The GCP compute infrastructure coordinated via shell tooling in
   `scripts/burst/`.

## APIs & External Services

**Web / HTTP APIs:** None.

- No outgoing HTTP calls. No `HTTP.jl`, `Downloads` use, no REST clients.
- No inbound endpoints; no web server in the tree.
- No webhooks (incoming or outgoing).
- No message queues, pub/sub, or streaming clients.

**Cloud-provider integration:** GCP compute, driven via the `gcloud` CLI
from `claude-code-host` — not from Julia. See
[Compute Orchestration](#compute-orchestration-gcp-burst-vm) below.

## Native & Foreign Libraries

**FFTW (C library):**
- Binary: `FFTW_jll 3.3.11+0` (`Manifest.toml`).
- Provider pin: `LocalPreferences.toml` → `[FFTW] provider = "fftw"`.
- Julia wrapper: `FFTW.jl 1.10.0`.
- Used for: forward in-place FFT / IFFT of the complex field `ũω` on
  `(Nt, M)` grids inside every ODE RHS call
  (`src/simulation/simulate_disp_mmf.jl`,
  `src/simulation/sensitivity_disp_mmf.jl`,
  `src/simulation/simulate_disp_gain_mmf.jl`).
- Planner flag: pinned to `FFTW.ESTIMATE` project-wide for deterministic
  bit-identical output across runs
  (`scripts/determinism.jl:54-59` documents the rationale; the
  replacement of `flags=FFTW.MEASURE` was Phase-15 mechanical work).
- Thread count: `FFTW.set_num_threads(1)` for reproducibility
  (`scripts/determinism.jl:75`).

**BLAS / LAPACK:**
- Binary: `OpenBLAS_jll 0.3.29+0` (default). `MKL_jll 2025.2.0+0` is in
  the Manifest as a transitive dep via `FFTW.jl` but the active provider
  is OpenBLAS.
- Used for: `norm`, `dot`, small dense linear algebra in the Arpack
  eigensolver path, and internal L-BFGS work inside `Optim.jl`.
- Thread count: `BLAS.set_num_threads(1)` in deterministic runs
  (`scripts/determinism.jl:76`).

**ARPACK (sparse eigensolver):**
- Binary: `Arpack_jll 3.5.2+0`.
- Julia wrapper: `Arpack.jl 0.5.4`.
- Used for: GRIN multimode fiber mode computation — a sparse
  finite-difference eigenvalue problem solved with `Arpack.eigs` in
  `src/simulation/fibers.jl`.

**Sundials (transitive):**
- Pulled in by `DifferentialEquations.jl` 7.17.0. Not directly invoked;
  the code uses Tsit5 / Vern9 explicit integrators.

## Python / Matplotlib Bridge

**Stack:**
- `PyCall.jl 1.96.4` — embedded Python runtime.
- `Conda.jl 1.10.3` — auto-provisions a private Python + Matplotlib
  install on first use.
- `PyPlot.jl 2.11.6` — Matplotlib wrapper (direct import of
  `matplotlib.pyplot`).

**Backend:** Forced to `Agg` (headless PNG) in every plotting driver:

```julia
ENV["MPLBACKEND"] = "Agg"
using PyPlot
```

Seen in `scripts/mmf_raman_optimization.jl:28`,
`scripts/longfiber_regenerate_standard_images.jl:24`,
`scripts/multivar_demo.jl:25`, `scripts/phase_analysis.jl:35`,
`scripts/hessian_figures.jl:32`,
`scripts/generate_sweep_reports.jl:28`,
`scripts/longfiber_validate_100m_fix.jl:23`,
`scripts/test_visualization_smoke.jl:27`.

**Used directly:**
- `scripts/visualization.jl` — core plotting primitives (evolution
  waterfalls, phase diagnostics, optimization comparison).
- `scripts/standard_images.jl` — the mandatory four-image set emitted by
  every optimization driver (see `CLAUDE.md` "Standard output images").
- `scripts/generate_presentation_figures.jl`,
  `scripts/generate_sweep_reports.jl` — downstream figure generation
  from saved JLD2 results.
- `scripts/hessian_figures.jl`,
  `scripts/figures.jl` — phase-specific diagnostic figures.

**rcParams:** Verified by `scripts/test_visualization_smoke.jl:60-61`
(e.g. `font.size == 10`).

**Output format:** PNG at 300 DPI (`CLAUDE.md` constraint — archival +
screen + print).

## Data Storage & File Formats

**No databases.** All persistence is flat files on the local filesystem.

### JLD2 (primary payload format)

- Library: `JLD2.jl 0.6.4`.
- Canonical writer / reader: `save_run` / `load_run` in
  `scripts/polish_output_format.jl:78-198`.
- Schema version: `"1.0"`
  (`scripts/polish_output_format.jl:36` `OUTPUT_FORMAT_SCHEMA_VERSION`).
- Required keys in the saved `result` NamedTuple
  (`scripts/polish_output_format.jl:41-43`):
  `phi_opt`, `uω0`, `uωf`, `convergence_history`, `grid`, `fiber`,
  `metadata`.
- File locations:
  - `results/raman/**/*.jld2` — individual optimization runs.
  - `results/raman/sweeps/` — (L, P) sweep outputs.
  - `results/cost_audit/` — cost-audit study outputs.
  - `results/research/` — exploratory runs.
- Every JLD2 has a companion JSON sidecar (same stem) — see below.

### JSON sidecars (metadata-only, human-readable)

- Library: `JSON3.jl 1.14.3`.
- Written alongside every JLD2 by `save_run`, with the same stem and
  `.json` extension.
- Required scalar fields
  (`scripts/polish_output_format.jl:45-50`):
  `schema_version`, `payload_file`, `run_id`, `git_sha`,
  `julia_version`, `timestamp_utc`, `fiber_preset`, `L_m`, `P_W`,
  `lambda0_nm`, `pulse_fwhm_fs`, `Nt`, `time_window_ps`,
  `J_final_dB`, `J_initial_dB`, `n_iter`, `converged`, `seed`.
- Grep-able and cat-able; intended as the cross-language / cross-process
  contract. `load_run` accepts either the `.jld2` or the `.json` path
  and resolves the payload.

### NumPy `.npz` (external numerical inputs)

- Library: `NPZ.jl 0.4.3`.
- **GRIN fiber parameter cache** — `fibers/DispersiveFiber_GRIN_*.npz`
  (21 files as of this writing). Filename encodes `r`, `M`, `λ0`, `Nt`,
  `time_window`, `nx`, `Nbeta`. Written by the GRIN solver in
  `src/simulation/fibers.jl`; read back on subsequent runs to skip the
  eigenvalue solve.
- **Yb-doped fiber cross-sections** —
  `src/gain_simulation/Yb_absorption.npz`,
  `src/gain_simulation/Yb_emission.npz`, and the duplicates in `data/`.
  Loaded by `src/gain_simulation/gain.jl` and interpolated with
  `Interpolations.jl`.

### CSV (experimental data)

- Library: `CSV.jl 0.10.16` + `DataFrames.jl 1.8.2`.
- Files: `data/F_vs_P.csv`, `data/251120_data_f_vs_p.csv`.
- Consumed by `data/plotFvsP.jl` only; off the simulation hot path.

### PNG (output images)

- Produced by all plotting scripts at 300 DPI (see `CLAUDE.md`).
- Standard four-image set per optimization run (per
  `CLAUDE.md::save_standard_set`):
  - `{tag}_phase_profile.png`
  - `{tag}_evolution.png`
  - `{tag}_phase_diagnostic.png`
  - `{tag}_evolution_unshaped.png`
- Stored under `results/images/`, `results/raman/.../`, and the
  `presentation-*` directories.

### Report cards & Markdown

- `results/raman/**/report.md` — per-run auto-generated report.
- `results/raman/sweeps/SWEEP_REPORT.md` — aggregated sweep report.
- `results/RESULTS_SUMMARY.md`, `results/SYNTHESIS-2026-04-19.md` —
  hand-maintained and generator-refreshed summaries.
- Generators: `scripts/generate_sweep_reports.jl`,
  `scripts/generate_presentation_figures.jl`.

### Burst-run logs

- `results/burst-logs/<tag>_<timestamp>.log` — tee'd stdout+stderr from
  `scripts/burst/run-heavy.sh` for every heavy run on the burst VM.

## Authentication & Identity

**Not applicable.** No auth anywhere in the code or data paths.
Network access to GCP is authenticated by the user's `gcloud` CLI
credentials, which live outside the repo.

## Compute Orchestration (GCP burst VM)

Orchestration for the burst VM lives in `scripts/burst/` (Bash, not
Julia). None of this runs inside the Julia process; it is invoked from
`claude-code-host`'s shell.

**Inventory (`scripts/burst/`):**
| File | Role |
|---|---|
| `run-heavy.sh` | Mandatory wrapper — acquires `/tmp/burst-heavy-lock`, enforces session-tag regex `^[A-Za-z]-[A-Za-z0-9_-]+$`, launches the job in a named tmux, tees logs to `results/burst-logs/`, releases lock on exit (trap-protected). |
| `watchdog.sh` | Systemd `--user` service on the burst VM. Kills the youngest heavy Julia process when load > 35 or available memory < 4 GB AND ≥ 2 heavy jobs are active. |
| `install.sh` | Idempotent one-shot deployer — copies the wrappers into `~/bin/` on the burst VM (branch-independent). |
| `spawn-temp.sh` | On-demand ephemeral VM spawner. Creates a machine-image clone of `fiber-raman-burst`, runs the command inside the same `run-heavy` wrapper locally, destroys the VM on exit via trap + 6-hour auto-shutdown safety net. |
| `list-ephemerals.sh` | List / destroy orphan ephemeral VMs. |
| `README.md` | Full protocol documentation — session tags, lock semantics, ephemeral-VM usage, cost notes. |

**Shell helpers (installed on `claude-code-host` into `~/bin/`):**
- `burst-start`, `burst-stop`, `burst-ssh`, `burst-status`
- `burst-run-heavy` (resolves to `scripts/burst/run-heavy.sh` on the VM)
- `burst-spawn-temp`, `burst-list-ephemerals`

**Environment variables consumed:**
- `WAIT_TIMEOUT_SEC` — wait-for-lock grace period
  (`scripts/burst/run-heavy.sh:27`).
- `BURST_AUTO_SHUTDOWN_HOURS` — ephemeral auto-shutdown horizon.

**Synchronization with the local Mac:** the gitignored `.planning/`
directory and Claude memory are mirrored between machines via
`sync-planning-to-vm` / `sync-planning-from-vm` (rsync-based, see
`CLAUDE.md` "Multi-Machine Workflow").

## CI/CD & Deployment

**CI:** None configured. No `.github/workflows/`, no
`.gitlab-ci.yml`, no CircleCI, no Jenkins. The pre-commit gate is the
`make test` fast tier, run manually.

**CD:** None — nothing to deploy. Research outputs ship as JLD2/JSON/PNG
artifacts to the advisor meeting and presentation directories.

**Deployment target:** N/A.

## Environment Configuration

**No `.env*` files** exist in the repo (confirmed by `ls` at project
root).

**No secrets, no API keys, no OAuth tokens** anywhere in the tree.

**Configuration surface:**
- `Project.toml` — deps and compat constraints.
- `Manifest.toml` — fully resolved lockfile.
- `LocalPreferences.toml` — FFTW provider pin.
- `CLAUDE.md` — authoritative prose spec for workflow conventions.
- `Makefile` — sanctioned launch commands.

## Webhooks & Callbacks

**Incoming:** None. No HTTP listeners, no gRPC servers, no Unix sockets.

**Outgoing:** None. No clients initiate network connections from the
Julia process.

## Integration Surface Summary

| Surface | Direction | Format | Producer | Consumer |
|---|---|---|---|---|
| Optimization result | file | JLD2 + JSON | `save_run` in optimization drivers | `load_run` in analysis scripts, report generators, tests |
| GRIN mode cache | file | NPZ | `src/simulation/fibers.jl` | `src/simulation/fibers.jl` (subsequent runs) |
| Yb cross-section data | file (static) | NPZ | external (pre-committed) | `src/gain_simulation/gain.jl` |
| F-vs-P experimental | file (static) | CSV | external lab instrument | `data/plotFvsP.jl` |
| Plot output | file | PNG (300 DPI) | `scripts/standard_images.jl`, `scripts/visualization.jl`, figure generators | humans (advisor meetings, presentations) |
| Report cards | file | Markdown | `scripts/generate_sweep_reports.jl` | humans |
| Burst-run logs | file | plain text | `scripts/burst/run-heavy.sh` | humans, `tail -f` during monitoring |
| Matplotlib | in-process FFI | PyCall | every plotting script | PyPlot → PNG |
| FFTW | linked lib | in-memory | `FFTW_jll` | every forward / adjoint RHS |
| BLAS | linked lib | in-memory | `OpenBLAS_jll` | LinearAlgebra, Optim, Arpack |
| Arpack | linked lib | in-memory | `Arpack_jll` | GRIN mode solve |
| GCP burst VM | subprocess (ssh) | shell | `claude-code-host` session | `fiber-raman-burst` VM |

---

*Integration audit: 2026-04-19*
