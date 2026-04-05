# Practical Assessment: Experimental Implementation of Spectral Phase Raman Suppression

**Date:** 2026-04-05
**Context:** Phases 9-12 demonstrated that adjoint-optimized spectral phase shaping can suppress Raman scattering by 37-78 dB in single-mode fibers. This document assesses whether these computed phase profiles could be implemented with real pulse shaper hardware available to an ultrafast optics lab at Cornell.

---

## 1. Simulation Requirements vs Hardware Capabilities

### 1.1 What Our Simulations Require

| Parameter | Requirement | Source |
|-----------|------------|--------|
| Spectral resolution | ±0.33 THz = ±0.26 nm at 1550nm | Phase 11 H2 verdict |
| Phase amplitude precision | ±25% scaling costs ~30 dB | Phase 10 H3 verdict |
| Signal bandwidth | ~10 THz (~80 nm at 1550nm) | Phase 10 ablation — HNLF needs full bandwidth |
| Spectral degrees of freedom | Nt = 8192 at Δf = 200 GHz/bin (optimization grid) | Phase 7 sweep, Nt floor |
| Phase range | 0 to ~20 rad (typical φ_opt amplitude) | Phase 9 polynomial decomposition |
| Wavelength | 1550 nm (C-band) | Project definition |
| Pulse duration | 185 fs FWHM sech² | All simulations |

### 1.2 Available Hardware Classes

#### A. Finisar/Coherent WaveShaper 1000S/4000S (LCoS-based)

The WaveShaper is the workhorse programmable optical processor in telecom and ultrafast labs. It uses Liquid Crystal on Silicon (LCoS) technology in a 4f-like geometry.

| Spec | WaveShaper 1000S | Our Requirement | Verdict |
|------|-----------------|-----------------|---------|
| Spectral resolution | 1 GHz (0.008 nm) | 0.33 THz (2.6 nm) | **40x better than needed** |
| Bandwidth setting | 10 GHz to 5 THz, 1 GHz steps | ~10 THz | Covers C+L band (~10 THz) |
| Attenuation control | 35 dB | — | Sufficient for amplitude shaping |
| Phase control | Yes (amplitude + phase) | Phase-only needed | Supported |
| Wavelength range | C-band (1530-1565 nm) or C+L | 1550 nm | Exact match |
| Port count | 1x1 or 1x4 | 1x1 sufficient | Compatible |

**Assessment:** The WaveShaper spectral resolution (1 GHz) is 330x finer than our 0.33 THz requirement. Bandwidth covers C-band. This device could implement our φ_opt profiles.

**Limitation:** The WaveShaper is designed for CW or quasi-CW signals (telecom). For 185 fs pulses (~80 nm bandwidth), the C-band-only version (35 nm usable) may not cover the full pulse spectrum. The C+L version (~80 nm) would be tight but possibly sufficient for the transform-limited spectrum. The key question is whether the 185 fs pulse bandwidth exceeds the device's aperture.

#### B. Hamamatsu LCOS-SLM X15213 Series (4f pulse shaper)

A research-grade SLM used in a custom 4f geometry. This is what most ultrafast optics labs would build.

| Spec | X15213 Series | Our Requirement | Verdict |
|------|--------------|-----------------|---------|
| Pixel count | 1280 × 256 | ~8192 effective bins | **Marginal — see below** |
| Phase range | >2π across 400-2050 nm | ~20 rad (~3.2 × 2π) | Needs multi-wrapping (standard technique) |
| Wavelength range | 400-2050 nm | 1550 nm | Covered |
| Phase levels | 8-bit (256 levels) | <25% amplitude error → ~70 levels min | Sufficient |
| Update rate | ~60 Hz | Static (single shot) | Sufficient |

**Spectral resolution in a 4f setup** depends on the grating + lens combination, not just the SLM pixel count. With a 600 gr/mm grating and f=200mm lens at 1550 nm:
- Spectral resolution per pixel: ~0.06 nm = ~7.5 GHz
- Usable bandwidth with 1280 pixels: ~77 nm ≈ 9.6 THz

This gives **1280 independent spectral channels** across the pulse bandwidth. Our optimization uses Nt=8192 bins, but many of those bins are outside the signal band. The actual signal bandwidth (>-40 dB) spans roughly 1000-2000 effective bins. **1280 pixels is marginal but potentially sufficient** — the critical question is whether the ~6x reduction in spectral degrees of freedom degrades the suppression.

