# Notebooks

Exploratory notebooks live here.

Notebooks are not the maintained workflow surface. Promote reusable code into
`src/`, maintained commands into `scripts/canonical/`, and active research
drivers into `scripts/research/`.

## Research Engine Template

Use `templates/experiment_explorer.ipynb` when exploring the configurable
fiber-optic optimization front layer from Jupyter.

The template imports the thin Python helper in `python/fiber_research_engine/`.
That helper delegates to the maintained Julia CLI commands, so notebooks use
the same validation, objective registry, sweep planning, and artifact contracts
as command-line workflows.

The helper also exposes `dry_run_amp_on_phase_refinement(...)` for planning the
optional amp-on-phase second-stage workflow from a notebook. Treat that path as
experimental: use notebooks for planning and inspection, then launch substantial
refinement jobs through the canonical CLI or burst wrapper.

Notebook rule:

- use notebooks for discovery, visualization, comparison, and small safe runs
- do not implement objective logic, solver dispatch, or artifact conventions in
  notebooks
- launch heavy jobs and campaign sweeps through CLI/compute plans
