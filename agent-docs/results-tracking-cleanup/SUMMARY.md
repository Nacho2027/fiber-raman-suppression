# Summary

- Reduced tracked `results/**` content to durable summaries, validation notes, and fixtures.
- Untracked generated PNG sets, burst logs, and non-essential run-output payloads without deleting local files.
- Tightened `.gitignore` so routine result images, logs, and JLD2s stay local by default.
- Updated `AGENTS.md` and `CLAUDE.md` so agents no longer treat `git pull` as a mandatory session-start action in the Syncthing workflow.
