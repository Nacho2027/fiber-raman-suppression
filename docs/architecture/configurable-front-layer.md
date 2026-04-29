# Config Runner Design

Approved experiment settings go in TOML. The physics stays in Julia.

The design goal is a reusable runner for fiber-optic optimization studies, not
just a wrapper around one Raman script. Raman-band suppression is the first
well-tested case. Other objectives and controls should reuse the same config,
manifest, artifact, and comparison machinery after their physics code exists.

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
- Non-Raman questions are allowed; fake objectives declared only in TOML are
  not.
- The same result indexer should work for supported and exploratory runs, while
  preserving the run status.

See [configurable experiments](../guides/configurable-experiments.md) for the
user-facing commands.
