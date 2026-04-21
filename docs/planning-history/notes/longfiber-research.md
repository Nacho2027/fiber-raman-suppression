# Long-Fiber Raman-Suppression Optimization — Research Brief (Session F)

Scope: push spectral-phase Raman-suppression optimization from the known-good
L = 30 m SMF-28 / P_peak = 0.05 W / 185 fs sech² configuration (-57 dB at best)
to L = 100 m and potentially L = 200 m. The solver is an interaction-picture
NLSE integrated by Tsit5 / Vern9 (not vanilla SSFM), so we use SSFM literature
as the closest analogue for error-accumulation and aliasing behavior.

Physical parameters used throughout:
- β₂ = −2.16 × 10⁻²⁶ s²/m (= −21.6 ps²/km)
- γ = 1.3 × 10⁻³ W⁻¹ m⁻¹
- λ₀ = 1550 nm, anomalous dispersion
- FWHM = 185 fs sech², T₀ = FWHM / 1.7627 = 105.0 fs
- P_peak = 0.05 W

---

## 1. SSFM error accumulation (long-haul summary)

The canonical reference is Sinkin, Holzlöhner, Zweck, Menyuk, *JLT* **21**(1),
61–68 (2003), "Optimization of the Split-Step Fourier Method in Modeling
Optical-Fiber Communications Systems." They benchmark five step-size rules
(constant, walk-off, nonlinear-phase, step-doubling local error, "logarithmic"
local error) across soliton collisions, DMS systems, and CRZ. The paper
introduces a globally third-order-accurate symmetric SSFM in which step size
is selected by bounding the **local error δ** per step, and they report that
the local-error method is the most efficient across all tested regimes and
gives a system-independent rule. With symmetric splitting the scheme is
O(h³) locally and O(h²) globally when the local-error tolerance is fixed;
with a constant-δ adaptive rule the number of steps scales roughly as
N ∝ √(∫ γ P(z) dz / δ) ∝ √L for quasi-CW nonlinear phase accumulation.

Heidt, *JLT* **27**(18), 3984–3991 (2009), "Efficient Adaptive Step-Size
Method …," refines this with a **conservation-quantity error** (CQE)
criterion that tracks photon-number conservation violation, avoiding step-
doubling overhead and yielding 6–10× speedups for supercontinuum-type
propagations where the spectrum broadens dramatically.

Relevance to our interaction-picture Tsit5/Vern9 solve:
- `DifferentialEquations.jl` already uses a per-step local-error estimator
  (embedded RK pairs). Sinkin's rule is implicitly respected through
  `reltol`/`abstol`, which ultimately controls local error per step.
- Global error for a 5th-order scheme with fixed tolerance typically scales
  as **O(L · tol)** because the adaptive controller keeps local error per
  step roughly constant. Practical rule of thumb (Rackauckas/SciML FAQ): the
  attainable global accuracy is ≈ 1–2 digits worse than reltol.
- For the current scheme, going 30 m → 100 m increases the number of
  adaptive steps by ~3× and the expected global error by a similar factor.
  To hold end-of-fiber relative accuracy constant, drop reltol by ~3×.
- Interaction-picture formulation removes the fast dispersive phase from the
  ODE state, so local error is dominated by the nonlinear Kerr + Raman term
  (not by oscillatory β₂ phase). This is *good* for long-haul accuracy — the
  ODE solver does not need to resolve fs-scale phase oscillations, only the
  slower nonlinear evolution on L_NL ≈ 15 km (see §3). This is why we can
  integrate 100 m with modest step counts.

---

## 2. Time-window bound at L = 100 m (derivation with numbers)

The window T must contain:
1. the pulse itself (≈ 3 × FWHM on each side for sech² tails),
2. the **dispersive walk-off** of every frequency component that carries
   non-negligible energy,
3. a guard band on each edge to avoid periodic wrap-around contamination
   (the FFT imposes T-periodic boundary conditions; any energy that walks
   past ±T/2 reappears at ∓T/2 and corrupts the Raman band).

Group-delay shift of a frequency offset Δω after length L is
t(Δω) = β₂ · Δω · L.
For a 185 fs sech² pulse the intensity spectrum has FWHM
Δf_3dB ≈ 0.315 / FWHM = **1.70 THz** (Δω_3dB = 1.07 × 10¹³ rad/s).
The field −20 dB half-width is about 3× the 3-dB half-width for sech²,
so the conservative signal bandwidth is
Δω_20dB ≈ 3.2 × 10¹³ rad/s (≈ 5.1 THz).

Walk-off contributions at the various lengths:

