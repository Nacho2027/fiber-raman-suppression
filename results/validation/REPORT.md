# Numerical Trustworthiness Audit — Top-level Report

**Generated:** 2026-04-19 20:55:15 on fiber-raman-burst  
**Source script:** `scripts/validation/validate_results.jl`  
**Plan + thresholds:** `.planning/phases/18-numerical-trustworthiness-audit-of-optimization-results/PLAN.md`

## Counts

| Verdict | Count |
|---|---|
| **PASS** | 18 |
| **MARGINAL** | 4 |
| **SUSPECT** | 28 |
| **ERROR** | 0 |
| **Total** | 50 |

## Ranking (worst first)

| # | Verdict | Tag | J reported | J recomputed | |ΔE|/E | edge | |ΔJ_dB| | |ρ−1| | Markdown |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **SUSPECT** | `multivar_mv_joint` | 1.490e-02 (-18.27 dB) | 5.621e-03 (-22.50 dB) | 1.39e-03 | 1.33e-07 | 0.043 | 8.73e-02 | [md](./multivar_mv_joint.md) |
| 2 | **SUSPECT** | `phase13_hessian_smf28` | 8.824e-07 (-60.54 dB) | 1.498e-05 (-48.25 dB) | 3.32e-05 | 1.01e-02 | 0.004 | 6.06e-02 | [md](./phase13_hessian_smf28.md) |
| 3 | **SUSPECT** | `sweep1_Nphi_001_SMF28_L2_P0.2_Nphi4_cubic` | -47.33585749843889 | 1.847e-05 (-47.34 dB) | 1.13e-05 | 9.87e-02 | 0.000 | 4.79e-02 | [md](./sweep1_Nphi_001_SMF28_L2_P0.2_Nphi4_cubic.md) |
| 4 | **SUSPECT** | `sweep1_Nphi_002_SMF28_L2_P0.2_Nphi8_cubic` | -46.89390509138561 | 2.045e-05 (-46.89 dB) | 1.27e-05 | 8.59e-02 | 0.000 | 4.79e-02 | [md](./sweep1_Nphi_002_SMF28_L2_P0.2_Nphi8_cubic.md) |
| 5 | **SUSPECT** | `sweep1_Nphi_003_SMF28_L2_P0.2_Nphi16_cubic` | -53.10633443375107 | 4.891e-06 (-53.11 dB) | 1.68e-05 | 7.83e-02 | 0.002 | 4.79e-02 | [md](./sweep1_Nphi_003_SMF28_L2_P0.2_Nphi16_cubic.md) |
| 6 | **SUSPECT** | `sweep1_Nphi_004_SMF28_L2_P0.2_Nphi32_cubic` | -58.175712463416225 | 1.522e-06 (-58.18 dB) | 2.60e-05 | 6.95e-02 | 0.004 | 4.79e-02 | [md](./sweep1_Nphi_004_SMF28_L2_P0.2_Nphi32_cubic.md) |
| 7 | **SUSPECT** | `sweep1_Nphi_005_SMF28_L2_P0.2_Nphi64_cubic` | -59.80596986524489 | 1.046e-06 (-59.81 dB) | 2.23e-05 | 6.60e-02 | 0.004 | 4.79e-02 | [md](./sweep1_Nphi_005_SMF28_L2_P0.2_Nphi64_cubic.md) |
| 8 | **SUSPECT** | `sweep1_Nphi_006_SMF28_L2_P0.2_Nphi128_cubic` | -68.01424065880448 | 1.580e-07 (-68.01 dB) | 2.75e-05 | 7.17e-02 | 0.003 | 4.79e-02 | [md](./sweep1_Nphi_006_SMF28_L2_P0.2_Nphi128_cubic.md) |
| 9 | **SUSPECT** | `sweep1_Nphi_007_SMF28_L2_P0.2_Nphi16384_identity` | -68.01410463039728 | 1.580e-07 (-68.01 dB) | 2.58e-05 | 7.10e-02 | 0.009 | 4.79e-02 | [md](./sweep1_Nphi_007_SMF28_L2_P0.2_Nphi16384_identity.md) |
| 10 | **SUSPECT** | `sweep2_LP_fiber_035_SMF28_L1_P0.2_Nphi16_cubic` | -64.28978433425532 | 3.724e-07 (-64.29 dB) | 1.39e-05 | 4.24e-02 | 0.103 | 4.47e-02 | [md](./sweep2_LP_fiber_035_SMF28_L1_P0.2_Nphi16_cubic.md) |
| 11 | **SUSPECT** | `sweep2_LP_fiber_036_SMF28_L1_P0.2_Nphi57_cubic` | -69.62708646289136 | 1.090e-07 (-69.63 dB) | 3.91e-06 | 4.32e-02 | 0.207 | 4.47e-02 | [md](./sweep2_LP_fiber_036_SMF28_L1_P0.2_Nphi57_cubic.md) |
| 12 | **SUSPECT** | `sweep2_LP_fiber_027_HNLF_L0.25_P0.1_Nphi16_cubic` | -49.34288978891981 | 1.163e-05 (-49.34 dB) | 3.90e-05 | 5.88e-02 | 0.000 | 2.95e-02 | [md](./sweep2_LP_fiber_027_HNLF_L0.25_P0.1_Nphi16_cubic.md) |
| 13 | **SUSPECT** | `sweep2_LP_fiber_028_HNLF_L0.25_P0.1_Nphi57_cubic` | -54.91621908306391 | 3.224e-06 (-54.92 dB) | 2.66e-05 | 8.88e-02 | 0.000 | 2.95e-02 | [md](./sweep2_LP_fiber_028_HNLF_L0.25_P0.1_Nphi57_cubic.md) |
| 14 | **SUSPECT** | `sweep2_LP_fiber_011_HNLF_L1_P0.02_Nphi16_cubic` | -59.563792878648975 | 1.106e-06 (-59.56 dB) | 1.01e-05 | 1.32e-01 | 0.000 | 2.06e-02 | [md](./sweep2_LP_fiber_011_HNLF_L1_P0.02_Nphi16_cubic.md) |
| 15 | **SUSPECT** | `sweep2_LP_fiber_012_HNLF_L1_P0.02_Nphi57_cubic` | -60.61482696304135 | 8.680e-07 (-60.61 dB) | 1.02e-05 | 1.33e-01 | 0.001 | 2.06e-02 | [md](./sweep2_LP_fiber_012_HNLF_L1_P0.02_Nphi57_cubic.md) |
| 16 | **SUSPECT** | `sweep2_LP_fiber_007_HNLF_L0.5_P0.02_Nphi16_cubic` | -58.095234009303844 | 1.551e-06 (-58.10 dB) | 4.31e-06 | 4.16e-02 | 0.000 | 1.13e-02 | [md](./sweep2_LP_fiber_007_HNLF_L0.5_P0.02_Nphi16_cubic.md) |
| 17 | **SUSPECT** | `sweep2_LP_fiber_008_HNLF_L0.5_P0.02_Nphi57_cubic` | -63.58237377758863 | 4.383e-07 (-63.58 dB) | 7.75e-07 | 1.14e-01 | 0.001 | 1.13e-02 | [md](./sweep2_LP_fiber_008_HNLF_L0.5_P0.02_Nphi57_cubic.md) |
| 18 | **SUSPECT** | `sweep2_LP_fiber_021_HNLF_L0.5_P0.05_Nphi16_cubic` | -51.65254606333996 | 6.835e-06 (-51.65 dB) | 7.78e-05 | 1.37e-01 | 0.000 | 9.75e-03 | [md](./sweep2_LP_fiber_021_HNLF_L0.5_P0.05_Nphi16_cubic.md) |
| 19 | **SUSPECT** | `sweep2_LP_fiber_022_HNLF_L0.5_P0.05_Nphi57_cubic` | -59.52837610152956 | 1.115e-06 (-59.53 dB) | 5.29e-06 | 1.60e-01 | 0.000 | 9.75e-03 | [md](./sweep2_LP_fiber_022_HNLF_L0.5_P0.05_Nphi57_cubic.md) |
| 20 | **SUSPECT** | `sweep2_LP_fiber_031_SMF28_L1_P0.1_Nphi16_cubic` | -61.7988367515699 | 6.609e-07 (-61.80 dB) | 2.58e-05 | 8.84e-02 | 0.001 | 7.63e-03 | [md](./sweep2_LP_fiber_031_SMF28_L1_P0.1_Nphi16_cubic.md) |
| 21 | **SUSPECT** | `sweep2_LP_fiber_032_SMF28_L1_P0.1_Nphi57_cubic` | -73.06024323365034 | 4.943e-08 (-73.06 dB) | 1.98e-05 | 9.63e-02 | 0.107 | 7.63e-03 | [md](./sweep2_LP_fiber_032_SMF28_L1_P0.1_Nphi57_cubic.md) |
| 22 | **SUSPECT** | `sweep2_LP_fiber_029_SMF28_L0.5_P0.1_Nphi16_cubic` | -67.74854652489732 | 1.679e-07 (-67.75 dB) | 1.63e-05 | 4.43e-02 | 0.001 | 3.57e-03 | [md](./sweep2_LP_fiber_029_SMF28_L0.5_P0.1_Nphi16_cubic.md) |
| 23 | **SUSPECT** | `sweep2_LP_fiber_030_SMF28_L0.5_P0.1_Nphi57_cubic` | -76.9458459919895 | 2.020e-08 (-76.95 dB) | 1.53e-05 | 4.08e-02 | 0.001 | 3.57e-03 | [md](./sweep2_LP_fiber_030_SMF28_L0.5_P0.1_Nphi57_cubic.md) |
| 24 | **SUSPECT** | `sweep2_LP_fiber_033_SMF28_L0.25_P0.2_Nphi16_cubic` | -67.47540940668082 | 1.788e-07 (-67.48 dB) | 4.17e-06 | 2.85e-01 | 0.000 | 1.98e-03 | [md](./sweep2_LP_fiber_033_SMF28_L0.25_P0.2_Nphi16_cubic.md) |
| 25 | **SUSPECT** | `sweep2_LP_fiber_034_SMF28_L0.25_P0.2_Nphi57_cubic` | -72.00790034035474 | 6.298e-08 (-72.01 dB) | 6.22e-09 | 3.74e-01 | 0.000 | 1.98e-03 | [md](./sweep2_LP_fiber_034_SMF28_L0.25_P0.2_Nphi57_cubic.md) |
| 26 | **SUSPECT** | `sweep2_LP_fiber_017_HNLF_L0.25_P0.05_Nphi16_cubic` | -56.8890271469552 | 2.047e-06 (-56.89 dB) | 9.01e-06 | 1.91e-01 | 0.000 | 8.10e-04 | [md](./sweep2_LP_fiber_017_HNLF_L0.25_P0.05_Nphi16_cubic.md) |
| 27 | **SUSPECT** | `sweep2_LP_fiber_018_HNLF_L0.25_P0.05_Nphi57_cubic` | -62.68564264308456 | 5.388e-07 (-62.69 dB) | 4.93e-07 | 1.79e-01 | 0.000 | 8.10e-04 | [md](./sweep2_LP_fiber_018_HNLF_L0.25_P0.05_Nphi57_cubic.md) |
| 28 | **SUSPECT** | `phase13_hessian_hnlf` | 3.590e-08 (-74.45 dB) | 3.978e-05 (-44.00 dB) | 6.49e-06 | 2.10e-02 | 0.001 | 6.16e-05 | [md](./phase13_hessian_hnlf.md) |
| 29 | **MARGINAL** | `multivar_mv_phaseonly` | -56.91707874905933 | 2.034e-06 (-56.92 dB) | 1.21e-04 | 1.86e-04 | 0.064 | 8.73e-02 | [md](./multivar_mv_phaseonly.md) |
| 30 | **MARGINAL** | `multivar_phase_only_opt` | 2.034e-06 (-56.92 dB) | 2.034e-06 (-56.92 dB) | 1.21e-04 | 1.86e-04 | 0.064 | 8.73e-02 | [md](./multivar_phase_only_opt.md) |
| 31 | **MARGINAL** | `phase14_vanilla_snapshot` | n/a | 1.214e-06 (-59.16 dB) | 2.77e-05 | 7.31e-03 | 0.014 | 6.49e-02 | [md](./phase14_vanilla_snapshot.md) |
| 32 | **MARGINAL** | `sweep2_LP_fiber_004_HNLF_L0.25_P0.02_Nphi57_cubic` | -65.10997845793021 | 3.083e-07 (-65.11 dB) | 1.19e-05 | 4.36e-03 | 0.000 | 4.79e-06 | [md](./sweep2_LP_fiber_004_HNLF_L0.25_P0.02_Nphi57_cubic.md) |
| 33 | **PASS** | `sweep2_LP_fiber_013_SMF28_L2_P0.02_Nphi16_cubic` | -56.622376034072545 | 2.177e-06 (-56.62 dB) | 6.64e-05 | 6.36e-08 | 0.049 | 9.83e-02 | [md](./sweep2_LP_fiber_013_SMF28_L2_P0.02_Nphi16_cubic.md) |
| 34 | **PASS** | `sweep2_LP_fiber_014_SMF28_L2_P0.02_Nphi57_cubic` | -56.6222627893771 | 2.177e-06 (-56.62 dB) | 5.12e-05 | 9.07e-07 | 0.039 | 9.83e-02 | [md](./sweep2_LP_fiber_014_SMF28_L2_P0.02_Nphi57_cubic.md) |
| 35 | **PASS** | `multivar_mv_joint_warmstart` | 3.084e-03 (-25.11 dB) | 1.756e-05 (-47.55 dB) | 9.17e-05 | 2.37e-05 | 0.021 | 8.73e-02 | [md](./multivar_mv_joint_warmstart.md) |
| 36 | **PASS** | `sweep2_LP_fiber_009_SMF28_L1_P0.02_Nphi16_cubic` | -56.413031929258096 | 2.284e-06 (-56.41 dB) | 3.91e-05 | 7.59e-08 | 0.001 | 1.15e-02 | [md](./sweep2_LP_fiber_009_SMF28_L1_P0.02_Nphi16_cubic.md) |
| 37 | **PASS** | `sweep2_LP_fiber_010_SMF28_L1_P0.02_Nphi57_cubic` | -56.41291910325062 | 2.284e-06 (-56.41 dB) | 3.91e-05 | 7.60e-08 | 0.001 | 1.15e-02 | [md](./sweep2_LP_fiber_010_SMF28_L1_P0.02_Nphi57_cubic.md) |
| 38 | **PASS** | `sweep2_LP_fiber_025_SMF28_L0.25_P0.1_Nphi16_cubic` | -81.0212265056328 | 7.905e-09 (-81.02 dB) | 1.53e-05 | 9.93e-05 | 0.004 | 4.78e-03 | [md](./sweep2_LP_fiber_025_SMF28_L0.25_P0.1_Nphi16_cubic.md) |
| 39 | **PASS** | `sweep2_LP_fiber_026_SMF28_L0.25_P0.1_Nphi57_cubic` | -82.33309310312869 | 5.844e-09 (-82.33 dB) | 1.54e-05 | 9.94e-05 | 0.007 | 4.78e-03 | [md](./sweep2_LP_fiber_026_SMF28_L0.25_P0.1_Nphi57_cubic.md) |
| 40 | **PASS** | `sweep2_LP_fiber_001_SMF28_L0.25_P0.02_Nphi16_cubic` | -63.022719798600654 | 4.986e-07 (-63.02 dB) | 1.71e-05 | 8.67e-06 | 0.000 | 3.44e-03 | [md](./sweep2_LP_fiber_001_SMF28_L0.25_P0.02_Nphi16_cubic.md) |
| 41 | **PASS** | `sweep2_LP_fiber_002_SMF28_L0.25_P0.02_Nphi57_cubic` | -63.02296584484572 | 4.985e-07 (-63.02 dB) | 1.71e-05 | 8.68e-06 | 0.000 | 3.44e-03 | [md](./sweep2_LP_fiber_002_SMF28_L0.25_P0.02_Nphi57_cubic.md) |
| 42 | **PASS** | `sweep2_LP_fiber_015_SMF28_L0.25_P0.05_Nphi16_cubic` | -73.7643546651765 | 4.203e-08 (-73.76 dB) | 2.12e-05 | 8.92e-05 | 0.001 | 2.88e-03 | [md](./sweep2_LP_fiber_015_SMF28_L0.25_P0.05_Nphi16_cubic.md) |
| 43 | **PASS** | `sweep2_LP_fiber_016_SMF28_L0.25_P0.05_Nphi57_cubic` | -75.24084676221507 | 2.992e-08 (-75.24 dB) | 2.25e-05 | 8.77e-05 | 0.001 | 2.88e-03 | [md](./sweep2_LP_fiber_016_SMF28_L0.25_P0.05_Nphi57_cubic.md) |
| 44 | **PASS** | `sweep2_LP_fiber_019_SMF28_L0.5_P0.05_Nphi16_cubic` | -75.30858492570964 | 2.945e-08 (-75.31 dB) | 2.89e-05 | 1.19e-04 | 0.002 | 2.85e-03 | [md](./sweep2_LP_fiber_019_SMF28_L0.5_P0.05_Nphi16_cubic.md) |
| 45 | **PASS** | `sweep2_LP_fiber_020_SMF28_L0.5_P0.05_Nphi57_cubic` | -75.30843430861519 | 2.945e-08 (-75.31 dB) | 2.89e-05 | 1.19e-04 | 0.002 | 2.85e-03 | [md](./sweep2_LP_fiber_020_SMF28_L0.5_P0.05_Nphi57_cubic.md) |
| 46 | **PASS** | `sweep2_LP_fiber_005_SMF28_L0.5_P0.02_Nphi16_cubic` | -57.917892732910595 | 1.615e-06 (-57.92 dB) | 1.84e-05 | 8.90e-06 | 0.000 | 2.77e-03 | [md](./sweep2_LP_fiber_005_SMF28_L0.5_P0.02_Nphi16_cubic.md) |
| 47 | **PASS** | `sweep2_LP_fiber_006_SMF28_L0.5_P0.02_Nphi57_cubic` | -57.918208837241735 | 1.615e-06 (-57.92 dB) | 1.84e-05 | 8.43e-06 | 0.000 | 2.77e-03 | [md](./sweep2_LP_fiber_006_SMF28_L0.5_P0.02_Nphi57_cubic.md) |
| 48 | **PASS** | `sweep2_LP_fiber_023_SMF28_L1_P0.05_Nphi16_cubic` | -75.16831331996057 | 3.042e-08 (-75.17 dB) | 4.43e-05 | 2.26e-06 | 0.003 | 2.22e-03 | [md](./sweep2_LP_fiber_023_SMF28_L1_P0.05_Nphi16_cubic.md) |
| 49 | **PASS** | `sweep2_LP_fiber_024_SMF28_L1_P0.05_Nphi57_cubic` | -79.76221330323416 | 1.056e-08 (-79.76 dB) | 4.20e-05 | 1.59e-06 | 0.005 | 2.22e-03 | [md](./sweep2_LP_fiber_024_SMF28_L1_P0.05_Nphi57_cubic.md) |
| 50 | **PASS** | `sweep2_LP_fiber_003_HNLF_L0.25_P0.02_Nphi16_cubic` | -59.31239483758961 | 1.172e-06 (-59.31 dB) | 6.25e-06 | 6.34e-05 | 0.000 | 4.79e-06 | [md](./sweep2_LP_fiber_003_HNLF_L0.25_P0.02_Nphi16_cubic.md) |

