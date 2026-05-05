using Test

const _PLAYGROUND_SCAFFOLD_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

function _julia_binary()
    exe = Sys.iswindows() ? "julia.exe" : "julia"
    return joinpath(Sys.BINDIR, exe)
end

@testset "Playground scaffold CLI" begin
    mktempdir() do tmp
        objective_dir = joinpath(tmp, "objectives")
        variable_dir = joinpath(tmp, "variables")
        config_dir = joinpath(tmp, "configs")
        config_path = joinpath(config_dir, "demo_scaffold_experiment.toml")

        run(Cmd(`$(_julia_binary()) --project=$(_PLAYGROUND_SCAFFOLD_ROOT) scripts/canonical/scaffold_playground.jl demo_scaffold --mode control --dimension 3 --initial 0,0,0 --lower -1,-1,-1 --upper 1,1,1 --max-iter 1 --objective-dir $objective_dir --variable-dir $variable_dir --config-dir $config_dir --force`;
            dir=_PLAYGROUND_SCAFFOLD_ROOT))

        @test isfile(joinpath(objective_dir, "demo_scaffold_objective.toml"))
        @test isfile(joinpath(objective_dir, "demo_scaffold_objective.jl"))
        @test isfile(joinpath(variable_dir, "demo_scaffold_control.toml"))
        @test isfile(joinpath(variable_dir, "demo_scaffold_control.jl"))
        @test isfile(config_path)

        config_text = read(config_path, String)
        @test occursin("kind = \"demo_scaffold_objective\"", config_text)
        @test occursin("variables = [\"demo_scaffold_control\"]", config_text)
        @test occursin("kind = \"nelder_mead\"", config_text)

        check_cmd = Cmd(`$(_julia_binary()) --project=$(_PLAYGROUND_SCAFFOLD_ROOT) scripts/canonical/run_experiment.jl --playground-check $config_path --local-smoke`;
            dir=_PLAYGROUND_SCAFFOLD_ROOT)
        output = read(
            setenv(
                check_cmd,
                "FIBER_OBJECTIVE_EXTENSION_DIRS" => objective_dir,
                "FIBER_VARIABLE_EXTENSION_DIRS" => variable_dir,
            ),
            String,
        )
        @test occursin("Runtime Extension Doctor", output)
        @test occursin("Status: `PASS`", output)
        @test occursin("Artifact plan implemented: `true`", output)
        @test occursin("allowed=true", output)
    end
end
