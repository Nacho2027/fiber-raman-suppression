# Phase 18 — MMF Raman Baseline: Execute the Aggressive Config

**Opened:** 2026-04-19 (integration of Session C)
**Status:** Code complete, tests pass, **production run pending**.
**Owner:** next MMF-focused agent (separate from the integration pass).

---

## TL;DR for the next agent

Session C built a complete M=6 multimode-fiber Raman-suppression optimizer and validated it (13/13 correctness tests pass). But the one production run that happened used a **sub-soliton config** (N_sol ≈ 0.9) and correctly found zero headroom to suppress. The **aggressive config that would actually exercise Raman** (L=2m, P=0.5W on GRIN-50) was queued on the burst VM but the VM became unreachable before the run confirmed. **Your job:** re-launch that aggressive run, produce the first real M=6 baseline numbers, fill in the SUMMARY, and decide whether to promote Phase 17 (joint φ + c_m optimization) to active work.

---

## What's already done (trust these, don't redo)

### Code (all on `main` as of this merge)

| File | Purpose |
|---|---|
| `scripts/mmf_fiber_presets.jl` | `:GRIN_50` (OM4-like, 25μm radius, NA=0.2, α=2, M=6) + `:STEP_9` presets + default mode weights |
| `scripts/mmf_setup.jl` | `setup_mmf_raman_problem()` — wraps `MultiModeNoise.get_disp_fiber_params` + `get_initial_state`. **Does NOT call `setup_raman_problem`** (that's SMF-only). |
| `src/mmf_cost.jl` | Three cost variants: `mmf_cost_sum` (baseline, integrating-detector), `mmf_cost_fundamental` (LP01-only), `mmf_cost_worst_mode` (log-sum-exp smooth-max) |
| `scripts/mmf_raman_optimization.jl` | `cost_and_gradient_mmf(φ, c_m, uω0_base, fiber, sim, band_mask; variant=:sum, λ_gdd, λ_boundary)`, `optimize_mmf_phase`, `plot_mmf_result`, `run_mmf_baseline` |
| `scripts/mmf_m1_limit_run.jl` | M=1 reference via the protected SMF optimizer — gives apples-to-apples comparison |
| `scripts/mmf_joint_optimization.jl` | Joint `(φ, c_m)` optimizer stub for Phase 17 (not needed for this phase) |
| `scripts/mmf_run_phase16_all.jl` | End-to-end runner — 3 seeds × 2 configs (mild + aggressive) |
| `scripts/mmf_run_phase16_aggressive.jl` | **This is the one to launch.** Aggressive config (L=2m, P=0.5W, 1 seed, M=6 + M=1). |
| `scripts/mmf_smoke_test.jl` | Fast smoke (Nt=2^10, L=0.1m) — use to sanity-check after any code change |
| `scripts/mmf_analyze_phase16.jl` | Post-processor: reads the JLD2 and writes markdown + figures |
| `test/test_phase16_mmf.jl` | 4 testsets, 13 assertions. **Run these before trusting the stack.** |

### Key correctness assertions (already passing on burst VM)

- **Energy conservation at M=6**: `|E_in − E_out| / E_in < 1e-4` at L=0.3m (rel_loss = 2.937e-5).
- **M=1-limit equivalence**: seeding the M=6 cost with M=1 / LP01-only launch reproduces the SMF `cost_and_gradient` to `max|ΔJ_dB| < 0.1 dB` and `max|Δ∇J| / max|∇J| < 1e-3`.
- **FD gradient check at M=6**: 5 random φ indices, ε=1e-5, rel_err max ≈ 2e-6.
- **Shape sanity**: 6/6 pass — output `∂J/∂φ` is `(Nt,)` not `(Nt, M)` after the mode-sum reduction.

All 13 assertions took ≈ 5m36s on `julia -t 4` on the burst VM. Good rerun cadence is `make smoke` (not defined yet — add if useful) or `julia --project=. -t auto test/test_phase16_mmf.jl`.

### Session C's own decision log

Read these **before touching the code**:
- `.planning/sessions/C-multimode-decisions.md` — D1–D8 with rationale (why shared φ across modes, why `:sum` cost, why the LP01-dominant mode-weights, why GRIN_50).
- `.planning/sessions/C-standdown.md` — final handoff with landmines.
- `.planning/phases/16-multimode-raman-suppression-baseline/16-CONTEXT.md` — original phase goal + plan.
- `.planning/phases/16-multimode-raman-suppression-baseline/16-01-SUMMARY.md` — has `_TBD_` rows waiting for your numbers.
- `.planning/phases/17-mmf-joint-phase-mode-optimization/17-CONTEXT.md` — Phase 17 scaffold if this phase succeeds.

---

## What you need to do

### Step 1 — re-verify the stack on burst VM

The code is old enough (2026-04-17) that dep resolution or a post-merge collision may have shifted things. Do a clean test run before any production launch.

```bash
# On claude-code-host:
burst-start
burst-ssh "cd fiber-raman-suppression && git pull && \
    ~/bin/burst-run-heavy C2-tests \
    'julia -t auto --project=. test/test_phase16_mmf.jl'"
# Tail the log (path printed by burst-run-heavy)
burst-ssh "tail -f fiber-raman-suppression/results/burst-logs/C2-tests_*.log"
```

Success: all 4 testsets green. If anything red, stop and investigate — likely a stale-API reference (e.g., `compute_noise_map_modem` was archived 2026-04-17; check that no new Session-B move caught C).

### Step 2 — smoke test

```bash
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy C2-smoke \
    'julia -t auto --project=. scripts/mmf_smoke_test.jl'"
```

Expected wall time: ~1–2 min. Produces no JLD2; purely a precompile + shape check.

### Step 3 — launch the aggressive baseline

```bash
burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy C2-agg \
    'julia -t auto --project=. scripts/mmf_run_phase16_aggressive.jl'"
```

**Config** (hard-coded in the script): GRIN-50, L=2m, P_cont=0.5W, pulse FWHM 185 fs, `time_window = 20` ps (double baseline — critical, see Landmine 4 below), seed=42, max_iter=30 L-BFGS, both M=6 and M=1.

**Expected wall time**: 30–90 min. Watch-dog-friendly on a 22-core VM.

**Expected physics at this config** (per Renninger & Wise 2013, Wright + Ziegler 2020, and session C's own literature review in `C-multimode-decisions.md`):
- N_sol ≈ 2–3 → firmly Raman-active regime.
- J_ref at M=6 *likely higher* (closer to 0 dB) than J_ref at M=1 because intermodal XPM/Raman distribute Kerr peaks across more modes.
- ΔJ_dB from optimization *likely smaller* at M=6 than at M=1 because the shaper has fewer effective DoF per mode.
- **If ΔJ_dB(M=6) > ΔJ_dB(M=1), that's interesting physics** — shared φ has unlocked a multimode-specific suppression pathway. Follow up.

### Step 4 — fill in the SUMMARY

Open `.planning/phases/16-multimode-raman-suppression-baseline/16-01-SUMMARY.md`, replace the `_TBD_` rows with the JLD2 numbers, and commit.

Expected artifacts on disk after the run:
- `results/raman/phase16/phase16_summary.jld2`
- `results/raman/phase16/aggressive_M6_seed42.jld2`
- `results/raman/phase16/aggressive_M1_seed42.jld2`
- `results/raman/phase16/*_phase_profile.png`, `*_evolution.png`, `*_phase_diagnostic.png`, `*_evolution_unshaped.png` (the 4-PNG standard set — driver already wires this)

### Step 5 — decide on next work

Three seeds Session C planted (`.planning/seeds/mmf-*.md`):
- **(a) joint (φ, c_m) optimization** — the Rivera-lab-connected direction. `scripts/mmf_joint_optimization.jl` is the starting stub. This is the one most worth promoting to Phase 17.
- **(b) length-generalization study** — does the optimal φ at L=1m transfer to 0.5/2/5m? Session F showed it does at M=1; open question at M=6.
- **(c) fiber-type comparison** — GRIN-50 vs STEP-9 side-by-side.

Pick (a) if the aggressive baseline shows non-trivial suppression at M=6. Pick (b) if the baseline is good and you want a quick follow-up. Pick (c) for breadth.

---

## Landmines / non-obvious things

1. **`.planning/` is `.gitignore`'d.** The 10 MMF planning docs are on main only because they were force-added in commit `ee7e73c` on `sessions/C-multimode` before integration. If you create new planning files, you must `git add -f` them.
2. **`scripts/mmf_m1_limit_run.jl` calls `setup_raman_problem` with `fiber_preset = :SMF28_beta2_only`.** This preset lives in `scripts/common.jl::FIBER_PRESETS`. It was present as of commit `aa2e9b3` and is still present after the 2026-04-19 integration pass. If anyone later renames SMF presets, this script will break — add a regression test if you touch it.
3. **The mild config (L=1m, P=0.05W) is a CORRECT zero-improvement result, not a bug.** N_sol ≈ 0.9 → sub-soliton → no Raman to suppress. Don't "fix" `mmf_run_phase16_all.jl`'s mild-config run — the aggressive driver is the one that exercises the physics.
4. **`scripts/mmf_run_phase16_aggressive.jl::run_m6` uses `time_window = 20.0` ps** (double the 10-ps baseline default) because at P=0.5W the SPM spectral broadening dominates. If you copy this driver to a smaller-power config, shrink the window or you waste grid points. If you raise P further, verify the window via `recommended_time_window()`.
5. **`scripts/mmf_raman_optimization.jl` includes `scripts/visualization.jl`** (read-only via `include`) to pull in the plotters that `save_standard_set` needs. If someone changes `plot_optimization_result_v2` or `plot_phase_diagnostic` signatures, this driver also needs updating.
6. **Protected-file rule.** Session C touched NO shared files (`scripts/common.jl`, `scripts/raman_optimization.jl`, `scripts/sharpness_optimization.jl`, `src/simulation/*.jl`). Keep it that way — MMF work lives in its own namespace. If you need shared-file edits, escalate.
7. **Rule P5 (burst-run-heavy) is mandatory.** Never `tmux new -d 'julia ...'` directly. Always `~/bin/burst-run-heavy <tag> '<cmd>'` so the watchdog and heavy-lock can do their job. Session C learned this the hard way during the 2026-04-17 burst-VM lockup.
8. **Session C's queued burst-VM job** (tag `C-phase16-agg`, PID 16617 at handoff) may still be alive. Before launching a new aggressive run, check `burst-ssh "~/bin/burst-status"` and either wait for it or `~/bin/burst-run-heavy`-cancel. If it completed while the VM was back up, its log is at `results/burst-logs/C-phase16-agg_*.log` on the burst VM — grep for `phase16_summary.jld2` to see if it actually saved.
9. **Ephemeral-VM orphans: none as of handoff.** Session C's 4 spawn attempts were all rejected by GCP quota and destroyed by the trap. Still worth running `~/bin/burst-list-ephemerals` once when you start.

---

## Success criteria

- [ ] `julia test/test_phase16_mmf.jl` → 13/13 pass on current main.
- [ ] Aggressive baseline JLD2 on disk: `results/raman/phase16/aggressive_M6_seed42.jld2` (+ M=1 counterpart).
- [ ] Standard 4-PNG set present for both M=6 and M=1.
- [ ] `16-01-SUMMARY.md` has real numbers in all the `_TBD_` cells.
- [ ] At least one-paragraph physics interpretation written (ΔJ_dB comparison M=6 vs M=1; any surprises).
- [ ] Decision on next step: promote (a), (b), or (c) from seeds — or park all three and move on.
- [ ] Burst VM stopped when done (`burst-stop`).

## Related follow-ups in `.planning/phases/18-*/`

- `18-multivar-convergence-fix` — Session A's joint-{φ, A, E} L-BFGS bug at M=1. Independent; could share a preconditioning insight with this phase if the M=6 L-BFGS also misbehaves.
- `18-sharp-ab-execution` — Session G's unrun sharpness A/B. Independent.
- `18-cost-config-c` — Session H's HNLF high-power hang. Probably related to the same "long max_iter + multiple competing basins" pathology that might hit the aggressive MMF config.

If you hit long hangs at M=6, consider the same mitigation Phase 18-cost-config-c recommends: shorter `max_iter`, more aggressive early-stop (`|grad| < 1e-4` OR `ΔJ < 0.1 dB over 5 iter`), and live log-tailing.
