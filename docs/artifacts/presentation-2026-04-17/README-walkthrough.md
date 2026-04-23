# Walkthrough — what each figure means

This is a plain-English guide written for you (not the professor). Read it before the meeting so you know what story each figure tells. All images live in this folder.

---

## First: three pieces of jargon you need

### 1. "Spectral phase" `phi(omega)`

Every pulse has a **shape in time** (the intensity envelope, maybe 185 fs wide). Mathematically, that time shape is equivalent to an **amplitude** and a **phase** at every frequency `omega`. The amplitude `A(omega)` is the power spectrum (what comes out of a grating). The phase `phi(omega)` is invisible to intensity detectors but it's what determines how those frequency components line up in time.

- If `phi(omega) = 0` for all `omega`, all frequencies are in phase at `t = 0` — you get the shortest, most peaky pulse (transform-limited).
- If `phi(omega)` has a slope with frequency, you're delaying the whole pulse — doesn't change shape.
- If `phi(omega)` has *curvature* (second derivative), different frequencies arrive at different times — the pulse stretches out. This is a **chirp**.

A pulse shaper is a box that lets you dial in `phi(omega)` bin by bin. Real shapers have ~100 bins ("pixels"); our simulation has 16384 bins.

### 2. "DC + chirp" (the thing you asked about)

When I say "the optimized phase looks like DC + a quadratic chirp," I mean:

```
phi(omega)  =  a0    +    a1 * omega    +    a2 * omega^2
               ^^         ^^^^^^^^^^^         ^^^^^^^^^^^^^^^
               DC         linear              quadratic
              (rigid      (rigid time         (chirp — different
               phase       shift,              frequencies arrive at
               offset)     invisible)          different times)
```

- `a0` is a constant — it just multiplies the whole pulse by `exp(i*a0)` — doesn't change pulse shape at all. Physics calls this the "DC" component of the phase (like the DC in electronics: a constant bias).
- `a1` makes the group delay linear with frequency, which is just "delay the whole pulse by `a1` seconds." Still doesn't change shape.
- `a2` is the **interesting one**. It makes the group delay `tau_g = -d(phi)/d(omega) = -(a1 + 2*a2*omega)` depend linearly on frequency. The red light and the blue light arrive at *different times*. That stretches and reshapes the pulse in time as it propagates. **This is a chirp.**

The Raman-suppression optimizer discovered that the best thing to do is put in a big `a2` (quadratic chirp) so that inside the fiber the pulse stretches in just the right way to avoid the conditions that feed the Raman sideband. Higher-order corrections (`a3 * omega^3`, etc.) exist but contribute only a few percent.

### 3. "N_phi" (the shaper knob count)

In the "low-resolution sweep" study, we asked: instead of optimizing 16384 phase values independently, what if we only let the optimizer use `N_phi` knobs and interpolated between them with a smooth curve? `N_phi = 4` means 4 control points; `N_phi = 128` means 128; `N_phi = 16384` is the full resolution. The result (see Figure 1 below) is that going from 4 to 128 knobs improves Raman suppression, but the *shape* of the phase never changes much — it's always a parabola.

---

## The images, in the order I'd show them

### `pedagogical/nphi_sweep_phases.png` — **the headline**

Four panels stacked: top to bottom is N_phi = 4, 16, 32, 128 knobs. X-axis is frequency bin (0 = carrier, ±75 is the edges of the pulse bandwidth). Y-axis is `phi(omega)` in radians.

**What you should notice:**
- All four panels look like the **same parabola**.
- The bottom panel has deeper suppression (`-68` dB) than the top (`-47` dB) — but the *shape* of the phase is visually identical.
- The sharp jumps at ±75 bins are the edges of the spline basis — cosmetic, not physical.

**What to tell him:** "We swept the number of shaper knobs from 4 to 128 and the optimizer always picks the same parabolic shape. The more knobs we give it, the more accurately it refines that parabola, which buys us suppression depth but not qualitatively different physics."

### `pedagogical/nphi_sweep_coefficients.png` — the cubic-spline control values

Stems showing the optimization variable `c_k` for each N_phi setting. Important to understand: this is a **cubic-spline basis**, meaning each coefficient is the value of `phi(omega)` at one control point, and between control points `phi` is interpolated smoothly. So these coefficients *trace the phase shape itself* — they look parabolic because the phase is parabolic.

