# Research Extensions

Use extension files to make proposed objectives or variables visible without
pretending they are ready to execute.

## Objective scaffold

```bash
julia -t auto --project=. scripts/canonical/scaffold_objective.jl pulse_compression   --label "Pulse compression"   --status planning
```

## Variable scaffold

```bash
julia -t auto --project=. scripts/canonical/scaffold_variable.jl mode_weights   --label "Mode weights"   --status planning
```

## Promotion checklist

- physics formula documented;
- gradient or derivative-free solver choice justified;
- validation tests added;
- artifact plan implemented;
- smoke run inspected;
- docs updated with the claim boundary.

Planning contracts should be easy to discover and hard to mistake for supported
science.
