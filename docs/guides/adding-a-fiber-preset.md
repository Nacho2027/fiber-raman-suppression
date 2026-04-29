# Adding a Fiber Preset

Add a preset only when the parameters are documented and a small run or dry-run
can check the wiring.

## Where

Most supported presets are registered in `scripts/common.jl`. Config-driven
experiments reference those names from TOML.

## Steps

1. Add the preset with units stated next to each physical value.
2. Add or update a small config that uses it.
3. Run a validation command:

```bash
./fiberlab validate
julia -t auto --project=. scripts/canonical/optimize_raman.jl --list
```

4. Run a smoke or dry-run before any expensive campaign.
5. Update docs only if the preset is meant for other users.

Do not bury calibration assumptions in a config name. Put them in comments or a
status note.
