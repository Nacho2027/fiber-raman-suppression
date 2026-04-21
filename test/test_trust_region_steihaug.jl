# ═══════════════════════════════════════════════════════════════════════════════
# Phase 33 Plan 01 Task 1 — Steihaug solver + DirectionSolver trait + radius update
# ═══════════════════════════════════════════════════════════════════════════════
#
# Run:  julia --project=. test/test_trust_region_steihaug.jl
#
# These are analytic-quadratic unit tests. No ODE solves, no FFTs; they verify
# the inner-CG arithmetic, boundary-crossing quadratic root, negative-curvature
# detection, and the Nocedal-Wright §4.1 radius update rule.
#
# Every assertion has an exactly-known answer (2x2 matrices, closed-form
# Newton steps). Tolerances are 1e-10 where analytic.
# ═══════════════════════════════════════════════════════════════════════════════

using Test
using LinearAlgebra
using Printf

include(joinpath(@__DIR__, "..", "scripts", "trust_region_core.jl"))

# ─────────────────────────────────────────────────────────────────────────────
# Small helper: wrap a dense symmetric matrix as an H_op closure
# ─────────────────────────────────────────────────────────────────────────────
make_H_op(H::AbstractMatrix) = v -> H * v

@testset "Phase 33 Plan 01 — Steihaug solver" begin

    @testset "Steihaug: SPD 2x2 interior Newton step" begin
        H = [2.0 0.0; 0.0 4.0]
        g = [1.0, 1.0]
        Δ = 10.0   # large enough that the full Newton step is interior
        # Use a tighter forcing tolerance so CG runs to the true Newton step,
        # not to the superlinear-local early-exit point. The default forcing
        # `min(0.5, √‖g‖)·‖g‖` is right for the outer loop but too loose for
        # a unit test that wants the analytic Newton step to 1e-10.
        solver = SteihaugSolver(; max_iter = 50, tol_forcing = g -> 1e-12)
        result = solve_subproblem(solver, g, make_H_op(H), Δ)
        # Analytic Newton step: p* = -H⁻¹ g = [-0.5, -0.25]
        @test result.exit_code == :INTERIOR_CONVERGED
        @test isapprox(result.p, [-0.5, -0.25]; atol = 1e-10)
        # m(p*) = g'p* + 0.5 p*'H p* = -0.75 + 0.5·(2·0.25 + 4·0.0625)
        #       = -0.75 + 0.375 = -0.375
        # pred_reduction = -m(p*) = 0.5·g'H⁻¹g = 0.5·(1/2 + 1/4) = 0.375
        @test isapprox(result.pred_reduction, 0.375; atol = 1e-10)
        @test result.pred_reduction >= 0
        @test result.inner_iters >= 1
        @test result.hvps_used >= 1
        @test norm(result.p) <= Δ * (1 + 1e-8)

        # Default-forcing variant: CG exits early (superlinear forcing), but
        # every returned quantity must still be valid and reduce the model.
        solver_default = SteihaugSolver()
        result_d = solve_subproblem(solver_default, g, make_H_op(H), Δ)
        @test result_d.exit_code == :INTERIOR_CONVERGED
        @test result_d.pred_reduction > 0
        @test result_d.pred_reduction <= 0.375 + 1e-10   # ≤ true Newton decrease
        @test norm(result_d.p) <= Δ * (1 + 1e-8)
    end

    @testset "Steihaug: SPD 2x2 trust-region boundary" begin
        H = [2.0 0.0; 0.0 4.0]
        g = [1.0, 1.0]
        Δ = 0.1    # tight radius: Newton step (norm ≈ 0.559) does not fit
        solver = SteihaugSolver()
        result = solve_subproblem(solver, g, make_H_op(H), Δ)
        @test result.exit_code == :BOUNDARY_HIT
        @test isapprox(norm(result.p), Δ; atol = 1e-10)
        @test result.pred_reduction >= 0
        @test norm(result.p) <= Δ * (1 + 1e-8)
    end

    @testset "Steihaug: indefinite 2x2 negative curvature" begin
        H = [1.0 0.0; 0.0 -1.0]
        g = [0.1, 0.0]
        Δ = 1.0
        solver = SteihaugSolver()
        result = solve_subproblem(solver, g, make_H_op(H), Δ)
        # First inner step: d = -g = [-0.1, 0]; d'Hd = 1·0.01 = 0.01 > 0 → CG accepts.
        # α = (r'r)/(d'Hd) = 0.01/0.01 = 1; p_new = [-0.1, 0], norm=0.1 < Δ.
        # r_new = r + α Hd = [0.1,0] + [-0.1, 0] = [0, 0]. ‖r_new‖=0 ≤ ε → INTERIOR_CONVERGED.
        # That exits the 1-D x direction. So this particular (g, Δ) converges in x.
        # But the problem in x is convex with minimizer at p=[-0.1,0]. Fine — a fresh
        # restart with a gradient pointing into the unstable direction reveals neg-curv:
        g2 = [0.0, 0.1]
        result2 = solve_subproblem(solver, g2, make_H_op(H), Δ)
        # With g2 = [0, 0.1]: d = [0, -0.1]; Hd = [0, 0.1]; d'Hd = -0.01 ≤ 0 → neg-curv on FIRST iter.
        @test result2.exit_code == :NEGATIVE_CURVATURE
        @test isapprox(norm(result2.p), Δ; atol = 1e-10)
        @test result2.pred_reduction >= 0.0
        @test norm(result2.p) <= Δ * (1 + 1e-8)

        # Mixed-gradient test: exit code must be one of {BOUNDARY_HIT, NEGATIVE_CURVATURE};
        # either way step is on boundary and reduces the model.
        g3 = [0.1, 0.1]
        result3 = solve_subproblem(solver, g3, make_H_op(H), Δ)
        @test result3.exit_code in (:BOUNDARY_HIT, :NEGATIVE_CURVATURE)
        @test isapprox(norm(result3.p), Δ; atol = 1e-8)
        @test result3.pred_reduction >= 0.0
    end

    @testset "Steihaug: zero gradient degenerate" begin
        H = [2.0 0.0; 0.0 4.0]
        g = zeros(2)
        Δ = 1.0
        solver = SteihaugSolver()
        result = solve_subproblem(solver, g, make_H_op(H), Δ)
        @test result.exit_code == :NO_DESCENT
        @test isapprox(result.p, zeros(2); atol = 0)
        @test result.pred_reduction == 0.0
        @test result.inner_iters == 0
        @test result.hvps_used == 0
    end

    @testset "Steihaug: gauge-like pure-null H (d'Hd≈0) stays bounded" begin
        # H returns essentially zero — mimics a gauge-only curvature response
        # that leaks past the outer projection. Steihaug must treat this as
        # either ill-conditioned positive curvature (BOUNDARY_HIT once CG's
        # un-damped step exceeds Δ) or negative curvature (step to boundary
        # along -g). Both end up on the trust boundary with p = -Δ·ĝ; both
        # give the same pred_reduction ≈ ‖g‖·Δ. What we ABSOLUTELY forbid is
        # ‖p‖ > Δ (the failure mode described in P1).
        g = [1.0, 2.0]
        Δ = 0.5
        solver = SteihaugSolver()

        # Truly zero H: d'Hd = 0 → NEGATIVE_CURVATURE branch.
        H_op_zero = v -> zeros(length(v))
        result_zero = solve_subproblem(solver, g, H_op_zero, Δ)
        @test result_zero.exit_code == :NEGATIVE_CURVATURE
        @test isapprox(norm(result_zero.p), Δ; atol = 1e-10)
        @test result_zero.pred_reduction >= 0.0
        @test isapprox(result_zero.pred_reduction, norm(g) * Δ; atol = 1e-10)

        # Tiny-positive H: d'Hd > 0 but CG step wildly exceeds Δ → BOUNDARY_HIT.
        H_op_tiny = v -> 1e-20 .* v
        result_tiny = solve_subproblem(solver, g, H_op_tiny, Δ)
        @test result_tiny.exit_code in (:BOUNDARY_HIT, :NEGATIVE_CURVATURE)
        @test norm(result_tiny.p) <= Δ * (1 + 1e-8)
        @test isapprox(norm(result_tiny.p), Δ; atol = 1e-6)
        @test result_tiny.pred_reduction >= 0.0
    end

    @testset "Radius update: Nocedal-Wright Algorithm 4.1 table" begin
        # Defaults: η₁=0.25, η₂=0.75, γ_shrink=0.25, γ_grow=2.0, Δ_max=10.0
        Δ_max = 10.0
        # Iter 1: Δ=1.0, ρ=0.1 (< η₁) → Δ_next = γ_shrink * step_norm = 0.25 * 0.8 = 0.2
        Δ1 = update_radius(1.0, 0.1, 0.8, Δ_max)
        @test isapprox(Δ1, 0.25 * 0.8; atol = 1e-14)
        # Iter 2: Δ=0.2, ρ=0.5 (between η₁ and η₂) → Δ_next = Δ unchanged = 0.2
        Δ2 = update_radius(0.2, 0.5, 0.18, Δ_max)
        @test isapprox(Δ2, 0.2; atol = 1e-14)
        # Iter 3: Δ=0.2, ρ=0.9 (> η₂), step on boundary (0.19 >= 0.9*0.2=0.18) → grow → min(2·0.2, 10) = 0.4
        Δ3 = update_radius(0.2, 0.9, 0.19, Δ_max)
        @test isapprox(Δ3, 0.4; atol = 1e-14)
        # Iter 4: Δ=0.4, ρ=-0.3 (< η₁) → shrink → 0.25 * step_norm = 0.25 * 0.1 = 0.025
        Δ4 = update_radius(0.4, -0.3, 0.1, Δ_max)
        @test isapprox(Δ4, 0.25 * 0.1; atol = 1e-14)
        # Iter 5: Δ=0.025, ρ=1.2 (> η₂), step on boundary (0.024 >= 0.9*0.025=0.0225) → grow → min(2·0.025, 10) = 0.05
        Δ5 = update_radius(0.025, 1.2, 0.024, Δ_max)
        @test isapprox(Δ5, 0.05; atol = 1e-14)
        # Iter 6: Δ=6.0, ρ=0.9 (> η₂), step on boundary → grow but capped at Δ_max = 10.0
        Δ6 = update_radius(6.0, 0.9, 5.5, Δ_max)
        @test isapprox(Δ6, 10.0; atol = 1e-14)
        # Iter 7: Δ=1.0, ρ=0.9 (> η₂), step NOT on boundary (0.5 < 0.9*1.0=0.9) → Δ unchanged
        Δ7 = update_radius(1.0, 0.9, 0.5, Δ_max)
        @test isapprox(Δ7, 1.0; atol = 1e-14)
    end

    @testset "TRExitCode enum: all 7 typed codes present" begin
        @test Int(CONVERGED_2ND_ORDER) isa Int
        @test Int(CONVERGED_1ST_ORDER_SADDLE) isa Int
        @test Int(RADIUS_COLLAPSE) isa Int
        @test Int(MAX_ITER) isa Int
        @test Int(MAX_ITER_STALLED) isa Int
        @test Int(NAN_IN_OBJECTIVE) isa Int
        @test Int(GAUGE_LEAK) isa Int
        # All distinct
        codes = [CONVERGED_2ND_ORDER, CONVERGED_1ST_ORDER_SADDLE, RADIUS_COLLAPSE,
                 MAX_ITER, MAX_ITER_STALLED, NAN_IN_OBJECTIVE, GAUGE_LEAK]
        @test length(unique(codes)) == 7
    end

    @testset "DirectionSolver trait is abstract and subtyped by SteihaugSolver" begin
        @test DirectionSolver isa Type
        @test SteihaugSolver <: DirectionSolver
        s = SteihaugSolver()
        @test s isa DirectionSolver
        @test s.max_iter == 20
        # tol_forcing is callable
        @test s.tol_forcing([1.0, 0.0]) >= 0
    end

    @testset "SubproblemResult struct shape" begin
        # Fabricate a minimal result and verify fields
        r = SubproblemResult([0.1, -0.2], 0.05, :INTERIOR_CONVERGED, 3, 3)
        @test r.p == [0.1, -0.2]
        @test r.pred_reduction == 0.05
        @test r.exit_code == :INTERIOR_CONVERGED
        @test r.inner_iters == 3
        @test r.hvps_used == 3
    end

end

println("\nAll Steihaug / radius-update unit tests passed.")
