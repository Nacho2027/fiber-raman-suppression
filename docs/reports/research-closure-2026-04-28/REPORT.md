# Research Closure Report

Date: 2026-04-28

Stop opening new research branches until the current results are packaged:
clear commands, selected figures, accurate status notes, and fewer orphaned
files.

## Main decisions

| Lane | Decision |
|---|---|
| Single-mode phase optimization | Main command path. |
| Staged `amp_on_phase` | Research follow-up after a phase solution. |
| Direct joint multivariable optimization | Negative/deferred; do not promote. |
| 200 m long fiber | Completed image-backed result, not optimizer-converged. |
| MMF | One corrected simulation result, not a general MMF claim. |
| Newton/preconditioning | Research note only. |

## Supported lab rollout

Use the single-mode phase commands:

```bash
make lab-ready
make golden-smoke
```

Default configs:

- `research_engine_export_smoke` for export smoke;
- `research_engine_poc` for the configurable single-mode baseline;
- approved canonical run/sweep configs for maintained examples.

## Evidence checked

| Lane | Evidence | Status |
|---|---|---|
| Long fiber | `results/raman/phase16/200m_overngt_opt_resume_result.jld2` and standard images | completed milestone |
| MMF | `results/raman/phase36_window_validation_gdd/mmf_window_validation_summary.md` and plots | qualified simulation |
| Multivar | `results/raman/multivar/variable_ablation_overnight_*_20260427/` | staged positive, direct joint negative |
| Supported smoke | latest `results/raman/smoke/smf28_phase_export_smoke_*` | export path checked |

## Numbers to keep

- Long fiber: `L = 200 m`, `P = 0.05 W`, `Nt = 65536`, `J_final = -55.1648 dB`, `converged = false`.
- MMF candidate: corrected 4096-grid boundary+GDD run, `J_ref = -17.96 dB`, `J_opt = -49.69 dB`, improvement `31.73 dB`.
- Staged multivar at SMF-28, `L = 2.0 m`, `P = 0.30 W`: phase-only `-40.79 dB`; amplitude on fixed phase `-46.91 dB`; direct warm `phase+amplitude+energy` `-31.04 dB`.

## Claims to avoid

- Direct joint multivariable optimization is generally better.
- MMF suppression is launch-robust, coupling-robust, or experimentally validated.
- The 200 m long-fiber result is optimizer-converged.
- Newton/preconditioning is ready for routine runs.

## Next work

1. Keep README and guides centered on the commands people should run.
2. Promote only selected figures and fixtures into git.
3. Leave routine `results/` output uncommitted.
4. Keep experimental configs visible but gated.
