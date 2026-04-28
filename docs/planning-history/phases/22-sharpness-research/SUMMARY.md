# Phase 22 Summary

**Generated:** 2026-04-20 03:07:14

## Verdict

- Across the resolved Hessian spectra in the completed Phase 22 sweep, every measured optimum remained Hessian-indefinite in the optimized control space. That is the main geometry result: flattening the basin, when it happened at all, did not convert these optima into clean positive-definite minima.
- On the canonical point, the best robustness gain was 0.058 rad at a depth cost of 10.08 dB; on the Pareto-57 point, the best gain was 0.066 rad at a depth cost of 16.12 dB.
- SAM did not produce a useful robustness Pareto in this sweep: its best sigma shift was -0.006 rad on the canonical point and 0.001 rad on Pareto-57, both negligible relative to the trace and strong-MC objectives.
- MC gave the cheaper robustness option on the canonical point (+0.014 rad for 3.85 dB depth loss), while the Hessian-trace penalty delivered the largest tolerance gains (+0.058 rad canonical, +0.066 rad Pareto-57) at a much steeper cost (10.08 dB and 16.12 dB, respectively).
- The current evidence does not justify replacing the default log-dB optimizer. The defensible default remains the plain objective; `trH` and, secondarily, strong MC are optional robustness modes when shaper error tolerance matters more than Raman depth.

## Artifacts

- Result bundle: `/Users/ignaciojlizama/RiveraLab/raman-wt-sharpness/scripts/../results/raman/phase22/phase22_results.jld2`
- Pareto plot: `/Users/ignaciojlizama/RiveraLab/raman-wt-sharpness/scripts/../results/raman/phase22/phase22_pareto.png`
- Standard images: `/Users/ignaciojlizama/RiveraLab/raman-wt-sharpness/scripts/../.planning/phases/22-sharpness-research/images`
- Completed records: `26` successful / `0` failed
- Hessian spectra: `26` resolved / `0` unresolved

## Pareto Plot

![Phase 22 Pareto](../../../figures/phase22_pareto.png)

## Hessian Indefiniteness Table

| Operating Point | Flavor | Strength | J_dB | sigma_3dB | Hessian | Indefinite? | |lambda_min|/lambda_max |
|---|---|---:|---:|---:|---|:---:|---:|
| canonical | mc | 1.000e-02 | -78.29 | 0.021 | ok | YES | 2.640e-02 |
| canonical | mc | 2.500e-02 | -79.77 | 0.016 | ok | YES | 5.946e-02 |
| canonical | mc | 5.000e-02 | -78.09 | 0.022 | ok | YES | 1.025e-02 |
| canonical | mc | 7.500e-02 | -73.01 | 0.039 | ok | YES | 1.364e-02 |
| canonical | plain | 0 | -76.86 | 0.025 | ok | YES | 5.540e-03 |
| canonical | sam | 1.000e-02 | -78.59 | 0.018 | ok | YES | 1.486e-02 |
| canonical | sam | 2.500e-02 | -78.40 | 0.019 | ok | YES | 5.540e-03 |
| canonical | sam | 5.000e-02 | -78.38 | 0.020 | ok | YES | 5.302e-03 |
| canonical | sam | 1.000e-01 | -78.55 | 0.019 | ok | YES | 1.354e-02 |
| canonical | trH | 1.000e-04 | -78.24 | 0.022 | ok | YES | 1.403e-02 |
| canonical | trH | 3.000e-04 | -76.25 | 0.023 | ok | YES | 2.199e-02 |
| canonical | trH | 1.000e-03 | -73.83 | 0.037 | ok | YES | 1.793e-02 |
| canonical | trH | 3.000e-03 | -66.79 | 0.083 | ok | YES | 1.077e-02 |
| pareto57 | mc | 1.000e-02 | -82.53 | 0.012 | ok | YES | 2.418e-01 |
| pareto57 | mc | 2.500e-02 | -82.18 | 0.012 | ok | YES | 2.409e-01 |
| pareto57 | mc | 5.000e-02 | -81.65 | 0.013 | ok | YES | 3.033e-01 |
| pareto57 | mc | 7.500e-02 | -67.98 | 0.077 | ok | YES | 7.869e-02 |
| pareto57 | plain | 0 | -82.56 | 0.011 | ok | YES | 2.382e-01 |
| pareto57 | sam | 1.000e-02 | -82.59 | 0.012 | ok | YES | 2.391e-01 |
| pareto57 | sam | 2.500e-02 | -82.60 | 0.012 | ok | YES | 2.392e-01 |
| pareto57 | sam | 5.000e-02 | -82.60 | 0.012 | ok | YES | 2.390e-01 |
| pareto57 | sam | 1.000e-01 | -82.61 | 0.012 | ok | YES | 2.391e-01 |
| pareto57 | trH | 1.000e-04 | -79.76 | 0.016 | ok | YES | 2.334e-01 |
| pareto57 | trH | 3.000e-04 | -73.61 | 0.035 | ok | YES | 3.855e-01 |
| pareto57 | trH | 1.000e-03 | -66.44 | 0.077 | ok | YES | 9.838e-02 |
| pareto57 | trH | 3.000e-03 | -69.38 | 0.043 | ok | YES | 5.685e-02 |
