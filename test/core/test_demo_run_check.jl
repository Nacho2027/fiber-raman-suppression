using Test
using MultiModeNoise

if !isdefined(Main, :_ROOT)
    const _ROOT = normpath(joinpath(@__DIR__, "..", ".."))
end

include(joinpath(_ROOT, "scripts", "workflows", "demo_run_check.jl"))

function _write_demo_export_fixture(export_dir::AbstractString, rows::Integer)
    mkpath(export_dir)
    write(joinpath(export_dir, "README.md"), "# Demo export\n")
    write(joinpath(export_dir, "source_run_config.toml"), "id = \"demo\"\n")
    write(joinpath(export_dir, "metadata.json"), """
{
  "phase_csv": "phase_profile.csv"
}
""")
    open(joinpath(export_dir, "phase_profile.csv"), "w") do io
        println(io, "index,frequency_offset_THz,absolute_frequency_THz,wavelength_nm,phase_wrapped_rad,phase_unwrapped_rad,group_delay_fs")
        for idx in 1:rows
            println(io, "$(idx),0.0,193.4,1550.0,0.0,0.0,0.0")
        end
    end
end

@testset "Live demo run check" begin
    parsed = parse_demo_run_check_args(["--latest", "research_engine_live_demo", "--min-delta-db", "-30"])
    @test parsed.mode == :latest
    @test parsed.target == "research_engine_live_demo"
    @test parsed.min_delta_db == -30.0
    @test parsed.require_export

    tmp = mktempdir()
    run_dir = joinpath(tmp, "run")
    mkpath(run_dir)

    payload = (
        fiber_name = "SMF-28",
        run_tag = "demo",
        L_m = 2.0,
        P_cont_W = 0.2,
        lambda0_nm = 1550.0,
        fwhm_fs = 185.0,
        gamma = 1.1e-3,
        betas = [-2.17e-26, 1.2e-40],
        Nt = 8,
        time_window_ps = 0.08,
        J_before = 1e-1,
        J_after = 1e-5,
        delta_J_dB = MultiModeNoise.lin_to_dB(1e-5) - MultiModeNoise.lin_to_dB(1e-1),
        grad_norm = 1e-4,
        converged = false,
        iterations = 10,
        wall_time_s = 90.0,
        convergence_history = [-10.0, -30.0, -50.0],
        phi_opt = reshape(collect(range(-0.2, stop=0.2, length=8)), 8, 1),
        uω0 = ones(ComplexF64, 8, 1),
        E_conservation = 0.0,
        bc_input_frac = 1e-6,
        bc_output_frac = 1e-6,
        bc_input_ok = true,
        bc_output_ok = true,
        trust_report = Dict("overall_verdict" => "PASS"),
        trust_report_md = "opt_trust.md",
        band_mask = trues(8),
        sim_Dt = 0.01,
        sim_omega0 = 2π * 193.4,
    )

    MultiModeNoise.save_run(joinpath(run_dir, "opt_result.jld2"), payload)
    write(joinpath(run_dir, "opt_trust.md"), "# trust\n")
    write(joinpath(run_dir, "run_config.toml"), "id = \"demo\"\n")
    for suffix in REQUIRED_STANDARD_IMAGE_SUFFIXES
        write(joinpath(run_dir, "opt" * suffix), "")
    end
    _write_demo_export_fixture(joinpath(run_dir, "export_handoff"), 8)

    report = demo_run_check_report(run_dir; min_delta_db=-20.0)
    @test report.status == :pass
    @test isempty(report.blockers)
    @test report.quality == "EXCELLENT"
    @test report.converged == false
    @test report.export_handoff_complete
    @test report.export_phase_csv_rows == 8

    strict_report = demo_run_check_report(run_dir; min_delta_db=-50.0)
    @test strict_report.status == :fail
    @test "insufficient_suppression_delta" in strict_report.blockers

    rendered = sprint(io -> render_demo_run_check_report(report; io=io))
    @test occursin("Live Demo Run Check", rendered)
    @test occursin("Optimizer converged: `false`", rendered)
    @test occursin("canonical convergence certification", rendered)

    wrapper = read(joinpath(_ROOT, "scripts", "canonical", "demo_run_check.jl"), String)
    @test occursin("workflows\", \"demo_run_check.jl", wrapper)
    @test occursin("demo_run_check_main(ARGS)", wrapper)
end
