# Summary

Rewrote the current human-facing Markdown surface to remove bloated prose and make the docs task-led.

Changed areas:

- top-level `README.md` and `CLAUDE.md`;
- `docs/README.md`;
- current guides under `docs/guides/`;
- architecture notes under `docs/architecture/`;
- status, synthesis, report, artifact, and research-note index Markdown;
- top-level planning-history entry files, now marked as archive pointers;
- README files under `configs/`, `scripts/`, `fibers/`, `data/`, `notebooks/`, `test/`, `lab_extensions/`, and `src/_archived/`;
- removed ignored Syncthing conflict Markdown from `docs/guides/`.

Style applied:

- lead with runnable commands or decisions;
- make supported vs experimental status explicit;
- keep hard numbers only where they affect a claim;
- cut agent-process narration from user docs;
- leave detailed historical phase logs in the archive instead of pretending they are onboarding docs.

Verification:

- checked non-archive Markdown relative links: 123 files, no broken links;
- checked for common filler phrases in current docs; only untouched presentation walkthrough prose matched;
- did not run Julia/Python tests because this was a documentation-only rewrite.

Not touched intentionally:

- generated PDFs, dirty TeX files, and result images that were already moving in the worktree;
- deep `docs/planning-history/phases/`, `quick/`, `sessions/`, and similar archive records.
