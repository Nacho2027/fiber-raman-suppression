# Multivar Research Supervision Status

Campaign: `20260424T033354Z`

Lane: `multivar`

Target: ephemeral `c3-highcpu-8`

Initial tag: `V-multivar`

Initial command:

```bash
julia -t auto --project=. scripts/research/multivar/multivar_demo.jl
```

Launcher log:

```text
results/burst-logs/parallel/20260424T033354Z/multivar.log
```

## Live Log

### 2026-04-24 03:35 UTC

- Took over supervision for the multivar lane only.
- Confirmed local repo is at `6e950cd Harden campaign tmux launch` with
  unrelated dirty files already present; no cleanup or revert attempted.
- Confirmed Syncthing has one connected peer.
- Read the common supervision rules and multivar prompt.
- Current science context: multivar infrastructure is valid, but prior
  canonical SMF-28 `L=2 m`, `P=0.30 W` results did not beat phase-only:
  `mv_phaseonly` around `-56.9 dB`, `mv_joint_warmstart` recomputed around
  `-47.6 dB`, and cold joint worse/suspect.
- Confirmed the current launcher is still in startup, not failed:
  it refreshed `fiber-raman-burst-template` and began creating
  `fiber-raman-temp-v-multivar-20260424t033354z`.
- No relaunch performed.

Next polling checks:

```bash
tail -n 300 results/burst-logs/parallel/20260424T033354Z/multivar.log
gcloud compute instances list --format='table(name,zone.basename(),machineType.basename(),status,networkInterfaces[0].accessConfigs[0].natIP)' | grep -E 'fiber-raman-temp-v-multivar|fiber-raman-burst' || true
```

### 2026-04-24 03:37 UTC

- Initial ephemeral VM reached SSH readiness but the actual remote command
  failed before Julia started.
- Failure class: local SSH known-host mismatch for recycled GCP host alias,
  not a multivar code or numerical failure.
- Relevant launcher error:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED
Offending ED25519 key in /home/ignaciojlizama/.ssh/google_compute_known_hosts:24
remove with:
ssh-keygen -f "/home/ignaciojlizama/.ssh/google_compute_known_hosts" -R "compute.6535802653958953491"
```

- The helper destroyed `fiber-raman-temp-v-multivar-20260424t033354z`.
- Plan: remove the stale host-key alias and relaunch the same multivar command
  once. This is a launch-infrastructure retry, not a science rerun.

### 2026-04-24 03:39 UTC

- The original `multivar` tmux window exited after the launcher returned
  `rc=255`.
- The offending host-key alias was already absent when checked with
  `ssh-keygen -R`, so no repo or SSH file changed.
- Relaunched the same `V-multivar` command in a new `multivar` tmux window
  under the original campaign session.
- Long-fiber activity is visible in the campaign logs, but is outside this
  lane's scope and was not modified.

### 2026-04-24 03:41 UTC

- User patched `~/bin/burst-spawn-temp` locally so future ephemeral runs ignore
  stale host keys and archive modified results back before VM destruction.
- Per user instruction, the earlier `V-multivar rc=0` run is not
  scientifically accepted because it used the pre-sync helper.
- Supervision target is now the fixed-helper relaunch:
  - tag: `V-multivar2`
  - log: `results/burst-logs/parallel/20260424T033354Z/multivar-fixed.log`
  - command: `julia -t auto --project=. scripts/research/multivar/multivar_demo.jl`
  - VM: `fiber-raman-temp-v-multivar2-20260424t034055z`
- Do not launch a duplicate unless `V-multivar2` clearly fails.

### 2026-04-24 03:43 UTC

- `V-multivar2` failed before any scientific run started.
- First real error in returned heavy log
  `results/burst-logs/V-multivar2_20260424T034205Z.log`:

```text
Package PyPlot ... is required but does not seem to be installed:
 - Run `Pkg.instantiate()` to install all recorded dependencies.
```

- Failure class: ephemeral dependency instantiation issue in the clean
  worktree, not a multivar code/numerical failure.
- Next action: relaunch with an explicit `Pkg.instantiate()` before
  `scripts/research/multivar/multivar_demo.jl`, preserving `V-multivar2` as a
  failed operational log.

### 2026-04-24 03:44 UTC

- Relaunched as `V-multivar3` with dependency preflight:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'; julia -t auto --project=. scripts/research/multivar/multivar_demo.jl
```

