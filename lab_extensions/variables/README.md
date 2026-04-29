# Variable Extensions

Variable extensions describe proposed controls. A variable is not supported
until vector mapping, bounds, solver behavior, artifacts, and tests exist.

```bash
julia -t auto --project=. scripts/canonical/scaffold_variable.jl my_variable   --label "My variable" --status planning
./fiberlab variables --validate
```
