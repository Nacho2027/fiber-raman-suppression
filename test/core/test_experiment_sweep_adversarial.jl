using Test

const _SWEEP_ADV_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :load_experiment_sweep_spec)
    include(joinpath(_SWEEP_ADV_ROOT, "scripts", "lib", "experiment_sweep.jl"))
end
if !isdefined(Main, :execute_experiment_sweep)
    include(joinpath(_SWEEP_ADV_ROOT, "scripts", "lib", "experiment_runner.jl"))
    include(joinpath(_SWEEP_ADV_ROOT, "scripts", "workflows", "run_experiment_sweep.jl"))
end

function _mutated_sweep_config(base_id::AbstractString, replacements::Pair{String,String}...)
    text = read(resolve_experiment_sweep_config_path(base_id), String)
    for (old, new) in replacements
        occursin(old, text) || error("missing sweep mutation anchor in $base_id: $old")
        text = replace(text, old => new; count=1)
    end
    dir = mktempdir()
    path = joinpath(dir, string(base_id, "_mutated.toml"))
    write(path, text)
    return path
end

function _sweep_validation_message(path::AbstractString)
    try
        spec = load_experiment_sweep_spec(path)
        expand_experiment_sweep(spec)
        return ""
    catch err
        return sprint(showerror, err)
    end
end

function _expect_sweep_rejected(base_id::AbstractString, expected::AbstractString, replacements::Pair{String,String}...)
    path = _mutated_sweep_config(base_id, replacements...)
    message = _sweep_validation_message(path)
    @test !isempty(message)
    @test occursin(expected, message)
    return message
end

@testset "Experiment sweep adversarial coverage" begin
    @testset "Approved sweep expands through the same config contracts" begin
        ids = approved_experiment_sweep_config_ids()
        @test "smf28_power_micro_sweep" in ids
        for id in ids
            sweep_spec = load_experiment_sweep_spec(id)
            @test validate_experiment_sweep_spec(sweep_spec) === sweep_spec
            expanded = expand_experiment_sweep(sweep_spec)
            rendered = render_experiment_sweep_plan(sweep_spec)
            @test length(expanded.cases) == length(sweep_spec.sweep.values)
            @test all(case -> validate_experiment_spec(case.spec) isa NamedTuple, expanded.cases)
            @test occursin("Experiment sweep: $(sweep_spec.id)", rendered)
            @test occursin("No command in this plan launches optimization", rendered)
        end
    end

    @testset "Sweep metadata mistakes fail closed" begin
        _expect_sweep_rejected("smf28_power_micro_sweep", "experiment sweep maturity must be `supported` or `experimental`",
            "maturity = \"supported\"" => "maturity = \"research\"")
        _expect_sweep_rejected("smf28_power_micro_sweep", "experiment sweep must define at least one value",
            "values = [0.001, 0.002, 0.003]" => "values = []")
        _expect_sweep_rejected("smf28_power_micro_sweep", "sweep labels length must match values length",
            "values = [0.001, 0.002, 0.003]" => "values = [0.001, 0.002, 0.003]\nlabels = [\"low\", \"mid\"]")
        _expect_sweep_rejected("smf28_power_micro_sweep", "sweep labels must be nonempty",
            "values = [0.001, 0.002, 0.003]" => "values = [0.001, 0.002, 0.003]\nlabels = [\"low\", \"\", \"high\"]")
        _expect_sweep_rejected("smf28_power_micro_sweep", "sweep labels must be unique",
            "values = [0.001, 0.002, 0.003]" => "values = [0.001, 0.002, 0.003]\nlabels = [\"same\", \"same\", \"high\"]")
        _expect_sweep_rejected("smf28_power_micro_sweep", "execution.mode=\"dry_run\"",
            "mode = \"dry_run\"" => "mode = \"execute\"")
        _expect_sweep_rejected("smf28_power_micro_sweep", "execution.require_validate_all=true",
            "require_validate_all = true" => "require_validate_all = false")
    end

    @testset "Unsupported sweep axes and generated bad configs fail closed" begin
        _expect_sweep_rejected("smf28_power_micro_sweep", "unsupported problem sweep field `preset`",
            "parameter = \"problem.P_cont\"" => "parameter = \"problem.preset\"")
        _expect_sweep_rejected("smf28_power_micro_sweep", "unsupported sweep section `controls`",
            "parameter = \"problem.P_cont\"" => "parameter = \"controls.variables\"")
        _expect_sweep_rejected("smf28_power_micro_sweep", "must have shape section.field",
            "parameter = \"problem.P_cont\"" => "parameter = \"problem\"")
        _expect_sweep_rejected("smf28_power_micro_sweep", "problem.P_cont must be positive and finite",
            "values = [0.001, 0.002, 0.003]" => "values = [0.001, -0.002, 0.003]")
        _expect_sweep_rejected("smf28_power_micro_sweep", "problem.Nt must be positive",
            "parameter = \"problem.P_cont\"" => "parameter = \"problem.Nt\"",
            "values = [0.001, 0.002, 0.003]" => "values = [1024, 0]")
        _expect_sweep_rejected("smf28_power_micro_sweep", "solver.max_iter must be positive",
            "parameter = \"problem.P_cont\"" => "parameter = \"solver.max_iter\"",
            "values = [0.001, 0.002, 0.003]" => "values = [1, 0]")
        _expect_sweep_rejected("smf28_power_micro_sweep", "objective `made_up_cost` is not registered",
            "parameter = \"problem.P_cont\"" => "parameter = \"objective.kind\"",
            "values = [0.001, 0.002, 0.003]" => "values = [\"raman_band\", \"made_up_cost\"]")
    end

    @testset "Planning-only sweeps stay inspectable but do not execute cases" begin
        path = _mutated_sweep_config(
            "smf28_power_micro_sweep",
            "base_experiment = \"research_engine_smoke\"" => "base_experiment = \"smf28_longfiber_phase_poc\"",
            "values = [0.001, 0.002, 0.003]" => "values = [0.04, 0.05]",
            "output_root = \"results/raman/sweeps/front_layer\"" => "output_root = \"$(replace(mktempdir(), "\\" => "\\\\"))\"",
        )
        sweep_spec = load_experiment_sweep_spec(path)
        expanded = expand_experiment_sweep(sweep_spec)
        @test length(expanded.cases) == 2
        @test all(case -> experiment_execution_mode(case.spec) == :long_fiber_phase, expanded.cases)

        result = execute_experiment_sweep(sweep_spec; timestamp="adversarial_no_compute")
        @test all(row -> row.status == :skipped, result.results)
        @test all(row -> occursin("planning-only", row.error), result.results)
        @test isfile(result.summary_path)
        @test isfile(result.summary_json_path)
        @test isfile(result.summary_csv_path)
    end
end
