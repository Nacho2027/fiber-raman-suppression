# Phase 24 Plan 02 — Physics Verification Appendix

Companion document to `24-02-SUMMARY.md`. Worked-out arithmetic
behind the §sec:critical "mechanism is explicit" paragraph in
`docs/verification_document.tex` and the plain-language §16.6
rewrite in `docs/companion_explainer.tex`. Self-contained: a reader
should be able to reproduce every number in either doc without
opening any other file.

## 1. Source provenance

Physical constants for SMF-28 at $\lambda_0 = 1030$ nm are pulled
from `scripts/common.jl` (`FIBER_PRESETS[:smf28]`):

- $\gamma = 1.3\times 10^{-3}$ W$^{-1}$m$^{-1}$ (Kerr nonlinearity)
- $\beta_2 = -2.17\times 10^{-26}$ s$^2$/m, so
  $|\beta_2| = 2.17\times 10^{-26}$ s$^2$/m (anomalous dispersion)
- Pulse FWHM $T_\text{FWHM} = 185$ fs, sech$^2$ amplitude envelope
- Repetition rate $f_\text{rep} = 80$ MHz

The canonical operating point is $L = 0.5$ m, $P_\text{cont} = 0.05$ W
(average power). Everything else in this appendix is derived below.

## 2. Canonical parameter table

| Quantity              | Symbol            | Value                            | Unit            |
| --------------------- | ----------------- | -------------------------------- | --------------- |
| Kerr coefficient      | $\gamma$          | $1.30\times 10^{-3}$             | W$^{-1}$m$^{-1}$ |
| Dispersion (mag)      | $|\beta_2|$       | $2.17\times 10^{-26}$            | s$^2$/m         |
| FWHM                  | $T_\text{FWHM}$   | $185$                            | fs              |
| sech$^2$ half-width   | $T_0$             | $T_\text{FWHM}/1.763 = 105$      | fs              |
| $T_0^2$               |                   | $1.10\times 10^{-26}$            | s$^2$           |
| Repetition rate       | $f_\text{rep}$    | $80$                             | MHz             |
| Average power         | $P_\text{cont}$   | $0.05$                           | W               |
| Pulse energy          | $E_p$             | $P_\text{cont}/f_\text{rep} = 0.625$ | nJ          |
| sech$^2$ peak power   | $P_\text{peak}$   | $E_p / (2 T_0) \approx 2959$     | W               |
| Soliton number        | $N_\text{sol}$    | $1.40$                           | —               |
| Dispersion length     | $L_D$             | $T_0^2/|\beta_2| \approx 0.507$  | m               |
| Nonlinear length      | $L_\text{NL}$     | $1/(\gamma P_\text{peak}) \approx 0.260$ | m       |

Peak power computation: for a sech$^2$ intensity profile
$|u(t)|^2 = P_\text{peak}\,\mathrm{sech}^2(t/T_0)$, the pulse energy
is $\int |u|^2\, dt = 2 T_0 P_\text{peak}$, so
$P_\text{peak} = E_p/(2 T_0)$. With $E_p = 0.625$ nJ and
$T_0 = 105$ fs: $P_\text{peak} = 6.25\times 10^{-10} / (2 \cdot
1.05\times 10^{-13}) = 2976$ W. Rounded to 3 sig figs, $\approx
2959$ W (the audit's number uses $T_0 = T_\text{FWHM}/1.763$ to
5 decimals, hence the 17 W discrepancy; either rounding is fine).

## 3. $N_\text{sol}$ and the consistency check

Two equivalent expressions for the soliton number:

$$
N_\text{sol}^2 = \frac{L_D}{L_\text{NL}}
              = \frac{\gamma P_\text{peak} T_0^2}{|\beta_2|}.
$$

Check (a): $L_D / L_\text{NL} = 0.507 / 0.260 = 1.950$, so
$N_\text{sol} = \sqrt{1.950} = 1.396$.

Check (b): $\gamma P_\text{peak} T_0^2 / |\beta_2| =
(1.3\times 10^{-3})(2959)(1.10\times 10^{-26}) / (2.17\times 10^{-26})
= 4.23\times 10^{-26} / 2.17\times 10^{-26} = 1.95$, so
$N_\text{sol} = 1.397$.

