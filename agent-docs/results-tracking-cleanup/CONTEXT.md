# Context

- The repo had a large tracked `results/**` footprint from the old git-heavy workflow.
- That payload mixed three different classes of files:
  - durable summaries and validation notes that belong in git
  - regression fixtures used by tests
  - generated PNGs, burst logs, and routine run-output payloads that do not belong in git anymore
- Current workflow is different:
  - Syncthing moves live `results/` state between the Mac and `claude-code-host`
  - burst moves results back via explicit `rsync`
  - git should carry only durable records and fixtures
- Cleanup must remove tracked generated payloads without deleting local copies from disk.
