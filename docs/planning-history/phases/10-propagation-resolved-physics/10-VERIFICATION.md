---
phase: 10-propagation-resolved-physics
verified: 2026-04-03T04:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: null
gaps: []
human_verification:
  - test: "View figures physics_10_01 through physics_10_09 for visual coherence"
    expected: "Semilogy J(z) curves clearly show shaped vs unshaped divergence; heatmaps show Raman band evolution; ablation bar charts and robustness curves are readable with correct axis labels"
    why_human: "Visual correctness and communicative quality cannot be verified programmatically"
  - test: "Confirm smf28_L5m_P0.2W long-fiber finding is physically meaningful"
    expected: "Shaped J(z) should show breakdown at z=0.204m as reported; unshaped should stay near initial value"
    why_human: "Requires domain knowledge to interpret whether the onset z-position is physically sensible for this fiber/power combination"
---

# Phase 10: Propagation-Resolved Physics Verification Report

**Phase Goal:** Understand the 84% of Raman suppression that Phase 9 attributed to "configuration-specific nonlinear interference" by running NEW simulations with z-resolved diagnostics and spectral phase ablation experiments. Track where Raman energy builds up along the fiber, determine which frequency components of phi_opt matter most, and test robustness of optimal phases to parameter perturbations.
**Verified:** 2026-04-03T04:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Z-resolved Raman energy evolution computed for 6 configs (3 SMF-28 + 3 HNLF) with and without optimal phase | VERIFIED | 12 JLD2 files in `results/raman/phase10/` (50 z-points each); PHASE10_ZRESOLVED_FINDINGS.md table with all 6 configs; physics_10_01 figure |
| 2 | Spectral phase ablation reveals which frequency bands of phi_opt contribute most to suppression | VERIFIED | `scripts/phase_ablation.jl` runs 10-band zeroing with super-Gaussian windows; `ablation_smf28_canonical.jld2` and `ablation_hnlf_canonical.jld2` store band_zeroing_J[10]; PHASE10_ABLATION_FINDINGS.md table identifies critical bands |
| 3 | Perturbation robustness quantified: scaling, shift, truncation vs 3 dB degradation | VERIFIED | `perturbation_smf28_canonical.jld2` and `perturbation_hnlf_canonical.jld2` contain scale_J[8] and shift_J[7] with real computed values; findings documents report 3 dB envelope as [1.0, 1.0] for both configs (sharply peaked optimum) and sub-1 THz shift tolerance |
| 4 | At least one new hypothesis about suppression mechanism emerges from z-resolved data | VERIFIED | PHASE10_ZRESOLVED_FINDINGS.md Section 6 states 3 preliminary hypotheses (delayed-onset, redistribution, regime-separation); PHASE10_ABLATION_FINDINGS.md Section 5 states 4 hypotheses (H1-H4) with supporting evidence from the ablation data |
| 5 | All new simulations save z-resolved data to JLD2 for future analysis | VERIFIED | 12 `*_zsolved.jld2` files (50-z-point uω_z/ut_z/J_z arrays) and 4 ablation/perturbation JLD2 files present in `results/raman/phase10/` |

**Score:** 5/5 truths verified

---

### Required Artifacts

#### Plan 01 Artifacts

| Artifact | Min Lines | Actual Lines | Status | Notes |
|----------|-----------|--------------|--------|-------|
| `scripts/propagation_z_resolved.jl` | 300 | 827 | VERIFIED | Contains all required functions and main block |
| `results/raman/phase10/` (12 JLD2 files) | — | 12 *_zsolved.jld2 present | VERIFIED | Sizes 13 MB (HNLF short) to 53 MB (SMF-28 5m) — consistent with 50×Nt×1 complex field arrays |
| `results/images/physics_10_01_raman_fraction_vs_z.png` | 50 KB | 504 KB | VERIFIED | |
| `results/images/physics_10_02_spectral_evolution_comparison.png` | 50 KB | 276 KB | VERIFIED | |
| `results/images/physics_10_03_temporal_evolution_comparison.png` | 50 KB | 281 KB | VERIFIED | |
| `results/images/physics_10_04_nsol_regime_comparison.png` | 50 KB | 436 KB | VERIFIED | |
| `results/raman/PHASE10_ZRESOLVED_FINDINGS.md` | — | 5.4 KB | VERIFIED | Contains 6-row onset table, N_sol regime analysis, 3 hypotheses |