- New launcher log:

```text
results/burst-logs/parallel/20260424T033354Z/multivar-fixed2.log
```

### 2026-04-24 03:45 UTC

- `V-multivar3` failed during VM creation before any remote run started.
- Launcher error:

```text
Operation rate exceeded for resource
'projects/riveralab/global/machineImages/fiber-raman-burst-template'.
Too frequent operations from the source resource.
```

- Failure class: GCP machine-image operation rate limit from rapid ephemeral
  retries, not a multivar code/numerical failure.
- No ephemeral VMs remain active after cleanup.
- Next action: wait for the machine-image rate limiter to cool down, then
  relaunch with the same `Pkg.instantiate()` preflight.

### 2026-04-24 03:48 UTC

- Waited three minutes for the machine-image operation rate limit to cool down.
- Confirmed no ephemeral VMs were active.
- Relaunched as `V-multivar4` with the same dependency preflight.
- New launcher log:

```text
results/burst-logs/parallel/20260424T033354Z/multivar-fixed3.log
```

### 2026-04-24 03:49 UTC

- Operational correction received: avoid rapid relaunches against the machine
  image, and use a single `bash -lc ...` command for the whole remote payload
  to avoid top-level semicolon parsing bugs.
- `V-multivar4` was already launched with the older semicolon-form command.
- Process inspection confirmed the command was parsed incorrectly before remote
  execution.
- Cancelled the malformed `V-multivar4` launcher. No ephemeral VMs remained
  after cleanup.
- Next valid retry must wait several minutes and use:

```bash
bash -lc 'julia --project=. -e "using Pkg; Pkg.instantiate()" && exec julia -t auto --project=. scripts/research/multivar/multivar_demo.jl'
```

### 2026-04-24 03:54 UTC

- Completed a five-minute cooldown; no ephemeral VMs were active.
- `V-multivar4` never created a VM; it ended with the same machine-image
  operation-rate error and is not a science run.
- Relaunched as `V-multivar5` with the corrected single-payload command:

```bash
bash -lc 'julia --project=. -e "using Pkg; Pkg.instantiate()" && exec julia -t auto --project=. scripts/research/multivar/multivar_demo.jl'
```

- New launcher log:

```text
results/burst-logs/parallel/20260424T033354Z/multivar-live.log
```

### 2026-04-24 05:02 UTC

- Latest accepted science run is `V-multivar8`, not the earlier failed/retried
  attempts.
- `V-multivar8` completed with `rc=0` on an ephemeral burst VM and copied back
  its modified results archive.
- Key log: `results/burst-logs/V-multivar8_20260424T043923Z.log`.
- Output directory: `results/raman/multivar/smf28_L2m_P030W/`.
- Numerical conclusion:
  - phase-only: `J_after = -40.8 dB`, `Delta-J = -39.30 dB`
  - joint cold start: `J_after = -18.3 dB`, `Delta-J = -16.78 dB`
  - joint warm start: `J_after = -31.2 dB`, `Delta-J = -29.72 dB`
  - warm multivar is still `+9.58 dB` worse than phase-only; cold multivar is
    `+22.52 dB` worse than phase-only
- Visual inspection completed for:
  - `multivar_vs_phase_comparison.png`
  - phase-only standard images
  - cold-start joint standard images
  - warm-start joint standard images
- The returned images were generated before the latest standard-plot cosmetic
  cleanup, so some metadata footers overlap lower labels. This is cosmetic and
  does not affect the negative multivar conclusion.
- Human-facing status note written at
  `docs/status/multivar-canonical-negative-result-2026-04-24.md`.

### 2026-04-24 06:05 UTC

- Follow-up broad ablation `V-mvabl1` was stopped after it completed the
  non-decision `amp_unshaped` case and then spent excessive time in
  `energy_unshaped`.
- Partial `V-mvabl1` result:
  - phase-only reference: `J_after = -40.79 dB`
  - amplitude-only on unshaped input: `J_after = -1.66 dB`
  - conclusion: unshaped amplitude-only is not useful, but this did not answer
    the main closure question.
- Launched focused closure ablation `V-ampphase1` with:

