# Numerical Trust Report

- Schema version: `28.0`
- Timestamp (UTC): `2026-04-21T21:59:52Z`
- Overall verdict: **NOT_RUN**

## Determinism
- Verdict: **PASS**
- Applied: `true`
- FFTW threads: `1`
- BLAS threads: `1`

## Boundary
- Verdict: **PASS**
- Input edge fraction: `3.445e-07`
- Output edge fraction: `3.447e-07`
- Max edge fraction: `3.447e-07`

## Energy
- Verdict: **SUSPECT**
- Relative drift: `2.684e+08`

## Gradient Validation
- Verdict: **NOT_RUN**
- Status: `not_run`

## Cost Surface
- Verdict: **PASS**
- Surface: `10*log10(physics + regularizers)`
- λ_gdd: `1.000e-04`
- λ_boundary: `1.000e+00`
- Boundary penalty measurement: `pre-attenuator temporal edge fraction of shaped input pulse`

## Continuation
- ID: `p32_smf28_L_polywarm`
- Ladder: `L` step=`1` value=`1.0`
- Predictor / corrector: `trivial` / `lbfgs_warm_restart`
- Path status: **OK**
- Cold-start baseline: `false`
- Detector corrector_iters: `40`
- Detector phase_jump_ratio: `0.0`
- Detector cost_discontinuity_dB: `NaN`
- Detector edge_fraction_delta: `3.446999597133841e-7`
