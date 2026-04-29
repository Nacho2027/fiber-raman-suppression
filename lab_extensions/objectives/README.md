# Objective Extensions

Objective extensions are planning contracts for research ideas. They are visible
to the CLI, but not executable until code, validation, and artifacts exist.

```bash
julia -t auto --project=. scripts/canonical/scaffold_objective.jl my_objective   --label "My objective" --status planning
./fiberlab objectives --validate
```
