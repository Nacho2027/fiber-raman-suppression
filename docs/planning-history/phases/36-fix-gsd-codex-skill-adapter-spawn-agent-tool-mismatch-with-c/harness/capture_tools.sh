#!/usr/bin/env bash
# capture_tools.sh — Phase 36 Wave 0 Codex tool-surface inventory.
#
# Resolves the Codex native binary path, then extracts the tool-name
# dispatch strings via `strings | grep`. Also captures the relevant
# CLI help and feature-flag listing so reviewers can confirm the
# multi_agent feature flag state and inspect available subcommands.
#
# Caller usage:
#     bash harness/capture_tools.sh > evidence/codex_tools.txt 2>&1
#
# Exit codes:
#     0 — binary resolved and inventory printed
#     2 — Codex native binary could not be located on this machine
#         (downstream plans may still consume the partial output)

set -euo pipefail

echo "=== Phase 36 Codex tool-surface capture ==="
echo "Run timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

PRIMARY="$HOME/.nvm/versions/node/v22.3.0/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/codex/codex"

BIN=""
if [ -x "$PRIMARY" ]; then
    BIN="$PRIMARY"
    echo "--- Codex native binary (primary path resolved) ---"
else
    echo "--- Codex native binary (primary path missing — falling back to find) ---"
    BIN=$(find "$HOME/.nvm" "$HOME/.codex" /usr/local/lib/node_modules -type f -name codex 2>/dev/null \
              | xargs -I {} file {} 2>/dev/null \
              | grep -E 'Mach-O|ELF' \
              | head -1 \
              | cut -d: -f1 \
              || true)
fi

if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "BINARY NOT FOUND" >&2
    echo "BINARY NOT FOUND"
    exit 2
fi

echo "$BIN"
file "$BIN" 2>/dev/null || true
echo

echo "--- Tool-name dispatch strings (one per line, sorted unique) ---"
# `strings` on Mach-O frequently concatenates short identifiers into longer
# blobs (e.g. "hide_spawn_agent_metadatamulti_agent_v2..."), so an anchored
# whole-line regex misses real tool names that ARE present in the binary.
# Approach: dump all printable strings once, then probe each candidate tool
# name as a substring; emit the bare name on its own line when found.
#
# NOTE: avoid `grep -q` here. With `set -o pipefail` plus a multi-MB stream,
# `grep -q` exits at first match and the upstream `printf` then takes a
# SIGPIPE; the pipeline returns failure and the conditional misses real
# matches. Redirecting grep's stdout to /dev/null instead lets grep drain
# the pipe and report success cleanly.
TOOL_DUMP="$(strings "$BIN" 2>/dev/null || true)"
for tool in spawn_agent spawn_agents_on_csv exec_command apply_patch wait close_agent send_input send_message resume_agent followup_task list_agents update_plan request_user_input web_search_request; do
    if printf '%s\n' "$TOOL_DUMP" | grep -E "(^|[^A-Za-z0-9_])${tool}([^A-Za-z0-9_]|$)" >/dev/null; then
        echo "$tool"
    fi
done | sort -u
echo

echo "--- Raw strings hits (substring grep) for cross-check ---"
printf '%s\n' "$TOOL_DUMP" \
    | grep -oE '(spawn_agent|spawn_agents_on_csv|exec_command|apply_patch|close_agent|send_input|send_message|resume_agent|followup_task|list_agents|update_plan|request_user_input|web_search_request)' \
    | sort -u \
    || echo "(no tool-name substrings matched — investigate)"
echo

echo "--- codex --help (head -40) ---"
codex --help 2>&1 | head -40 || echo "(codex --help failed)"
echo

echo "--- codex exec --help (head -40) ---"
codex exec --help 2>&1 | head -40 || echo "(codex exec --help failed)"
echo

echo "--- codex features list (head -40) ---"
codex features list 2>&1 | head -40 || echo "(codex features list failed)"
echo

echo "=== capture complete ==="