#### Plan 02 Artifacts

| Artifact | Min Lines | Actual Lines | Status | Notes |
|----------|-----------|--------------|--------|-------|
| `scripts/phase_ablation.jl` | 400 | 1116 | VERIFIED | Contains all 4 experiment functions and main block |
| `results/raman/phase10/ablation_smf28_canonical.jld2` | — | 7.7 KB | VERIFIED | Contains band_zeroing_J[10], cumulative_J[6], sub_bands[10], J_full, J_flat — real computed values |
| `results/raman/phase10/ablation_hnlf_canonical.jld2` | — | 7.7 KB | VERIFIED | Same structure |
| `results/raman/phase10/perturbation_smf28_canonical.jld2` | — | 1.8 KB | VERIFIED | Contains scale_J[8], shift_J[7], scale_factors, shift_THz — real propagation outputs |
| `results/raman/phase10/perturbation_hnlf_canonical.jld2` | — | 1.8 KB | VERIFIED | Same structure |
| `results/images/physics_10_05_ablation_band_zeroing.png` | 50 KB | 192 KB | VERIFIED | |
| `results/images/physics_10_06_ablation_cumulative.png` | 50 KB | 228 KB | VERIFIED | |
| `results/images/physics_10_07_scaling_robustness.png` | 50 KB | 291 KB | VERIFIED | |
| `results/images/physics_10_08_spectral_shift_robustness.png` | 50 KB | 273 KB | VERIFIED | |
| `results/images/physics_10_09_ablation_summary.png` | 50 KB | 615 KB | VERIFIED | |
| `results/raman/PHASE10_ABLATION_FINDINGS.md` | — | 6.9 KB | VERIFIED | Contains band table, 3 dB analysis, 4 hypotheses |

---

### Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|-----|--------|----------|
| `scripts/propagation_z_resolved.jl` | `results/raman/sweeps/*/opt_result.jld2` | `JLD2.load` on line 123 | WIRED | `jld2_path = joinpath("results", "raman", "sweeps", fiber_dir, config_name, "opt_result.jld2")` |
| `scripts/propagation_z_resolved.jl` | `scripts/common.jl` | `include("common.jl")` on line 42 | WIRED | Direct include confirmed |
| `scripts/propagation_z_resolved.jl` | `MultiModeNoise.solve_disp_mmf` | Lines 159, 166 | WIRED | `MultiModeNoise.solve_disp_mmf(uω0_shaped, fiber_shaped, sim)` with zsave set |
| `scripts/phase_ablation.jl` | `results/raman/sweeps/smf28/L2m_P0.2W/opt_result.jld2` | `JLD2.load` on line 93 | WIRED | Absolute path constructed via `_PAB_PROJECT_ROOT`; L2m_P0.2W in PAB_CONFIGS |
| `scripts/phase_ablation.jl` | `results/raman/sweeps/hnlf/L1m_P0.01W/opt_result.jld2` | `JLD2.load` on line 93 | WIRED | L1m_P0.01W in PAB_CONFIGS |
| `scripts/phase_ablation.jl` | `scripts/common.jl` | `include(joinpath(_PAB_SCRIPT_DIR, "common.jl"))` on line 46 | WIRED | Absolute path via script dir |
| `scripts/phase_ablation.jl` | `MultiModeNoise.solve_disp_mmf` | Line 145 | WIRED | `sol = MultiModeNoise.solve_disp_mmf(uω0_mod, fiber_prop, sim)` |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `PHASE10_ZRESOLVED_FINDINGS.md` | J_z_shaped, J_z_unshaped, onset_z | `pz_load_and_repropagate` → `solve_disp_mmf` → `spectral_band_cost` on each z-slice | Yes — JLD2 files are 13-53 MB (large complex field arrays); J values are non-trivial floats (e.g., -77.6 dB shaped vs -31.9 dB unshaped for SMF-28 N=1.3) | FLOWING |
| `PHASE10_ABLATION_FINDINGS.md` | band_zeroing_J[10], scale_J[8], shift_J[7] | `pab_propagate_and_cost` → `solve_disp_mmf` → `spectral_band_cost` at z=L | Yes — JLD2 files contain non-trivial float arrays; values span large dynamic range (e.g., SMF-28 J_full = 8.8e-7, J_flat = 0.77); shift_J shows catastrophic degradation at ±5 THz consistent with expected physics | FLOWING |
| `perturbation_*.jld2` | scale_J, shift_J | Real propagation loop in `pab_propagate_and_cost` | Yes — 8 scale values and 7 shift values contain physically meaningful floats distinguishable from stubs; `perturbation_smf28_canonical.jld2` has J_full = 8.824e-7 matching J_full in ablation file | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for image files and JLD2 binary data (no runnable entry points to test without re-running 60+ propagations). Script syntax was already validated at commit time (commits 966352e and 2385e1e both run successfully per SUMMARY evidence).

