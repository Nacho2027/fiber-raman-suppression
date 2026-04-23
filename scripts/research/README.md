# Research Scripts

This directory is reserved for active experimental workflows that are still
scientifically useful but are not part of the small supported command-line
surface exposed in `scripts/canonical/`.

Typical contents belong to one of these categories:

- continuation and warm-start experiments
- trust-region / second-order optimization research
- multimode and long-fiber investigations
- benchmark and diagnostic runs that inform current roadmap work

When a research workflow becomes stable and broadly supported, prefer promoting
its reusable logic into `src/` and exposing only a thin canonical entry point.

Current grouped areas include:

- [`mmf/`](./mmf/README.md) — multimode Raman optimization and analysis tooling
- [`longfiber/`](./longfiber/README.md) — long-fiber Raman workflows and validation helpers
- [`sweep_simple/`](./sweep_simple/README.md) — reduced-parameter sweep and continuation tooling
- [`simple_profile/`](./simple_profile/README.md) — simple-profile analysis and synthesis workflow
- [`cost_audit/`](./cost_audit/README.md) — methodology audit comparing objective variants
- [`recovery/`](./recovery/README.md) — honest-grid recovery and validation workflows
- [`sharpness/`](./sharpness/README.md) — sharpness-focused research drivers and analyses
- [`phases/`](./phases/README.md) — phase-numbered historical and active research workflows
- [`analysis/`](./analysis/README.md) — continuation, acceleration, and numerical-trust helpers
- [`trust_region/`](./trust_region/README.md) — trust-region and preconditioned-CG research utilities
- [`benchmarks/`](./benchmarks/README.md) — benchmarking and performance-modeling drivers
- [`multivar/`](./multivar/README.md) — multivariable optimization experiments
- [`propagation/`](./propagation/README.md) — propagation and reach-analysis experiments
