# Lab Physics Validity Audit

Date: 2026-04-28

## Bottom Line

The codebase is doing real nonlinear fiber simulation, but it is not yet a
closed digital twin of the lab. The strongest supported claim is:

> The repository can produce numerically disciplined, idealized predictions for
> Raman suppression from spectral pulse shaping in specified fiber models.

The unsafe claim is:

> A phase exported from the current repo will predict the exact Raman suppression
> seen through a real fiber and real SLM without calibration and hardware replay.

If the lab uses the current phase-only SMF workflow as a starting point and then
adds measured shaper/fiber calibration plus closed-loop or replay validation,
there is a good chance of seeing a real suppression trend. If the lab loads the
raw full-grid optimum as-is and expects the simulated dB number to reproduce,
the risk is high.

## Evidence Reviewed

Repo state caveat: the working tree was very dirty and `main` was behind
`origin/main` by 28 commits at audit start, so this report is an audit of the
current synced workspace, not a clean release tag.

Local evidence reviewed:

- Forward and adjoint propagation kernels:
  `src/simulation/simulate_disp_mmf.jl`,
  `src/simulation/sensitivity_disp_mmf.jl`
- Fiber setup and material/model parameters:
  `src/helpers/helpers.jl`, `src/simulation/fibers.jl`,
  `scripts/lib/common.jl`, `scripts/research/mmf/mmf_setup.jl`
- Objective and optimization paths:
  `scripts/lib/raman_optimization.jl`,
  `scripts/research/mmf/mmf_raman_optimization.jl`,
  `scripts/research/multivar/multivar_optimization.jl`,
  `src/mmf_cost.jl`
- Lab/export/readiness paths:
  `scripts/workflows/lab_ready.jl`,
  `scripts/workflows/export_run.jl`,
  `scripts/lib/experiment_runner.jl`
- Validation and trust paths:
  `scripts/research/analysis/numerical_trust.jl`,
  `scripts/research/analysis/verification.jl`,
  `test/phases/test_phase27_numerics_regressions.jl`,
  `test/phases/test_phase16_mmf.jl`,
  `test/core/test_canonical_lab_surface.jl`
- Current status and research conclusions:
  `docs/guides/supported-workflows.md`,
  `docs/reports/research-closure-2026-04-28/REPORT.md`,
  `docs/reports/mmf-raman-readiness-2026-04-28/REPORT.md`,
  `docs/status/longfiber-200m-closure-2026-04-28.md`,
  `docs/status/multivar-amp-on-phase-positive-result-2026-04-24.md`,
  `agent-docs/current-agent-context/*.md`,
  `agent-docs/stability-universality/*`

External sources checked:

- Hult's RK4IP paper: interaction-picture methods are standard for accurate
  GNLSE simulation of fiber supercontinuum dynamics:
  https://opg.optica.org/abstract.cfm?uri=jlt-25-12-3770
- Dudley, Genty, and Coen's supercontinuum review: the GNLSE with dispersion,
  Kerr, delayed Raman, and self-steepening is the right baseline model class for
  ultrashort nonlinear fiber propagation:
  https://doi.org/10.1103/RevModPhys.78.1135
- Weiner's SLM pulse-shaping review: real femtosecond shapers have finite
  pixels, wrapping, calibration, polarization, and spectral mapping constraints:
  https://engineering.purdue.edu/~fsoptics/articles/Femtosecond_Optical_Pulse_Shaping-Weiner.pdf
- Hamamatsu LCOS-SLM docs: real LCOS phase depends on pixel voltage, wavelength,
  and device characteristics:
  https://lcos-slm.hamamatsu.com/us/en/learn/about_lcos-slm/principle.html
  and
  https://lcos-slm.hamamatsu.com/us/en/learn/technical_information/characteristics.html
- Meadowlark SLM principles: SLMs are independently addressed LC pixels with
  device-level retardance/phase behavior:
  https://www.meadowlark.com/wp-content/uploads/2024/10/SLM-Principles-1.pdf
- GRIN MMF Raman and self-cleaning literature: MMF Raman behavior is
  mode-resolved and launch/coupling sensitive:
  https://arxiv.org/abs/1301.6203,
  https://arxiv.org/abs/1603.02972,
  https://arxiv.org/abs/1902.04453,
  https://arxiv.org/abs/1908.07745

## What The Code Gets Right

1. The propagation model is physically serious.

   The forward solver integrates an interaction-picture GNLSE/GMMNLSE. It
   includes linear dispersion, Kerr nonlinearity through a mode-overlap tensor,
   delayed Raman response, and self-steepening. That is the correct modeling
   family for ultrashort pulse propagation in silica fiber when polarization,
   random coupling, and detailed loss are not the target.

