using Test
using JSON3
using JLD2
using SHA

const _EXPLORATION_CONTRACT_RUNNER_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :run_exploration_contract_bundle)
    include(joinpath(_EXPLORATION_CONTRACT_RUNNER_ROOT, "scripts", "lib", "exploration_contract_runner.jl"))
end

function _write_freeform_quadratic_contract(dir)
    source = """
    function exploration_context()
        return (target = [0.25, -0.5], scale = 1.0)
    end

    function exploration_loss_gradient(x, context)
        params = exploration_parameter_dict(x, context)
        params["chirp"] == x[1] || error("named parameter helper mismatch")
        delta = x .- context.target
        cost = context.scale * sum(abs2, delta)
        gradient = 2 .* context.scale .* delta
        diagnostics = (; distance = sqrt(sum(abs2, delta)))
        return cost, gradient, diagnostics
    end

    function exploration_artifacts(result, context, output_dir)
        path = joinpath(output_dir, "variable_summary.txt")
        open(path, "w") do io
            println(io, "x_opt=", result.x_opt)
            println(io, "target=", context.target)
        end
        return Dict("variable_summary" => path)
    end
    """
    write(joinpath(dir, "execution.jl"), source)
    for filename in ("problem.jl", "variable.jl", "objective.jl")
        write(joinpath(dir, filename), "# Optional contract shard for test.\n")
    end
    manifest = Dict{String,Any}(
        "schema" => "fiber_exploration_contract_v1",
        "name" => "freeform_quadratic_test",
        "problem" => Dict("regime" => "custom"),
        "variable" => Dict("name" => "arbitrary_vector"),
        "objective" => Dict("name" => "distance_to_target"),
        "execution" => Dict(
            "initial" => [1.5, 1.0],
            "parameter_names" => ["chirp", "energy_scale"],
            "parameter_metadata" => Dict(
                "chirp" => Dict("unit" => "rad", "scale" => 1.0, "description" => "phase curvature"),
                "energy_scale" => Dict("unit" => "relative", "scale" => 0.5, "group" => "launch"),
            ),
            "lower" => [-2.0, -2.0],
            "upper" => [2.0, 2.0],
            "loss_gradient" => "exploration_loss_gradient",
            "context_function" => "exploration_context",
            "artifact_function" => "exploration_artifacts",
            "source_path" => "execution.jl",
        ),
        "solver" => Dict("kind" => "lbfgs", "max_iter" => 12, "uses_adjoint" => true),
        "artifacts" => Dict(
            "output_root" => joinpath(dir, "outputs"),
            "run_tag" => "unit test",
            "run_note" => "quadratic smoke for exploration runner",
        ),
    )
    open(joinpath(dir, "contract.json"), "w") do io
        JSON3.pretty(io, manifest)
        println(io)
    end
    return joinpath(dir, "contract.json")
end

