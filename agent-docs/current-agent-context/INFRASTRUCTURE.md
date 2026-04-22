# Infrastructure Notes

This file preserves the durable parts of the old GCP setup and provisioning notes without dragging forward GSD-era workflow assumptions.

Source artifacts:

- `.planning/quick/260416-gcp-setup/SUMMARY.md`
- `.planning/todos/pending/provision-gcp-vm.md`

## What still matters

- The project uses a split-machine model:
  - local Mac for primary editing and local work
  - `claude-code-host` for remote sessions and orchestration
  - `fiber-raman-burst` for heavy Julia compute
- The Mac and `claude-code-host` working trees are now intended to stay in live sync via Syncthing.
- `.git` is not part of that sync. Syncthing moves the working tree; git still records history and GitHub pushes.
- The helper-script model is operationally important:
  - `burst-start`
  - `burst-stop`
  - `burst-ssh`
  - `burst-status`
- Burst is still explicit-transfer infrastructure, not part of the live sync mesh.
- The big invariant is still the same: heavy simulation work belongs on the burst VM, not the always-on host.

## What became historical

- The original provisioning checklist is no longer active runbook material.
- One-time setup details such as package installation, OAuth bootstrap, and initial `.planning` sync mechanics are preserved only as history.

## Agent guidance

- Treat `CLAUDE.md` as the authoritative live compute-discipline document.
- Use this file only for context on why the split-machine setup exists and what classes of helper scripts/hosts are expected to be present.
- If host specs, IPs, or helper commands drift, update `CLAUDE.md` first and then update this note if needed.