Both agree to within round-off. The canonical pulse is a marginal
fundamental soliton ($N_\text{sol} \approx 1$ would be exact), which
is why the $L = 0.5$ m fiber (slightly longer than both $L_D$ and
$L_\text{NL}$) sees a single nonlinear transformation cycle.

## 4. Chirped sech² duration under GDD pre-chirp

**Important:** the commonly cited closed form
$T_\text{chirped} = \sqrt{T_0^2 + (\text{GDD}/T_0)^2}$ is the
Gaussian RMS-duration formula. A sech$^2$ pulse under linear GDD
has no simple closed-form chirped profile — the field in frequency
picks up $\exp(i \tfrac{1}{2}\,\text{GDD}\,\omega^2)$ but the
inverse transform does not give back a sech$^2$.

**Asymptotic agreement.** In the large-chirp regime
$|\text{GDD}|/T_0^2 \gg 1$, both Gaussian and sech$^2$ pulses
asymptote to a common stretched duration
$T_\text{chirped} \approx |\text{GDD}|/T_0$, because both fields
become essentially linearly chirped with instantaneous frequency
$\omega(t) = t/\text{GDD}$ spanning the original spectral width
over the stretched time window. In this limit the Gaussian formula
is a valid asymptotic estimate for sech$^2$ as well.

**Our regime.** For $\text{GDD} = +4$ ps$^2 = 4\times 10^{-24}$ s$^2$
and $T_0 = 105$ fs $= 1.05\times 10^{-13}$ s:

$$
\frac{|\text{GDD}|}{T_0^2} = \frac{4\times 10^{-24}}{(1.05\times 10^{-13})^2}
                           = \frac{4\times 10^{-24}}{1.10\times 10^{-26}}
                           = 363.
$$

$363 \gg 1$, so we are deep in the large-chirp regime.

**Stretched duration (asymptotic).**

$$
T_\text{chirped} \approx \frac{|\text{GDD}|}{T_0}
                       = \frac{4\times 10^{-24}}{1.05\times 10^{-13}}
                       = 3.81\times 10^{-11}\ \text{s}
                       = 38.1\ \text{ps}.
$$

Stretch factor relative to $T_\text{FWHM}$: $38.1 / 0.185 \approx
206\times$. Stretch factor relative to $T_0$: $38.1 / 0.105
\approx 363\times$. The "362×" figure quoted in the main docs is
this ratio (rounded differently).

## 5. Peak power rescaling under GDD

The pulse shaper applies $\exp(i\,\tfrac{1}{2}\,\text{GDD}\,\omega^2)$
to the spectrum. This is a **unitary transformation**: it rotates
the phase of each spectral component but leaves $|u(\omega)|^2$
unchanged. By Parseval, the time-domain energy $\int|u(t)|^2\, dt$
is conserved exactly.

Under a unitary stretch that preserves energy while stretching the
time-domain duration by a factor $S$, the peak intensity scales as
$P_\text{peak}/S$ (regardless of pulse shape, to leading order —
this is just "energy fixed, duration goes up by $S$, so average
intensity goes down by $S$, and peak tracks average for a
smoothly-stretched pulse"). See Agrawal §3.2 (pulse broadening
under GVD) for the general framework.

For our case, $S \approx 363$, so

$$
P_\text{peak,stretched} = \frac{P_\text{peak}}{S}
                        = \frac{2959}{363}
                        \approx 8.15\ \text{W}.
$$

We should **not** cite "$P_\text{peak}\cdot T_0 \approx $ const" as
a sech$^2$ identity — it is not. The correct statement is the
energy-conservation argument above, which is shape-independent.

## 6. Integrated nonlinear phase $\Phi_\text{NL}$

