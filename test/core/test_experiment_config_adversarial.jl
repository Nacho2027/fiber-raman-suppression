using Test

const _ADVERSARIAL_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :load_experiment_spec)
    using MultiModeNoise
    include(joinpath(_ADVERSARIAL_ROOT, "scripts", "lib", "experiment_spec.jl"))
end
if !isdefined(Main, :control_layout_plan)
    include(joinpath(_ADVERSARIAL_ROOT, "scripts", "lib", "control_layout.jl"))
end
if !isdefined(Main, :experiment_artifact_plan)
    include(joinpath(_ADVERSARIAL_ROOT, "scripts", "lib", "artifact_plan.jl"))
end
if !isdefined(Main, :run_experiment_main)
    include(joinpath(_ADVERSARIAL_ROOT, "scripts", "lib", "experiment_runner.jl"))
    include(joinpath(_ADVERSARIAL_ROOT, "scripts", "workflows", "run_experiment.jl"))
end
if !isdefined(Main, :lab_ready_config_report)
    include(joinpath(_ADVERSARIAL_ROOT, "scripts", "workflows", "lab_ready.jl"))
end

function _mutated_experiment_config(base_id::AbstractString, replacements::Pair{String,String}...)
    text = read(resolve_experiment_config_path(base_id), String)
    for (old, new) in replacements
        occursin(old, text) || error("missing mutation anchor in $base_id: $old")
        text = replace(text, old => new; count=1)
    end
    dir = mktempdir()
    path = joinpath(dir, string(base_id, "_mutated.toml"))
    write(path, text)
    return path
end

function _validation_message(path::AbstractString)
    try
        validate_experiment_spec(load_experiment_spec(path))
        return ""
    catch err
        return sprint(showerror, err)
    end
end

function _expect_rejected(base_id::AbstractString, expected::AbstractString, replacements::Pair{String,String}...)
    path = _mutated_experiment_config(base_id, replacements...)
    message = _validation_message(path)
    @test !isempty(message)
    @test occursin(expected, message)
    return message
end

