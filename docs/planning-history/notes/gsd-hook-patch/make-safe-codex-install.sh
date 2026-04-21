#!/usr/bin/env bash
# make-safe-codex-install.sh — install GSD for another runtime (Codex,
# OpenCode, Gemini CLI, etc.) without breaking the Claude-side local patches.
#
# Protects:
#   - ~/.claude/hooks/gsd-workflow-guard.js  (strict-mode enforcement patch)
#   - ~/bin/gsd-sdk                          (query-subcommand shim, issue #2414)
#
# Usage:
#   bash make-safe-codex-install.sh [installer args...]
#
# Examples:
#   bash make-safe-codex-install.sh --codex --global
#   YES=1 bash make-safe-codex-install.sh --codex --global        # no prompt
#
# The script:
#   1. Snapshots both patched files + their sha256 hashes
#   2. Prints `npx get-shit-done-cc --help` so you can confirm the right flag
#   3. Prompts before running (skip with YES=1)
#   4. Runs the installer with your args, verbatim
#   5. Diffs hook hash before/after; restores from backup if changed
#   6. Checks the shim is still in place; restores if removed
#   7. Smoke-tests the shim (`gsd-sdk query config-get`) and the hook
#      (simulate a source-file PreToolUse event and confirm it denies)
#
# Backups live at ~/.claude/gsd-backups/<timestamp>/ and are kept — you can
# diff / restore manually later.

set -euo pipefail

HOOK="$HOME/.claude/hooks/gsd-workflow-guard.js"
SHIM="$HOME/bin/gsd-sdk"
STAMP=$(date +%Y%m%d-%H%M%S)
BAK_DIR="$HOME/.claude/gsd-backups/$STAMP"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()    { printf '\033[32m%s\033[0m\n' "$*"; }

sha() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

# 1. Sanity check ------------------------------------------------------------

[ -f "$HOOK" ] || { err "missing: $HOOK — nothing to protect"; exit 1; }

mkdir -p "$BAK_DIR"
cp -p "$HOOK" "$BAK_DIR/gsd-workflow-guard.js"
HOOK_HASH=$(sha "$HOOK")

if [ -f "$SHIM" ]; then
    cp -p "$SHIM" "$BAK_DIR/gsd-sdk"
    SHIM_HASH=$(sha "$SHIM")
else
    warn "note: $SHIM not found — shim won't be restored post-install"
    SHIM_HASH=""
fi

bold "Backup: $BAK_DIR"
echo "  hook sha256: $HOOK_HASH"
[ -n "$SHIM_HASH" ] && echo "  shim sha256: $SHIM_HASH"
echo

# 2. Preview installer flags -------------------------------------------------

bold "Installer help (first 60 lines)"
echo "----------------------------------------"
npx --yes get-shit-done-cc@latest --help 2>&1 | head -60 || \
    warn "(--help returned nonzero; continuing)"
echo "----------------------------------------"
echo

# 3. Confirm -----------------------------------------------------------------

bold "About to run: npx get-shit-done-cc@latest $*"
if [ "${YES:-}" != "1" ]; then
    read -rp "Proceed? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) err "Aborted."; exit 1 ;;
    esac
fi

# 4. Run installer -----------------------------------------------------------

bold "Running installer..."
set +e
npx --yes get-shit-done-cc@latest "$@"
install_rc=$?
set -e
[ $install_rc -eq 0 ] || warn "installer exited with code $install_rc — continuing to verify state"

# 5. Verify hook ------------------------------------------------------------

bold "Verifying Claude-side patches"
POST_HOOK_HASH=$(sha "$HOOK")
if [ "$HOOK_HASH" = "$POST_HOOK_HASH" ]; then
    ok "hook unchanged"
else
    warn "hook was modified by installer (pre=$HOOK_HASH post=$POST_HOOK_HASH)"
    warn "restoring from backup..."
    cp "$BAK_DIR/gsd-workflow-guard.js" "$HOOK"
    chmod +x "$HOOK"
    node --check "$HOOK" && ok "hook restored, syntax OK"
fi

if [ -n "$SHIM_HASH" ]; then
    if [ -f "$SHIM" ]; then
        POST_SHIM_HASH=$(sha "$SHIM")
        if [ "$SHIM_HASH" = "$POST_SHIM_HASH" ]; then
            ok "shim unchanged"
        else
            warn "shim was modified (this is unusual — the installer shouldn't touch ~/bin)"
            warn "restoring..."
            cp "$BAK_DIR/gsd-sdk" "$SHIM"
            chmod +x "$SHIM"
        fi
    else
        warn "shim was removed — restoring..."
        cp "$BAK_DIR/gsd-sdk" "$SHIM"
        chmod +x "$SHIM"
    fi
fi

# 6. Smoke tests -------------------------------------------------------------

bold "Smoke tests"
echo -n "which gsd-sdk: "
which gsd-sdk || { err "gsd-sdk not found on PATH"; exit 2; }

echo -n "shim routes query: "
out=$(gsd-sdk query config-get workflow.discuss_mode 2>&1 || true)
echo "$out" | head -1
case "$out" in
    *Expected*run*) err "shim appears bypassed — check PATH ordering"; exit 3 ;;
esac

echo -n "hook denies source edits: "
deny_out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.jl"},"cwd":"'"$HOME/RiveraLab/fiber-raman-suppression"'"}' | node "$HOOK" 2>&1 || true)
if echo "$deny_out" | grep -q '"permissionDecision":"deny"'; then
    ok "yes"
elif [ -z "$deny_out" ]; then
    warn "hook exited silent — strict mode may be off for the fiber-raman-suppression project"
else
    echo "$deny_out" | head -1
fi

echo
ok "Done. Backup retained at: $BAK_DIR"
