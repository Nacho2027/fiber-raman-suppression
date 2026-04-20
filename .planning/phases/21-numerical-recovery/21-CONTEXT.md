# Phase 21: Numerical Recovery of SUSPECT Results — Context

**Gathered:** 2026-04-20  
**Status:** Ready for execution  
**Mode:** Autonomous overnight recovery  
**Session owner:** `sessions/I-recovery`

<domain>
## Phase Boundary

Phase 21 exists to decide which Phase 18-era SUSPECT results survive on an
honest temporal grid. The numerical-trustworthiness audit already established
that the core failure mode is not random optimizer noise: many saved `phi_opt`
files are genuine stationary points on their own grids, but those grids were
too small, so the optimizer partly fit time-window edge reflections instead of
the intended nonlinear physics.

This phase therefore does **not** re-litigate the adjoint, the cost function,
or the qualitative Hessian story. It re-anchors the affected dB numbers on
grids where the pulse physically fits. A result only counts as recovered when
the output edge fraction is `< 1e-3` on the validation grid.

Priority order from the user:
1. Sweep-1 at `SMF-28, L=2 m, P=0.2 W` for 7 `N_phi` levels.
2. Session F 100 m result — validate the nonstandard `100m_validate_fixed.jld2`
   schema honestly and fold it into the same recovery logic.
3. Phase 13 Hessian anchors (`SMF-28` and `HNLF`) — re-anchor only the dB,
   keeping the eigenstructure verdict intact unless the stationary point itself
   disappears.
4. Opportunistic MMF aggressive regime (`M=6, L=2 m, P=0.5 W`) if budget
   remains after the first three priorities.

</domain>

<decisions>
## Implementation Decisions

### D21-01: Owned namespace only
- New code lives under `scripts/recovery_*.jl`.
- New tracked artifacts live under `.planning/phases/21-numerical-recovery/`.
- No edits to `scripts/common.jl`, `scripts/visualization.jl`, `src/**`,
  `Project.toml`, or `Manifest.toml`.
- Existing Session F / Session C helpers may be **read** and **included**, but
  not modified.

### D21-02: Honest-grid rule
- Grids are chosen from first principles using the same ingredients the code
  already encodes physically: dispersive walk-off (`|β₂| L Δω`) plus
  SPM-broadened bandwidth (`δω ≈ 0.86 φ_NL / T0` for sech² pulses), with a
  larger safety factor than the production sweep used.
- The formula only sets the **starting guess** for the time window.
- The final grid is accepted only after direct forward propagation of the flat
  pulse and the relevant warm-start `phi_opt` seeds shows output edge fraction
  `< 1e-3`.
- If that check fails, the time window is doubled and `Nt` is increased to keep
  femtosecond-scale resolution.

### D21-03: Warm-start policy
- When an existing `phi_opt` exists, the recovery run starts from it.
- For single-mode runs, warm starts are interpolated to the new grid with
  `longfiber_interpolate_phi(...)` from Session F's helper.
- For Sweep-1 low-dimensional runs, the interpolated `phi_opt` is projected
  onto the new basis as the initial coefficient vector.

### D21-04: Parallelism policy
- Within a priority bucket, independent optimizations run under
  `Threads.@threads`.
- Sweep-1 launches the 7 `N_phi` cases independently in parallel.
- Phase 13 launches the 2 re-anchor configs independently in parallel.
- No heavy jobs overlap across priority buckets; the burst VM still runs one
  heavy wrapper invocation at a time.

### D21-05: Standard-image rule is mandatory
- Every recovered or validated `phi_opt` must emit the four canonical images
  through `save_standard_set(...)`.
- Output directory for Phase 21 image artifacts:
  `.planning/phases/21-numerical-recovery/images/`.
- Runs that save a `phi_opt` but not the image set are incomplete.