@testset "Experiment config adversarial coverage" begin
    @testset "Approved configs expose coherent plans" begin
        ids = approved_experiment_config_ids()
        @test length(ids) >= 7
        for id in ids
            spec = load_experiment_spec(id)
            caps = validate_experiment_spec(spec)
            mode = experiment_execution_mode(spec)
            layout = control_layout_plan(spec)
            artifacts = experiment_artifact_plan(spec)
            rendered = render_experiment_plan(spec)

            @test spec.problem.regime in registered_experiment_regimes()
            @test spec.controls.variables in caps.variables
            @test spec.objective.kind in caps.objectives
            @test spec.solver.kind in caps.solvers
            @test !isempty(layout.blocks)
            @test !isempty(layout.total_length)
            @test occursin("Experiment spec: $(spec.id)", rendered)
            @test occursin("Execution: mode=$(mode)", rendered)
            @test artifacts.implemented isa Bool
        end
    end

    @testset "Supported single-mode variable tuples are selectable" begin
        base = "smf28_phase_amplitude_energy_poc"
        cases = (
            ("phase_amplitude", "variables = [\"phase\", \"amplitude\", \"energy\"]" => "variables = [\"phase\", \"amplitude\"]", "16384"),
            ("phase_energy", "variables = [\"phase\", \"amplitude\", \"energy\"]" => "variables = [\"phase\", \"energy\"]", "8193"),
            ("phase_amplitude_energy", "variables = [\"phase\", \"amplitude\", \"energy\"]" => "variables = [\"phase\", \"amplitude\", \"energy\"]", "16385"),
        )
        for (label, replacement, expected_length) in cases
            path = _mutated_experiment_config(base, replacement)
            spec = load_experiment_spec(path)
            @test validate_experiment_spec(spec).variables isa Tuple
            @test experiment_execution_mode(spec) == :multivar
            @test control_layout_plan(spec).total_length == expected_length
            @test experiment_artifact_plan(spec).implemented
            @test occursin(label == "phase_energy" ? "energy" : "phase", render_experiment_plan(spec))
        end
    end

    @testset "Objective matrix boundaries are explicit" begin
        peak = load_experiment_spec("research_engine_peak_smoke")
        @test validate_experiment_spec(peak) isa NamedTuple
        @test experiment_objective_contract(peak).kind == :raman_peak

        _expect_rejected(
            "smf28_phase_amplitude_energy_poc",
            "objective `raman_peak` does not support variables",
            "kind = \"raman_band\"" => "kind = \"raman_peak\"",
        )

        for objective in registered_objective_kinds(:multimode)
            path = _mutated_experiment_config(
                "grin50_mmf_phase_sum_poc",
                "kind = \"mmf_sum\"" => "kind = \"$(objective)\"",
            )
            spec = load_experiment_spec(path)
            @test validate_experiment_spec(spec) isa NamedTuple
            @test experiment_execution_mode(spec) == :multimode_phase
            @test occursin("$(objective)", render_experiment_plan(spec))
        end
    end

    @testset "Unsafe numeric knobs are rejected before execution" begin
        _expect_rejected("research_engine_smoke", "problem.Nt must be positive",
            "Nt = 1024" => "Nt = 0")
        _expect_rejected("research_engine_smoke", "problem.time_window must be positive and finite",
            "time_window = 5.0" => "time_window = -5.0")
        _expect_rejected("research_engine_smoke", "problem.L_fiber must be positive and finite",
            "L_fiber = 0.05" => "L_fiber = 0.0")
        _expect_rejected("research_engine_smoke", "problem.P_cont must be positive and finite",
            "P_cont = 0.001" => "P_cont = -0.001")
        _expect_rejected("research_engine_smoke", "problem.pulse_fwhm must be positive and finite",
            "pulse_fwhm = 1.85e-13" => "pulse_fwhm = -1.85e-13")
        _expect_rejected("research_engine_smoke", "problem.pulse_rep_rate must be positive and finite",
            "pulse_rep_rate = 8.05e7" => "pulse_rep_rate = 0.0")
        _expect_rejected("research_engine_smoke", "problem.beta_order must be positive",
            "beta_order = 3" => "beta_order = 0")
        _expect_rejected("research_engine_smoke", "solver.max_iter must be positive",
            "max_iter = 1" => "max_iter = 0")
        _expect_rejected("research_engine_smoke", "solver.reltol must be positive and finite",
            "store_trace = true" => "store_trace = true\nreltol = -1.0")
        _expect_rejected("research_engine_smoke", "solver.g_abstol must be positive and finite",
            "store_trace = true" => "store_trace = true\ng_abstol = 0.0")
        _expect_rejected("research_engine_smoke", "solver.f_abstol must be positive and finite",
            "store_trace = true" => "store_trace = true\nf_abstol = -1.0")
    end

    @testset "Cost-function typos and unsafe regularizers fail closed" begin
        _expect_rejected("research_engine_smoke", "objective `made_up_cost` is not registered",
            "kind = \"raman_band\"" => "kind = \"made_up_cost\"")
        _expect_rejected("research_engine_smoke", "regularizer `not_real`",
            "name = \"boundary\"" => "name = \"not_real\"")
        _expect_rejected("research_engine_smoke", "regularizer `boundary` lambda must be nonnegative and finite",
            "lambda = 1.0" => "lambda = -1.0")
        _expect_rejected("research_engine_peak_smoke", "regularizer `energy`",
            "name = \"boundary\"" => "name = \"energy\"")
        _expect_rejected("research_engine_temporal_peak_scalar_smoke",
            "scalar extension objective `temporal_peak_scalar` must set objective.log_cost=false",
            "log_cost = false" => "log_cost = true")
        _expect_rejected("research_engine_temporal_peak_scalar_smoke", "regularizer `boundary`",
            "name = \"energy\"" => "name = \"boundary\"")
    end

    @testset "Unsupported front-layer combinations fail closed" begin
        _expect_rejected("research_engine_smoke", "experiment maturity must be `supported` or `experimental`",
            "maturity = \"supported\"" => "maturity = \"research\"")
        _expect_rejected("research_engine_smoke", "unknown experiment regime",
            "regime = \"single_mode\"" => "regime = \"free_space\"")
        _expect_rejected("research_engine_smoke", "variables (:amplitude,) are not currently supported",
            "variables = [\"phase\"]" => "variables = [\"amplitude\"]")
        _expect_rejected("research_engine_smoke", "solver `adam` is not supported",
            "kind = \"lbfgs\"" => "kind = \"adam\"")
        _expect_rejected("research_engine_gain_tilt_scalar_search_smoke", "solver.scalar_lower must be less than solver.scalar_upper",
            "scalar_lower = -0.09" => "scalar_lower = 0.09")
        _expect_rejected("research_engine_gain_tilt_scalar_search_smoke", "bounded_scalar currently supports controls.variables=[\"gain_tilt\"], [\"quadratic_phase\"], or one promoted scalar variable extension",
            "variables = [\"gain_tilt\"]" => "variables = [\"phase\", \"gain_tilt\"]")
        _expect_rejected("research_engine_gain_tilt_scalar_search_smoke", "plots.temporal_pulse.time_range must be [low, high] with low < high",
            "time_range = [-0.75, 0.75]" => "time_range = [0.75, -0.75]")
        _expect_rejected("research_engine_smoke", "grid_policy `mystery_grid` is not supported",
            "grid_policy = \"auto_if_undersized\"" => "grid_policy = \"mystery_grid\"")
        _expect_rejected("research_engine_smoke", "phase-like adjoint execution currently requires the full standard artifact bundle",
            "write_standard_images = true" => "write_standard_images = false")
        _expect_rejected("research_engine_export_smoke", "requires include_group_delay=true",
            "include_group_delay = true" => "include_group_delay = false")
    end

    @testset "Experimental regimes advertise planning boundaries" begin
        _expect_rejected("smf28_phase_amplitude_energy_poc", "does not yet support manifest updates or trust-report writing",
            "write_trust_report = false" => "write_trust_report = true")
        _expect_rejected("smf28_phase_amplitude_energy_poc", "does not yet support phase/SLM export handoff",
            "enabled = false" => "enabled = true")
        _expect_rejected("smf28_longfiber_phase_poc", "standard long_fiber front-layer smoke requires Nt <= 4096",
            "mode = \"burst_required\"" => "mode = \"standard\"")
        _expect_rejected("smf28_longfiber_phase_poc", "does not yet support phase export handoff",
            "enabled = false" => "enabled = true")
        _expect_rejected("grin50_mmf_phase_sum_poc", "parameterization `full_grid` is not supported",
            "parameterization = \"shared_across_modes\"" => "parameterization = \"full_grid\"")
        _expect_rejected("grin50_mmf_phase_sum_poc", "multimode front-layer execution does not yet support manifest updates or trust-report writing",
            "update_manifest = false" => "update_manifest = true")

        for id in ("smf28_longfiber_phase_poc", "grin50_mmf_phase_sum_poc")
            report = lab_ready_config_report(id)
            @test !report.pass
            @test "planning_only_execution_mode" in report.blockers
            @test_throws ErrorException run_experiment_main([id])
        end
    end
end
