# Config Runner Design

Approved experiment settings go in TOML. The physics stays in Julia.

## Boundary

TOML chooses from contracts. Julia code owns physics, gradients, solver
behavior, validation, and artifacts.

## Flow

```text
configs/experiments/<id>.toml
        -> config loader and validators
        -> run/explore command
        -> run implementation
        -> result payload, manifest, images, optional export
```

## Design rules

- A config must say whether it is supported, smoke-only, experimental, or
  planning-only.
- Planning-only configs may validate and print compute plans, but should not run
  as if they are supported workflows.
- New objectives and variables need code, tests, and plots before they can run.
- The same result indexer should work for supported and exploratory runs, while
  preserving the run status.

See [configurable experiments](../guides/configurable-experiments.md) for the
user-facing commands.