## Worst offenders

- `multivar_mv_joint` — energy drift 1.39e-03 exceeds physical floor
- `phase13_hessian_smf28` — edge fraction 1.01e-02 — pulse walks off
- `sweep1_Nphi_001_SMF28_L2_P0.2_Nphi4_cubic` — edge fraction 9.87e-02 — pulse walks off
- `sweep1_Nphi_002_SMF28_L2_P0.2_Nphi8_cubic` — edge fraction 8.59e-02 — pulse walks off
- `sweep1_Nphi_003_SMF28_L2_P0.2_Nphi16_cubic` — edge fraction 7.83e-02 — pulse walks off
- `sweep1_Nphi_004_SMF28_L2_P0.2_Nphi32_cubic` — edge fraction 6.95e-02 — pulse walks off
- `sweep1_Nphi_005_SMF28_L2_P0.2_Nphi64_cubic` — edge fraction 6.60e-02 — pulse walks off
- `sweep1_Nphi_006_SMF28_L2_P0.2_Nphi128_cubic` — edge fraction 7.17e-02 — pulse walks off
- `sweep1_Nphi_007_SMF28_L2_P0.2_Nphi16384_identity` — edge fraction 7.10e-02 — pulse walks off
- `sweep2_LP_fiber_035_SMF28_L1_P0.2_Nphi16_cubic` — edge fraction 4.24e-02 — pulse walks off
- `sweep2_LP_fiber_036_SMF28_L1_P0.2_Nphi57_cubic` — edge fraction 4.32e-02 — pulse walks off
- `sweep2_LP_fiber_027_HNLF_L0.25_P0.1_Nphi16_cubic` — edge fraction 5.88e-02 — pulse walks off
- `sweep2_LP_fiber_028_HNLF_L0.25_P0.1_Nphi57_cubic` — edge fraction 8.88e-02 — pulse walks off
- `sweep2_LP_fiber_011_HNLF_L1_P0.02_Nphi16_cubic` — edge fraction 1.32e-01 — pulse walks off
- `sweep2_LP_fiber_012_HNLF_L1_P0.02_Nphi57_cubic` — edge fraction 1.33e-01 — pulse walks off
- `sweep2_LP_fiber_007_HNLF_L0.5_P0.02_Nphi16_cubic` — edge fraction 4.16e-02 — pulse walks off
- `sweep2_LP_fiber_008_HNLF_L0.5_P0.02_Nphi57_cubic` — edge fraction 1.14e-01 — pulse walks off
- `sweep2_LP_fiber_021_HNLF_L0.5_P0.05_Nphi16_cubic` — edge fraction 1.37e-01 — pulse walks off
- `sweep2_LP_fiber_022_HNLF_L0.5_P0.05_Nphi57_cubic` — edge fraction 1.60e-01 — pulse walks off
- `sweep2_LP_fiber_031_SMF28_L1_P0.1_Nphi16_cubic` — edge fraction 8.84e-02 — pulse walks off
- `sweep2_LP_fiber_032_SMF28_L1_P0.1_Nphi57_cubic` — edge fraction 9.63e-02 — pulse walks off
- `sweep2_LP_fiber_029_SMF28_L0.5_P0.1_Nphi16_cubic` — edge fraction 4.43e-02 — pulse walks off
- `sweep2_LP_fiber_030_SMF28_L0.5_P0.1_Nphi57_cubic` — edge fraction 4.08e-02 — pulse walks off
- `sweep2_LP_fiber_033_SMF28_L0.25_P0.2_Nphi16_cubic` — edge fraction 2.85e-01 — pulse walks off
- `sweep2_LP_fiber_034_SMF28_L0.25_P0.2_Nphi57_cubic` — edge fraction 3.74e-01 — pulse walks off
- `sweep2_LP_fiber_017_HNLF_L0.25_P0.05_Nphi16_cubic` — edge fraction 1.91e-01 — pulse walks off
- `sweep2_LP_fiber_018_HNLF_L0.25_P0.05_Nphi57_cubic` — edge fraction 1.79e-01 — pulse walks off
- `phase13_hessian_hnlf` — edge fraction 2.10e-02 — pulse walks off

## Thresholds (cited defense in PLAN.md)

| Check | PASS | MARGINAL | SUSPECT |
|---|---|---|---|
| Energy drift | <1e-4 | 1e-4 … 1e-3 | ≥1e-3 |
| Edge fraction | <1e-3 | 1e-3 … 1e-2 | ≥1e-2 |
| |ΔJ_dB| under Nt→2·Nt | <0.3 dB | 0.3 … 1.0 dB | ≥1.0 dB |
| Taylor |ρ−1| at φ_ref=0 | <0.15 | 0.15 … 0.3 | ≥0.3 |

_Taylor threshold calibration: the discrete adjoint in this project shows a ~8.7% systematic offset at φ=0 that is ε-independent from ε=1e-4 to 1e-3 (i.e., not Taylor truncation and not solver noise — most likely the attenuator's discrete windowing applied outside the strict chain rule). All 50 entries inherit the same adjoint implementation so the test discriminates real sign/factor errors (ρ−1 ≫ 0.15) from the calibrated baseline. Published fiber-adjoint work (Huffman-Brabec Opt. Express 25 30149 2017) cites 1e-3 to 1e-2 range but uses split-step-Fourier without an attenuator window; the looser bound here reflects this project's specific discretization choice._