```bash
MV_AMP_PHASE_AMP_ITER=60 julia -t auto --project=. scripts/research/multivar/multivar_amp_on_phase_ablation.jl
```

- `V-ampphase1` completed with `rc=0`, copied results back, released the heavy
  lock, and destroyed the ephemeral VM.
- Output directory:
  `results/raman/multivar/amp_on_phase_20260424T055752Z/`.
- Numerical conclusion:
  - phase-only reference physics objective: `-40.79 dB`
  - amplitude-only on fixed phase physics objective: `-44.34 dB`
  - improvement over phase-only: `-3.55 dB`
  - amplitude range: `[0.908, 1.090]`
  - decision threshold: `3.0 dB`
  - verdict: PASS
- Visual inspection completed for both full standard image sets:
  - `phase_only_reference_phase_profile.png`
  - `phase_only_reference_phase_diagnostic.png`
  - `phase_only_reference_evolution.png`
  - `phase_only_reference_evolution_unshaped.png`
  - `amp_on_phase_phase_profile.png`
  - `amp_on_phase_phase_diagnostic.png`
  - `amp_on_phase_evolution.png`
  - `amp_on_phase_evolution_unshaped.png`
- Interpretation: the broad joint optimizer remains negative/experimental, but
  fixed-phase amplitude shaping is now a promising multivar candidate. It
  should not become lab-default yet; it needs deterministic rerun,
  hardware-constrained export review, and a small robustness check around the
  canonical point.
- Human-facing follow-up status note written at
  `docs/status/multivar-amp-on-phase-positive-result-2026-04-24.md`.

## Decision Rules For This Session

- Do not relaunch unless the existing `V-multivar` lane has clearly failed.
- If the demo completes, verify:
  - `phase_only_L2m_P0p3W_*` standard images
  - `mv_cold_L2m_P0p3W_*` standard images
  - `mv_warm_L2m_P0p3W_*` standard images
  - `multivar_vs_phase_comparison.png`
- If warm joint still fails to beat phase-only, the next high-value ablation is
  an amplitude-only-on-top-of-phase run, not generic optimizer tweaking.
- If amplitude-only does not beat phase-only by at least `3 dB`, document a
  negative/low-value conclusion for current multivar at the canonical point.
- Since amplitude-on-fixed-phase beat phase-only by `3.55 dB`, do not close the
  multivar lane entirely. Close/defer broad joint optimization, and advance only
  the fixed-phase amplitude candidate through validation.

### 2026-04-26 19:30 UTC

- Relaunched the focused amplitude-on-fixed-phase ablation as
  `V-ampphase-repeat2` after one pre-compute machine-image availability
  failure.
- `V-ampphase-repeat2` completed with `rc=0`, copied results back, released the
  heavy lock, and destroyed the ephemeral VM.
- Output directory:
  `results/raman/multivar/amp_on_phase_20260426T1915Z_repeat2/`.
- Numerical conclusion reproduced the 2026-04-24 result:
  - phase-only reference physics objective: `-40.79 dB`
  - amplitude-only on fixed phase physics objective: `-44.34 dB`
  - improvement over phase-only: `-3.55 dB`
  - amplitude range: `[0.908, 1.090]`
  - verdict: PASS
- Amplitude profile details:
  - `8192` bins
  - min `0.908455`, max `1.090233`
  - mean `0.999560`, standard deviation `0.006874`
  - `E_opt = E_ref = 103.522487676`
- Visual inspection completed for both full standard image sets:
  - `phase_only_reference_phase_profile.png`
  - `phase_only_reference_phase_diagnostic.png`
  - `phase_only_reference_evolution.png`
  - `phase_only_reference_evolution_unshaped.png`
  - `amp_on_phase_phase_profile.png`
  - `amp_on_phase_phase_diagnostic.png`
  - `amp_on_phase_evolution.png`
  - `amp_on_phase_evolution_unshaped.png`
- Interpretation: fixed-phase amplitude shaping is reproducible enough to keep
  as a serious research candidate, but it is not lab-default or hardware-ready
  until the repo has an amplitude-aware export schema, hardware-grid
  interpolation policy, clipping/transmission policy, and round-trip validation.
- Human-facing repeatability and handoff note written at
  `docs/status/multivar-amp-on-phase-repeatability-handoff-2026-04-26.md`.
