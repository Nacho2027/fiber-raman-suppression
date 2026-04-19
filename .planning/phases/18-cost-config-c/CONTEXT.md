# Phase 18 — Cost Audit Config C (HNLF L=1m P=0.5W)

**Opened:** 2026-04-19 (integration of Session H).
**Status:** Blocked. Needs a different compute strategy.

## Background

Session H ran a 4-variant × 3-config cost-function audit. Results at merge:

| Config | Fiber | L | P | Status | Winner / note |
|---|---|---|---|---|---|
| A | SMF-28 | 2 m | 0.20 W | ✅ 4/4 | **log_dB** (-75.8 dB, 10.6 s) vs linear (-70.5 dB, 17 s) |
| B | HNLF | ? | ? | ~ 3/4 | sharp variant DNF |
| C | HNLF | 1 m | 0.50 W | ❌ 0/4 | Both attempts on burst VM hung > 1 h |

Config C hung *twice* under default max_iter. That tells us something: either the HNLF-high-power configuration has a much harder cost-landscape than A/B (Raman threshold exceeded, multiple competing basins), or one of the 4 variants has a pathological interior loop (e.g., the noise-aware scaffold) that slows compute by 10×.

## Recommended strategy for re-attempt

1. **Single-variant pilot first.** Run only `log_dB` on Config C (since it won on Config A). That isolates whether the config is the bottleneck or a specific variant is.
2. **Shorter max_iter + more aggressive early-stop.** Cap at `max_iter=30` and require `|grad| < 1e-4` OR `ΔJ < 0.1 dB over 5 iter`.
3. **Metric subset.** Drop noise-aware for Config C (it's a scaffold anyway — no validated cost yet).
4. **Monitor live.** Stream the log via `tail -f results/burst-logs/H2-configC_*.log` and kill within 30 min if stalled. Do not leave it to run overnight.

## Definition of done

- At least `log_dB` lands a finite J on HNLF L=1m P=0.5W with convergence metadata.
- SUMMARY.md gains a row for Config C (can be single-variant).
- Bonus: if the hang has a clear cause (e.g., one variant explodes step-size), note it for Phase 14 sharp-A/B execution.

## Owned namespace

- `scripts/cost_audit_config_c.jl` (new; slim).
- `results/raman/phase16-cost-audit/configC/` (new).
- `.planning/phases/18-cost-config-c/` (this dir).