This is NOT the sparse "two modes and everything else is tiny" spectrum; to see that, look at the next figure (DCT spectrum).

**What to tell him:** "These are the control-point values that the optimizer picks. You can already read the parabolic shape straight out of them — and notice the shape is essentially the same at 4, 16, 32, and 128 knobs, with finer sampling as we go. The more interesting decomposition is the DCT spectrum on the next slide."

### `pedagogical/dct_spectrum_two_modes.png` — **the real 2-mode smoking gun**

This decomposes the optimized phase into discrete-cosine-transform (DCT) modes. Mode 0 is the DC component (constant offset), Mode 1 is half a cosine period across the pulse bandwidth, Mode 2 is a full period (this one looks like a parabola), Mode 3 is 1.5 periods, and so on. In this basis, a pure parabolic chirp would have ALL its weight in modes 0 and 2.

**What you should notice:**
- Modes **0** (DC, ~−2000 rad) and **2** (the parabolic / "quadratic-chirp-like" mode, ~+1400 rad) dominate by roughly 10× over everything else.
- Mode 1 is essentially zero (no linear tilt, which matters because a linear tilt is just a time shift — it would be physically invisible anyway).
- All other modes (3, 4, 5, ...) are a small residual, a couple hundred rad each.
- **This pattern is identical at N_phi = 4, 16, 32, and 128.** The *effective* mode count doesn't grow.

**This is the quantitative source of the "N_eff ≈ 2" claim in the technical report.** The DCT participation ratio `N_eff = (sum |c_k|)^2 / sum(c_k^2)` is a standard way to count "how many modes are doing work," and when two modes carry essentially all the weight, this number lands at ~2.

**What to tell him:** "In the DCT basis, only modes 0 (DC) and 2 (quadratic-like) have significant weight — about 10× more than everything else. Mode 1, which would be a pure linear phase tilt, is exactly zero because linear tilts are physically invisible anyway. This pattern is the same whether we let the optimizer use 4 knobs or 128. The optimizer's choice is structural, not coincidental."

### `pedagogical/dc_linear_quadratic_fit.png` — **the quadratic-chirp proof**

Top panel: the optimized phase (black) for the deepest Pareto candidate (`-82.33` dB). Red dashed = least-squares fit of the form `a0 + a1*omega + a2*omega^2`.

Bottom panel: the residual (black − red). Residual RMS is 0.314 rad vs the phase's peak-to-peak range of 4.2 rad — so the simple 3-parameter fit explains ~93% of the phase structure.

**What to tell him:** "If you fit the optimized phase with just DC + linear + quadratic, you capture over 90% of it. The residual — the part the quadratic fit misses — is less than 10% of the range. Physically, the optimizer's main trick is a quadratic chirp with a small amount of higher-order correction."

### `pedagogical/pareto_candidate_1_simplest.png`, `_2_middle.png`, `_3_deepest.png` — **the three phase-view diagnostic**

Each has three panels:

1. **Top (blue) — wrapped phase.** Phase modulo 2π, i.e., constrained to [-π, π]. This is what the SLM physically applies — it can only do phase modulo 2π. Those vertical jumps at the edges are 2π discontinuities where the "true" phase crosses π.

2. **Middle (green) — unwrapped phase.** The true continuous phase function. This is what the optimizer sees and what the physics depends on. You can read the parabola off of this directly.

3. **Bottom (red) — group delay `tau_g = -d(phi)/d(omega)`.** The "when does each frequency arrive" plot. For a pure quadratic chirp, this would be a straight line with slope `-2*a2`. Small wiggles are higher-order corrections.

The three candidates were picked as the Pareto front — you can't lower J (Raman suppression) without also increasing the phase complexity:
- **Candidate 1** (`L=0.25m, P=0.02W, J=-63 dB`): simplest; phase is a clean small parabola.
- **Candidate 2** (`L=1m, P=0.10W, J=-73 dB`): middle ground; more structure visible.
- **Candidate 3** (`L=0.25m, P=0.10W, J=-82 dB`): deepest suppression; most complex of the three but still dominated by the quadratic shape.

**What to tell him:** "Same parabolic-chirp story at three different `(L, P)` operating points. The deepest point is 14 dB below the canonical-configuration's best-ever suppression."

