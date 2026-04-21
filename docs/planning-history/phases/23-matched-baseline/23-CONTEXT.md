# Phase 23 — Matched Quadratic-Chirp 100m Baseline Context

**Gathered:** 2026-04-20  
**Status:** Ready for planning  
**Owner:** Session `M-matched100m`

## Objective

Determine whether Session F's `J = -51.50 dB` warm-start transfer at
`L = 100 m` is primarily a generic dispersive pre-chirp effect or whether the
non-quadratic structure of the stored `phi_opt@2m` materially improves Raman
suppression beyond what a matched quadratic chirp can do.

## Locked Decisions

- Use the same physical regime as the audited claim:
  `SMF-28`, `β_order = 2`, `L = 100.0 m`, `P_cont = 0.05 W`.
- Use Session F's long-fiber wrapper rather than `setup_raman_problem(...)`,
  so the chosen `Nt` and `time_window` are honored exactly.
- Require Phase-18-style numerical honesty before trusting any `J_dB`.
  Operationally: edge fraction must stay below `1e-3`, and preferably in the
  `1e-6` to `1e-5` range already demonstrated by Session F.
- Emit the mandatory standard image set for:
  - warm-start rerun
  - matched quadratic baseline
  - every `a₂` sweep point if a sweep is used
- All new executable code stays under `scripts/matched_*.jl`.
- Do not modify shared files such as `scripts/common.jl`,
  `scripts/visualization.jl`, `scripts/raman_optimization.jl`, or `src/**`.

## Canonical Inputs

- Audit framing:
  `results/PHYSICS_AUDIT_2026-04-19.md` §S5 and §W1
- Session F results:
  `results/raman/phase16/FINDINGS.md`
- Warm-start artifact to reuse:
  `results/raman/phase16/100m_validate_fixed.jld2`
- Long-fiber numerical wrapper and interpolation pattern:
  `scripts/longfiber_setup.jl`
- Session F handoff / status:
  `.planning/sessions/F-standdown.md`
  `.planning/sessions/F-longfiber-status.md`

## Existing Code Insights

- `scripts/longfiber_setup.jl::setup_longfiber_problem(...)` gives the exact
  100 m grid Session F used without the auto-sizing override.
- `scripts/longfiber_setup.jl::longfiber_interpolate_phi(...)` already handles
  physical-frequency interpolation from the stored 2 m grid to the 100 m grid.
- `scripts/standard_images.jl::save_standard_set(...)` already produces the
  mandatory four-image bundle once `phi_opt`, `uω0`, `fiber`, `sim`,
  `band_mask`, `Δf`, and the Raman threshold are available.
- Session F's reference configuration was:
  `Nt = 32768`, `time_window = 160 ps`, with trusted BC/energy metrics.

## Open Gray Areas Resolved For Auto Mode

- **How to choose the quadratic baseline?**
  Use a threaded coarse sweep over `a₂` by default. This is more robust than a
  single least-squares fit if the warm-start trajectory is not exactly
  quadratic-compatible.
- **What does "matched" mean?**
  Match the warm-start peak-power trajectory as closely as practical using a
  scalar mismatch metric over `z`, then judge the selected chirp by endpoint
  `J_dB` and visual evolution overlay.
- **What counts as a decisive result?**
  Adopt the audit-friendly thresholds: within `~3 dB` kills S5, `>=10 dB`
  worse preserves S5, in-between means partial explanation.

## Deliverables

- `scripts/matched_quadratic_100m.jl` or equivalent phase-owned driver
- Standard images under
  `.planning/phases/23-matched-baseline/images/`
- One overlay plot comparing warm-start vs matched-quadratic evolution
- `.planning/phases/23-matched-baseline/SUMMARY.md` with:
  - `J_dB` comparison
  - one-paragraph verdict suitable for `verification_document.tex` §S5
  - notes on grid trustworthiness and matching method
