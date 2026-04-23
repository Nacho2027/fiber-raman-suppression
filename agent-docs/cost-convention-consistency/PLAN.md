# Plan

Completed:

1. Read the required numerics context and seed docs.
2. Mapped every shared single-mode cost/gradient/HVP/reporting path.
3. Added an explicit machine-readable cost-surface spec helper.
4. Threaded that spec into trust reporting and HVP metadata.
5. Added gradient Taylor-remainder regression tests and HVP convention tests.
6. Documented the authoritative convention in `docs/cost-convention.md`.
7. Extended the explicit-surface convention to the multivariable and MMF shared-phase paths.
8. Fixed the MMF shared-phase `log_cost` ordering bug so regularizers are included before the dB transform.
9. Added multivariable/MMF regression coverage for explicit cost-surface specs and Taylor/FD consistency.

Deliberately not done in this session:

- broad refactors of MMF or multivariable objective code
- the MMF joint `(φ, c_m)` optimizer audit
- retroactive relabeling of historical artifacts under `results/`
