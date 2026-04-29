# Codebase Visual Map

```text
configs/experiments/*.toml
        |
        v
./fiberlab  ->  scripts/canonical/*.jl
        |              |
        |              v
        |        scripts/lib/ and scripts/workflows/
        |              |
        v              v
      manifests     src/ simulation, IO, helpers
        |              |
        v              v
results/raman/<run>/  JLD2, JSON, PNGs
```

Research drivers in `scripts/research/` may call the same lower layers, but they
are not automatically part of the supported CLI surface.

Docs should point new users to `./fiberlab`, `scripts/canonical/`, and the
supported configs first.
