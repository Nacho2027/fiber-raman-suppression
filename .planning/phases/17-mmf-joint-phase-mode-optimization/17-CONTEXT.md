---
phase: 17-mmf-joint-phase-mode-optimization
session: sessions/C-multimode (planted seed; may be executed by Session C if time allows, otherwise future session)
started: 2026-04-17 (planning only)
---

# Phase 17 — Joint (spectral phase + input mode coefficients) Optimization for MMF Raman Suppression

**Goal.** Compare phase-only vs joint (φ, c_m) Raman suppression at M=6 GRIN-50, L=1m, P=0.05W. Measure the dB improvement delta and characterize the optimal mode content.

**Why it matters (Rivera Lab link).** The only published classical analog of Rivera's arXiv:2509.03482 (2025) result — spatial wavefront shaping reduces quantum noise in MMF by 12 dB. That paper reshapes the spatial wavefront (equivalent to our `c_m`) while our earlier work reshaped only the temporal spectral phase. Phase 17 answers: *does the experimental "knob" Rivera's group uses matter for classical Raman suppression, and by how much?*

## Tasks (plan 01 — already scaffolded, just needs execution)

1. **Validate joint gradient** — `test/test_phase17_joint.jl`:
   - FD check on `cost_and_gradient_joint` at 5 random indices in the φ block (reuse existing MMF FD test protocol).
   - FD check on 2 indices in the (r, α) block.
   - M=1 sanity: at M=1 there's no c_m freedom, so the joint grad on the c_m block should be zero (constraint-projected) and the φ block should match `cost_and_gradient_mmf`.
2. **Warm-start benchmark** — run phase-only 20 iters at Phase 16 baseline config, then warm-start joint 30 iters. Compare against cold-start joint 50 iters. Warm-start should win on time.
3. **Three-seed baseline** — seeds 42, 123, 7. Produce `results/raman/phase17/joint_baseline_*.jld2` + figures.
4. **Mode-content characterization** — figure: initial vs final `|c_m|²` histogram. Table: angular drift `angle(c_opt_m) - angle(c_init_m)` per mode.
5. **Ablation** — c_m-only optimization (fix φ=0). How much gain comes from each knob independently?
6. **Write SUMMARY** with the delta measurements.

## Dependencies

- Phase 16 plan 01 baseline MUST complete first (provides the φ_init for warm-starts and the phase-only reference number).
- `scripts/mmf_joint_optimization.jl` (already scaffolded under sessions/C-multimode branch).

## Success criteria

- [ ] `test/test_phase17_joint.jl` passes 3 testsets.
- [ ] Joint optimization converges (J_history monotonic-ish).
- [ ] If ΔdB(joint) − ΔdB(phase-only) > 2 dB → paper-quality finding. Write up as a short note.
- [ ] If ΔdB delta < 1 dB → interesting *negative* finding. Document the physics reason (maybe the phase shaper already captures most of the available control authority).

## Out of scope

- Per-mode SPATIAL phase (only 1D mode-index basis; true spatial SLM control would require re-solving the fiber modes at each SLM pattern).
- Experimental realizability of arbitrary `c_m` — assumes perfect mode control.
- Quantum noise metrics (seed territory).

## Pre-execution checks

- `ls scripts/mmf_joint_optimization.jl` → file exists on sessions/C-multimode.
- `grep cost_and_gradient_joint scripts/mmf_joint_optimization.jl` → implementation present.
- Phase 16 plan 01 SUMMARY.md complete and φ_opt_phase_only JLD2 files available.