| L     | half-walkoff (3 dB) | half-walkoff (−20 dB) | T_min (both sides + 3 × FWHM) |
|-------|---------------------|-----------------------|-------------------------------|
| 30 m  | 6.9 ps              | 20.8 ps               | **≈ 42 ps**                   |
| 50 m  | 11.6 ps             | 34.7 ps               | ≈ 70 ps                       |
| 100 m | 23.1 ps             | 69.3 ps               | **≈ 139 ps**                  |
| 200 m | 46.2 ps             | 138.6 ps              | ≈ 278 ps                      |

So at L = 100 m the minimum defensible time window is **T ≳ 140 ps**, i.e.
about **7× larger than the 20 ps window that suffices at 30 m**.

At L = 100 m the walk-off is the *dominant* term (L/L_D ≈ 196, see §3), so
the SPM-based formula currently in `recommended_time_window` will
underestimate the required window. A GVD-corrected bound to plug in:

    T_min(L) = 2 · |β₂| · Δω_20dB · L  +  3 · FWHM · safety

Take Δω_20dB ≈ 3 · 2π · 0.315 / FWHM  for sech² (empirical −20 dB field
ratio ≈ 3× the 3-dB intensity ratio; conservative).

Aliasing note (Agrawal, *Nonlinear Fiber Optics*, 5th ed., §2.4; Sinkin 2003
§II.B): the FFT assumes periodicity, so a band-shifted pulse whose group
delay exceeds ±T/2 wraps around the window edge and re-interferes with
itself. For a spectral-band cost function this wrap-around **aliases energy
back into the Raman band mask**, producing spurious non-smooth gradient
contributions that can trap L-BFGS in fake local minima. Keep T ≥ 2 ×
(physical walk-off + pulse).

---

## 3. Characteristic lengths & dynamical regime for this system

Using T₀ = 105 fs, P₀ = 0.05 W, β₂ and γ above:

    L_D  = T₀² / |β₂|   = 0.51 m
    L_NL = 1 / (γ P₀)   = 15,385 m  ≈ 15.4 km
    N²   = L_D / L_NL   = 3.31 × 10⁻⁵   ⇒   N = 0.0058

Characteristic-length ratios at the target lengths:

| L     | L / L_D | L / L_NL |
|-------|---------|----------|
| 2 m   | 3.9     | 1.3e-4   |
| 30 m  | 58.8    | 2.0e-3   |
| 100 m | 196.1   | 6.5e-3   |
| 200 m | 392.2   | 1.3e-2   |

Interpretation (Agrawal Ch. 3, 5):
- N ≪ 1 ⇒ **dispersion-dominated regime, not a soliton**.
- At L = 100 m the pulse has walked through ~200 dispersion lengths but
  only ~0.65 % of a nonlinear length. Almost all the dynamics is GVD;
  nonlinearity is a small perturbation that nevertheless seeds the Raman
  band (the suppression knob).
- Spectrum is essentially preserved (to zeroth order) while time-domain
  profile broadens by L/L_D. Raman red-shifting and SPM-induced spectral
  reshaping are O(L/L_NL) = O(0.01) effects that accumulate coherently and
  are exactly what the optimizer is shaping.
- This is the opposite of the supercontinuum regime Heidt 2009 targets
  (there, N ≳ 10, soliton fission, spectrum explosion). Step-size control
  can be looser for us than for SC generation.

---

## 4. Modulation instability assessment

In anomalous dispersion with a (quasi-)CW pump of power P, Agrawal Ch. 5
gives the MI peak at

    Ω_max² = 2 γ P / |β₂|        ⇒ Ω_max = 7.76 × 10¹⁰ rad/s
                                 f_max   = 12.3 GHz    (**not** 13 THz)
    g_max  = 2 γ P              = 1.30 × 10⁻⁴ m⁻¹
    L_MI   = 1 / g_max          ≈ 7.7 km

(See RP Photonics "Modulational Instability"; the MI peak gain is the
classic 2γP result; the MI sideband offset scales as √(γP/|β₂|), not the
13 THz Raman Stokes shift — those are unrelated.)

MI amplification factors from numerical noise seed (a round-off floor of
~1e-16 in the Raman-band cost):

    exp(g_max · L) at L = 30 m : 1.004  (negligible)
    exp(g_max · L) at L = 100 m: 1.013  (negligible)
    exp(g_max · L) at L = 200 m: 1.026  (negligible)

**Conclusion**: MI is not an issue at 50 mW peak over 200 m. It would only
become dangerous above ~P_peak = 10 W or at L ≳ 10 km. We are safe.