2. The Raman objective is physically interpretable.

   The core objective is an output spectral-energy fraction in a Raman-shifted
   band. That is a meaningful detector-level quantity. The MMF code also exposes
   sum-over-modes, fundamental-only, and worst-mode views, which is the right
   direction because a real detector or mode filter changes what "Raman" means.

3. The adjoint machinery is not hand-wavy.

   The code uses one forward solve plus one backward adjoint solve to get a
   phase gradient. Regression tests cover finite-difference agreement and
   Taylor remainder behavior for the current regularized log-cost surface.

4. Several historical numerical artifacts were found and fixed.

   The repo has explicit fixes and tests for boundary measurement, log-cost
   regularizer chaining, and the MMF FFT convention. This matters: the project
   has already caught false-positive style failure modes instead of ignoring
   them.

5. The supported surface is appropriately narrow.

   `docs/guides/supported-workflows.md` correctly limits the first lab-facing
   workflow to single-mode, phase-only runs. MMF, long-fiber, and multivariable
   results are marked experimental or caveated.

## Main Gaps Versus A Real Fiber And Real SLM

### 1. No measured SLM transfer model

The simulation applies `u0(omega) * exp(i phi(omega))` directly on the numerical
frequency grid. A real pulse shaper has:

- finite pixel count and fill factor;
- spectral-axis calibration from wavelength/frequency to pixel;
- phase-voltage lookup table;
- phase wrapping convention;
- finite bit depth;
- pixel crosstalk/fringing;
- aperture clipping and diffraction;
- polarization dependence;
- insertion loss and phase-amplitude coupling.

The repo has a neutral CSV export and some hardware-like perturbation probes,
but not a calibrated device model. This is the largest gap between simulated
dB numbers and lab dB numbers.

### 2. Full-grid masks can be much too fragile

The stability/universality probes are a major warning. Deep masks often lose
tens of dB when resampled, smoothed, wrapped, or quantized. Examples recorded
under `agent-docs/stability-universality/RESULTS.md`:

- `cubic32_reduced`: 128-pixel active-band resampling loses about 44 dB;
  wrapped 128x10 mask loses about 60 dB.
- `simple_phase17`: 0.05 rad phase noise loses about 8.6 dB; wrapped 128x10
  loses about 45 dB.
- `poly3_transferable`: much shallower, but survives 0.05 rad noise,
  128-pixel resampling, and smoothing with near-zero loss; wrapping still costs
  about 8 dB in the current probe.

This means the deepest numerical optimum is not automatically the best lab mask.
The most lab-plausible first tests are reduced, smooth, calibrated, and replayed
profiles, even if their raw simulated suppression is shallower.

### 3. Fiber parameters are presets, not measurements

Single-mode presets use fixed `gamma`, `beta2`, `beta3`, and `fR`. MMF presets
use idealized GRIN/step-index geometry, scalar modes, finite-difference
dispersion derivatives, and fixed mode weights. Real fibers vary by spool,
wavelength, bend state, launch condition, temperature, connector state, and
polarization.

The model is good enough to test mechanisms. It is not enough to predict exact
lab suppression unless the lab measures or fits:

- dispersion around the operating wavelength;
- nonlinear coefficient/effective area;
- loss spectrum;
- launch spectrum and pulse shape at the fiber input;
- actual average power and repetition rate at the fiber input;
- output collection and detector transfer.

### 4. Polarization is essentially outside the current lab claim

The main paths are scalar or scalar-mode models. They do not include birefringent
polarization evolution, polarization-mode dispersion, polarization-dependent SLM
response, or vector Raman effects. For SMF phase-only work this can be acceptable
if the lab uses polarization-maintaining conditions or actively controls input
polarization. Without that, polarization drift can change the nonlinear response
and the shaper response.

### 5. MMF is not experimentally predictive yet

The MMF code is useful but not lab-ready. Current accepted MMF result is an
idealized six-scalar-mode GRIN-50 simulation with shared spectral phase. Open
gates remain:

- high-grid refinement did not complete with accepted artifacts;
- launch-composition sensitivity is incomplete;
- random/degenerate mode coupling is not included in the accepted claim;
- spatial wavefront control is not modeled as the same actuator as shared
  spectral phase;
- real MMF experiments are highly launch and coupling dependent.

MMF should be presented only as a qualified simulation candidate.

### 6. Detection and noise are simplified

