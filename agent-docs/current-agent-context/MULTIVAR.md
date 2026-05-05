# Multivar Context

Multivariable optimization is no longer represented by active research
drivers. Reusable pieces were promoted into the Julia API; old ablation and
reference scripts were archived.

Current API surface:

- `scripts/lib/multivar_optimization.jl`
- `scripts/lib/multivar_artifacts.jl`
- `scripts/lib/amp_on_phase_refinement.jl`
- Front-layer variable extension configs.

Verdict:

- Phase-only remains the default supported optimization path.
- Joint phase/amplitude/energy optimization is available only as explicit
  experimental API usage.
- Amp-on-phase is optional staged refinement, not the default pipeline.
- Failed or superseded ablation drivers should stay archived.

See `docs/research-verdicts.md` for the human-facing lane summary.
