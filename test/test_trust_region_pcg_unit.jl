# test/test_trust_region_pcg_unit.jl — Phase 34 Plan 02 Task 3.
#
# Analytic-quadratic unit tests for PreconditionedCGSolver.
# No ODE, no Raman oracle — integration tests land in Plan 03.
#
# Run:  julia --project=. test/test_trust_region_pcg_unit.jl
#
# Test suite covers:
#   1. :none fallback parity with SteihaugSolver (tolerance 1e-8)
#   2. SubproblemResult contract (‖p‖₂ ≤ Δ·(1+1e-8), pred_reduction ≥ 0)
#   3. Diagonal preconditioner reduces CG iterations on ill-conditioned SPD
#   4. Indefinite H → :NEGATIVE_CURVATURE exit, step on boundary
#   5. Zero-norm gradient → :NO_DESCENT with 0 HVPs (H_op never called)

using Test
using LinearAlgebra

include(joinpath(@__DIR__, "..", "scripts", "research", "trust_region", "trust_region_pcg.jl"))
# trust_region_core.jl is brought in transitively via trust_region_pcg.jl.

# ─────────────────────────────────────────────────────────────────────────────
@testset "Phase 34 Plan 02 — PreconditionedCGSolver" begin

    @testset ":none parity with SteihaugSolver on SPD diagonal H" begin
        # H = diag(1, 4, 9, 16, 25); g random; Δ large → interior Newton step
        n = 5
        H = Diagonal([1.0, 4.0, 9.0, 16.0, 25.0])
        H_op = v -> H * v
        g = [1.0, -1.0, 1.0, -1.0, 1.0]
        Δ = 10.0

        steih  = SteihaugSolver(max_iter = 50, tol_forcing = _ -> 1e-12)
        pcg_none = PreconditionedCGSolver(
            preconditioner = :none,
            max_iter       = 50,
            tol_forcing    = _ -> 1e-12
        )

        res_s = solve_subproblem(steih,    g, H_op, Δ)
        res_p = solve_subproblem(pcg_none, g, H_op, Δ; M = nothing)

        # Steps must agree to 1e-8 (Euclidean norm)
        @test norm(res_s.p - res_p.p) < 1e-8
        # Both should converge interior on big Δ + SPD
        @test res_s.exit_code == :INTERIOR_CONVERGED
        @test res_p.exit_code == :INTERIOR_CONVERGED
        # Predicted reductions should agree (both Euclidean)
        @test abs(res_s.pred_reduction - res_p.pred_reduction) < 1e-6
    end

    @testset ":none parity — tighter SPD, boundary-hit case" begin
        # Δ small enough to force boundary hit
        n = 4
        H = Diagonal([1.0, 4.0, 9.0, 16.0])
        H_op = v -> H * v
        g = [2.0, 2.0, 2.0, 2.0]
        Δ = 0.1   # Newton step ≈ [2, 0.5, 0.22, 0.125] has ‖p*‖ > 0.1

        steih    = SteihaugSolver(max_iter = 50)
        pcg_none = PreconditionedCGSolver(preconditioner = :none, max_iter = 50)

        res_s = solve_subproblem(steih,    g, H_op, Δ)
        res_p = solve_subproblem(pcg_none, g, H_op, Δ; M = nothing)

        @test norm(res_s.p - res_p.p) < 1e-8
        @test norm(res_p.p) <= Δ * (1 + 1e-8)
        @test res_p.pred_reduction >= 0.0
    end

    @testset "SubproblemResult contract: ‖p‖₂ ≤ Δ·(1+1e-8) and pred_reduction ≥ 0" begin
        n = 8
        H    = Diagonal(Float64[1, 2, 3, 4, 5, 6, 7, 8])
        H_op = v -> H * v

        for (seed, Δ) in enumerate([0.1, 1.0, 10.0])
            g = Float64.((-1) .^ (1:n))   # alternating signs, deterministic
            pcg = PreconditionedCGSolver(preconditioner = :none)
            res = solve_subproblem(pcg, g, H_op, Δ; M = nothing)

            @test norm(res.p) <= Δ * (1 + 1e-8)
            @test res.pred_reduction >= 0.0
            @test res.hvps_used >= 1
            @test res.inner_iters >= 1
            @test res.exit_code in (:INTERIOR_CONVERGED, :BOUNDARY_HIT, :NEGATIVE_CURVATURE, :MAX_ITER)
        end
    end

    @testset "Diagonal preconditioner reduces iterations on ill-conditioned SPD" begin
        n = 8
        # H = diag(1, 100, 1, 100, ...): condition number = 100
        # Exact preconditioner M = H → PCG with M converges in 1 CG iter
        diag_H = Float64[1, 100, 1, 100, 1, 100, 1, 100]
        H      = Diagonal(diag_H)
        H_op   = v -> H * v
        g      = ones(Float64, n)
        Δ      = 100.0   # large Δ so interior convergence is reached

        M_exact = v -> v ./ diag_H   # exact inverse of H = M⁻¹

        steih    = SteihaugSolver(max_iter = 50)
        pcg_diag = PreconditionedCGSolver(preconditioner = :diagonal, max_iter = 50)

        res_s = solve_subproblem(steih,    g, H_op, Δ)
        res_p = solve_subproblem(pcg_diag, g, H_op, Δ; M = M_exact)

        # PCG with exact M = H should converge in ≤ 1 CG iteration
        @test res_p.inner_iters <= res_s.inner_iters
        @test res_p.inner_iters <= 2   # 1 CG step + 1 pred_reduction HVP

        # Both satisfy the SubproblemResult contract
        @test norm(res_p.p) <= Δ * (1 + 1e-8)
        @test res_p.pred_reduction >= 0.0
    end

    @testset "Diagonal preconditioner step quality on ill-conditioned SPD" begin
        # Verify the PCG step is at least as good as Steihaug in terms of model decrease
        n = 6
        diag_H = Float64[1, 50, 1, 50, 1, 50]
        H      = Diagonal(diag_H)
        H_op   = v -> H * v
        g      = ones(Float64, n)
        Δ      = 5.0

        M_exact = v -> v ./ diag_H

        steih    = SteihaugSolver(max_iter = 50)
        pcg_diag = PreconditionedCGSolver(preconditioner = :diagonal, max_iter = 50)

        res_s = solve_subproblem(steih,    g, H_op, Δ)
        res_p = solve_subproblem(pcg_diag, g, H_op, Δ; M = M_exact)

        # Both must satisfy basic contract
        @test norm(res_p.p) <= Δ * (1 + 1e-8)
        @test res_p.pred_reduction >= 0.0
        # PCG with exact preconditioner should give ≥ as much model reduction
        @test res_p.pred_reduction >= res_s.pred_reduction - 1e-6
    end

    @testset "Indefinite H → :NEGATIVE_CURVATURE exit at Δ-boundary" begin
        n = 4
        # H = diag(1, -1, 1, -1): indefinite, first search direction d = -g
        # hits negative curvature on the first H_op call
        H    = Diagonal(Float64[1, -1, 1, -1])
        H_op = v -> H * v
        g    = Float64[1, 1, 1, 1]
        Δ    = 1.0

        pcg = PreconditionedCGSolver(preconditioner = :none)
        res = solve_subproblem(pcg, g, H_op, Δ; M = nothing)

        @test res.exit_code === :NEGATIVE_CURVATURE
        @test norm(res.p) <= Δ * (1 + 1e-8)
        @test res.pred_reduction >= 0.0
        # inner_iters = 1 (exits immediately on first negative κ)
        @test res.inner_iters >= 1
    end

    @testset "Indefinite H — preconditioner :none parity with Steihaug on negative-curvature" begin
        n = 4
        H    = Diagonal(Float64[1, -1, 1, -1])
        H_op = v -> H * v
        g    = Float64[1, 1, 1, 1]
        Δ    = 1.0

        steih    = SteihaugSolver(max_iter = 50)
        pcg_none = PreconditionedCGSolver(preconditioner = :none, max_iter = 50)

        res_s = solve_subproblem(steih,    g, H_op, Δ)
        res_p = solve_subproblem(pcg_none, g, H_op, Δ; M = nothing)

        # Both should see negative curvature
        @test res_s.exit_code === :NEGATIVE_CURVATURE
        @test res_p.exit_code === :NEGATIVE_CURVATURE
        # Steps should agree (same first search direction d = -g)
        @test norm(res_s.p - res_p.p) < 1e-8
    end

    @testset "Zero-norm gradient → :NO_DESCENT with 0 HVPs (H_op not called)" begin
        n = 4
        H    = Diagonal(Float64[1, 2, 3, 4])
        # Use an H_op that errors if called — proves zero HVPs consumed
        H_op = v -> error("H_op must NOT be called when ‖g‖ < eps()")
        g    = zeros(Float64, n)

        pcg = PreconditionedCGSolver(preconditioner = :none)
        res = solve_subproblem(pcg, g, H_op, 1.0; M = nothing)

        @test res.exit_code === :NO_DESCENT
        @test res.hvps_used == 0
        @test res.inner_iters == 0
        @test res.pred_reduction == 0.0
        @test all(res.p .== 0.0)
    end

    @testset "hvps_used ≥ inner_iters + 1 (one final pred_reduction HVP)" begin
        # On a normal exit (not :NO_DESCENT), hvps_used = inner_iters + 1
        n = 5
        H    = Diagonal([1.0, 4.0, 9.0, 16.0, 25.0])
        H_op = v -> H * v
        g    = ones(Float64, n)
        Δ    = 0.5   # force boundary hit

        pcg = PreconditionedCGSolver(preconditioner = :none, max_iter = 50)
        res = solve_subproblem(pcg, g, H_op, Δ; M = nothing)

        @test res.hvps_used >= res.inner_iters + 1
    end

    @testset "dispersion preconditioner satisfies SubproblemResult contract" begin
        n = 8
        H    = Diagonal(Float64[1, 2, 3, 4, 5, 6, 7, 8])
        H_op = v -> H * v
        g    = ones(Float64, n)
        Δ    = 2.0
        ωs   = collect(range(-4.0, 3.5, length = n))
        sim  = Dict{String,Any}("Nt" => n, "M" => 1, "ωs" => ωs)
        M_disp = build_dispersion_precond(sim)

        pcg = PreconditionedCGSolver(preconditioner = :dispersion, max_iter = 50)
        res = solve_subproblem(pcg, g, H_op, Δ; M = M_disp)

        @test norm(res.p) <= Δ * (1 + 1e-8)
        @test res.pred_reduction >= 0.0
        @test res.hvps_used >= 1
        @test res.exit_code in (:INTERIOR_CONVERGED, :BOUNDARY_HIT, :NEGATIVE_CURVATURE, :MAX_ITER)
    end

    @testset "projection hook removes preconditioner-induced gauge leak" begin
        n = 6
        H = Diagonal(fill(2.0, n))
        H_op = v -> H * v
        g = [-1.0, 0.0, 1.0, -1.0, 0.0, 1.0]  # mean-zero
        Δ = 1.0

        # Deliberately inject a constant-shift leak through the preconditioner.
        M_leaky = v -> collect(v .+ 3.0)
        proj_mean_zero = v -> begin
            w = collect(Float64.(v))
            return w .- mean(w)
        end

        pcg = PreconditionedCGSolver(preconditioner = :diagonal, max_iter = 20)
        res = solve_subproblem(pcg, g, H_op, Δ; M = M_leaky, proj = proj_mean_zero)

        @test abs(mean(res.p)) <= 1e-10
        @test norm(res.p) <= Δ * (1 + 1e-8)
        @test res.pred_reduction >= 0.0
        @test res.exit_code in (:INTERIOR_CONVERGED, :BOUNDARY_HIT, :NEGATIVE_CURVATURE, :MAX_ITER)
    end

end  # testset
