# Session-update message — paste this into every active Claude Code session

This message informs each in-flight session of two rule changes that took effect
2026-04-17. Both are now in `CLAUDE.md` on `main`, but already-running sessions
won't pick them up until you tell them. Paste the entire block below as a user
message into every active session.

---

```
IMPORTANT: rule changes as of 2026-04-17.

Please git pull main first so CLAUDE.md is current in your context, then
acknowledge and adapt the rest of your session to the two rules below.
Full documentation lives in scripts/burst/README.md and in CLAUDE.md
Rule P5 + the Project section.

─────────────────────────────────────────────────────────────────────────
1. MANDATORY burst-VM heavy-lock wrapper (new Rule P5)
─────────────────────────────────────────────────────────────────────────

The burst VM lockup on 2026-04-17 was caused by 7+ concurrent heavy Julia
jobs. A mandatory wrapper plus a systemd-user watchdog is now installed
on fiber-raman-burst. You MUST use them.

Do NOT launch heavy Julia with a bare `tmux new -d -s ... 'julia ...'`.
The required pattern is:

    burst-ssh "cd fiber-raman-suppression && ~/bin/burst-run-heavy \
              <SESSION-TAG> '<your julia command>'"

Session tag must match ^[A-Za-z]-[A-Za-z0-9_-]+$ (examples: A-demo,
E-sweep2, F-T5, H-audit). The wrapper enforces this, acquires the lock,
runs the job in tmux, releases the lock on exit (even on crash), and
tees output to results/burst-logs/<tag>_<timestamp>.log.

If the lock is already held, the wrapper prints who holds it and exits.
To wait instead of failing:

    WAIT_TIMEOUT_SEC=3600 burst-ssh "cd fiber-raman-suppression && \
        ~/bin/burst-run-heavy <tag> 'julia ...'"

Before any burst-VM work, check state:

    burst-ssh "~/bin/burst-status"

The watchdog (`raman-watchdog.service`, systemd --user) kills the
youngest heavy Julia if load > 35 OR available memory < 4 GB, AND ≥ 2
heavy julias are running. One heavy job at 100% CPU is fine.

If you want to run a heavy job in parallel with the one on the main
burst VM, use the ephemeral-VM spawner FROM claude-code-host (not the
burst VM itself):

    ~/bin/burst-spawn-temp <SESSION-TAG> '<your julia command>'

It creates a second VM from a machine image of fiber-raman-burst, runs
your job, and destroys the VM on exit via a trap. ~$0.90/hr while
running. Use it whenever it helps — the guidelines are:

  - Soft cap: try not to have more than ~2 ephemerals active at once.
    A dozen concurrent would drain the budget fast.
  - At the end of a work block, run `~/bin/burst-list-ephemerals` to
    confirm nothing is orphaned. If something is, kill it:
        ~/bin/burst-list-ephemerals --destroy
  - The spawner already self-cleans in two ways: a trap that destroys
    the VM on exit/crash, and a 6-hour auto-shutdown scheduled on the
    VM itself at launch. So a one-off failure will not bill overnight,
    but still glance at the list between work sessions.

Good uses include: second heavy job while the main VM is busy,
isolated reproducibility runs, quick experiments that should not
disturb a multi-hour run on the main burst VM.

The pre-2026-04-17 pattern `touch /tmp/burst-heavy-lock` is DEPRECATED.
If you see it in any of your session's scripts or cached commands,
replace it with burst-run-heavy.

─────────────────────────────────────────────────────────────────────────
2. MANDATORY standard output images (new Project-level rule)
─────────────────────────────────────────────────────────────────────────

Every optimization driver that produces a phi_opt MUST end with a call
to save_standard_set(...) from scripts/standard_images.jl. This
produces the four images the research group expects:

    {tag}_phase_profile.png      — 6-panel before/after comparison
    {tag}_evolution.png          — colorful spectral-evolution waterfall
    {tag}_phase_diagnostic.png   — wrapped/unwrapped/group-delay of phi_opt
    {tag}_evolution_unshaped.png — matching waterfall with phi ≡ 0

Template — three lines at the end of your driver, after phi_opt exists:

    include(joinpath(@__DIR__, "standard_images.jl"))
    save_standard_set(phi_opt, uω0, fiber, sim,
                      band_mask, Δf, raman_threshold;
                      tag = "smf28_L2m_P0p2W",
                      fiber_name = "SMF28", L_m = 2.0, P_W = 0.2,
                      output_dir = "results/raman/my_run/")

For any run you produced earlier that doesn't yet have these images,
regenerate with:

    ~/bin/burst-run-heavy R-stdimages \
        'julia -t auto --project=. scripts/regenerate_standard_images.jl'

Runs without the standard image set are NOT "done." Do not claim a
driver is complete without these four PNGs on disk.

─────────────────────────────────────────────────────────────────────────
Acknowledgement
─────────────────────────────────────────────────────────────────────────

Please acknowledge you have received and will follow both rules, and
list the specific in-flight actions in your session that need to change
(e.g., "my next planned burst-VM launch was a bare tmux; switching to
burst-run-heavy," or "my optimizer driver does not yet call
save_standard_set; adding it now"). Then continue your work.
```

---

# Where to paste it

Paste the fenced block above into every active Claude Code session you have
open for Sessions A, B, C, D, E, F, G, H. It's one-time per session — once
each session has been told, the rules are durable for the rest of that
session's life (and future fresh sessions pick them up from `main` via
`CLAUDE.md`).

# What you do NOT need to do

- You don't need to paste this into sessions you start **after** these commits
  landed. Fresh sessions read the updated `CLAUDE.md` at start.
- You don't need to restart existing sessions — pasting this gives them the
  new rules for the rest of their current conversation.
