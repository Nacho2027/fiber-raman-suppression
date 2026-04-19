# ⚠️  BIG WARNING — Session G (sharp-ab) is BROKEN

**Broken as of:** 2026-04-19 integration pass.
**Cause (per user):** Session G ran into Opus 4.7-side issues mid-Phase 16 and the agent never executed any of its 3 committed scripts on the burst VM.

## What's here

Three Julia drivers were committed on `sessions/G-sharp-ab` and are now in `main`:

- `scripts/sharp_ab_slim.jl`  — A/B pair: vanilla vs sharpness-aware optimizer
- `scripts/sharp_robustness_slim.jl` — post-hoc robustness analysis of the pair
- `scripts/sharp_ab_figures.jl` — figure-generation wrapper

## What's NOT here

- **Zero JLD2 result files.** The drivers were never run.
- **Zero FINDINGS.md.** No physics conclusion exists.
- **No standard-images set** (the mandatory 4-PNG output for any `phi_opt`).
- **No verification** that the scripts actually run on the current main.

## Before you re-use any of this

1. **Read the scripts end-to-end.** They may reference stale API (Session G forked before Phase 15 determinism, before Session B's `src/_archived` move, and likely before Session A's multivar-phi_opt storage schema changes). Compile-check via `julia --project -e 'include("scripts/sharp_ab_slim.jl")'` before launching a run.
2. **Wire `save_standard_set(...)` at the end** if it's missing. Phase-14 drivers are among the 4 Session B flagged as un-wired (see the sibling commit `fix(viz): wire save_standard_set into four legacy drivers`). `sharp_ab_slim.jl` needs to be checked too.
3. **Use the burst-run-heavy wrapper** (Rule P5). Do not launch these with bare `tmux new ... julia`.

## What "done" looks like for the follow-up

Execute the 3 drivers on the burst VM in sequence:

```
burst-ssh "cd fiber-raman-suppression && git pull && ~/bin/burst-run-heavy \
    G2-sharp-ab 'julia -t auto --project=. scripts/sharp_ab_slim.jl'"
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy \
    G2-robustness 'julia -t auto --project=. scripts/sharp_robustness_slim.jl'"
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy \
    G2-figures 'julia -t auto --project=. scripts/sharp_ab_figures.jl'"
```

Then produce a `FINDINGS.md` in `results/raman/phase14-sharp-ab/` with the A/B verdict (does sharpness-aware beat vanilla on robustness? by how much?).

## Do NOT

- Trust results in any JLD2 that predates 2026-04-19 from an earlier aborted G run — the agent never completed one.
- Merge any `sharp_*.jld2` found loose in the repo without verifying provenance.