Partial check — key invariant verified programmatically:

| Behavior | Evidence | Status |
|----------|----------|--------|
| perturbation J_full matches ablation J_full (same config) | `perturbation_smf28.jld2` J_full = 8.824093394820633e-7; `ablation_smf28.jld2` J_full = 8.824093394820633e-7 — identical to float precision | PASS |
| 12 z-solved JLD2 files for 6 configs x 2 conditions | Confirmed by `ls` showing exactly 12 `*_zsolved.jld2` files | PASS |
| ablation band_zeroing_J has 10 values (one per sub-band) | `band_zeroing_J: length=10` confirmed from JLD2 inspection | PASS |
| scale_J has 8 values matching PAB_SCALE_FACTORS | `scale_J: length=8` with values [0.775, 9.1e-5, ..., 2.7e-5] confirmed | PASS |
| shift_J has 7 values matching PAB_SHIFT_THZ | `shift_J: length=7` with values matching expected degradation curve | PASS |

---

### Requirements Coverage

The PLAN frontmatter requirement IDs (SC-1 through SC-5, "Phase 9 deferred H5") map to the 5 ROADMAP Success Criteria — these are phase-local IDs, not REQUIREMENTS.md IDs (which use VERIF-xx, XRUN-xx, PATT-xx, SWEEP-xx prefixes). No Phase 10 rows exist in REQUIREMENTS.md; the ROADMAP explicitly states "Requirements: Derived from Phase 9 deferred hypothesis H5 and open questions." No orphaned REQUIREMENTS.md IDs were found.

| Requirement ID (Plan) | Maps To | Status | Evidence |
|-----------------------|---------|--------|----------|
| SC-1: Z-resolved Raman energy evolution for 6 configs | ROADMAP Success Criterion 1 | SATISFIED | 12 JLD2 files + physics_10_01 figure + findings table |
| SC-2: Spectral phase ablation reveals critical frequency bands | ROADMAP Success Criterion 2 | SATISFIED | 10-band zeroing results in ablation JLD2 + findings table |
| SC-3: Perturbation robustness quantified (3 dB envelope) | ROADMAP Success Criterion 3 | SATISFIED | Scale and shift experiments; 3 dB envelope = [1.0, 1.0] (narrow peak) documented |
| SC-4: New hypothesis from z-resolved/ablation data | ROADMAP Success Criterion 4 | SATISFIED | 3 hypotheses in PHASE10_ZRESOLVED_FINDINGS.md; 4 hypotheses (H1-H4) in PHASE10_ABLATION_FINDINGS.md |
| SC-5: All new simulations save z-resolved data to JLD2 | ROADMAP Success Criterion 5 | SATISFIED | 16 JLD2 files in results/raman/phase10/ |
| Phase 9 deferred H5: propagation-resolved diagnostics | Internal research requirement | SATISFIED | 50-point z-resolved propagation of 12 runs directly addresses H5 |

