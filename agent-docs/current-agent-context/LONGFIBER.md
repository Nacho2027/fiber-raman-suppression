# Long-Fiber Context

Long-fiber work is a promoted high-resource capability, not an active
research-driver lane.

Current API surface:

- Front-layer long-fiber configs.
- `scripts/lib/longfiber_setup.jl` for explicit long-fiber grid setup.
- `scripts/lib/longfiber_checkpoint.jl` for checkpoint/resume helpers.
- `scripts/lib/experiment_runner.jl` for supported execution and reach
  diagnostics.

Verdict:

- 50-100 m single-mode studies are credible exploratory workflows.
- Larger single-mode studies require explicit high-resource validation.
- Multimode long-fiber remains experimental.

See `docs/research-verdicts.md` for the human-facing lane summary.
