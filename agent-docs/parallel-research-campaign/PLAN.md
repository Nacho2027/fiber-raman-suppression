## Plan

1. Use one local tmux session on `claude-code-host` as the orchestration
   surface Codex polls.
2. Split compute intentionally:
   - MMF on the permanent burst VM
   - multivar on one ephemeral burst VM
   - long-fiber on one ephemeral burst VM
3. Keep Codex polling local launcher logs instead of fragile remote tmux
   attachment.
4. Treat the scientific campaigns as staged, not monolithic:
   - MMF: regime map first, then deeper `{φ, c_m}` work
   - multivar: ablation / two-stage rescue first, then regime map
   - long-fiber: 100 m hardening first, then continuation ladder to 200 m
5. Only escalate to larger parallel batches after the first pass proves the
   lane is worth more burst time.
