using Test
using LinearAlgebra

const _ADJOINT_CONTRACT_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :ReducedPhaseControlMap)
    using MultiModeNoise
    include(joinpath(_ADJOINT_CONTRACT_ROOT, "scripts", "lib", "adjoint_contracts.jl"))
end
if !isdefined(Main, :load_experiment_spec)
    include(joinpath(_ADJOINT_CONTRACT_ROOT, "scripts", "lib", "experiment_spec.jl"))
end

@testset "Adjoint control-map and objective contracts" begin
    @testset "FieldObjective exposes terminal adjoint contract" begin
        Nt = 32
        uωf = ComplexF64.(reshape(
            [exp(-0.03 * (i - 16)^2) * cis(0.1 * i) for i in 1:Nt],
            Nt,
            1,
        ))
        band_mask = falses(Nt)
        band_mask[23:28] .= true
        sim = Dict{String,Any}("Nt" => Nt, "M" => 1, "Δt" => 0.05)
        context = (band_mask=band_mask, sim=sim)

        for kind in (:raman_band, :raman_peak, :temporal_width)
            objective = FieldObjective(kind)
            J, λωL = evaluate_objective(objective, uωf, context)
            @test isfinite(J)
            @test size(λωL) == size(uωf)
            @test terminal_adjoint(objective, uωf, context) == λωL

            idx = kind == :raman_peak ? 24 : 16
            ε = 1e-6
            perturb = zeros(ComplexF64, size(uωf))
            perturb[idx, 1] = 1.0 + 0.25im
            Jp, _ = evaluate_objective(objective, uωf .+ ε .* perturb, context)
            Jm, _ = evaluate_objective(objective, uωf .- ε .* perturb, context)
            fd = (Jp - Jm) / (2ε)
            adj = 2 * real(conj(λωL[idx, 1]) * perturb[idx, 1])
            @test adj ≈ fd rtol=1e-4 atol=1e-7
        end

        @test_throws ArgumentError FieldObjective(:unknown_metric)
    end

    @testset "Custom adjoint objectives are finite-difference checkable" begin
        Nt = 24
        uωf = ComplexF64.(reshape(
            [exp(-0.04 * (i - 12)^2) * cis(0.07 * i) for i in 1:Nt],
            Nt,
            1,
        ))
        weights = reshape(collect(range(0.25, 1.0, length=Nt)), Nt, 1)
        objective = CustomFieldObjective(:weighted_output_energy, function (field, context)
            w = context.weights
            J = sum(w .* abs2.(field))
            λωL = w .* field
            return J, λωL
        end)

        report = check_terminal_adjoint(
            objective,
            uωf,
            (weights=weights,),
            indices=(CartesianIndex(3, 1), CartesianIndex(12, 1), CartesianIndex(21, 1)),
        )

        @test report.kind == :weighted_output_energy
        @test report.pass
        @test isfinite(report.cost)
        @test length(report.rows) == 6
        @test all(row -> row.rel_error < 1e-6 || row.abs_error < 1e-8, report.rows)

        io = IOBuffer()
        render_adjoint_contract_check_report(report; io=io)
        rendered = String(take!(io))
        @test occursin("Objective weighted_output_energy Check", rendered)
        @test occursin("PASS", rendered)

        bad_shape = CustomFieldObjective(:bad_shape, function (field, context)
            return 0.0, zeros(ComplexF64, size(field, 1))
        end)
        @test_throws ArgumentError evaluate_objective(bad_shape, uωf, (;))

        bad_cost = CustomFieldObjective(:bad_cost, function (field, context)
            return Inf, zero(field)
        end)
        @test_throws ArgumentError evaluate_objective(bad_cost, uωf, (;))
    end

    @testset "Reduced phase is a front-layer adjoint variable" begin
        @test :reduced_phase in registered_variable_kinds(:single_mode)
        contract = variable_contract(:reduced_phase, :single_mode)
        @test contract.backend == :spectral_reduced_phase
        @test :basis_coefficients in contract.parameterizations
        @test (:reduced_phase,) in objective_contract(:raman_band, :single_mode).supported_variables

        spec = load_experiment_spec("research_engine_reduced_phase_adjoint_smoke")
        @test spec.controls.variables == (:reduced_phase,)
        @test spec.controls.parameterization == :basis_coefficients
        @test spec.solver.kind == :lbfgs
        @test experiment_execution_mode(spec) == :reduced_phase
        @test validate_experiment_spec(spec) isa NamedTuple

        layout = control_layout_plan(spec)
        @test layout.total_length == "2"
        block = only(filter(block -> block.name == :reduced_phase, layout.blocks))
        @test block.shape == "vector[2]"
    end

    @testset "Reduced phase control map builds physical phase" begin
        control = ReducedPhaseControlMap(orders=(2, 3, 4))
        sim = Dict{String,Any}("Nt" => 32, "M" => 1, "Δt" => 0.05)
        context = (sim=sim, Nt=32, M=1)
        built = build_control(control, [1.0, -0.5, 0.25], context)

        @test size(built.phase) == (32, 1)
        @test built.amplitude == ones(32, 1)
        @test built.optimizer_values == [1.0, -0.5, 0.25]
        @test built.scalar_controls["reduced_phase[1]"] == 1.0
        @test built.diagnostics[:basis_count] == 3
        @test maximum(abs.(built.phase)) > 0.0
    end

    @testset "Reduced phase pullback matches finite differences" begin
        control = ReducedPhaseControlMap(orders=(2, 3))
        sim = Dict{String,Any}("Nt" => 48, "M" => 1, "Δt" => 0.05)
        context = (sim=sim, Nt=48, M=1)
        x = [0.7, -0.2]

        objective(values) = begin
            built = build_control(control, values, context)
            0.5 * sum(abs2, built.phase)
        end

        built = build_control(control, x, context)
        grad_phase = built.phase
        grad_x = pullback_control(control, grad_phase, context)
        fd = similar(grad_x)
        ε = 1e-6
        for i in eachindex(x)
            xp = copy(x); xm = copy(x)
            xp[i] += ε; xm[i] -= ε
            fd[i] = (objective(xp) - objective(xm)) / (2ε)
        end

        @test grad_x ≈ fd rtol=1e-6 atol=1e-7

        report = check_control_pullback(control, x, context)
        @test report.control == :reduced_phase
        @test report.pass
        @test length(report.rows) == 2
        io = IOBuffer()
        render_adjoint_contract_check_report(report; io=io)
        @test occursin("Control reduced_phase Check", String(take!(io)))
    end

    @testset "Reduced phase adjoint cost gradient matches coefficient finite difference" begin
        control = ReducedPhaseControlMap(orders=(2, 3))
        uω0, fiber, sim, band_mask, _, _ = setup_raman_problem(
            fiber_preset = :SMF28,
            L_fiber = 0.01,
            P_cont = 0.001,
            Nt = 64,
            time_window = 2.0,
            β_order = 3,
            pulse_fwhm = 1.85e-13,
            pulse_rep_rate = 8.05e7,
            pulse_shape = "sech_sq",
            raman_threshold = -5.0,
        )
        x = [0.05, -0.03]
        J, grad_x = reduced_phase_adjoint_cost_gradient(
            x, uω0, fiber, sim, band_mask;
            control = control,
            objective_kind = :raman_band,
            λ_gdd = 0.0,
            λ_boundary = 0.0,
            log_cost = false,
        )

        @test isfinite(J)
        @test size(grad_x) == size(x)
        @test all(isfinite, grad_x)

        ε = 1e-5
        fd = similar(grad_x)
        for i in eachindex(x)
            xp = copy(x); xm = copy(x)
            xp[i] += ε; xm[i] -= ε
            Jp, _ = reduced_phase_adjoint_cost_gradient(
                xp, uω0, fiber, sim, band_mask;
                control = control,
                objective_kind = :raman_band,
                λ_gdd = 0.0,
                λ_boundary = 0.0,
                log_cost = false,
            )
            Jm, _ = reduced_phase_adjoint_cost_gradient(
                xm, uω0, fiber, sim, band_mask;
                control = control,
                objective_kind = :raman_band,
                λ_gdd = 0.0,
                λ_boundary = 0.0,
                log_cost = false,
            )
            fd[i] = (Jp - Jm) / (2ε)
        end

        @test grad_x ≈ fd rtol=2e-3 atol=2e-8
    end
end