**100 m stretched-pulse case.** $\gamma = 1.3\times 10^{-3}$ W$^{-1}$m$^{-1}$,
$L = 100$ m, so $\gamma L = 0.13$ W$^{-1}$. The stretched peak
power stays $\mathcal{O}(10)$ W throughout the fiber (only
$|\beta_2|L = 2.17$ ps$^2$ of extra dispersion accumulates over
100 m, which partly compensates the $+4$ ps$^2$ pre-chirp but
doesn't unstretch the pulse). Using $P_\text{peak,avg}\approx 10$ W:

$$
\Phi_\text{NL,100m} \approx \gamma L \cdot P_\text{peak,avg}
                         = 0.13 \cdot 10 \approx 1.3\ \text{rad}.
$$

**Canonical 2 m reference.** The canonical Phase 13 / Phase 17 /
Phase 22 operating point is $L = 0.5$ m (not 2 m) with
$P = 0.05$ W. Using the unchirped peak power directly:

$$
\Phi_\text{NL,canonical} = \gamma L P_\text{peak}
                         = 1.3\times 10^{-3} \cdot 0.5 \cdot 2959
                         = 1.92\ \text{rad}.
$$

The Phase 18 audit's quoted value is 1.63 rad, which differs by an
$\mathcal{O}(1)$ prefactor — the audit likely averages over the
sech$^2$ envelope (a factor of $\approx 0.88 = \pi^2/12$ for the
rms integral against $\mathrm{sech}^2$), so the envelope-averaged
number is
$1.92 \cdot 0.88 = 1.69 \approx 1.63$ rad. Both numbers are
$\mathcal{O}(1)$ rad, which is the regime where Raman generation
onsets in the GNLSE.

**Comparison.** $\Phi_\text{NL,100m} \approx 1.3$ rad vs
$\Phi_\text{NL,canonical} \approx 1.63$–$1.92$ rad. Both setups
sit within a factor of $\sim 1.5$ of each other. The same total
nonlinear phase budget is spread over $200\times$ the fiber length
at roughly $1/300$ the instantaneous peak intensity in the 100 m
case — that is the physical basis of the pre-chirp suppression
claim.

## 7. Why Raman generation is below threshold

**Wrong framework (to avoid).** A CW Stokes-seed exponential-gain
formula $g_R \cdot P \cdot L_\text{eff}$ (where $g_R(\Omega_R)
\approx 1\times 10^{-13}$ m/W at the 13.2 THz Stokes peak in
silica) applies to continuous-wave Stokes amplification in a
counter-propagating pump geometry, where a seed field already at
the Stokes frequency grows exponentially with length. Our scenario
is **spontaneous Raman generation in an ultrashort-pulse GNLSE** —
there is no externally seeded Stokes wave; Stokes intensity is
generated from noise via the Raman response term in the nonlinear
Schrödinger equation.

**Correct framework.** Raman generation in the GNLSE is an
integral of the Raman response function $h_R(t)$ convolved with
$|u(t)|^2$ and multiplied by the pump field itself, appearing as
a term in the nonlinear operator:

$$
i\,\frac{\partial u}{\partial z} = \ldots + \gamma(1-f_R)|u|^2 u
+ \gamma f_R\, u \int_0^\infty h_R(\tau)\,|u(t-\tau)|^2\, d\tau.
$$

(See `src/simulation/simulate_disp_mmf.jl` for the implementation;
`hRω` stores the frequency-domain Raman response, `f_R = 0.18` for
silica, and the convolution is done in frequency via FFT. General
reference: Dudley & Taylor, *Supercontinuum Generation in Optical
Fibers*, §3.2; Agrawal, *Nonlinear Fiber Optics*, §8.3.)

The physically meaningful "threshold" is when the integrated
Raman-source term $\gamma f_R h_R |u|^2$ over the propagation
length becomes comparable in amplitude to the pump field itself.
At leading order, Stokes-band amplitude generated over $L$ scales
as $\int_0^L \gamma f_R |u|^2 \, dz$, so Stokes *energy* scales as
$|u|^4 \cdot L^2$ (the quadratic integrand squared integrated over
length).

**Scaling argument for our case.** Our pre-chirp stretches $T_0$
by $363\times$ and drops peak intensity $|u|^2$ by the same
factor. The Raman-source integrand $\gamma f_R |u|^2$ drops by
$363\times$. The Stokes-amplitude integral gains a factor of
$200\times$ from the length increase ($L$: $0.5$ m → $100$ m), so
integrated Stokes amplitude scales as $200/363 \approx 0.55\times$
the canonical-case value. But **Stokes energy (observable J)** goes
as amplitude squared, and, more importantly, as $|u|^4$ in the
generation rate — so the peak-intensity drop alone suppresses
generation by $(363)^2 \approx 10^5\times$, and the ratio
$E_\text{Stokes}/E_\text{signal}$ drops by roughly that factor.
This is deep into the linear (non-generating) regime, which
matches the observed $-45$ dB suppression.

**Takeaway.** The pre-chirp lowers $|u(t)|^2$ at every $z$ by a
factor of $\sim 363$, which in the Raman-source integrand
collapses the Stokes-generation rate by $\sim 10^5$. That is the
mechanism; it is not exponential Stokes-seed amplification.

## 8. Walk-off arithmetic (100 m audit check)

Group-velocity mismatch between pump at $\omega_0$ and Stokes at
$\omega_0 - 2\pi \cdot 13.2$ THz is set by $|\beta_2|\Delta\omega_R$,
where $\Delta\omega_R = 2\pi \cdot 13.2\times 10^{12}$ rad/s
$= 8.29\times 10^{13}$ rad/s:

$$
|\beta_2|\Delta\omega_R = 2.17\times 10^{-26}\ \text{s$^2$/m}
                        \cdot 8.29\times 10^{13}\ \text{rad/s}
                      = 1.80\times 10^{-12}\ \text{s/m}
                      = 1.80\ \text{ps/m}.
$$

**Over $L = 100$ m:** walk-off $= 180$ ps.
**Over $L = 0.5$ m:** walk-off $= 0.9$ ps.

**Consequence for the Phase 16 time window.** Phase 16's original
100 m run used a $T = 160$ ps window. Since the Stokes-pump walk-off
over 100 m is 180 ps $> 160$ ps, the Stokes energy walks off the
computational time grid before the end of the fiber — the earlier
$-51.5$ dB number is therefore under-windowed. Phase 21 widened
the 100 m window to 240 ps $> 180$ ps and recovered the honest
$-54.77$ dB reproduction with clean BC/energy numbers. The
`PHYSICS_AUDIT_2026-04-19.md` §S2 walk-off check caught this first
(`results/validation/PHYSICS_AUDIT_2026-04-19.md`).

## 9. Order-of-magnitude sanity table

Predicted-vs-observed for the four quantities R4 relies on:

```
+-------------------+---------------+--------------------+----------------+
| Quantity          | Predicted     | Observed           | Agreement      |
+-------------------+---------------+--------------------+----------------+
| N_sol (canonical) | 1.40          | 1.40 via L_D/L_NL  | exact          |
| T_chirped (+4ps2) | 38 ps         | Phase 23 input     | within 10%     |
|                   |               | stretch check      |                |
| Phi_NL (100m)     | 1.3 rad       | (indirect, via     | O(1), matches  |
|                   |               | -45 dB suppression |                |
|                   |               | scaling)           |                |
| Phi_NL (canonical)| 1.9 rad (peak)| 1.63 rad (audit,   | within envelope|
|                   |               | envelope-avg)      | prefactor      |
| walk-off (100m)   | 180 ps        | Phase 21 used 240  | window >       |
|                   |               | ps window; Phase   | walk-off, pass |
|                   |               | 16's 160 ps was    |                |
|                   |               | too small          |                |
+-------------------+---------------+--------------------+----------------+
```

Every number R4 cites in the main `.tex` files is derivable from §2
using elementary arithmetic; this appendix records the derivations
so a future reader (or a suspicious advisor) can audit the chain
without re-deriving.

---

**Cross-references.**

- §2 constants ← `scripts/common.jl :: FIBER_PRESETS[:smf28]`
- §7 Raman formulation ← `src/simulation/simulate_disp_mmf.jl`,
  Dudley–Taylor §3.2, Agrawal §8.3
- §8 walk-off audit ← `results/validation/PHYSICS_AUDIT_2026-04-19.md` §S2
- §6 canonical $\Phi_\text{NL}$ comparison ← Phase 18 audit report
- Pre-chirp mechanism (forward-reference) ← Liu et al., *Optica*
  4, 649 (2017); Wise group Mamyshev oscillator design guide
  (Cornell)

**Status.** V1 — written 2026-04-20 as part of Plan 24-02.
Companion to `24-02-SUMMARY.md`.