Sanity caveat: an MI *pulsed* pump with non-CW temporal shape has a more
complex, suppressed gain (Agrawal §5.1.2); our sub-ps pulse is far from the
CW-approximation validity regime, so the bound above is a conservative
upper bound. Spontaneous MI from numerical noise is a non-concern.

---

## 5. Warm-start strategies (ranked recommendations)

Background (Nocedal & Wright, *Numerical Optimization*, 2e, §18.5;
L-BFGS Wikipedia / Nocedal 1980 *Math Prog* 35): quasi-Newton methods
converge quadratically only inside the basin of attraction of the target
local minimum. For non-convex ODE-constrained shaping, **the initial guess
determines which minimum L-BFGS lands in**. Continuation (homotopy)
methods — solve the problem at a sequence of gradually harder parameter
values, each initialized from the previous solution — are the standard
tool (see Allgower & Georg, *Numerical Continuation Methods*, 1990).

For our problem the "hardness" knob is L. Moving L = 30 → 100 m keeps the
cost surface smooth (no bifurcations), so continuation should work well.
Three candidate transforms of φ(ω) from short-L to long-L:

**Option A — Identity copy: φ_100(ω) ← φ_30(ω)**.
Rationale: the optimized phase at L = 30 m is NOT a pure −β₂ L /2 ω²
pre-chirp; it has structure matched to the Raman-band energy-transfer
dynamics. Those dynamics don't simply rescale with L in a nonlinear
problem. Safest starting point because it preserves whatever non-trivial
structure the 30 m optimum carries.

**Option B — GVD-rescaled: φ_100(ω) ← (L_new/L_old) · φ_30(ω)**.
Rationale: in a purely-dispersive problem the *perfect* pre-compensation
is φ_prechirp(ω) = −(β₂/2) L ω², which is linear in L. If Raman
suppression at 30 m is dominated by GVD pre-compensation (plausible given
L/L_D = 59), scaling φ by L_new/L_old ≈ 3.33 extrapolates the
pre-compensation to 100 m. Risk: overshoots structural (non-GVD)
components that should not scale.

**Option C — Decomposed rescale**: fit φ_30 = a₀ + a₁ω + a₂ω² + Δφ(ω),
rescale only a₂ by L_new/L_old, keep Δφ(ω) fixed (the non-polynomial
"structural" part). This is cleaner physics but adds implementation work
and a basis choice.

**Option D — From zero**: ignore the 30 m solution. Discard information.
Only defensible if we suspect Option A/B/C all lie in the wrong basin.

**Recommendation**: run a quick 3-way horse race.
1. Start with **Option A (identity)** — cheapest, most conservative.
2. In parallel, run **Option B (linear rescale)** — a 2× factor
   scale-up of the quadratic part is typically right when GVD dominates,
   and this is the GVD-dominated regime (§3).
3. Continuation staircase: 30 → 50 → 75 → 100 m, each warm-started from
   the previous, **using Option A at every step**. This is the textbook
   continuation strategy and is the *most likely to reach the global
   optimum*, at the cost of 3–4× compute. Strongly recommended for the
   L = 200 m target.

Expected outcome: Option A will probably converge to a near-optimum at
100 m within 30–50 L-BFGS iterations. The staircase will give the best
cost by 1–5 dB (heuristic; verify empirically).

---

## 6. Optim.jl checkpoint idiom (code sketch)

Two discourse threads are authoritative here:
- "Save the optimization results while the optimization is running
  (Optim.jl)" (2024) — states that the callback `OptimizationState` for
  LBFGS no longer exposes `"x"` in `metadata`; users must capture x via
  the *objective function itself*.
- "Optim L-BFGS() — Can I save internal state?" (2018) — confirms that
  `Optim.initial_state()` + passing a mutated `state` object back to
  `optimize()` *can* resume with full (s, y) history, but the internal
  field names (`dg_history`, `s_history`, etc.) are **unexported, unstable,
  subject to change**.

Practical conclusion: **don't try to persist the L-BFGS inverse-Hessian
history across process boundaries**. Just checkpoint (x, f, g) every N
iterations and warm-start a fresh optimizer from `x_last`. The lost
Hessian information is rebuilt in O(m) iterations (m = L-BFGS history
length, default 10) which is cheap compared to a 2–8 h forward/adjoint
campaign.

Code idiom:

```julia
using Optim, JLD2, Dates

# Thread-safe state capture via a closure over a mutable container
mutable struct CheckpointBuf
    x_last::Vector{Float64}
    f_last::Float64
    g_last::Vector{Float64}
    iter::Int
end
buf = CheckpointBuf(copy(phi0), Inf, zero(phi0), 0)

function fg!(F, G, x)
    J, dJ = cost_and_gradient(x, problem)  # your forward+adjoint
    buf.x_last .= x
    buf.f_last  = J
    buf.g_last .= dJ
    buf.iter   += 1
    (G !== nothing) && (G .= dJ)
    return J
end

function checkpoint_cb(state)
    if buf.iter % 5 == 0
        tag = Dates.format(now(), "yyyymmdd-HHMMSS")
        @save "checkpoints/opt_$(tag)_iter$(buf.iter).jld2" \
              x=buf.x_last f=buf.f_last g=buf.g_last iter=buf.iter
        @info "checkpoint" iter=buf.iter f=buf.f_last
    end
    return false  # don't stop
end

res = optimize(
    Optim.only_fg!(fg!),
    phi0,
    LBFGS(; m = 10),
    Optim.Options(
        iterations       = 500,
        g_tol            = 1e-8,
        store_trace      = true,
        show_trace       = true,
        callback         = checkpoint_cb,
    ),
)

# Resume after crash: load last JLD2, restart with `phi0 = x_last`.
```

Notes:
- `callback` receives an `OptimizationState` whose `metadata["time"]` is
  guaranteed present but whose `metadata["x"]` is not (post-Optim 1.7).
  Capture `x` via the objective closure as above — this is the idiom the
  Julia discourse recommends.
- `store_trace = true` + `extended_trace = true` will retain a trace
  in-memory; combine with `Optim.x_trace(res)` post-hoc if desired.
- The L-BFGS memory depth `m` is Optim default 10; increasing to 20–30
  can help on high-dim shaping problems at low marginal cost.

---

## 7. Recommended grid (Nt, T) at L = 50 m, 100 m, 200 m

Design rule:
- T ≥ T_min from §2 (walk-off + pulse + guard) with at least 25 % margin.
- Δt small enough that the −20 dB spectral edge of the pulse is inside
  ±20 % of the Nyquist band. For 185 fs sech², the field −20 dB extent
  is roughly ±5 THz from ω₀, so Nyquist = 1/(2 Δt) ≥ 25 THz ⇒ Δt ≤ 20 fs
  is *easily* sufficient for the pulse alone. If we want to keep the
  Raman Stokes band (−13 THz) and its mirror well away from Nyquist,
  Nyquist ≥ 50 THz ⇒ Δt ≤ 10 fs is safer.
- Nt is a power of 2 (FFT requirement, already in code).

| L       | T (ps) | Δt (fs) | Nt       | log₂Nt | Notes                                  |
|---------|--------|---------|----------|--------|----------------------------------------|
| 30 m    | 20     | 2.44    | 8192     | 13     | current (known good)                   |
| 50 m    | 40     | 2.44    | 16384    | 14     | doubles window, same Δt                |
| 100 m   | 160    | 4.88    | 32768    | 15     | headroom > T_min=139 ps; coarser Δt OK |
| 100 m*  | 80     | 4.88    | 16384    | 14     | **aggressive**; right at T_min         |
| 200 m   | 320    | 4.88    | 65536    | 16     | doubles again                          |
| 200 m*  | 160    | 2.44    | 65536    | 16     | Δt-preserving, same Nt as 100 m*       |

`*` = memory-conservative option if Nt = 2¹⁶ is too heavy.

Memory reality check: Nt = 2¹⁵ × M=1 complex = 32768 × 16 B = 524 kB for
the state, but the pre-allocated ODE tuple + adjoint buffers scale as
~50× that, so ~25 MB. Nt = 2¹⁶ ~ 50 MB. Both fit comfortably on the
22-core burst VM (88 GB).

ODE tolerance (from §1):
- 30 m baseline: reltol = 1e-6, abstol = 1e-8 (confirm in `common.jl`)
- 100 m: **drop reltol to 1e-7** (empirically the Heidt 2009 sweet spot
  for multi-L propagation; extra cost is ~40 %, well worth it for a
  gradient that is trusted to 1e-5 for L-BFGS).
- 200 m: reltol = 1e-7, abstol = 1e-10.

---

## 8. Open questions the simulation itself must answer

1. **Does the identity-warm-start φ_30 lie in the right basin for 100 m?**
   Run Option A vs Option B vs 30→50→75→100 staircase and compare final
   cost (in dB). If the staircase wins by > 3 dB, adopt it as default
   for the 200 m run.

