# GSD local patches — strict workflow guard + gsd-sdk query shim

This directory carries two files distributed via `sync-planning-to-vm` to
`claude-code-host` (and from there to `fiber-raman-burst` / ephemeral burst VMs):

1. **`gsd-workflow-guard.js`** → patched `~/.claude/hooks/gsd-workflow-guard.js`
2. **`gsd-sdk.shim`** → `~/bin/gsd-sdk` (workaround for upstream issue #2414)

Both patches are local-only, reversible, and do not modify the installed
GSD package. They survive `/gsd-update` (the hook may need re-copying if an
update rewrites it; the shim is untouched).

---

## What the patch does

Adds a new enablement level `hooks.workflow_guard_strict: true` (read from
`.planning/config.json`) that makes the hook return a `PreToolUse` **deny**
instead of an advisory warning. The existing `hooks.workflow_guard: true` soft
mode is preserved. The patch also extends the allow-list to include Claude
Code's own state directories (`~/.claude/projects/`, `~/.claude/hooks/`,
`~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/commands/`,
`~/.claude/get-shit-done/`, settings, keybindings), so memory writes and
settings edits are never blocked.

Default behavior is unchanged for any project that does NOT set
`workflow_guard_strict` — the hook only warns, or stays silent if neither flag
is set.

## Install on a new machine (claude-code-host, burst VM, etc.)

```bash
# 1. Patched workflow guard (enforcement)
cp ~/fiber-raman-suppression/.planning/notes/gsd-hook-patch/gsd-workflow-guard.js \
   ~/.claude/hooks/gsd-workflow-guard.js
chmod +x ~/.claude/hooks/gsd-workflow-guard.js
node --check ~/.claude/hooks/gsd-workflow-guard.js && echo "hook syntax OK"

# 2. gsd-sdk query shim (unblocks /gsd-add-phase, /gsd-autonomous, etc.)
mkdir -p ~/bin
cp ~/fiber-raman-suppression/.planning/notes/gsd-hook-patch/gsd-sdk.shim \
   ~/bin/gsd-sdk
chmod +x ~/bin/gsd-sdk

# Ensure ~/bin is ahead of the real gsd-sdk on PATH.  If `which gsd-sdk`
# returns ~/bin/gsd-sdk, you're good.  If not, add this to ~/.zshrc or
# ~/.bashrc near the TOP of the file:
#   export PATH="$HOME/bin:$PATH"
# then restart the shell.

which gsd-sdk            # should print $HOME/bin/gsd-sdk
gsd-sdk query config-get workflow.discuss_mode   # should print "discuss" or similar
gsd-sdk --version        # should fall through to real @gsd-build/sdk (v0.1.0)
```

Both patches are picked up on next invocation — no daemon to restart.

## Verify it works

```bash
# Should DENY a source-file edit when strict is on:
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PWD"'/src/simulation/simulate_disp_mmf.jl"},"cwd":"'"$PWD"'"}' \
  | node ~/.claude/hooks/gsd-workflow-guard.js

# Should silently ALLOW memory writes:
echo '{"tool_name":"Write","tool_input":{"file_path":"'"$HOME"'/.claude/projects/foo/memory/bar.md"},"cwd":"'"$PWD"'"}' \
  | node ~/.claude/hooks/gsd-workflow-guard.js ; echo "(exit $?)"
```

## Adding GSD for another runtime (Codex, OpenCode, Gemini CLI)

Don't run the installer blind — it can overwrite the patched hook. Use the
wrapper in this directory, which snapshots + diffs + auto-restores:

```bash
bash ~/fiber-raman-suppression/.planning/notes/gsd-hook-patch/make-safe-codex-install.sh --codex --global

# Skip the confirm prompt:
YES=1 bash ~/fiber-raman-suppression/.planning/notes/gsd-hook-patch/make-safe-codex-install.sh --codex --global
```

What it does:
1. Backs up hook + shim into `~/.claude/gsd-backups/<timestamp>/`
2. Prints `npx get-shit-done-cc --help` so you can confirm the exact flag
3. Runs the installer with your args
4. Diffs hook hash — restores from backup if changed
5. Checks shim is still in place — restores if missing
6. Smoke-tests both (shim routing + hook deny on a fake source-file edit)

Your existing `~/bin/gsd-sdk` shim also helps the new runtime for free —
Codex-side skills call `gsd-sdk query` too and will route through it.

## After `/gsd-update`

A GSD update can overwrite `~/.claude/hooks/gsd-workflow-guard.js`. To restore:

```bash
cp ~/fiber-raman-suppression/.planning/notes/gsd-hook-patch/gsd-workflow-guard.js \
   ~/.claude/hooks/gsd-workflow-guard.js
```

Or use `/gsd-reapply-patches` if the GSD install tree has been configured to
track this patch through the official patch-management flow.

## Upstream context

- **#2397** — `hooks.workflow_guard` key is live and documented at
  `docs/CONFIGURATION.md:52`, but missing from `VALID_CONFIG_KEYS`, so
  `gsd-tools config-set` rejects it. Same is true for the new
  `workflow_guard_strict` flag added here. Edit `.planning/config.json`
  directly.
- **#2414, #2393, #2423, #2429** — the `gsd-sdk query` CLI the skills depend
  on was never published. `@gsd-build/sdk@0.1.0` only exposes `run | auto |
  init`, but skills call `gsd-sdk query init.phase-op`, `gsd-sdk query
  frontmatter.get`, etc. The binary that actually implements those handlers —
  `~/.claude/get-shit-done/bin/gsd-tools.cjs` — ships with the install but is
  never PATH-linked. The `gsd-sdk.shim` here bridges that gap until upstream
  closes these issues.
- Both hook and shim file headers document the rationale and precedence.
