# Amp-on-Phase Refinement

`amp_on_phase` means: first solve phase, then optimize amplitude on that fixed
phase. It is not the first lab command to run.

## When to use it

Use it when you already have a phase solution and want to test whether a small
amplitude refinement improves Raman suppression at nearby operating points.

## Commands

Dry-run:

```bash
julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl   --config smf28_amp_on_phase_refinement_poc --dry-run
```

Run only on suitable compute:

```bash
julia -t auto --project=. scripts/canonical/refine_amp_on_phase.jl   --config smf28_amp_on_phase_refinement_poc
```

## Caveat

The positive result is staged amplitude on fixed phase. Direct joint
phase/amplitude/energy optimization is a negative or deferred research path, not
a promoted method.
