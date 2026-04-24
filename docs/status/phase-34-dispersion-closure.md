# Phase 34 Dispersion Closure Decision

This note formally closes the current dispersion-preconditioning-as-Raman-suppression research branch.

## Decision

Close this avenue as an active Raman-suppression line of research.

Do not treat `:dispersion` preconditioning as a current roadmap item for improving Raman suppression, and do not continue routine exploratory sweeps for this question.

## Why this branch is being closed

The project now has enough honest evidence to make a decision.

What survived the Phase 34 fixes and reruns:

- the trust-region plumbing issue was real and is now fixed
- gauge-safe PCG projection was necessary and is now in place
- continuation-style starts matter much more than preconditioning alone
- `:dispersion` is the only tested preconditioner that showed any recurring upside

What did **not** survive:

- a broad claim that `:dispersion` improves the Raman objective in a stable or general way
- a claim that preconditioning can replace continuation as the main basin-access mechanism
- a claim that the apparent `:dispersion` advantage persists cleanly across nearby bounded regimes

The strongest result obtained was narrower than needed for an open research branch:

- a localized bounded-case win near one continuation-supported regime

That is not enough to justify continuing this as a Raman-suppression program.

## What the project should remember

Future sessions should treat the Phase 34 outcome this way:

1. Phase 31 was the durable roadmap change.
2. Phase 34 helped diagnose the local second-order story more honestly.
3. That diagnosis did **not** turn into a strong general Raman-suppression result for dispersion preconditioning.

So the durable lesson is:

- path quality remains the main lever
- dispersion preconditioning is not a convincing standalone Raman-suppression result

## What is still worth keeping

The work was not useless. It produced durable assets:

- a corrected trust-region preconditioning path
- gauge-safe PCG handling
- bounded comparison scripts and summaries
- a clearer decision boundary for future work

Those assets remain useful if trust-region work is revisited for other reasons.

## Reopen criterion

Do not reopen this branch for Raman suppression unless there is a materially different hypothesis, for example:

- a new physically motivated metric or objective
- a clearly different continuation protocol
- strong external evidence that dispersion-aware geometry should matter directly for the Raman objective

Absent that, this line should stay closed.

## If dispersion is revisited at all

If dispersion is revisited, it should be under a different framing where dispersion is first-order physics rather than a narrow optimizer-side effect, for example:

- supercontinuum spectral engineering
- dispersive-wave placement
- pulse-compression or spectral-shaping objectives

That would be a new research branch, not a continuation of this one.
