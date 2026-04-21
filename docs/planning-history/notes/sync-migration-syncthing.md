# Sync migration — Mac ↔ VM via Syncthing

**Decided:** 2026-04-21
**Replaces:** the git-based `sync-planning-to-vm` / `sync-planning-from-vm` helpers + manual force-add ceremony for gitignored files

## Why we're moving

The git-based cross-machine workflow kept biting us. The specific failure modes that killed hours this milestone:

- `phase22_results.jld2` (the full 26-optimum sharpness bundle) generated on the Mac during the S-sharpness overnight run never made it to the VM because `*.jld2` is gitignored. Had to be discovered days later when Phase 33 needed it as a warm start.
- Phase 22's full `.planning/phases/22-sharpness-research/` planning trail (24 standard image sets + PLAN/RESEARCH/CONTEXT) stayed Mac-local for the same reason, requiring a manual force-add pass.
- Every session has been forced to either remember to `git add -f` gitignored planning artifacts OR have the next session rediscover the gap.
- Multi-commit merge ceremony (integrate(phaseN): …) eats time that should go to research.

Git is still the right tool for history, rollback, and GitHub pushes. It is the *wrong* tool for "Mac and VM should see the same files continuously."

## The new setup

**Syncthing** — continuous bidirectional sync daemon. Install once on each machine, point at the repo directory, and it propagates file changes in seconds over any network. NAT-traversing, works with intermittent connectivity (Mac closes its lid → VM keeps working → Mac opens → Syncthing catches up seamlessly).

### Install

- **Mac:** `brew install syncthing` then `brew services start syncthing`
- **VM:** `sudo apt install syncthing` then `systemctl --user enable --now syncthing`
- Both machines: open `http://127.0.0.1:8384` in a browser for the Syncthing UI

### Configure

1. On each machine, note the device ID (Actions → Show ID in the UI)
2. Add the other machine's device ID to each side (Remote Devices → Add)
3. Add the repo directory as a Shared Folder on one side (e.g. Mac → `~/RiveraLab/fiber-raman-suppression`, VM → `~/fiber-raman-suppression`)
4. Share it with the other device; accept on the other side
5. In folder settings → Ignore Patterns, add at minimum:
   ```
   .git
   .DS_Store
   ```
   Do NOT ignore `.planning/`, `.jld2`, `Manifest.toml`, or anything else that git ignores but you want synced. The whole point is Syncthing handles files git won't.

### Conflict behavior

If two machines edit the same file between syncs, Syncthing keeps the most recent version as canonical and renames the other with a `.sync-conflict-<date>-<device>` suffix. With our session-namespace discipline (Rule P1), simultaneous edits on the same file are rare.

## What each tool is for now

| Concern | Tool |
|---|---|
| Continuous Mac ↔ VM file movement | **Syncthing** |
| Git history / rollback / branches | **git** (local on each machine, Syncthing keeps repos aligned) |
| Push to GitHub (origin/main for Ignacio's records) | **git push** (from either machine; Syncthing then mirrors the updated `.git` — but prefer pushing from one side to avoid `.git` conflicts) |
| Heavy Julia compute | **burst-run-heavy on burst VM** (unchanged) |

## Migration checklist

- [ ] Install Syncthing on Mac and VM
- [ ] Pair the two devices and share the repo directory
- [ ] Set ignore patterns to `.git` + `.DS_Store` only
- [ ] Verify a test file created on Mac appears on VM within ~30 seconds
- [ ] Deprecate `sync-planning-to-vm` and `sync-planning-from-vm` (leave on disk but don't use)
- [ ] Update CLAUDE.md's Multi-Machine Workflow section to reflect Syncthing as primary
- [ ] Remove `*.jld2` and `.planning/` from `.gitignore` reasoning around "needs Syncthing helpers" — Syncthing now handles these natively

## What git still does (for clarity)

- `git commit` + `git push` for history and GitHub presence — commits should still be atomic per phase/plan
- Session branches (`sessions/<tag>`) for parallel-agent discipline (Rule P2) — still useful for review and integration
- Merges to main at phase integration time — still useful for marking "landed" state

The difference: you no longer rely on `git push` to move files between your Mac and your VM for *live collaboration*. Syncthing does that continuously. Git is for deliberate version control.
