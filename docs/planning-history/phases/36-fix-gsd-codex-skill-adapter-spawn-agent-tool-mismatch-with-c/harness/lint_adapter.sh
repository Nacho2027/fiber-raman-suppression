#!/usr/bin/env bash
# Phase 36-02 — static lint over installed Codex skills.
#
# For every ~/.codex/skills/*/SKILL.md, asserts that the Direction A
# adapter rewrite is present (USER AUTHORIZATION NOTICE, integrity
# contract literals, spawn_agent mapping). For skills whose name
# matches the hard-coded BLACKLIST below, additionally requires the
# "adapter is unreliable" STOP phrase.
#
# Exits 0 iff every skill passes its required literals.

set -euo pipefail

SKILLS_ROOT="${HOME}/.codex/skills"

# Hard-coded BLACKLIST — must match BLACKLIST_SKILLS in the patched
# generator (~/src/gsd-fork/bin/install.js) byte-for-byte. Sourced from
# this repo's CLAUDE.md "Codex Runtime Constraints > Blacklist" section.
BLACKLIST=(
  gsd-plan-phase
  gsd-execute-phase
  gsd-execute-plan
  gsd-autonomous
  gsd-plan-review-convergence
  gsd-verify-work
  gsd-review
  gsd-ship
  gsd-debug
  gsd-audit-fix
  gsd-audit-milestone
  gsd-audit-uat
  gsd-code-review
  gsd-ingest-docs
  gsd-new-milestone
  gsd-new-project
)

# Required literals for ALL skills (Direction A integrity contract).
# Each literal is grep -F (fixed-string) tested.
GENERAL_LITERALS=(
  'USER AUTHORIZATION NOTICE'
  'phase{PHASE}-{PLAN}'
  'manifest.json'
  'spawn_agent(agent_type='
)

# Additional literal required for BLACKLIST skills only.
BLACKLIST_LITERAL='adapter is unreliable'

is_blacklisted() {
  local name="$1"
  for b in "${BLACKLIST[@]}"; do
    [ "$name" = "$b" ] && return 0
  done
  return 1
}

if [ ! -d "$SKILLS_ROOT" ]; then
  echo "FAIL: $SKILLS_ROOT does not exist — install GSD for Codex first" >&2
  exit 2
fi

# Portable file collection (macOS ships bash 3.2, no mapfile).
SKILL_FILES=()
while IFS= read -r f; do
  SKILL_FILES+=("$f")
done < <(find "$SKILLS_ROOT" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -type f | sort)

if [ "${#SKILL_FILES[@]}" -eq 0 ]; then
  echo "FAIL: no SKILL.md files found under $SKILLS_ROOT" >&2
  exit 2
fi

total=0
pass=0
fail=0

for skill_md in "${SKILL_FILES[@]}"; do
  total=$((total + 1))
  skill_name="$(basename "$(dirname "$skill_md")")"

  missing=()
  for lit in "${GENERAL_LITERALS[@]}"; do
    if ! grep -qF -- "$lit" "$skill_md"; then
      missing+=("$lit")
    fi
  done

  if is_blacklisted "$skill_name"; then
    if ! grep -qF -- "$BLACKLIST_LITERAL" "$skill_md"; then
      missing+=("$BLACKLIST_LITERAL (blacklist STOP phrase)")
    fi
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "PASS: $skill_name"
    pass=$((pass + 1))
  else
    for m in "${missing[@]}"; do
      echo "FAIL: $skill_name missing $m"
    done
    fail=$((fail + 1))
  fi
done

echo
echo "Total: $total, Pass: $pass, Fail: $fail"

if [ "$fail" -eq 0 ]; then
  exit 0
else
  exit 1
fi
