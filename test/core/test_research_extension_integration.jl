using Test

const _EXT_INTEGRATION_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :load_experiment_spec)
    using MultiModeNoise
    include(joinpath(_EXT_INTEGRATION_ROOT, "scripts", "lib", "experiment_spec.jl"))
end
if !isdefined(Main, :run_experiment_main)
    include(joinpath(_EXT_INTEGRATION_ROOT, "scripts", "lib", "experiment_runner.jl"))
    include(joinpath(_EXT_INTEGRATION_ROOT, "scripts", "workflows", "run_experiment.jl"))
end

function _extension_mutated_config(replacements::Pair{String,String}...)
    text = read(resolve_experiment_config_path("research_engine_smoke"), String)
    for (old, new) in replacements
        occursin(old, text) || error("missing extension mutation anchor: $old")
        text = replace(text, old => new; count=1)
    end
    dir = mktempdir()
    path = joinpath(dir, "extension_planning_attempt.toml")
    write(path, text)
    return path
end

function _extension_validation_message(path::AbstractString)
    try
        validate_experiment_spec(load_experiment_spec(path))
        return ""
    catch err
        return sprint(showerror, err)
    end
end

@testset "Research extension integration" begin
    @testset "Non-Raman objective extension is discoverable but gated" begin
        @test :pulse_compression_planning in registered_objective_extension_kinds(:single_mode)
        contract = objective_extension_contract(:pulse_compression_planning, :single_mode)
        row = validate_objective_extension_contract(contract)
        @test row.valid
        @test !row.promotable
        @test "execution_planning_only" in row.blockers
        @test "backend_not_promoted" in row.blockers

        listing = sprint(io -> render_objective_registry(; io=io, regime=:single_mode))
        @test occursin("pulse_compression_planning", listing)
        @test occursin("execution=planning_only", listing)

        path = _extension_mutated_config(
            "kind = \"raman_band\"" => "kind = \"pulse_compression_planning\"",
        )
        message = _extension_validation_message(path)
        @test occursin("objective `pulse_compression_planning` is a research extension", message)
        @test occursin("not promoted for execution", message)
        @test occursin("execution_planning_only", message)
    end

    @testset "Non-standard variable extension is discoverable but gated" begin
        @test :gain_tilt_planning in registered_variable_extension_kinds(:single_mode)
        contract = variable_extension_contract(:gain_tilt_planning, :single_mode)
        row = validate_variable_extension_contract(contract)
        @test row.valid
        @test !row.promotable
        @test "execution_planning_only" in row.blockers
        @test "backend_not_promoted" in row.blockers

        listing = sprint(io -> render_variable_registry(; io=io, regime=:single_mode))
        @test occursin("gain_tilt_planning", listing)
        @test occursin("execution=planning_only", listing)

        path = _extension_mutated_config(
            "variables = [\"phase\"]" => "variables = [\"gain_tilt_planning\"]",
        )
        message = _extension_validation_message(path)
        @test occursin("variable `gain_tilt_planning` is a research extension", message)
        @test occursin("not promoted for execution", message)
        @test occursin("execution_planning_only", message)
    end

    @testset "Extension validation commands remain green without executing science" begin
        objective_report = run_experiment_main(["--validate-objectives"])
        variable_report = run_experiment_main(["--validate-variables"])
        @test objective_report.invalid == 0
        @test objective_report.promotable == 0
        @test variable_report.invalid == 0
        @test variable_report.promotable == 0
        @test variable_report.total >= 2
    end
end
