# Ops Scripts

This directory contains operational launchers and machine-specific orchestration
helpers.

These are infrastructure-facing scripts rather than scientific entry points.
They support running work on specific hosts or queues, but they are not part of
the small public workflow that new users should discover first.

Current helpers:

- `longfiber_burst_launcher.sh`
  - queue-oriented helper from the original long-fiber campaign
- `parallel_research_lane.sh`
  - launch one research lane on either the permanent burst VM or an ephemeral
    VM while teeing a stable local launcher log
- `parallel_research_campaign.sh`
  - create a local tmux session with one window per lane so Codex can supervise
    multimode, multivar, and long-fiber work in parallel
- `parallel_research_poll.sh`
  - summarize the local launcher logs for Codex polling without needing to
    attach to tmux
