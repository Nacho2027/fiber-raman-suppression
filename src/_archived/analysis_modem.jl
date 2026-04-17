# ═══════════════════════════════════════════════════════════════════════════════
# ARCHIVED — src/_archived/analysis_modem.jl
# ═══════════════════════════════════════════════════════════════════════════════
#
# Original location : src/analysis/analysis.jl
# Archived          : Phase 16 (Session B — Repo Polish for Team Handoff)
#
# Status            : BROKEN. This function will error at runtime:
#                     - The first `@tullio` on line 2 of the body is empty
#                       (no expression), triggering a macro-expansion failure.
#                     - `Xkkkk` and `no_derivative_term` are referenced before
#                       they are defined; the subsequent `@tullio Xkkkk := ...`
#                       appears after the first use.
#                     - `excess_noise` is used in the first `var_X` assignment
#                       before being defined further down.
#
# Original intent   : MMF (multimode fiber) mode-decomposition noise-map variant
#                     of `compute_noise_map` and `compute_noise_map_modek`. In
#                     the planned decomposition, the measurement X is projected
#                     onto a single spatial mode `m` (hence `modem`) rather than
#                     a mode pair `(k, l)` or a single mode `k`. The structure
#                     suggests an in-progress refactor that was never finished.
#                     Belongs to Michael Horodynski's original MMF quantum-noise
#                     work (pre-Raman-suppression era of this repository).
#
# Why archived      : Deleting it loses the skeleton + comments that document
#                     the original intent. A future multimode noise milestone
#                     may want to resurrect it (see "Resurrection protocol" in
#                     src/_archived/README.md). Fixing it correctly requires
#                     reconstructing the MMF mode-decomposition math, which is
#                     out of scope for a handoff polish phase.
#
# DO NOT `include` THIS FILE from `src/MultiModeNoise.jl`.
# ═══════════════════════════════════════════════════════════════════════════════

function compute_noise_map_modem(X, ∂Xmm∂u, U, ϕ, δF_in_ω)
    @tullio
    @tullio shot_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * Xkkkk # shot noise for only one mode as well?
    var_X = real.(shot_noise + excess_noise)

    @tullio Xkkkk := conj(∂Xmm∂u[ω,j]) * ∂Xmm∂u[ω,j]
    @tullio ∂Xmm∂u_U[ω] := ∂Xmm∂u[ω,j] * U[j]
    @tullio XUkkkk := δF_in_ω[ω] * conj(∂Xmm∂u_U[ω]) * ∂Xmm∂u_U[ω]
    @tullio excess_noise[i] := ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * ϕ[i,k] * XUkkkk
    var_X = real.(no_derivative_term + shot_noise + excess_noise)
    return var_X
end