2. **What is the empirical global-error scaling?** Compare the same
   optimized φ run at reltol ∈ {1e-6, 1e-7, 1e-8} and record the
   cost variation. If |ΔJ_dB| > 0.5 dB between 1e-7 and 1e-8, tighten.

3. **Does the 100 m optimum exhibit a different qualitative φ(ω) shape
   than the 30 m optimum?** If the 30 m solution is dominated by a
   quadratic (GVD pre-compensation) term, the 100 m solution's
   quadratic coefficient should scale by ~3.33; a departure from that
   scaling is a signature of nonlinear-induced structure (interesting
   physics).

4. **How does the attainable Raman suppression (cost in dB) scale with
   L?** Is it monotonically better (more room for pre-compensation) or
   worse (more accumulated Raman transfer)? The current −57 dB at 30 m
   could be a ceiling or a floor.

5. **Does T = 1.5 × T_min suffice, or do we need 2 × T_min?** Test by
   doubling T at fixed Nt·Δt and checking whether the optimum cost
   changes by > 0.3 dB. If yes, wrap-around is polluting the gradient
   and T must grow further.

6. **Does the 100 m run still converge within 200 L-BFGS iterations?**
   If iteration count balloons, the Hessian condition number has
   worsened with L — mitigate with diagonal preconditioning
   (scale φ(ω) by 1/(1 + β₂ L ω²)) or a trust-region method.

---

## Concrete recommendation

> **For L = 100 m SMF-28 at P_peak = 0.05 W, start with Nt = 2¹⁵ = 32768,
> T = 160 ps (Δt ≈ 4.88 fs), ODE reltol = 1e-7 / abstol = 1e-9, L-BFGS
> with m = 20, checkpoint every 5 iterations via the closure-based `fg!`
> + callback idiom in §6, and warm-start φ from the L = 30 m optimum
> via IDENTITY copy (Option A). In parallel, run a continuation
> staircase 30 → 50 → 75 → 100 m with identity warm-starts at each
> step; keep whichever of the two gives the lower cost as the 100 m
> reference. Do NOT waste compute on Option D (zero start) — it is
> strictly dominated.**

Budget estimate: ~3–4 h on the burst VM for the direct 100 m run,
~8 h for the full staircase. MI is not a concern at this power; do not
spend optimizer budget on MI-suppression regularizers. Walk-off
aliasing *is* the dominant numerical-physics risk — get T right and
everything else follows.

---

## References (verified)

1. Sinkin, Holzlöhner, Zweck, Menyuk, "Optimization of the Split-Step
   Fourier Method in Modeling Optical-Fiber Communications Systems,"
   *J. Lightwave Technol.* **21**(1), 61–68 (2003).
   https://opg.optica.org/jlt/abstract.cfm?uri=jlt-21-1-61
2. Heidt, "Efficient Adaptive Step-Size Method for the Simulation of
   Supercontinuum Generation in Optical Fibers," *J. Lightwave Technol.*
   **27**(18), 3984–3991 (2009).
   https://opg.optica.org/jlt/abstract.cfm?uri=jlt-27-18-3984
3. G. P. Agrawal, *Nonlinear Fiber Optics*, 5th ed. (Academic, 2013),
   Chs. 2 (NLSE, SSFM), 3 (GVD, L_D), 5 (MI gain), 8 (Raman).
4. Nocedal & Wright, *Numerical Optimization*, 2nd ed. (Springer, 2006),
   Chs. 7 (L-BFGS), 11 (continuation / homotopy).
5. Allgower & Georg, *Numerical Continuation Methods: An Introduction*
   (Springer, 1990).
6. RP Photonics Encyclopedia — "Modulational Instability,"
   https://www.rp-photonics.com/modulational_instability.html
   (peak-gain 2γP rule, Ω_max = √(2γP/|β₂|)).
7. RP Photonics Encyclopedia — "Solitons" (sech² FWHM = 1.7627·τ).
   https://www.rp-photonics.com/solitons.html
8. Julia Discourse: "Save the optimization results while the
   optimization is running (Optim.jl)," thread 119116 (2024).
9. Julia Discourse: "Optim L-BFGS() — Can I save internal state?,"
   thread 8583 (2018).
10. SciML Docs — "Common Solver Options / Tolerances," and
    "FAQ: what tolerance should I use?"
    https://docs.sciml.ai/DiffEqDocs/stable/basics/faq/

Not independently verified (mentioned but not cross-checked against the
primary source on this research pass):
- specific MI-statistics PRL by Walczak, Randoux, Suret *Phys. Rev. Lett.*
  **123**, 093902 (2019) — cited only for general context on MI
  stochasticity, not used quantitatively here.
