#!/usr/bin/env bash
# bootstrap_test_project.sh — Phase 36 Wave 0 throwaway test scaffold.
#
# Creates a fresh git repo at $TEST_DIR (default /tmp/gsd-codex-adapter-test)
# containing a minimal .planning/ scaffold with one phase that holds two
# trivial plans (create A.txt = "hello", create B.txt = "world"). Used by
# Plan 03's control + patched runs to exercise $gsd-execute-phase against
# the unpatched and patched adapters.
#
# Caller usage:
#     bash harness/bootstrap_test_project.sh
#     TEST_DIR=/path/to/somewhere bash harness/bootstrap_test_project.sh
#
# This plan does NOT execute this script — Plan 03 owns execution.

set -euo pipefail

TEST_DIR="${TEST_DIR:-/tmp/gsd-codex-adapter-test}"

echo "Bootstrapping throwaway test project at: $TEST_DIR"

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

git init -q
git config user.email "test@example.com"
git config user.name "Test Bootstrap"

mkdir -p .planning/phases/01-two-plan-phase

cat > .planning/ROADMAP.md <<'ROADMAP'
# Roadmap
## Phase 1: two-plan-phase
**Goal:** Create two trivial files across two plans to exercise the GSD execute-phase protocol.
**Plans:** 2 plans
- [ ] 01-01-PLAN.md — create A.txt
- [ ] 01-02-PLAN.md — create B.txt
ROADMAP

cat > .planning/phases/01-two-plan-phase/01-CONTEXT.md <<'CONTEXT'
Trivial test phase for adapter validation.
CONTEXT

cat > .planning/STATE.md <<'STATE'
---
status: planning
phase: 01
---
# State
- Phase 01 pending execution (two trivial plans: A.txt, B.txt).
STATE

cat > .planning/phases/01-two-plan-phase/01-01-PLAN.md <<'PLAN1'
---
phase: 1
plan: 01
type: execute
wave: 1
depends_on: []
files_modified: [A.txt]
autonomous: true
---

<objective>
Create A.txt at the repo root with the literal content "hello" (no trailing newline).
</objective>

<tasks>
<task type="auto">
  <name>Task: create A.txt</name>
  <files>A.txt</files>
  <action>Write the literal string "hello" (no newline) to A.txt at the repo root.</action>
  <verify><automated>test "$(cat A.txt)" = "hello"</automated></verify>
  <done>A.txt exists with content "hello"</done>
</task>
</tasks>
PLAN1

cat > .planning/phases/01-two-plan-phase/01-02-PLAN.md <<'PLAN2'
---
phase: 1
plan: 02
type: execute
wave: 1
depends_on: []
files_modified: [B.txt]
autonomous: true
---

<objective>
Create B.txt at the repo root with the literal content "world" (no trailing newline).
</objective>

<tasks>
<task type="auto">
  <name>Task: create B.txt</name>
  <files>B.txt</files>
  <action>Write the literal string "world" (no newline) to B.txt at the repo root.</action>
  <verify><automated>test "$(cat B.txt)" = "world"</automated></verify>
  <done>B.txt exists with content "world"</done>
</task>
</tasks>
PLAN2

git add -A
git commit -q -m "chore: seed test project"

echo "Bootstrapped: $TEST_DIR"
