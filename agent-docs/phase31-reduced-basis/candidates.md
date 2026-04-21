# Phase 31 — Candidate optima

Top 10 rows by AIC = 2·N_eff + 2·J_dB (lower = better).

| # | Branch | Kind / Penalty | N_phi / λ | J (dB) | N_eff | σ_3dB | J_HNLF (dB) | AIC |
|---|--------|---------------|-----------|--------|-------|-------|-------------|-----|
| 1 | A | cubic | 128 | -67.60 | 1.3 | 0.072 | -46.10 | -132.68 |
| 2 | A | cubic | 64 | -63.55 | 1.3 | 0.105 | -45.60 | -124.57 |
| 3 | A | linear | 64 | -63.94 | 2.6 | 0.104 | -44.32 | -122.68 |
| 4 | A | cubic | 32 | -60.77 | 1.3 | 0.143 | -44.25 | -119.02 |
| 5 | A | linear | 16 | -60.30 | 2.6 | 0.143 | -44.29 | -115.39 |
| 6 | B | penalty(:tikhonov) | λ=0.0e+00 | -57.75 | 2.5 | 0.174 | -42.12 | -110.59 |
| 7 | B | penalty(:gdd) | λ=0.0e+00 | -57.75 | 2.5 | 0.174 | -42.12 | -110.59 |
| 8 | B | penalty(:tod) | λ=0.0e+00 | -57.75 | 2.5 | 0.174 | -42.12 | -110.59 |
| 9 | B | penalty(:tv) | λ=0.0e+00 | -57.75 | 2.5 | 0.174 | -42.12 | -110.59 |
| 10 | B | penalty(:dct_l1) | λ=0.0e+00 | -57.75 | 2.5 | 0.174 | -42.12 | -110.59 |

## Recommendation

**Simplest optimum within 3 dB of best J_dB** (-67.6 dB):
- Branch: A
- Kind: cubic, N_phi = 128
- J_dB = -67.6, N_eff = 1.3
- σ_3dB = 0.072 rad, J_HNLF = -46.1 dB
