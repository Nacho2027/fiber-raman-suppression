## Context

- User wants deeper, simultaneous exploration of:
  - multimode
  - multivariable optimization
  - longer-fiber / more production-ready long-fiber work
- User explicitly wants the campaigns to run in parallel under tmux and be
  pollable by Codex.
- Existing project constraints still apply:
  - heavy Julia work belongs on burst resources
  - do not overload one burst VM with multiple heavy jobs
  - use wrappers/helpers rather than ad hoc long-running remote shells
- Existing infrastructure already supports:
  - permanent burst VM via `burst-ssh`, `burst-start`, `burst-stop`
  - ephemeral burst VMs via `~/bin/burst-spawn-temp`
- Important quota fact:
  - full 3-lane parallelism needs enough regional `C3_CPUS` quota
  - main `c3-highcpu-22` burst VM + two `c3-highcpu-8` ephemerals needs
    roughly 38 C3 CPUs, so 48 or 64 quota is the practical target