**Assessment:** A Hamamatsu SLM in a 4f setup can cover the bandwidth and resolution requirements. Phase multi-wrapping handles the >2π range. The pixel count is the tightest constraint — optimization would need to be re-run at Nt matched to the SLM pixel count to verify suppression is maintained.

#### C. IPG femtoSHAPE-HR (Turnkey 4f Pulse Shaper)

A commercial turnkey system integrating LCOS-SLM, 4f optics, and MIIPS characterization.

| Spec | femtoSHAPE-HR | Our Requirement | Verdict |
|------|--------------|-----------------|---------|
| Control type | Phase + amplitude | Phase-only needed | Supported |
| SLM type | LCOS (configurable) | — | Standard |
| Spectral range | Configurable per laser source | Need 1550 nm config | Available on request |
| MIIPS characterization | Built-in | Needed for calibration | Major advantage |
| Bandwidth | ~100 nm (configuration-dependent) | ~80 nm | Compatible |

**Assessment:** The femtoSHAPE-HR with a 1550 nm configuration would be the most turnkey solution. Built-in MIIPS characterization directly addresses the calibration challenge (see Section 2.3). However, the exact pixel count for the 1550 nm variant is not publicly listed.

---

## 2. Critical Implementation Challenges

### 2.1 Phase Amplitude Calibration (THE hardest problem)

Our H3 result shows that ±25% phase amplitude error costs ~30 dB of suppression. This means the pulse shaper must apply the correct phase to within ~10% accuracy at every spectral channel.

**What this requires:**
- Precise voltage-to-phase calibration of the SLM at 1550 nm
- Accounting for pixel crosstalk (adjacent pixel coupling in the SLM)
- Compensating for any residual phase from the 4f optics themselves
- Temporal stability of the calibration over the measurement duration

**State of the art:** MIIPS (Multiphoton Intrapulse Interference Phase Scan) and related techniques can characterize the spectral phase of an ultrashort pulse to ~0.01 rad precision. The femtoSHAPE-HR has this built in. For a custom 4f setup, FROG or SPIDER characterization at the shaper output would be needed.

**Verdict:** Achievable with careful calibration, but this is the primary experimental challenge. The ~10% amplitude accuracy requirement is demanding but within the capability of a well-calibrated system.

### 2.2 Spectral Bandwidth Coverage

The 185 fs sech² pulse at 1550 nm has a transform-limited bandwidth of ~15 nm (FWHM) but spectral wings extending to ~80 nm (at -40 dB). Our optimization uses the full -40 dB bandwidth.

- **WaveShaper C-band:** ~35 nm usable → clips spectral wings. Likely loses 5-15 dB of suppression.
- **WaveShaper C+L:** ~80 nm → barely sufficient for full coverage.
- **Custom 4f with 600 gr/mm grating:** ~77 nm with 1280-pixel SLM → covers the requirement.
- **Custom 4f with higher-resolution grating (1200 gr/mm):** Better resolution but half the bandwidth → insufficient.

**Verdict:** Bandwidth is achievable with the right grating choice. The 600 gr/mm / f=200mm combination is the sweet spot for 185 fs pulses at 1550 nm.

### 2.3 Pixel Count vs Optimization Grid

Our optimizer uses Nt=8192 spectral bins but the SLM has ~1280 pixels. Options:

1. **Re-optimize at SLM resolution:** Run the adjoint optimizer with Nt=1280 (matching the SLM pixel count). If suppression is maintained at similar levels, no problem. If it degrades significantly, the SLM resolution is genuinely insufficient.

2. **Downsample φ_opt:** Take the Nt=8192 optimal phase and interpolate down to 1280 points. Risk: the fine spectral features that make the phase work may be lost. Phase 10 showed sub-THz sensitivity, so this is a real concern.

3. **Use higher-pixel SLM:** Some LCOS-SLMs offer 1920×1080 pixels. Using the full horizontal dimension gives 1920 channels — closer to the requirement.

**Verdict:** This needs a computational test. Re-run optimization at Nt=1280 and compare suppression with Nt=8192. If within 10 dB, the SLM works. If >20 dB degradation, higher pixel count or a different approach is needed.

### 2.4 Phase Wrapping

Our φ_opt profiles span ~20 radians. SLMs provide 0-2π phase range. Multi-wrapping (applying φ mod 2π) is standard practice and introduces no physical error — the optical response is periodic in 2π.

**Verdict:** Non-issue. Standard technique, no degradation.

---

## 3. What Equipment Would the Rivera Lab Need?

### Minimum Viable Setup