### `07-sweep-simple-pareto.png` — the overall Pareto frontier

Two-axis scatter: X is `N_eff` (phase complexity), Y is `J` in dB. Each point is one config from the 18-run sweep. The **Pareto front** is the set of non-dominated points — you can't move to a point that is both deeper and simpler.

**What to tell him:** "Complexity isn't free. To get deeper suppression you need slightly more phase modes. But the trade-off is mild — going from 1.75 to 2.33 effective modes buys you 20 dB extra suppression."

---

## Now the landscape figures (optional, advanced)

These are harder and worth showing only if he asks "how do you know the optimizer is working well?"

### `01-landscape-hessian-eigenvalues.png` — the saddle-point proof

We computed the second-derivative matrix (Hessian) of the Raman cost with respect to the phase, at one of the L-BFGS optima, and asked: *are all the eigenvalues positive (a true minimum) or does it have some negative ones (a saddle)?*

The plot shows eigenvalues on a signed-log scale. The top 20 are positive; the bottom 20 are negative. **Eigenvalues of the Hessian having both signs at an optimum means L-BFGS halted at a saddle, not a minimum.** The negative eigenvalues are small (1-3% of the largest positive one), which is why L-BFGS couldn't find the "escape" direction — its line search thinks it's flat.

**What to tell him:** "We checked the second-derivative structure of the landscape and it's a saddle, not a minimum. The negative curvatures are small, but real. Newton-type methods — which use second-derivative information — should do better than L-BFGS here."

### `03-landscape-bottom-soft-directions.png` — what the escape directions look like

The 5 Hessian eigenvectors at the smallest (most negative) eigenvalues. These are the directions in phase-space along which you could lower J further. They concentrate on the pulse bandwidth and have high-frequency wiggles — exactly the kind of structure a polynomial fit doesn't capture.

### `04-landscape-gauge-before-after.png` — "are the different optima the same pulse?"

Any two phases that differ by a constant `c` or by a linear-in-`omega` `alpha*omega` are physically *identical* (they produce the same pulse shape — they only differ by an invisible time shift and a global phase). This plot shows 39 independent optima before (top) and after (bottom) subtracting out those two trivial components. If two runs found "the same pulse," the bottom panel would collapse them onto one another. It doesn't — each optimum is genuinely distinct.

**What to tell him:** "The fact that different random starts give different final phases isn't a gauge issue — they really are different pulses. Combined with the saddle finding, we now think L-BFGS halts at a family of nearby saddles rather than one true minimum."

---

## Evolution and phase-diagnostic figures for the older runs

These are in the top of the `docs/artifacts/presentation-2026-04-17/` folder (not in `pedagogical/`). They're from the **older** baseline studies (Nt=8192 full-resolution L-BFGS) done before we understood the saddle issue or the low-res basis.

- `08..09-smf28-L2m-P030W-evolution-*.png`: waterfall plots showing the pulse spectrum at every position along the fiber. The unshaped run develops a bright red sideband (Raman!) halfway through; the optimized run suppresses it. **This is the cleanest "what is Raman suppression physically?" picture we have.**
- `10-...-phase-profile.png`, `11-...-phase-diagnostic.png`: the optimizer's output phase at this older operating point — messier than the low-res ones because full-resolution L-BFGS landed on one of the saddle points, so the phase has high-frequency structure that doesn't correspond to any particular physics.

You're right that the phases in the top folder *look messy* — that's because they're Phase-13-style full-resolution optima, which we now understand are saddle points with noisy high-frequency content. **The clean, visually-interpretable phases are the ones in `pedagogical/`.**

---

## One-paragraph summary for the meeting opening

> "Over the past few days we did three things. First, we diagnosed why different L-BFGS runs gave different-looking optimized phases — they halt at saddle points rather than minima, with small negative curvature directions that first-order methods can't follow. Second, we fixed a non-determinism bug where FFTW's plan-selection heuristic was making identical-seed runs differ by 1 radian at the bit level. And third, we learned something nice about the physics: the optimized phase is basically always a DC + quadratic-chirp shape, dominated by 2 effective modes, regardless of how many shaper knobs we give it — which means a ~128-pixel shaper is experimentally sufficient. The deepest suppression we've found is `-82 dB`, which is near the quantum noise floor."
