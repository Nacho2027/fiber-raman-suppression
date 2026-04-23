# ═══════════════════════════════════════════════════════════════════════════════
# test/tier_full.jl — Phase 16 full tier (~20 min, BURST VM)
# ═══════════════════════════════════════════════════════════════════════════════
# Run on the burst VM. Includes everything in the slow tier plus:
#   - Same-process determinism bit-identity (Phase 15).
#   - Cross-process bit-identity — spawn 2 fresh Julia subprocesses with the
#     same seed and assert phi_opt_a == phi_opt_b, J_final == J_final.
#   - Phase 14 regression + sharpness tests.
#
# Reserve for milestone / release tags.
# ═══════════════════════════════════════════════════════════════════════════════

using Test

const _ROOT = normpath(joinpath(@__DIR__, ".."))

@testset "Phase 16 — full tier" begin

    # 1. Everything in the slow tier.
    @testset "Slow tier (rerun)" begin
        include(joinpath(_ROOT, "test", "tier_slow.jl"))
    end

    # 2. Phase 15 single-process bit-identity.
    @testset "Phase 15 determinism (same process)" begin
        include(joinpath(_ROOT, "test", "core", "test_determinism.jl"))
    end

    # 3. Phase 14 regression + sharpness.
    @testset "Phase 14 regression" begin
        include(joinpath(_ROOT, "test", "phases", "test_phase14_regression.jl"))
    end
    @testset "Phase 14 sharpness" begin
        include(joinpath(_ROOT, "test", "phases", "test_phase14_sharpness.jl"))
    end

    # 4. Cross-process bit identity — spawn two fresh Julia subprocesses
    #    with the same seed and compare output.
    @testset "Cross-process bit-identity (Phase 15)" begin
        # Minimal script printed to a tempfile, then run twice with identical args.
        mktempdir() do dir
            script_path = joinpath(dir, "xproc.jl")
            open(script_path, "w") do io
                println(io, """
                using Random, Optim
                const _ROOT = "$_ROOT"
                include(joinpath(_ROOT, "scripts", "lib", "determinism.jl"))
                ensure_deterministic_environment()
                include(joinpath(_ROOT, "scripts", "lib", "common.jl"))
                include(joinpath(_ROOT, "scripts", "lib", "raman_optimization.jl"))
                Random.seed!(42)
                uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(;
                    fiber_preset=:SMF28, Nt=2^10, time_window=10.0,
                    L_fiber=0.5, P_cont=0.05, β_order=3)
                φ0 = zeros(sim["Nt"], sim["M"])
                result = optimize_spectral_phase(uω0, fiber, sim, band_mask;
                    φ0=φ0, max_iter=5, store_trace=true, log_cost=true)
                phi_opt = Optim.minimizer(result)
                open(ARGS[1], "w") do f
                    for x in phi_opt
                        println(f, x)
                    end
                end
                """)
            end
            out_a = joinpath(dir, "phi_a.txt")
            out_b = joinpath(dir, "phi_b.txt")
            julia = Base.julia_cmd()
            run(`$julia --project=$_ROOT $script_path $out_a`)
            run(`$julia --project=$_ROOT $script_path $out_b`)
            a = readlines(out_a)
            b = readlines(out_b)
            @test a == b
        end
    end

end
