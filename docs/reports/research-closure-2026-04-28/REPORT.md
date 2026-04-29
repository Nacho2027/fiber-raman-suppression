# Research Closure Report

Date: 2026-04-28

The exploratory phase is closed for now. The next useful work is packaging:
clear workflows, selected figures, honest status notes, and fewer orphaned docs.

## Main decisions

| Lane | Decision |
|---|---|
| Single-mode phase optimization | Supported core workflow. |
| Staged `amp_on_phase` | Experimental but useful after a phase solution. |
| Direct joint multivariable optimization | Negative/deferred; do not promote. |
| 200 m long fiber | Completed image-backed result, not optimizer-converged. |
| MMF | Qualified simulation candidate, not paper-grade broad claim. |
| Newton/preconditioning | Research note only. |

## Supported lab rollout

Use the single-mode phase commands:

```bash
make lab-ready
make golden-smoke
```

Default configs:

- `research_engine_export_smoke` for handoff smoke;
- `research_engine_poc` for the configurable single-mode baseline;
- approved canonical run/sweep configs for maintained examples.

## Evidence checked

| Lane | Evidence | Status |
|---|---|---|
| Long fiber | `results/raman/phase16/200m_overngt_opt_resume_result.jld2` and standard images | completed milestone |
| MMF | `results/raman/phase36_window_validation_gdd/mmf_window_validation_summary.md` and plots | qualified simulation |
| Multivar | `results/raman/multivar/variable_ablation_overnight_*_20260427/` | staged positive, direct joint negative |
| Supported smoke | latest `results/raman/smoke/smf28_phase_export_smoke_*` | supported handoff path |

## Numbers worth keeping

- Long fiber: `L = 200 m`, `P = 0.05 W`, `Nt = 65536`, `J_final = -55.1648 dB`, `converged = false`.
- MMF candidate: corrected 4096-grid boundary+GDD run, `J_ref = -17.96 dB`, `J_opt = -49.69 dB`, improvement `31.73 dB`.
- Staged multivar at SMF-28, `L = 2.0 m`, `P = 0.30 W`: phase-only `-40.79 dB`; amplitude on fixed phase `-46.91 dB`; direct warm `phase+amplitude+energy` `-31.04 dB`.

## Claims to avoid

- Direct joint multivariable optimization is generally better.
- MMF suppression is launch-robust, coupling-robust, or experimentally validated.
- The 200 m long-fiber result is optimizer-converged.
- Newton/preconditioning is production-ready.

## Next work

1. Keep README and guides centered on supported workflows.
2. Promote only selected figures and fixtures into git.
3. Leave routine `results/` output uncommitted.
4. Keep experimental configs visible but gated.
