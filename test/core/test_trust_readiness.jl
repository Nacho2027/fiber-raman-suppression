using Test
using FiberLab

if !(@isdefined _ROOT)
    const _ROOT = normpath(joinpath(@__DIR__, "..", ".."))
end

include(joinpath(_ROOT, "scripts", "lib", "experiment_runner.jl"))
include(joinpath(_ROOT, "scripts", "lib", "results_index.jl"))
include(joinpath(_ROOT, "scripts", "workflows", "lab_ready.jl"))

if !(@isdefined _write_valid_test_png)
    function _write_valid_test_png(path::AbstractString)
        pixels = zeros(Float64, 8, 8)
        pixels[3:6, 3:6] .= 1.0
        FiberLab.PyPlot.imsave(path, pixels; cmap="viridis")
        return path
    end
end

function _trust_test_payload(report_path::AbstractString)
    return (
        fiber_name = "SMF-28",
        run_tag = "trust-test",
        L_m = 0.05,
        P_cont_W = 0.001,
        lambda0_nm = 1550.0,
        fwhm_fs = 185.0,
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        Nt = 8,
        time_window_ps = 1.0,
        J_before = 1e-2,
        J_after = 1e-4,
        delta_J_dB = -20.0,
        grad_norm = 1e-6,
        converged = true,
        iterations = 1,
        wall_time_s = 0.01,
        convergence_history = [-20.0, -40.0],
        phi_opt = zeros(8, 1),
        uω0 = ones(ComplexF64, 8, 1),
        E_conservation = 0.0,
        photon_number_drift = 0.0,
        bc_input_frac = 1e-8,
        bc_output_frac = 1e-8,
        bc_input_ok = true,
        bc_output_ok = true,
        trust_report = Dict("overall_verdict" => "PASS"),
        trust_report_md = String(report_path),
        band_mask = trues(8),
        sim_Dt = 0.125,
        sim_omega0 = 2π * 193.4,
    )
end

function _write_trust_test_bundle(root::AbstractString, spec, verdict::AbstractString)
    dir = joinpath(root, lowercase(verdict))
    mkpath(dir)
    prefix = joinpath(dir, "opt")
    trust_path = string(prefix, "_trust.md")
    artifact_path = string(prefix, "_result.jld2")
    FiberLab.save_run(artifact_path, _trust_test_payload(trust_path))
    cp(spec.config_path, joinpath(dir, "run_config.toml"); force=true)
    write(trust_path,
        "# Numerical Trust Report\n\n- Overall verdict: **$(uppercase(verdict))**\n")
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        _write_valid_test_png(string(prefix, suffix))
    end
    return (
        spec = spec,
        output_dir = dir,
        save_prefix = prefix,
        config_copy = joinpath(dir, "run_config.toml"),
        artifact_path = artifact_path,
        sidecar_path = string(prefix, "_result.json"),
    )
end

@testset "Scientific trust and readiness" begin
    @testset "Verdict evaluator is fail closed" begin
        for verdict in ("PASS", "MARGINAL", "SUSPECT", "NOT_RUN")
            status = trust_readiness(Dict("overall_verdict" => verdict); required=true)
            @test status.verdict == verdict
            @test status.pass == (verdict == "PASS")
        end
        @test trust_readiness(Dict("overall_verdict" => "unknown"); required=true).blocker ==
              "invalid_trust_report"
        @test trust_readiness(String[]; required=false).pass
        @test trust_readiness(String[]; required=true).blocker == "missing_trust_report"
    end

    @testset "Optional omitted gradient is neutral; requested omission fails" begin
        det = (applied=true, fftw_threads=1, blas_threads=1,
               version="test", phase="test")
        common = (
            det_status=det,
            edge_input_frac=1e-8,
            edge_output_frac=1e-8,
            energy_drift=1e-8,
            gradient_validation=nothing,
            log_cost=true,
            λ_gdd=0.0,
            λ_boundary=0.0,
        )
        optional = build_numerical_trust_report(; common..., gradient_required=false)
        required = build_numerical_trust_report(; common..., gradient_required=true)
        @test optional["schema_version"] == "1.0"
        @test optional["gradient_validation"]["verdict"] == "NOT_RUN"
        @test !optional["gradient_validation"]["included_in_overall"]
        @test optional["overall_verdict"] == "PASS"
        @test required["gradient_validation"]["included_in_overall"]
        @test required["overall_verdict"] == "NOT_RUN"
    end

    @testset "Manifest, index, and lab gate agree" begin
        spec = load_experiment_spec("research_engine_poc")
        mktempdir() do tmp
            for verdict in ("PASS", "MARGINAL", "SUSPECT", "NOT_RUN")
                bundle = _write_trust_test_bundle(tmp, spec, verdict)
                checked = _attach_trust_validation(_attach_artifact_validation(bundle))
                manifest = experiment_run_manifest_data(checked)
                @test manifest["trust"]["verdict"] == verdict
                @test manifest["execution"]["compare_ready"] == (verdict == "PASS")
                write_experiment_run_manifest(checked)

                gate = lab_ready_run_report(bundle.output_dir)
                index_row = only(build_results_index([bundle.output_dir]).rows)
                @test gate.pass == (verdict == "PASS")
                @test index_row.lab_ready == gate.pass
                @test index_row.manifest_compare_ready == gate.pass
            end

            invalid = _write_trust_test_bundle(tmp, spec, "INVALID")
            write(string(invalid.save_prefix, "_trust.md"), "# trust\n")
            @test !lab_ready_run_report(invalid.output_dir).pass
            @test "invalid_trust_report" in lab_ready_run_report(invalid.output_dir).blockers
        end
    end

    @testset "Configured failed-check blocking is enforced" begin
        spec = load_experiment_spec("research_engine_poc")
        mktempdir() do tmp
            blocking = _write_trust_test_bundle(tmp, spec, "MARGINAL")
            @test_throws ArgumentError _finalize_experiment_run(blocking)
            @test isfile(joinpath(blocking.output_dir, "run_manifest.json"))

            nonblocking_spec = (; spec...,
                verification=(; spec.verification..., block_on_failed_checks=false))
            nonblocking = _write_trust_test_bundle(tmp, nonblocking_spec, "SUSPECT")
            completed = _finalize_experiment_run(nonblocking)
            @test !completed.trust_validation.pass
            manifest = JSON3.read(read(completed.run_manifest_path, String))
            @test manifest.execution.compare_ready == false
        end
    end
end