---

### Anti-Patterns Found

No TODO, FIXME, PLACEHOLDER, or empty-return anti-patterns found in either script. No commented-out code stubs detected.

| File | Pattern | Severity | Verdict |
|------|---------|----------|---------|
| `propagation_z_resolved.jl` | `return null / return []` | — | NONE FOUND |
| `phase_ablation.jl` | `return null / return []` | — | NONE FOUND |
| Both scripts | TODO/FIXME/PLACEHOLDER | — | NONE FOUND |

One noteworthy pattern in `propagation_z_resolved.jl`: uses relative `include("common.jl")` (line 42) rather than absolute path. This works when the script is run from the `scripts/` directory or via `julia scripts/propagation_z_resolved.jl` from the project root (Julia sets the working directory to the script's directory for `include`). The `phase_ablation.jl` fixed this via `_PAB_PROJECT_ROOT`. Not a blocker — the script was successfully run as evidenced by the generated JLD2 files and commit 966352e.

---

### Human Verification Required

#### 1. Visual quality of all 9 diagnostic figures

**Test:** Open `results/images/physics_10_01_raman_fraction_vs_z.png` through `physics_10_09_ablation_summary.png`
**Expected:** J(z) semilogy curves clearly distinguish shaped (blue) vs unshaped (vermillion) trajectories; heatmaps show visible Raman band buildup; ablation bar charts and robustness curves are legible with correct axis labels and annotated baselines
**Why human:** Plot aesthetics, readability, and physics communication quality cannot be verified programmatically

#### 2. Physical plausibility of long-fiber SMF-28 breakdown finding

**Test:** Review `results/images/physics_10_01_raman_fraction_vs_z.png` panel for "SMF-28 N=2.6 (5m)" and the PHASE10_ZRESOLVED_FINDINGS.md Section 5
**Expected:** Shaped J(z) should begin rising at z~0.204 m while unshaped J(z) rises earlier; the 40 dB degradation relative to L=0.5m is explained by the inability of phi_opt to maintain suppression over the longer propagation distance
**Why human:** Requires domain judgment about whether z=0.204m onset (4.1% of 5m fiber) is physically reasonable vs a numerical artifact

---

### Gaps Summary

No gaps found. All 5 success criteria are achieved:

1. 12 z-resolved JLD2 files (50 z-points, shaped+unshaped for 6 configs) are present and contain large complex field arrays consistent with real propagation data.
2. Band zeroing experiments (10 sub-bands, super-Gaussian windowing) completed for both canonical configs with results saved to JLD2 and summarized in findings.
3. Scaling robustness (8 factors) and spectral shift sensitivity (7 offsets) are quantified — the ultra-narrow 3 dB envelope (scale = 1.0 exactly) and sub-1 THz shift tolerance are new quantitative findings not accessible from Phase 9.
4. Multiple new hypotheses are documented in both findings files, including the "spectrally distributed, not localized" interpretation (H1 in PHASE10_ABLATION_FINDINGS.md) that directly addresses the 84% non-polynomial phase finding from Phase 9.
5. All 16 JLD2 files in `results/raman/phase10/` persist for future analysis.

Both commits (966352e, 2385e1e) are present in git log.

---

_Verified: 2026-04-03T04:00:00Z_
_Verifier: Claude (gsd-verifier)_
