# Researcher Playbook

[<- docs index](../README.md) | [configurable experiments](./configurable-experiments.md)

Start here when a config change is not enough.

`./fiberlab` can check configs, list implemented objectives and variables, run
smoke cases, and compare saved results. It cannot create new physics from a
TOML name. If the metric or control is new, implement it in Julia first.

That is the intended abstraction: a researcher should be able to try a new
fiber-optic optimization question without rewriting the command runner every
time. The reusable pieces are configs, objective contracts, variable contracts,
manifests, plots, and comparison tables. The non-reusable piece is the physics;
that still has to be written and tested.

## 0. Start Here

Run:

```bash
./fiberlab playbook
./fiberlab explore list
./fiberlab capabilities
```

Then pick one of four cases.

## Path A: Config-Only Experiment

Use this when the system, variable, and objective already exist.

Examples:

- Change `L_fiber`, `P_cont`, `Nt`, or `time_window`.
- Switch between available objectives such as `raman_band`, `raman_peak`, or
  currently promoted non-Raman objectives.
- Use an existing variable set such as `phase`, `phase+amplitude+energy`, or
  `gain_tilt`.
- Tune solver iteration limits, scalar bounds, regularizer weights, and
  exploratory plot views.

Commands:

```bash
cp configs/experiments/templates/single_mode_phase_template.toml configs/experiments/my_experiment.toml
$EDITOR configs/experiments/my_experiment.toml
./fiberlab explore plan my_experiment
./fiberlab check config my_experiment
./fiberlab explore run my_experiment --local-smoke
./fiberlab explore compare results/raman --contains my_experiment
```

The checker reports:

- config schema and numeric sanity;
- whether the variable/objective/solver combination is implemented;
- optimizer-vector layout;
- required artifacts and output hooks;
- whether the run should be local, heavy, or blocked;
- generated artifact completeness after execution.

## Path B: Heavy Regime Experiment

Use this for MMF, long-fiber, or other compute-heavy regimes.

Commands:

```bash
./fiberlab explore plan grin50_mmf_phase_sum_poc
./fiberlab check config grin50_mmf_phase_sum_poc
./fiberlab explore run grin50_mmf_phase_sum_poc --heavy-ok --dry-run
```

The dry-run prints the dedicated command instead of launching expensive compute
behind your back. Run that command on a workstation, cluster, cloud VM,
or the Rivera Lab burst setup.

Current heavy results:

- MMF has a completed exploratory validation result with `Nt=8192`,
  `time_window=96 ps`, and boundary checks passing.
- Long-fiber has completed milestone results, but the config runner still
  blocks routine local execution.

## Path C: New Objective

Use this when the score you want to optimize is new.

Example: "I want to optimize pulse width, not Raman leakage."

Start with:

```bash
./fiberlab scaffold objective pulse_width \
  --description "Minimize output temporal pulse width." \
  --variables gain_tilt
./fiberlab objectives --validate
```

The scaffold is planning-only. It creates metadata and a Julia stub.
It does not become executable until the objective has:

- a defined physical metric and units;
- normalization/sign convention;
- compatible variables;
- a gradient strategy or a solver restriction such as bounded scalar search;
- output metrics/plots needed to inspect the result;
- a smoke config.

Use the validation commands below while developing it. Add regression tests
before telling anyone else to rely on it.

Minimum self-check before anyone trusts it:

```bash
./fiberlab objectives --validate
./fiberlab explore plan <new_config>
./fiberlab check config <new_config>
./fiberlab explore run <new_config> --local-smoke
./fiberlab check run <result_dir>
./fiberlab explore compare results/raman --contains <new_config>
```

## Path D: New Optimized Variable

Use this when the thing you want to change is new.

Examples:

- mode weights;
- launch angle;
- fiber scalar;
- reduced-basis phase coefficients;
- modal phase offsets.

Start with:

```bash
./fiberlab scaffold variable mode_weights \
  --description "Optimize normalized modal launch weights." \
  --units "normalized modal power fractions" \
  --bounds "nonnegative and sum to one" \
  --objectives mmf_sum
./fiberlab variables --validate
```

A variable is not just a name. To promote it, the repo needs:

- units and bounds/projection behavior;
- optimizer-vector shape;
- pack/unpack behavior;
- how the simulator consumes the variable;
- compatible objectives;
- variable-specific artifacts;
- at least one smoke config.

## What Outputs Should Exist?

A successful exploratory run should leave enough evidence that someone can
reopen the folder later.

Minimum common outputs:

```text
run_config.toml
run_manifest.json
opt_result.jld2
opt_explore_summary.json
opt_explore_overview.png
```

Phase-like runs should also have the standard image set:

```text
opt_phase_profile.png
opt_evolution.png
opt_phase_diagnostic.png
opt_evolution_unshaped.png
```

Variable-specific runs should add variable-specific artifacts, for example:

```text
opt_gain_tilt_profile.png
opt_energy_metrics.json
opt_amplitude_mask.png
opt_pulse_metrics.json
```

Use:

```bash
./fiberlab check run <result_dir>
```

This catches missing artifacts. It does not prove the physics is true; it proves
the run left the evidence the engine knows how to require.

## How To Compare Runs

Use:

```bash
./fiberlab explore compare results/raman --top 10
```

This includes lab-ready and exploratory runs. It labels status instead of hiding
experimental work:

- `Lab Ready`: passed the strict run checks.
- `Readiness`: mechanical run status such as `complete`, `not_converged`, or
  `missing_artifacts`.
- `Run Context`: `run`, `explore_local_smoke`, or another context from the
  manifest.
- `Compare Ready`: whether the run has enough metadata for stronger handoff.
- `Manifest Missing`: what still blocks promotion.

Use comparison to find candidates. Use plots, metrics, and physics review to
decide whether the candidate is scientifically meaningful.

## What Works Today?

Good current paths:

- supported single-mode phase Raman runs;
- configurable single-mode experiments;
- experimental single-mode multivariable runs;
- bounded scalar search over `gain_tilt`;
- non-Raman smoke runs that use implemented objective contracts;
- result manifests, generic exploratory overview plots, and comparison tables;
- heavy MMF/long-fiber planning and completed result evidence.

Still not fully automatic:

- arbitrary new full-grid objectives without gradients;
- arbitrary new optimized variables;
- local laptop execution of heavy MMF/long-fiber jobs;
- vendor-specific SLM export.

Rule:

```text
If the physics contract exists, edit TOML.
If the physics contract does not exist, scaffold it, implement it in Julia, then
run the checks.
```

## One-Minute Decision Tree

```text
Can I express the idea by changing an existing config?
  yes -> Path A.
  no  -> continue.

Is it MMF, long fiber, or otherwise heavy?
  yes -> Path B.
  no  -> continue.

Is the score/cost new?
  yes -> Path C.
  no  -> continue.

Is the optimized knob new?
  yes -> Path D.
  no  -> run ./fiberlab capabilities and check whether the combination is supported.
```
