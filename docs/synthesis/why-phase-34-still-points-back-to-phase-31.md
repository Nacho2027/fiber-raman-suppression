# Why Phase 34 Still Points Back To Phase 31

Phase 34 did not undo the Phase 31 lesson. It strengthened it.

The short version is:

- Phase 31 showed that a better path into the landscape can reach a much deeper basin than full-grid zero-start optimization.
- Phase 34 asked whether a more sophisticated local optimizer could recover that basin without needing that path.
- So far, the answer is mostly no.

## The simple connection

Phase 31 said:

- basin access is a central problem
- reduced-basis continuation is valuable because it gives the optimizer a better route

Phase 34 then tested a natural alternative:

- keep the hard full problem
- improve the local second-order solver with trust regions and preconditioning
- see whether better local curvature handling can replace the need for a better path

The bounded reruns do not support that replacement story.

## What Phase 34 adds

After the preconditioner wiring and gauge-safety fixes, Phase 34 now says something cleaner than it did before:

- preconditioning can change step quality
- `:dispersion` is the only tested preconditioner that currently looks worth carrying forward
- but preconditioning alone does not rescue poor cold starts

The strongest Phase 34 behavior appears when trust-region optimization is given a continuation-style start. On those bounded reruns:

- continuation-style starts produced accepted trust-region steps on harder targets
- same-config warm starts did not reliably do that
- `:dispersion` slightly outperformed `:none` once the path into the basin was already improved

That is the key bridge back to Phase 31.

## What future sessions should assume

The current project picture is:

1. A good path matters first.
2. Better local curvature handling matters second.
3. The most promising near-term combination is:
   continuation-style start + trust-region + `:dispersion`

That is different from both of these weaker stories:

- "just use a reduced basis forever"
- "just add a fancier Newton method and skip continuation"

The evidence so far supports a hybrid view:

- continuation gets you into a useful basin
- second-order / preconditioned methods may help once you are there

## What this means for roadmap decisions

Near-term work should not ask:

- can preconditioning replace continuation?

It should ask:

- can preconditioning improve trust-region performance once continuation has already supplied a viable starting point?

That is a much narrower and more research-grounded question.

## Short takeaway

Phase 31 changed the roadmap by showing that path quality controls basin reachability.

Phase 34, after its fixes and bounded reruns, now supports the same conclusion:

- local solver improvements help
- but they help most when the optimizer is already entering the right part of the landscape

So the project should keep treating continuation as the main access mechanism, with preconditioned trust-region work as a follow-on tool rather than a replacement strategy.
