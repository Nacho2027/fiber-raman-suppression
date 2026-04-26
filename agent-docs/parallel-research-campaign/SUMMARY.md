# Parallel Research Campaign Plan

Date: 2026-04-24

## Architecture

Run three Codex-supervised lanes in parallel from `claude-code-host`:

- **MMF** on the permanent `fiber-raman-burst` VM
- **multivar** on an ephemeral burst VM
- **long-fiber** on another ephemeral burst VM

Codex should poll **local launcher logs** produced on `claude-code-host`,
not depend on direct remote tmux inspection. This is more stable and keeps the
polling surface uniform across permanent and ephemeral machines.

Operational helpers added:

- [parallel_research_campaign.sh](/home/ignaciojlizama/fiber-raman-suppression/scripts/ops/parallel_research_campaign.sh)
- [parallel_research_lane.sh](/home/ignaciojlizama/fiber-raman-suppression/scripts/ops/parallel_research_lane.sh)
- [parallel_research_poll.sh](/home/ignaciojlizama/fiber-raman-suppression/scripts/ops/parallel_research_poll.sh)

## Recommended Compute Split

### Multimode

- Machine: permanent burst VM
- Why: likely the heaviest and least mature lane; best to keep it on the known
  machine with the most stable storage and logs
- First command:
  - `julia -t auto --project=. scripts/research/mmf/baseline.jl`
- Expected wall time:
  - first-pass regime/cost map: `6-12 h`
  - deeper `{φ, c_m}` follow-up: `8-24 h`

### Multivar

- Machine: ephemeral VM, suggested `c3-highcpu-8`
- Why: medium-heavy but independent; good fit for a secondary worker
- First-pass scientific program:
  - amplitude-only warm start from phase-only optimum
  - two-stage amplitude-first then joint release
  - only then a wider regime map if positive
- Current repo default command in the launcher is still the existing demo:
  - `julia -t auto --project=. scripts/research/multivar/multivar_demo.jl`
- Expected wall time:
  - rescue/ablation pass: `2-8 h`
  - regime map: `8-24 h`

### Long-fiber

- Machine: ephemeral VM, suggested `c3-highcpu-8`
- Why: continuation-style single-lane runs are long but operationally clean
- First-pass scientific program:
  - strengthen the 100 m result
  - then ladder continuation toward 200 m
- Current repo default command in the launcher is:
  - `LF100_MODE=fresh LF100_MAX_ITER=25 julia -t auto --project=. scripts/research/longfiber/longfiber_optimize_100m.jl`
- Expected wall time:
  - 100 m hardening pass: `2-6 h`
  - 200 m ladder campaign: `12-36 h`

## Important Constraints

1. Do not launch from a dirty worktree unless the mismatch with remote `main`
   is intentional. The lane helper refuses by default for this reason.
2. Full 3-lane parallelism needs enough `C3_CPUS` quota.
3. If quota is insufficient, the right fallback is:
   - keep MMF on permanent burst
   - serialize multivar and long-fiber on one ephemeral worker
   - not overload the permanent VM
4. Every lane that produces `phi_opt` must still leave the standard image set.
5. Raw JLD2/JSON output is not a completed research result. Each lane must also
   produce plots that make the physics readable by a human.

## Plot Guarantees

The canonical standard image set remains mandatory for every optimized phase:

- `{tag}_phase_profile.png`
- `{tag}_evolution.png`
- `{tag}_phase_diagnostic.png`
- `{tag}_evolution_unshaped.png`

Lane-specific plot expectations:

- **MMF:** total spectrum, per-mode spectrum, phase profile, convergence, and
  regime/cost heatmaps for sweeps.
- **Multivar:** phase-only versus multivar spectra, convergence comparison,
  amplitude-mask plots when amplitude is active, and ablation heatmaps or bar
  charts.
- **Long-fiber:** length-ladder heatmaps/tables, `J(z)` validation curves,
  phase profiles by length, and β-order or multistart comparison figures.

Verification update: the existing MMF, multivar, and long-fiber entrypoints were
checked for `save_standard_set(...)` usage. The MMF baseline plotting path also
had an undefined objective metadata reference fixed in
`scripts/research/mmf/mmf_raman_optimization.jl`, and the script now loads
cleanly in a local Julia smoke check.

## Codex Polling Loop

Launch:

```bash
scripts/ops/parallel_research_campaign.sh
```

Poll:

```bash
scripts/ops/parallel_research_poll.sh --log-root results/burst-logs/parallel/<campaign-id>
```

Or use:

```bash
tmux capture-pane -pt research-parallel-<campaign-id>:mmf
tmux capture-pane -pt research-parallel-<campaign-id>:multivar
tmux capture-pane -pt research-parallel-<campaign-id>:longfiber
```

## Recommended Scientific Order Inside The Parallel Campaign

### MMF

1. Finish the baseline regime/cost map.
2. Decide whether `{φ, c_m}` is worth a deep pass.
3. Only then run deeper MMF exploration.

Update, 2026-04-26:

- The Phase 36 MMF run produced large apparent suppression in the threshold and
  aggressive regimes, but the trust label was `invalid-window` with edge
  contamination. Treat those gains as unresolved, not as publishable physics.
- The next MMF step is now `scripts/research/mmf/mmf_window_validation.jl`.
  It reruns only threshold/aggressive GRIN-50 cases with deliberately larger
  temporal windows and writes standard plots plus
  `results/raman/phase36_window_validation/mmf_window_validation_summary.md`.
- Do not launch joint `{φ, c_m}` or broad fiber-type exploration until this
  window-validation pass decides whether the apparent MMF headroom is real.

### Multivar

1. Test whether amplitude-on-top-of-phase is real.
2. Test the two-stage path.
3. Only then widen the regime map.

Update, 2026-04-26:

- The generic joint phase+amplitude L-BFGS route remains a negative/weak result
  at the canonical point.
- The fixed-phase amplitude refinement is the active high-value sublane:
  the first pass improved the phase-only result by `3.55 dB`, and two repeat /
  bound-sensitivity ephemerals are now running.

### Long-fiber

1. Harden the 100 m claim.
2. Run continuation to 200 m.
3. Only then spend time on more production-ready workflow polishing.

Update, 2026-04-26:

- A fresh 100 m long-fiber run is active on an ephemeral VM with
  `LF100_MODE=fresh LF100_MAX_ITER=25`.
- Keep the interpretation narrow until this run returns: supported claim is
  still 50-100 m single-mode exploratory physics, not a production-ready
  long-fiber platform.
