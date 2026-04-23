#!/usr/bin/env bash
# codex-gsd-bootstrap.sh — run OpenAI Codex CLI against this repo with the
# GSD workflow guard configured for non-Claude runtimes.
#
# Why this exists:
#   The GSD workflow guard hook (~/.claude/hooks/gsd-workflow-guard.js) only
#   recognises Claude Code subagent contexts. Codex / Gemini / any non-Claude
#   runtime is treated as a "rogue" edit by the guard.
#
#   In GSD <= 1.38.0, with hooks.workflow_guard_strict: true, this caused a
#   HARD DENY on every Edit/Write to a tracked source file — Codex literally
#   could not work in the repo. The 1.38.1 hotfix removed strict mode
#   entirely (the `workflow_guard_strict` config key is now ignored), so on
#   1.38.1+ the only consequence of working outside a Claude Code subagent
#   is a noisy advisory warning on every edit. Edits proceed.
#
#   This wrapper still toggles `hooks.workflow_guard` (the soft-warning key)
#   to false for the duration of the session so Codex doesn't get spammed
#   with the advisory, then restores the original value on exit (even on
#   Ctrl-C or crash, via trap). It also runs `git fetch + ff-pull` so the
#   session starts from current main, and reminds you to paste
#   scripts/codex-gsd-prompt.md at the top of your prompt.
#
#   The workflow_guard_strict toggle below is kept as a no-op for
#   1.38.1+ but ensures forward-compatibility if a future GSD release
#   reintroduces a stricter guard.
#
# Usage:
#   ./scripts/codex-gsd-bootstrap.sh                   # interactive Codex session
#   ./scripts/codex-gsd-bootstrap.sh "fix the X bug"    # one-shot prompt
#   ./scripts/codex-gsd-bootstrap.sh -m gpt-5 ...       # passthrough flags
#
# All arguments after the script name are forwarded to `codex` verbatim.
#
# Pair with scripts/codex-gsd-prompt.md — paste that file's contents at the
# top of your Codex prompt so Codex knows the project rules (burst-VM, multi-
# machine sync, doc conventions, gsd-sdk CLI).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${REPO_ROOT}/.planning/config.json"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "error: ${CONFIG_PATH} not found — are you in the fiber-raman-suppression repo?" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "error: codex CLI not on PATH. Install with: npm i -g @openai/codex" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH (needed to safely toggle the guard config)." >&2
  exit 1
fi

# Snapshot original state of both guard keys so we can restore on exit.
# - workflow_guard is the active key in GSD 1.38.1+ (soft advisory mode)
# - workflow_guard_strict was the hard-deny key in <=1.38.0; the 1.38.1
#   hotfix made it a no-op, but we still toggle it for cross-version safety.
#
# We record each key as one of: "true", "false", or "absent" — so restore
# can omit keys that were never set rather than adding `: false` noise.
snapshot_key() {
  node -e '
    const fs=require("fs");
    const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const key=process.argv[2];
    let out;
    if (!c.hooks || !(key in c.hooks)) out = "absent";
    else out = c.hooks[key] ? "true" : "false";
    process.stdout.write(out);
  ' "$CONFIG_PATH" "$1"
}
ORIGINAL_GUARD=$(snapshot_key workflow_guard)
ORIGINAL_STRICT=$(snapshot_key workflow_guard_strict)

restore_guard() {
  local exit_code=$?
  node -e '
    const fs=require("fs");
    const path=process.argv[1];
    const guard=process.argv[2];   // "true" | "false" | "absent"
    const strict=process.argv[3];
    const c=JSON.parse(fs.readFileSync(path,"utf8"));
    c.hooks=c.hooks||{};
    if (guard==="absent") delete c.hooks.workflow_guard;
    else c.hooks.workflow_guard = (guard==="true");
    if (strict==="absent") delete c.hooks.workflow_guard_strict;
    else c.hooks.workflow_guard_strict = (strict==="true");
    fs.writeFileSync(path, JSON.stringify(c,null,2)+"\n");
  ' "$CONFIG_PATH" "$ORIGINAL_GUARD" "$ORIGINAL_STRICT"
  echo
  echo "[codex-gsd] restored hooks.workflow_guard=${ORIGINAL_GUARD}, workflow_guard_strict=${ORIGINAL_STRICT}"
  exit $exit_code
}
trap restore_guard EXIT INT TERM

# Flip BOTH guard keys OFF for this session.
node -e '
  const fs=require("fs");
  const path=process.argv[1];
  const c=JSON.parse(fs.readFileSync(path,"utf8"));
  c.hooks=c.hooks||{};
  c.hooks.workflow_guard=false;
  c.hooks.workflow_guard_strict=false;
  fs.writeFileSync(path, JSON.stringify(c,null,2)+"\n");
' "$CONFIG_PATH"

echo "[codex-gsd] hooks.workflow_guard=false (was ${ORIGINAL_GUARD}), workflow_guard_strict=false (was ${ORIGINAL_STRICT})"
echo "[codex-gsd] paste scripts/codex-gsd-prompt.md at the top of your prompt"
echo "[codex-gsd] launching codex (Ctrl-D / 'exit' to quit, strict will be restored)"
echo

cd "$REPO_ROOT"

# Always pull before working — multi-machine discipline (CLAUDE.md).
git fetch origin --quiet || true
if git status --porcelain | grep -q .; then
  echo "[codex-gsd] working tree has uncommitted changes — leaving them as-is."
else
  git pull --ff-only origin main --quiet || \
    echo "[codex-gsd] ff pull failed (diverged) — surface to user before editing."
fi

# Hand off to codex with whatever args the user passed.
codex "$@"