The objective is spectral energy fraction in a numerical band. Real lab data
will include spectrometer resolution, detector noise floor, baseline
subtraction, coupling efficiency, dynamic range limits, modal collection bias,
and possibly polarization-dependent collection. Those effects can dominate when
claiming deep suppression such as `-50 dB` or below.

## Lane-By-Lane Verdict

| Lane | Physics credibility | Lab predictive readiness | Verdict |
|---|---:|---:|---|
| SMF phase-only canonical workflow | High for ideal scalar fiber | Medium after calibration, low without calibration | Best lab starting point |
| Reduced/simple phase profiles | Medium to high | Medium to high if replayed through hardware constraints | Best first hardware experiment family |
| Deep full-grid phase optima | High as numerical solutions | Low unless they survive shaper replay | Use as optimizers/initializers, not direct masks |
| Staged amplitude-on-phase | Medium | Low to medium; needs loss-only/amplitude calibration | Optional experiment, not default |
| Direct joint phase+amplitude+energy | Runs but underperforms | Low | Do not promote |
| Long-fiber 50-200 m | Medium as research simulation | Low today; complex masks and nonconvergence | Research milestone, not lab-ready |
| MMF shared spectral phase | Medium for idealized mechanism | Low | Simulation-only claim |
| Trust-region/Newton methods | Numerical research | Not a lab physics path | Deferred method work |

## Expected Lab Outcome

If the lab runs the raw exported full-grid mask:

- It may show some suppression if the mechanism is dominated by coarse chirp or
  pulse stretching.
- It probably will not reproduce the exact simulated dB number.
- Fragile masks may collapse almost completely after pixel mapping, wrapping,
  or calibration error.

If the lab uses the repo correctly:

1. measure the input pulse and shaper axis;
2. replay the exported mask after pixelization, wrapping, calibration, and
   aperture cropping;
3. choose a profile that survives replay;
4. start with SMF phase-only before MMF/multivar;
5. use closed-loop lab feedback around the simulated mask;

then the project has a good chance of producing real Raman suppression in the
lab. The simulation should be treated as a mechanism generator and optimizer
initializer, not as a final absolute predictor.

## What Must Be Added Before Claiming Lab Predictiveness

Required before a strong lab claim:

1. A hardware replay layer:
   `phi_sim -> crop active bandwidth -> resample to pixels -> apply LUT/wrap ->
   optional smoothing/crosstalk -> reconstruct phi_replay -> rerun simulation`.

2. A measured SLM calibration bundle:
   spectral axis, phase-vs-gray LUT, phase range, bit depth, pixel count, active
   aperture, polarization orientation, insertion loss.

3. A measured fiber/pulse bundle:
   input spectrum, retrieved input phase or FROG/SPIDER/autocorrelation proxy,
   pulse energy at fiber input, fiber length, measured or fitted dispersion,
   measured loss, polarization condition.

4. A detector model:
   spectrometer resolution, background/noise floor, collection mode, and the
   exact Raman-band integration rule used in analysis.

5. Acceptance tests:
   replayed mask must keep most of its simulated suppression; no-shaper and
   flat-phase controls must be measured; a simple chirp/polynomial control must
   be included as a baseline; repeated load/run cycles must quantify drift.

## Recommended First Lab Protocol

1. Start with SMF-28 or the actual single-mode lab fiber, not MMF.
2. Use the supported phase-only workflow only.
3. Export three masks:
   flat phase, simple polynomial/chirp-like phase, and the best replay-surviving
   optimized phase.
4. Convert each mask through the same SLM calibration and replay path.
5. Simulate the replayed masks, not only the ideal masks.
6. In the lab, measure output spectra for all three under identical power and
   polarization settings.
7. Compare trends first: Raman-band fraction flat > simple > optimized. Only
   after that compare absolute dB values.
8. Use the measured discrepancy to fit the hardware/fiber model before moving
   to deeper masks, amplitude shaping, long fiber, or MMF.

## Overall Judgment

The codebase is scientifically valuable and not "fake physics." The numerical
model is in the right class, and the project has meaningful safeguards against
several known simulation artifacts.

But the current repo is not yet a lab digital twin. The main missing piece is
not another optimizer. It is hardware and experiment modeling: SLM calibration,
finite-pixel replay, measured fiber parameters, input-pulse characterization,
polarization control, and detector modeling.

The right confidence statement is:

> We should expect qualitative Raman-suppression mechanisms and relative trends
> to transfer to a carefully controlled SMF experiment after calibrated replay.
> We should not expect raw simulated `-40 dB` to `-70 dB` numbers or fragile
> full-grid masks to reproduce directly on a real SLM.
