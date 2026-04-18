---
phase: 16
slug: cost-function-head-to-head-audit
status: draft
nyquist_compliant: partial
wave_0_complete: true
created: 2026-04-17
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `16-RESEARCH.md` §Validation Architecture (lines 644–687).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Test.jl (Julia stdlib) — project standard; idiomatic shape from `test/test_phase14_regression.jl` |
| **Config file** | None — `@testset` blocks live directly in `test/*.jl` files |
| **Quick run command** | `julia --project=. test/test_cost_audit_unit.jl` |
| **Full suite command** | `julia --project=. test/test_cost_audit_unit.jl && julia --project=. test/test_phase14_regression.jl && julia --project=. test/test_determinism.jl` |
| **Estimated runtime** | ~30 s (unit) / ~5 min (integration smoke on config A at Nt=1024) / ~90 min (full batch, burst VM) |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. test/test_cost_audit_unit.jl` (≤ 30 s — 4 unit tests: D-04 gradient, D-04 zero-penalty reduction, determinism, import-order smoke).
- **After every plan wave:** Full quick-suite (add Phase 14 regression + determinism regression).
- **Before `/gsd-verify-work`:** All regression + unit green AND the 12-run batch CSVs/PNGs present AND `test/test_cost_audit_analyzer.jl` passes against real outputs.
- **Max feedback latency:** 30 s per task; 90 min per phase batch (burst VM).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 0 | D-04 gradient (curvature penalty matches FD at O(ε²)) | — | `@assert γ_curv ≥ 0` preconditions | unit (Taylor-remainder) | `julia --project=. test/test_cost_audit_unit.jl` | ❌ W0 | ⬜ pending |
| 16-01-02 | 01 | 0 | D-04 scale consistency (γ_curv=0 → D-01 byte-identical) | — | N/A | unit | `julia --project=. test/test_cost_audit_unit.jl` | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 0 | D-05/D-06 determinism (same seed → bit-identical φ_opt, linear variant) | — | N/A — uses Phase 15 determinism | unit | `julia --project=. test/test_cost_audit_unit.jl` | ❌ W0 | ⬜ pending |
| 16-01-04 | 01 | 0 | D-07/D-08 protocol smoke (4 variants valid OptimizationResult on config A, max_iter=10) | — | N/A | integration | `julia -t 4 --project=. test/test_cost_audit_integration_A.jl` | ❌ W0 | ⬜ pending |
| 16-01-05 | 01 | 1 | Phase 14 regression baseline (vanilla path unchanged) | — | N/A | regression | `julia --project=. test/test_phase14_regression.jl` | ✅ | ⬜ pending |
| 16-01-06 | 01 | 1 | Phase 15 determinism regression (bit-identity) | — | N/A | regression | `julia --project=. test/test_determinism.jl` | ✅ | ⬜ pending |
| 16-01-07 | 01 | 1 | D-04 wrapper module implemented (`scripts/cost_audit_noise_aware.jl`) | D-04 | `@assert` gradients finite | unit | same as 16-01-01..03 | ❌ W0 | ⬜ pending |
| 16-01-08 | 01 | 1 | Driver module implemented (`scripts/cost_audit_driver.jl`) | D-20 | FFTW wisdom loaded per-run; JLD2 host marker | integration | `julia -t 4 test/test_cost_audit_integration_A.jl` | ❌ W0 | ⬜ pending |
| 16-01-09 | 01 | 1 | Analyzer module implemented (`scripts/cost_audit_analyze.jl`) | — | N/A | contract | `julia --project=. test/test_cost_audit_analyzer.jl` | ❌ W0 | ⬜ pending |
| 16-01-10 | 01 | 2 | 12-run batch runs to completion on burst VM | D-20, R8 | `burst-stop` in trap; heavy-lock released | system | (driver run itself; gated by `results/cost_audit/summary_all.csv` presence) | ❌ (produced by 16-01-10) | ⬜ pending |
| 16-01-11 | 01 | 2 | CSV schema matches CONTEXT D-16 column list exactly | D-16 | N/A | contract | `julia --project=. test/test_cost_audit_analyzer.jl` (csv_schema assertion) | ❌ W0 | ⬜ pending |
| 16-01-12 | 01 | 2 | 4 PNGs at 300 DPI, file size > 20 KB each | D-18 | N/A | contract | `julia --project=. test/test_cost_audit_analyzer.jl` (figures_exist assertion) | ❌ W0 | ⬜ pending |
| 16-01-13 | 01 | 2 | Nyquist completeness (every (variant, config) has all 8 metrics; NaN only on explicitly-flagged DNF) | D-14 | N/A | nyquist | `julia --project=. test/test_cost_audit_analyzer.jl` (nyquist_complete assertion) | ❌ W0 | ⬜ pending |
| 16-01-14 | 01 | 3 | Decision doc `.planning/notes/cost-function-default.md` with recommendation + ML-literature section | — | N/A | manual review | (hand-written; `wc -w .planning/notes/cost-function-default.md > 500`) | ❌ | ⬜ pending |
| 16-01-15 | 01 | 3 | Rule P1 namespace compliance (no edits outside owned paths) | — | N/A | contract | `git diff --stat main...HEAD` ∩ forbidden-path-regex = ∅ | N/A | ⬜ pending |
| 16-01-16 | 01 | 3 | Performance budget (batch ≤ 120 min total wall on 22 cores) | — | N/A | performance | (manual log inspection vs. `results/cost_audit/wall_log.csv`) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_cost_audit_unit.jl` — Taylor-remainder gradient for D-04 curvature penalty; zero-penalty reduction to D-01; determinism smoke at Nt=1024 for speed (~ 2 min total). Covers D-04, D-05, D-06.
- [ ] `test/test_cost_audit_integration_A.jl` — Each of the 4 variants runs to completion on config A downsized to `max_iter=10`; produces non-NaN J_final. Target ≤ 5 min. Covers D-07, D-08.
- [ ] `test/test_cost_audit_analyzer.jl` — CSV schema, figures-exist, Nyquist completeness assertions. Runs post-batch on the real Wave-2 outputs. Covers D-14, D-16, D-18.
- [ ] `scripts/cost_audit_noise_aware.jl` — `cost_and_gradient_curvature` function + the `∂J/∂φ` gradient for the curvature penalty (hand-derived, same form as existing `λ_gdd` penalty at `raman_optimization.jl:114`).
- [ ] `scripts/cost_audit_driver.jl` — the 12-run orchestrator; FFTW wisdom load; deepcopy(fiber) per thread; per-(variant, config) JLD2 snapshot.
- [ ] `scripts/cost_audit_analyze.jl` — the CSV/figure producer; reads `results/cost_audit/<cfg>/*.jld2`, writes `summary.csv`, `summary_all.csv`, 4 PNGs.

*(No framework install needed — Test.jl is stdlib; existing tests follow the project's unadorned `@testset` pattern.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Batch ran on burst VM (not claude-code-host) | D-20 | No programmatic way to assert "this was hostname fiber-raman-burst" at test time; each JLD2 records `Sys.gethostname()` but verification is eyeball | `grep -l "fiber-raman-burst" results/cost_audit/**/*_meta.txt` must find 12 files |
| Decision doc reads well, cites ML literature correctly | — | Quality/style judgement, not mechanical | Read the doc end-to-end; verify Foret 2020, Kwon 2021, Zhuang 2022, Li 2018, Hochreiter & Schmidhuber 1997, Keskar 2017, Wilson 2017 all cited with the correct claims attributed |
| Performance budget | D-20 | Requires aggregating wall times across 12 runs + eigendecomps + analyzer; any hard-coded threshold would be brittle | Inspect `results/cost_audit/wall_log.csv`; confirm total ≤ 120 min |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (3 test files + 3 new scripts)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30 s per unit; < 5 min per integration
- [ ] `nyquist_compliant: true` set in frontmatter (after Wave 0 complete)

**Approval:** pending
