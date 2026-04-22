# Plan

1. Identify which tracked `results/**` files are still referenced by active docs, tests, or scripts.
2. Keep durable markdown, txt, csv, json summaries and true regression fixtures.
3. Untrack generated PNGs, logs, unreferenced JLD2 payloads, and generated sidecar JSON outputs with `git rm --cached`.
4. Tighten `.gitignore` so new generated result payloads stay out of git by default.
5. Remove the "always pull at session start" language from `AGENTS.md` and `CLAUDE.md`.