@testset "Freeform exploration contract runner" begin
    mktempdir() do dir
        manifest = _write_freeform_quadratic_contract(dir)

        check = check_exploration_contract_bundle(manifest)
        @test check.complete
        @test check.dimension == 2
        @test check.parameter_names == ("chirp", "energy_scale")
        @test check.parameter_metadata["chirp"]["unit"] == "rad"
        @test check.parameter_bounds["energy_scale"]["lower"] == -2.0
        @test check.parameters_initial["chirp"] == 1.5
        @test check.initial_cost > 0
        @test check.initial_grad_norm > 0

        dry = run_exploration_contract_bundle(dir; dry_run=true)
        @test dry.dry_run
        @test dry.dimension == 2

        result = run_exploration_contract_bundle(dir; timestamp="test")
        @test isdir(result.output_dir)
        @test isfile(result.artifact_path)
        @test isfile(result.manifest_json)
        @test isfile(result.trace_csv)
        @test isfile(result.trace_png)
        @test isfile(result.gradient_trace_png)
        @test isfile(result.parameter_before_after_png)
        @test isfile(result.parameter_delta_png)
        @test isfile(result.diagnostics_final_png)
        @test isfile(result.diagnostics_trace_csv)
        @test isfile(result.diagnostics_trace_png)
        @test isfile(result.diagnostics_delta_csv)
        @test isfile(result.diagnostics_delta_png)
        @test isfile(result.run_index)
        @test isfile(joinpath(result.output_dir, "parameter_summary.csv"))
        @test isfile(joinpath(result.output_dir, "execution_source.jl"))
        @test isfile(joinpath(result.output_dir, "variable_summary.txt"))
        @test result.payload.cost_final < result.payload.cost_initial
        @test result.payload.x_opt ≈ [0.25, -0.5] atol=1e-3

        saved = JLD2.load(result.artifact_path)
        @test saved["schema"] == "fiber_exploration_freeform_result_v1"
        @test saved["cost_final"] < saved["cost_initial"]
        @test saved["x_opt"] ≈ [0.25, -0.5] atol=1e-3
        @test saved["parameter_names"] == ("chirp", "energy_scale")
        @test saved["parameters_opt"]["chirp"] ≈ 0.25 atol=1e-3
        @test saved["parameter_metadata"]["energy_scale"]["unit"] == "relative"
        @test isfile(saved["parameter_summary_csv"])
        @test isfile(saved["parameter_before_after_png"])
        @test isfile(saved["parameter_delta_png"])
        @test isfile(saved["diagnostics_final_png"])
        @test isfile(saved["diagnostics_trace_csv"])
        @test isfile(saved["diagnostics_trace_png"])
        @test isfile(saved["diagnostics_delta_csv"])
        @test isfile(saved["diagnostics_delta_png"])
        @test saved["source_sha256"] == bytes2hex(sha256(read(saved["source_snapshot"])))
        @test occursin("distance", read(saved["diagnostics_delta_csv"], String))

        run_manifest = JSON3.read(read(result.manifest_json, String))
        @test run_manifest.schema == "fiber_exploration_freeform_manifest_v1"
        @test run_manifest.contract_name == "freeform_quadratic_test"
        @test run_manifest.run_tag == "unit test"
        @test run_manifest.run_note == "quadratic smoke for exploration runner"
        @test run_manifest.parameter_names == ["chirp", "energy_scale"]
        @test run_manifest.parameters_opt.chirp ≈ 0.25 atol=1e-3
        @test run_manifest.parameter_metadata.chirp.unit == "rad"
        @test run_manifest.parameter_bounds.chirp.lower == -2.0
        @test isfile(String(run_manifest.parameter_summary_csv))
        @test isfile(String(run_manifest.parameter_before_after_png))
        @test isfile(String(run_manifest.parameter_delta_png))
        @test isfile(String(run_manifest.gradient_trace_png))
        @test isfile(String(run_manifest.diagnostics_final_png))
        @test isfile(String(run_manifest.diagnostics_trace_csv))
        @test isfile(String(run_manifest.diagnostics_trace_png))
        @test isfile(String(run_manifest.diagnostics_delta_csv))
        @test isfile(String(run_manifest.diagnostics_delta_png))
        @test isfile(String(run_manifest.source_snapshot))
        @test haskey(run_manifest.custom_artifacts, :variable_summary) ||
              haskey(run_manifest.custom_artifacts, "variable_summary")
        index_text = read(result.run_index, String)
        @test occursin("freeform_quadratic_test", index_text)
        @test occursin("quadratic smoke for exploration runner", index_text)
    end

    @testset "adversarial contract failures are explicit" begin
        function bad_contract(source; execution_overrides=Dict{String,Any}())
            dir = mktempdir()
            write(joinpath(dir, "execution.jl"), source)
            for filename in ("problem.jl", "variable.jl", "objective.jl")
                write(joinpath(dir, filename), "# Optional contract shard for test.\n")
            end
            execution = Dict{String,Any}(
                "initial" => [0.0, 1.0],
                "parameter_names" => ["a", "b"],
                "loss_gradient" => "exploration_loss_gradient",
                "context_function" => nothing,
                "artifact_function" => nothing,
                "source_path" => "execution.jl",
            )
            merge!(execution, execution_overrides)
            open(joinpath(dir, "contract.json"), "w") do io
                JSON3.pretty(io, Dict(
                    "schema" => "fiber_exploration_contract_v1",
                    "name" => "bad_contract",
                    "execution" => execution,
                    "solver" => Dict("max_iter" => 1),
                    "artifacts" => Dict("output_root" => joinpath(dir, "outputs")),
                ))
                println(io)
            end
            return dir
        end

        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(""))
        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(
            "function exploration_loss_gradient(x, context)\n    return 0.0, [1.0]\nend\n"
        ))
        try
            check_exploration_contract_bundle(bad_contract(
                "function exploration_loss_gradient(x, context)\n    return 0.0, [1.0]\nend\n"
            ))
        catch err
            @test occursin("expected 2 for parameters [a, b]", sprint(showerror, err))
        end
        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(
            "function exploration_loss_gradient(x, context)\n    return Inf, [1.0, 1.0]\nend\n"
        ))
        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(
            "function exploration_loss_gradient(x, context)\n    return 0.0, [NaN, 1.0]\nend\n"
        ))
        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(
            "function exploration_loss_gradient(x, context)\n    return 0.0, [1.0, 1.0]\nend\n";
            execution_overrides=Dict("parameter_names" => ["only_one"]),
        ))
        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(
            "function exploration_loss_gradient(x, context)\n    return 0.0, [1.0, 1.0]\nend\n";
            execution_overrides=Dict("parameter_metadata" => Dict("missing" => Dict("unit" => "m"))),
        ))
        @test_throws ArgumentError check_exploration_contract_bundle(bad_contract(
            "function exploration_loss_gradient(x, context)\n    return 0.0, [1.0, 1.0]\nend\n";
            execution_overrides=Dict("parameter_metadata" => Dict("a" => Dict("scale" => 0.0))),
        ))
        artifact_failure = run_exploration_contract_bundle(bad_contract(
            """
            function exploration_loss_gradient(x, context)
                return sum(abs2, x), 2 .* x
            end
            function exploration_artifacts(result, context, output_dir)
                error("artifact exploded")
            end
            """;
            execution_overrides=Dict("artifact_function" => "exploration_artifacts"),
        ))
        @test isfile(artifact_failure.artifact_path)
        @test isfile(artifact_failure.manifest_json)
        @test isfile(artifact_failure.artifact_error_path)
        @test occursin("artifact exploded", artifact_failure.artifact_error)
        failed_manifest = JSON3.read(read(artifact_failure.manifest_json, String))
        @test occursin("artifact exploded", failed_manifest.artifact_error)
        @test isfile(String(failed_manifest.artifact_error_path))
    end
end