| Component | Specification | Estimated Cost | Purpose |
|-----------|--------------|---------------|---------|
| Femtosecond laser | 1550 nm, 185 fs, >100 mW avg | ~$50-100K | Pulse source (may already exist) |
| LCOS-SLM | Hamamatsu X15213-02 or equiv., 1280 pixels, 1550 nm AR-coated | ~$15-25K | Phase mask |
| Diffraction grating (2x) | 600 gr/mm, NIR-optimized | ~$1-2K | 4f disperser/recombiner |
| Cylindrical lenses (2x) | f=200mm, AR-coated 1550nm | ~$500-1K | 4f Fourier transform |
| Optical spectrum analyzer | 0.01 nm resolution | ~$20-40K | Measure Raman suppression |
| FROG or SPIDER | For pulse characterization | ~$20-50K (or build) | Calibrate phase |
| Single-mode fiber (SMF-28) | 0.5-5m | ~$50 | Test fiber |

**Total estimated cost:** ~$100-200K (much lower if laser and diagnostics already exist)

### Turnkey Alternative

| Component | Model | Estimated Cost |
|-----------|-------|---------------|
| IPG femtoSHAPE-HR | 1550 nm config with MIIPS | ~$50-80K |
| Fiber + OSA | As above | ~$20-40K |

### What Cornell Likely Already Has

A lab working on quantum noise in multimode fibers at 1550 nm almost certainly has:
- A mode-locked fiber laser or OPO at 1550 nm
- Optical spectrum analyzers
- Single-mode and multimode fibers
- Basic pulse characterization (autocorrelator at minimum)

**What they'd likely need to add:** The pulse shaper (SLM + 4f optics) and possibly FROG/SPIDER characterization if not already available. This is the ~$25-50K incremental cost.

---

## 4. Feasibility Verdict

| Requirement | Hardware Capability | Feasibility |
|-------------|-------------------|-------------|
| Spectral resolution (±0.33 THz) | WaveShaper: 1 GHz; 4f SLM: ~7.5 GHz | **Easy** — 40-330x margin |
| Phase amplitude (±10%) | SLM: 256 levels + MIIPS calibration | **Achievable** — requires careful calibration |
| Bandwidth (~10 THz) | 4f with 600gr/mm: ~9.6 THz | **Tight but sufficient** |
| Pixel count (8192 bins) | SLM: 1280-1920 pixels | **Needs computational test** — re-optimize at SLM resolution |
| Phase range (20 rad) | SLM: 2π with wrapping | **Non-issue** |
| Segmented optimization | Multiple shapers or re-circulating loop | **Challenging** — future work |

### Overall: FEASIBLE with one open question

The spectral phase profiles computed in this project **can be implemented experimentally** with commercially available hardware. The spectral resolution and bandwidth requirements are met with comfortable margin by standard 4f pulse shapers.

**The one open question** is whether the reduced pixel count (1280 SLM pixels vs 8192 optimization bins) degrades suppression. This is a computational test that should be run before purchasing hardware: re-optimize at Nt=1280 and verify >40 dB suppression is still achievable.

**The primary experimental challenge** is phase amplitude calibration — ensuring the SLM applies the correct phase to within ~10% at every pixel. This is demanding but within the demonstrated capability of MIIPS-calibrated systems.

**Segmented optimization** (re-shaping at intermediate fiber points) would require either a fiber re-circulating loop with an intracavity pulse shaper, or multiple concatenated shaper-fiber stages. This is experimentally more complex and would be a follow-up experiment.

---

## 5. Recommended Next Steps

1. **Computational:** Re-run optimization at Nt=1024 and Nt=1280 to determine minimum pixel count for >40 dB suppression
2. **Computational:** Test robustness to realistic SLM imperfections: pixel crosstalk, calibration noise, bandwidth clipping
3. **Equipment:** Procure LCOS-SLM + 4f optics for 1550 nm (if not already available)
4. **Experimental:** Demonstrate Raman suppression on a short fiber (L=0.5m SMF-28) as proof of concept
5. **Experimental:** Compare measured suppression with simulation prediction — the gap reveals calibration quality

---

## References

- Weiner, A.M. "Ultrafast optical pulse shaping: A tutorial review." Opt. Comm. 284, 3669 (2011)
- Hamamatsu LCOS-SLM X15213 series datasheet
- Finisar/Coherent WaveShaper 1000S product brief
- IPG femtoSHAPE-HR product page
- Phase 9-12 findings: `results/raman/CLASSICAL_RAMAN_SUPPRESSION_FINDINGS.md`

---

*Generated as part of the fiber-raman-suppression project practical assessment.*
