#!/usr/bin/env bash
# codex-gsd-bootstrap.sh — run OpenAI Codex CLI against this repo with GSD
# strict mode safely disabled for the duration of the session.
#
# Why this exists:
#   The GSD workflow guard hook (~/.claude/hooks/gsd-workflow-guard.js) only
#   recognises Claude Code subagent contexts. Codex / Gemini / any non-Claude
#   runtime triggers a hard-deny on every Edit/Write to a tracked source file.
#   This wrapper toggles strict off, runs Codex, and restores the original
#   value on exit (even on Ctrl-C or crash, via trap).
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

# Snapshot the current strict value (default true if absent) so we restore it.
ORIGINAL_STRICT=$(node -e '
  const fs=require("fs");
  const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  process.stdout.write(String((c.hooks && c.hooks.workflow_guard_strict !== false) ? "true" : "false"));
' "$CONFIG_PATH")

restore_strict() {
  local exit_code=$?
  node -e '
    const fs=require("fs");
    const path=process.argv[1];
    const target=process.argv[2]==="true";
    const c=JSON.parse(fs.readFileSync(path,"utf8"));
    c.hooks=c.hooks||{};
    c.hooks.workflow_guard_strict=target;
    fs.writeFileSync(path, JSON.stringify(c,null,2)+"\n");
  ' "$CONFIG_PATH" "$ORIGINAL_STRICT"
  echo
  echo "[codex-gsd] restored hooks.workflow_guard_strict = ${ORIGINAL_STRICT}"
  exit $exit_code
}
trap restore_strict EXIT INT TERM

# Flip strict OFF for this session.
node -e '
  const fs=require("fs");
  const path=process.argv[1];
  const c=JSON.parse(fs.readFileSync(path,"utf8"));
  c.hooks=c.hooks||{};
  c.hooks.workflow_guard_strict=false;
  fs.writeFileSync(path, JSON.stringify(c,null,2)+"\n");
' "$CONFIG_PATH"

echo "[codex-gsd] hooks.workflow_guard_strict = false (was ${ORIGINAL_STRICT})"
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
