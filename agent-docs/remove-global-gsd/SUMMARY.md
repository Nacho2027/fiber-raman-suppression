# Summary

## Completed

- Removed all GSD hook registrations from `~/.claude/settings.json`.
- Removed all GSD agent registrations and the GSD hook section from `~/.codex/config.toml`.
- Deleted global GSD skills, agents, hooks, helper payloads, manifests, and CLI shims from `~/.claude`, `~/.codex`, and `~/bin`.
- Left `~/src/gsd-fork` untouched.

## Verified removed

- `~/.claude/hooks/gsd-workflow-guard.js`
- `~/.claude/get-shit-done`
- `~/.codex/get-shit-done`
- `~/bin/gsd-sdk`
- all `gsd-*` entries under `~/.claude/{skills,agents,hooks}`
- all `gsd-*` entries under `~/.codex/{skills,agents,hooks}`

## Remaining references

- `rg` still finds `gsd` strings inside historical backup and session-history files under `~/.claude/backups/`, `~/.codex/history.jsonl`, and `~/.codex/sessions/`.
- Those are inert records, not active hooks, commands, or agent registrations.
