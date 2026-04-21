#!/usr/bin/env node
// gsd-hook-version: 1.38.0
// GSD Workflow Guard — PreToolUse hook
// Detects when Claude attempts file edits outside a GSD workflow context
// (no active /gsd- skill or Task subagent) and injects an advisory warning.
//
// By default this is a SOFT guard — it advises, not blocks. The edit still
// proceeds. The warning nudges Claude to use /gsd-quick or /gsd-fast instead
// of making direct edits that bypass state tracking.
//
// Two enablement levels, both read from .planning/config.json:
//   hooks.workflow_guard: true          → advisory warning (soft, vanilla)
//   hooks.workflow_guard_strict: true   → hard block (PreToolUse deny)
// Strict implies guard; setting strict alone activates the hook.
//
// Only triggers on Write/Edit tool calls to non-.planning/ files.

const fs = require('fs');
const path = require('path');

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name;

    // Only guard Write and Edit tool calls
    if (toolName !== 'Write' && toolName !== 'Edit') {
      process.exit(0);
    }

    // Check if we're inside a GSD workflow (Task subagent or /gsd- skill)
    // Subagents have a session_id that differs from the parent
    // and typically have a description field set by the orchestrator
    if (data.tool_input?.is_subagent || data.session_type === 'task') {
      process.exit(0);
    }

    // Check the file being edited
    const filePath = data.tool_input?.file_path || data.tool_input?.path || '';

    // Allow edits to .planning/ files (GSD state management)
    if (filePath.includes('.planning/') || filePath.includes('.planning\\')) {
      process.exit(0);
    }

    // Allow edits to Claude Code's own persistent state: auto-memory,
    // transcripts, user-global hooks/skills/agents/commands, and the GSD
    // install tree. These are orthogonal to project state tracking.
    const claudeStateDirs = [
      '/.claude/projects/',
      '/.claude/hooks/',
      '/.claude/skills/',
      '/.claude/agents/',
      '/.claude/commands/',
      '/.claude/get-shit-done/',
      '/.claude/keybindings.json',
      '/.claude/settings',
    ];
    if (claudeStateDirs.some(d => filePath.includes(d))) {
      process.exit(0);
    }

    // Allow edits to common config/docs files that don't need GSD tracking
    const allowedPatterns = [
      /\.gitignore$/,
      /\.env/,
      /CLAUDE\.md$/,
      /AGENTS\.md$/,
      /GEMINI\.md$/,
      /settings\.json$/,
    ];
    if (allowedPatterns.some(p => p.test(filePath))) {
      process.exit(0);
    }

    // Check if workflow guard is enabled and at what level
    const cwd = data.cwd || process.cwd();
    const configPath = path.join(cwd, '.planning', 'config.json');
    let strict = false;
    if (fs.existsSync(configPath)) {
      try {
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        strict = !!config.hooks?.workflow_guard_strict;
        if (!config.hooks?.workflow_guard && !strict) {
          process.exit(0); // Guard disabled (default)
        }
      } catch (e) {
        process.exit(0);
      }
    } else {
      process.exit(0); // No GSD project — don't guard
    }

    // If we get here: GSD project, guard enabled, file edit outside .planning/,
    // not in a subagent context.
    if (strict) {
      // Hard block — deny the tool call and tell Claude how to proceed.
      const output = {
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason:
            `GSD strict workflow guard: refusing direct ${toolName} on ${path.basename(filePath)}. ` +
            'Route this change through a GSD command so it lands in STATE.md with a SUMMARY. ' +
            'Use /gsd-fast for a trivial fix, /gsd-quick for a small task, or /gsd-execute-phase inside a planned phase. ' +
            'To bypass for this session, the user can set hooks.workflow_guard_strict to false in .planning/config.json.'
        }
      };
      process.stdout.write(JSON.stringify(output));
      return;
    }

    // Soft mode — advisory warning, edit still proceeds.
    const output = {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: `⚠️ WORKFLOW ADVISORY: You're editing ${path.basename(filePath)} directly without a GSD command. ` +
          'This edit will not be tracked in STATE.md or produce a SUMMARY.md. ' +
          'Consider using /gsd-fast for trivial fixes or /gsd-quick for larger changes ' +
          'to maintain project state tracking. ' +
          'If this is intentional (e.g., user explicitly asked for a direct edit), proceed normally.'
      }
    };

    process.stdout.write(JSON.stringify(output));
  } catch (e) {
    // Silent fail — never block tool execution
    process.exit(0);
  }
});
