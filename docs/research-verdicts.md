# Research Verdicts

Short source of truth for research lanes that used to live as active scripts.
Old run logs, reports, and exploratory drivers are in the external cleanup
archive.

| Lane | Verdict | Active Surface |
|---|---|---|
| Single-mode phase optimization | Keep. This is the supported baseline. | Experiment configs plus `scripts/lib/raman_optimization.jl`. |
| Reduced/extension phase controls | Keep as experimental API options. | Variable extensions and front-layer configs. |
| Multivar joint phase/amplitude/energy | Not default. Keep optimizer primitives for explicit experiments only. | `scripts/lib/multivar_optimization.jl`. |
| Amp-on-phase refinement | Optional, staged, experimental. Do not make it the default pipeline. | `scripts/lib/amp_on_phase_refinement.jl` and canonical refinement wrapper. |
| Multimode phase optimization | Keep as promoted experimental capability. | `scripts/lib/mmf_setup.jl` and `scripts/lib/mmf_raman_optimization.jl`. |
| Long-fiber phase optimization | Keep as promoted high-resource capability. | Front-layer long-fiber configs plus `scripts/lib/longfiber_setup.jl`. |
| Old phase/cost/trust/sweep campaigns | Closed or superseded. Do not keep active drivers. | Archive only. |
| Old Python API | Removed. | None. Julia is the supported API surface. |

Policy: failed or superseded research is documented here and archived, not kept
as runnable code in the main pipeline. Successful research must be promoted into
the maintained Julia API before it is treated as supported.
