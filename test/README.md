# Tests

The public test entrypoints stay small and stable:

- `runtests.jl` — dispatcher keyed by `TEST_TIER`
- `tier_fast.jl`
- `tier_slow.jl`
- `tier_full.jl`

Grouped tests live under:

- `core/` — repo structure, determinism, continuation, acceleration
- `cost_audit/` — cost-audit unit/integration/analyzer coverage
- `phases/` — phase-numbered regressions and milestone tests
- `trust_region/` — trust-region and PCG unit/integration coverage