### D21-06: Session F 100 m treatment
- The 100 m result is already numerically honest on its published grid
  (`Nt=32768`, `T=160 ps`, edge fraction `8.46e-6` in Session F's status log).
- The recovery work here is to discover the schema of
  `results/raman/phase16/100m_validate_fixed.jld2`, extract the stored `phi_opt`
  and headline numbers, re-run the forward validation on the same honest grid,
  and normalize the result into a Phase-21 report.
- Unless the schema is broken or the stored phase is missing, Phase 21 does not
  spend overnight compute re-optimizing the 100 m case.

### D21-07: Phase 13 treatment
- The Hessian eigenspectrum finding already survived the audit qualitatively.
- Recovery re-optimizes on honest grids seeded from the original `phi_opt`.
- Deliverable is the new honest `J_dB` plus a short note on whether the
  stationary point persisted after grid repair.

### D21-08: MMF is opportunistic
- MMF aggressive is only attempted after the first three priorities complete or
  cleanly fail.
- It reuses Session C's validated MMF setup and optimization path, but writes
  Phase-21-owned outputs and images.

</decisions>

<canonical_refs>
## Canonical References

### Local audit inputs
- `results/PHYSICS_AUDIT_2026-04-19.md`
- `results/validation/REPORT.md`
- `results/validation/sweep1_Nphi_001_SMF28_L2_P0.2_Nphi4_cubic.md`
- `results/validation/sweep1_Nphi_007_SMF28_L2_P0.2_Nphi16384_identity.md`
- `results/validation/phase13_hessian_smf28.md`
- `results/validation/phase13_hessian_hnlf.md`
- `.planning/sessions/F-longfiber-status.md`
- `.planning/sessions/F-longfiber-decisions.md`

### Existing code to reuse read-only
- `scripts/longfiber_setup.jl`
- `scripts/longfiber_checkpoint.jl`
- `scripts/sweep_simple_param.jl`
- `scripts/mmf_setup.jl`
- `scripts/mmf_raman_optimization.jl`
- `scripts/standard_images.jl`
- `scripts/raman_optimization.jl`

### Existing result containers
- `results/raman/phase_sweep_simple/sweep1_Nphi.jld2`
- `results/raman/phase13/hessian_smf28_canonical.jld2`
- `results/raman/phase13/hessian_hnlf_canonical.jld2`
- `results/raman/phase16/100m_validate_fixed.jld2`

</canonical_refs>

<code_context>
## Existing Code Insights

- `setup_raman_problem(...)` silently auto-overrides undersized windows and is
  therefore not suitable for a phase whose central purpose is honest grid
  selection. Session F's `setup_longfiber_problem(...)` is the correct bypass.
- `cost_and_gradient(...)` takes `φ` shaped like `uω0`, i.e. `(Nt, M)`.
- `optimize_spectral_phase(...)` returns an `Optim.Result`; the saved phase is
  `reshape(Optim.minimizer(result), Nt, M)`.
- `optimize_phase_lowres(...)` in `scripts/sweep_simple_param.jl` already
  handles low-dimensional phase parameterizations and returns the reconstructed
  full-grid `phi_opt`.
- `check_boundary_conditions(...)` evaluates energy in the first/last 5% of the
  time grid and is the exact gate used by the audit.
- `save_standard_set(...)` accepts `phi_opt` plus the setup tuple and already
  generates the mandatory image set at 300 DPI.

</code_context>

<specifics>
## Specific Questions This Phase Must Answer

1. Does the Sweep-1 `N_phi` knee persist once the pulse is kept off the window
   edges, or was the simplicity story partly an artifact of edge fitting?
2. Does Session F's 100 m result survive an honest schema-aware validation as a
   real long-fiber lower bound, even if it remains non-converged?
3. After re-anchoring Phase 13 on honest grids, are the saddle points still
   present and merely less impressive in dB, or do they move materially?
4. In a genuinely nonlinear MMF regime (`M=6, L=2 m, P=0.5 W`), does the
   validated multimode optimizer show nonzero Raman-suppression headroom?

</specifics>

<deferred>
## Deferred Ideas

- Matched quadratic-chirp 100 m baseline is Phase 23, not Phase 21.
- Sharpness-aware or Hessian-aware optimizer variants are Phase 22, not here.
- Shared-library fixes to `scripts/common.jl` remain out of scope.
- Bulk regeneration of all Phase 18 SUSPECT points is out of scope; this phase
  focuses only on the four priority buckets named by the user.

</deferred>

---

*Phase: 21-numerical-recovery*  
*Context gathered: 2026-04-20 by Session I autonomous recovery*
