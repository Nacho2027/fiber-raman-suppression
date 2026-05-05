using Test

const _EXT_INTEGRATION_ROOT = isdefined(Main, :_ROOT) ?
    getfield(Main, :_ROOT) :
    normpath(joinpath(@__DIR__, "..", ".."))

if !isdefined(Main, :load_experiment_spec)
    using FiberLab
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

    @testset "Scalar objective extension is promoted for bounded scalar search" begin
        @test :temporal_peak_scalar in registered_objective_extension_kinds(:single_mode)
        @test :temporal_peak_scalar in registered_objective_kinds(:single_mode)
        contract = objective_contract(:temporal_peak_scalar, :single_mode)
        @test contract.backend == :scalar_extension
        @test contract.execution == :executable
        @test (:gain_tilt,) in contract.supported_variables
        @test (:quadratic_phase,) in contract.supported_variables

        row = validate_objective_extension_contract(contract)
        @test row.valid
        @test row.promotable
        @test isempty(row.blockers)
        @test isempty(row.errors)

        spec = load_experiment_spec("research_engine_temporal_peak_scalar_smoke")
        @test spec.objective.kind == :temporal_peak_scalar
        @test spec.controls.variables == (:gain_tilt,)
        @test experiment_execution_mode(spec) == :scalar_search
        @test validate_experiment_spec(spec) isa NamedTuple

        quadratic_spec = load_experiment_spec("research_engine_temporal_peak_quadratic_phase_smoke")
        @test quadratic_spec.objective.kind == :temporal_peak_scalar
        @test quadratic_spec.controls.variables == (:quadratic_phase,)
        @test experiment_execution_mode(quadratic_spec) == :scalar_search
        @test validate_experiment_spec(quadratic_spec) isa NamedTuple
    end

    @testset "Scalar extension sidecar metadata is objective-specific" begin
        mktempdir() do dir
            result = Optim.optimize(x -> (x - 0.1)^2, -1.0, 1.0)
            cfg = MVConfig(variables = (:gain_tilt,), log_cost = false, λ_energy = 0.0)
            outcome = (
                result = result,
                cfg = cfg,
                φ_opt = zeros(8, 1),
                A_opt = ones(8, 1),
                E_opt = 1.0,
                E_ref = 1.0,
                J_opt = 0.5,
                g_norm = 0.0,
                wall_time_s = 0.1,
                iterations = 2,
                gain_tilt_opt = 0.05,
                gain_tilt_search = 0.05,
            )
            saved = save_multivar_result(joinpath(dir, "opt"), outcome; meta = Dict{Symbol,Any}(
                :objective_kind => :temporal_peak_scalar,
                :objective_backend => :scalar_extension,
                :objective_label => "temporal peak scalar test objective",
                :objective_base_term => "extension:temporal_peak_scalar",
                :fiber_name => "unit-test",
                :L_m => 1.0,
                :P_cont_W => 0.1,
                :lambda0_nm => 1550.0,
                :fwhm_fs => 185.0,
                :rep_rate_Hz => 80.5e6,
                :gamma => 1.0e-3,
                :time_window_ps => 1.0,
                :J_before => 0.6,
                :J_after_lin => 0.5,
                :delta_J_dB => -0.79,
            ))
            sidecar = JSON3.read(read(saved.json, String), Dict{String,Any})
            @test sidecar["cost_surface"]["objective_kind"] == "temporal_peak_scalar"
            @test sidecar["cost_surface"]["objective_backend"] == "scalar_extension"
            @test sidecar["cost_surface"]["objective_label"] == "temporal peak scalar test objective"
            @test sidecar["cost_surface"]["surface"] == "extension:temporal_peak_scalar"
            @test sidecar["generator"] == "scripts/lib/multivar_optimization.jl"
        end
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

    @testset "Scalar variable extension is promoted for bounded scalar search" begin
        @test :cubic_phase_scalar in registered_variable_extension_kinds(:single_mode)
        @test :cubic_phase_scalar in registered_variable_kinds(:single_mode)
        contract = variable_contract(:cubic_phase_scalar, :single_mode)
        @test contract.backend == :scalar_phase_extension
        @test contract.execution == :executable
        @test :temporal_peak_scalar in contract.compatible_objectives

        row = validate_variable_extension_contract(contract)
        @test row.valid
        @test row.promotable
        @test isempty(row.blockers)
        @test isempty(row.errors)

        spec = load_experiment_spec("research_engine_temporal_peak_cubic_phase_extension_smoke")
        @test spec.objective.kind == :temporal_peak_scalar
        @test spec.controls.variables == (:cubic_phase_scalar,)
        @test experiment_execution_mode(spec) == :scalar_search
        @test validate_experiment_spec(spec) isa NamedTuple
    end

    @testset "Vector variable extension is promoted for derivative-free vector search" begin
        @test :poly_phase_vector in registered_variable_extension_kinds(:single_mode)
        @test :poly_phase_vector in registered_variable_kinds(:single_mode)
        contract = variable_contract(:poly_phase_vector, :single_mode)
        @test contract.backend == :vector_phase_extension
        @test contract.execution == :executable
        @test contract.dimension == 2
        @test :temporal_peak_scalar in contract.compatible_objectives

        row = validate_variable_extension_contract(contract)
        @test row.valid
        @test row.promotable
        @test isempty(row.blockers)
        @test isempty(row.errors)

        spec = load_experiment_spec("research_engine_temporal_peak_poly_phase_vector_smoke")
        @test spec.objective.kind == :temporal_peak_scalar
        @test spec.controls.variables == (:poly_phase_vector,)
        @test spec.solver.kind == :nelder_mead
        @test experiment_execution_mode(spec) == :vector_search
        @test validate_experiment_spec(spec) isa NamedTuple
    end

    @testset "Vector field-control extension is promoted for derivative-free vector search" begin
        @test :phase_amp_energy_control in registered_variable_extension_kinds(:single_mode)
        @test :phase_amp_energy_control in registered_variable_kinds(:single_mode)
        contract = variable_contract(:phase_amp_energy_control, :single_mode)
        @test contract.backend == :vector_control_extension
        @test contract.execution == :executable
        @test contract.dimension == 3
        @test :temporal_peak_scalar in contract.compatible_objectives
        @test :amplitude_mask in contract.artifact_hooks
        @test :energy_scale in contract.artifact_hooks
        @test :energy_throughput in contract.artifact_hooks

        row = validate_variable_extension_contract(contract)
        @test row.valid
        @test row.promotable
        @test isempty(row.blockers)
        @test isempty(row.errors)

        spec = load_experiment_spec("research_engine_temporal_peak_phase_amp_energy_control_smoke")
        @test spec.objective.kind == :temporal_peak_scalar
        @test spec.controls.variables == (:phase_amp_energy_control,)
        @test spec.solver.kind == :nelder_mead
        @test experiment_execution_mode(spec) == :vector_search
        @test validate_experiment_spec(spec) isa NamedTuple

        layout = control_layout_plan(spec)
        @test layout.total_length == "3"
        block = only(filter(block -> block.name == :phase_amp_energy_control, layout.blocks))
        @test block.shape == "vector[3]"
        @test :amplitude_mask in block.artifact_hooks
        @test :energy_scale in block.artifact_hooks

        plan = experiment_artifact_plan(spec)
        hooks = Tuple(request.hook for request in plan.hooks)
        @test :standard_image_set in hooks
        @test :amplitude_mask in hooks
        @test :energy_scale in hooks
        @test :energy_throughput in hooks
        @test :exploratory_summary in hooks
        @test :exploratory_overview in hooks
        @test plan.implemented

        builder = _load_scalar_variable_builder(contract)
        sim = Dict{String,Any}("Nt" => 16, "M" => 1, "Δt" => 0.01)
        uω0 = ones(ComplexF64, 16, 1)
        state = _vector_control_state(:phase_amp_energy_control, [1.0, 0.5, 0.2], uω0, sum(abs2, uω0), sim, 16, 1, builder)
        @test state.scalar_controls["phase_amp_energy_control_phase_coeff"] == 1.0
        @test state.scalar_controls["phase_amp_energy_control_amplitude_tilt"] == 0.5
        @test state.scalar_controls["phase_amp_energy_control_energy_log_scale"] == 0.2
        @test state.scalar_controls["phase_amp_energy_control_energy_scale"] ≈ exp(0.2)
        @test maximum(abs.(state.φ)) ≈ 1.0
        @test minimum(state.A) > 0.0
        @test state.A != ones(16, 1)
        @test state.diagnostics[:extension_variable] == :phase_amp_energy_control
        @test state.diagnostics[:phase_amp_energy_control_energy_scale] ≈ exp(0.2)
    end

    @testset "Extension validation commands remain green without executing science" begin
        objective_report = run_experiment_main(["--validate-objectives"])
        variable_report = run_experiment_main(["--validate-variables"])
        @test objective_report.invalid == 0
        @test objective_report.promotable >= 1
        @test variable_report.invalid == 0
        @test variable_report.promotable >= 3
        @test variable_report.total >= 5
    end
end
