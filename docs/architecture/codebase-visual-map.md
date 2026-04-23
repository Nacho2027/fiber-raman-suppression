# Codebase Visual Map

This is a visual companion to [`repo-navigation.md`](./repo-navigation.md).

Use it when you want a fast picture of:

- the main code layers
- the canonical execution flow
- where results and manifests are written
- where to extend the system without guessing

## 1. Top-Level Layer Graph

```text
README / docs
    |
    v
scripts/canonical  (supported CLI wrappers)
    |\
    | \
    |  +--> scripts/validation   (result checks)
    v
scripts/workflows  (maintained workflow implementations)
    |
    v
scripts/lib        (shared script-layer helpers)
    |
    v
src/MultiModeNoise.jl  (package layer)

scripts/research   (active non-canonical experiments) ---> scripts/lib and src/
scripts/archive    (historical / reproducibility)      ---> usually do not extend

scripts/lib and src/ both feed:
results/  (JLD2 + JSON + images)
```

## 2. Directory Ownership Map

```text
src/                -> stable reusable package code
scripts/lib/        -> shared setup / orchestration / plotting helpers
scripts/canonical/  -> thin public entrypoints
scripts/workflows/  -> maintained workflow implementations
scripts/research/   -> study-local active experiments
scripts/archive/    -> historical material
test/               -> tiered regression suite
docs/               -> human-facing docs and maps
agent-docs/         -> agent continuity notes
```

## 3. Canonical Raman Run Flow

```text
scripts/canonical/optimize_raman.jl
    |
    v
scripts/lib/raman_optimization.jl
    |
    +--> scripts/lib/common.jl
    |       setup_raman_problem(...)
    |       setup_raman_problem_exact(...)
    |
    +--> scripts/lib/regularizers.jl
    +--> scripts/lib/objective_surface.jl
    +--> scripts/lib/visualization.jl
    +--> scripts/lib/standard_images.jl
    |
    +--> src/MultiModeNoise.jl  (simulation / optimization primitives)
    |
    +--> src/io/results.jl::save_run(...)
    |       |
    |       +--> _result.jld2
    |       +--> _result.json
    |
    +--> manifest update
    |       |
    |       +--> results/raman/manifest.json
    |
    +--> save_standard_set(...)
            |
            +--> standard PNG set
```

## 4. Canonical Read / Analysis Flow

```text
results/raman/manifest.json
results/raman/*/_result.jld2 + _result.json
    |
    v
src/io/results.jl
    - read_run_manifest(...)
    - load_canonical_runs(...)
    |
    +--> scripts/workflows/run_comparison.jl
    +--> scripts/research/analysis/physics_insight.jl
    +--> future canonical readers
```

## 5. Extension Points

```text
Need to add something?
    |
    +--> stable reusable primitive
    |       -> src/
    |
    +--> shared workflow helper
    |       -> scripts/lib/
    |
    +--> supported user workflow
    |       -> scripts/workflows/ + scripts/canonical/
    |
    +--> active experiment
    |       -> scripts/research/
    |
    +--> historical preservation
            -> scripts/archive/
```

## 6. Concrete File Map

These are the files most worth memorizing.

| Concern | Start here |
|---------|------------|
| Package entrypoint | [`../../src/MultiModeNoise.jl`](../../src/MultiModeNoise.jl) |
| Canonical run/result I/O | [`../../src/io/results.jl`](../../src/io/results.jl) |
| Single-mode setup | [`../../scripts/lib/common.jl`](../../scripts/lib/common.jl) |
| Canonical Raman optimization | [`../../scripts/lib/raman_optimization.jl`](../../scripts/lib/raman_optimization.jl) |
| Plotting / visualization | [`../../scripts/lib/visualization.jl`](../../scripts/lib/visualization.jl) |
| Mandatory post-run images | [`../../scripts/lib/standard_images.jl`](../../scripts/lib/standard_images.jl) |
| Canonical run wrapper | [`../../scripts/canonical/optimize_raman.jl`](../../scripts/canonical/optimize_raman.jl) |
| Canonical sweep wrapper | [`../../scripts/canonical/run_sweep.jl`](../../scripts/canonical/run_sweep.jl) |
| Canonical report wrapper | [`../../scripts/canonical/generate_reports.jl`](../../scripts/canonical/generate_reports.jl) |
| Validation entrypoint | [`../../scripts/canonical/validate_results.jl`](../../scripts/canonical/validate_results.jl) |
| Fast safety net | [`../../test/tier_fast.jl`](../../test/tier_fast.jl) |

## 7. “If I Need To Change X” Cheat Sheet

| I need to change... | First place to inspect |
|---------------------|------------------------|
| fiber preset / single-mode setup behavior | `scripts/lib/common.jl` |
| canonical optimization behavior | `scripts/lib/raman_optimization.jl` |
| canonical payload schema / manifest behavior | `src/io/results.jl` |
| standard output images | `scripts/lib/standard_images.jl` and `scripts/lib/visualization.jl` |
| maintained reporting workflows | `scripts/workflows/` |
| research-local experiment behavior | the specific `scripts/research/<area>/` directory |

## 8. Known Caveats

- `scripts/lib/` is still a transition layer, not a strict package boundary.
- Some maintained research analysis / propagation scripts still use local
  include webs.
- Research schemas and manifests are intentionally not fully normalized.

For the longer prose explanation, see [`repo-navigation.md`](./repo-navigation.md).
