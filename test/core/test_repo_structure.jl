using Test
using JSON3
using FiberLab

@testset "Repository structure" begin
    scripts_root = joinpath(@__DIR__, "..", "..", "scripts")
    test_root = joinpath(@__DIR__, "..")
    project_root = normpath(joinpath(test_root, ".."))

    loose_files = sort(filter(name -> isfile(joinpath(scripts_root, name)), readdir(scripts_root)))
    @test loose_files == ["README.md"]

    expected_script_dirs = [
        "canonical",
        "dev",
        "lib",
        "workflows",
    ]
    for dir in expected_script_dirs
        @test isdir(joinpath(scripts_root, dir))
    end

    canonical_files = [
        "AGENTS.md",
        "README.md",
        "llms.txt",
        "fiberlab",
        "docs/README.md",
        "docs/research-verdicts.md",
        "agent-docs/README.md",
        "agent-docs/current-agent-context/INDEX.md",
        "docs/architecture/repo-navigation.md",
        "docs/guides/supported-workflows.md",
        "docs/guides/installation.md",
        "results/README.md",
    ]
    for rel in canonical_files
        @test isfile(joinpath(project_root, rel))
    end

    @test !isdir(joinpath(project_root, "python"))
    @test !isfile(joinpath(project_root, "pyproject.toml"))
    @test !isfile(joinpath(project_root, ".stignore"))
    @test !isdir(joinpath(project_root, "docs", "planning-history"))
    legacy_runs = joinpath(project_root, "configs", "runs")
    @test !isdir(legacy_runs) ||
        isempty(filter(name -> endswith(name, ".toml"), readdir(legacy_runs)))
    @test !isfile(joinpath(scripts_root, "workflows", "run_comparison.jl"))
    @test !isfile(joinpath(scripts_root, "workflows", "optimize_raman.jl"))
    @test !isfile(joinpath(scripts_root, "ops", "parallel_research_lane.sh"))
    for rel in (
        "configs/sweeps/smf28_hnlf_default.toml",
        "docs/reference/julia-file-inventory.md",
        "scripts/canonical/generate_reports.jl",
        "scripts/canonical/index_telemetry.jl",
        "scripts/canonical/regenerate_standard_images.jl",
        "scripts/canonical/run_exploration_contract.jl",
        "scripts/canonical/run_sweep.jl",
        "scripts/lib/amplitude_optimization.jl",
        "scripts/lib/exploration_contract_runner.jl",
        "scripts/lib/longfiber_checkpoint.jl",
        "scripts/lib/longfiber_setup.jl",
        "scripts/lib/sharpness_optimization.jl",
        "scripts/lib/telemetry_index.jl",
        "scripts/ops/README.md",
        "scripts/ops/run_with_telemetry.sh",
        "scripts/workflows/generate_presentation_figures.jl",
        "scripts/workflows/generate_sweep_reports.jl",
        "scripts/workflows/index_telemetry.jl",
        "scripts/workflows/polish_output_format.jl",
        "scripts/workflows/regenerate_standard_images.jl",
        "scripts/workflows/run_sweep.jl",
        "test/core/test_exploration_contract_runner.jl",
    )
        @test !ispath(joinpath(project_root, rel))
    end

    source_roots = ["configs", "lab_extensions", "scripts", "src", "test"]
    source_sync_conflicts = String[]
    for root_name in source_roots
        root_path = joinpath(project_root, root_name)
        isdir(root_path) || continue
        for (root, _, files) in walkdir(root_path)
            for file in files
                occursin("sync-conflict", file) &&
                    push!(source_sync_conflicts, relpath(joinpath(root, file), project_root))
            end
        end
    end
    @test isempty(sort!(source_sync_conflicts))

    package_script_includes = String[]
    package_root = joinpath(project_root, "src")
    for (root, _, files) in walkdir(package_root)
        for file in files
            endswith(file, ".jl") || continue
            path = joinpath(root, file)
            occursin(r"include\([^\n]*scripts", read(path, String)) &&
                push!(package_script_includes, relpath(path, project_root))
        end
    end
    @test isempty(sort!(package_script_includes))

    lib_workflow_includes = String[]
    for file in readdir(joinpath(scripts_root, "lib"))
        endswith(file, ".jl") || continue
        path = joinpath(scripts_root, "lib", file)
        occursin(r"include\([^\n]*workflows", read(path, String)) &&
            push!(lib_workflow_includes, relpath(path, project_root))
    end
    @test isempty(sort!(lib_workflow_includes))

    for adapter in ("visualization.jl", "standard_images.jl")
        text = read(joinpath(scripts_root, "lib", adapter), String)
        @test !occursin(r"include\([^\n]*src[^\n]*fiberlab", text)
        @test occursin("FiberLab.", text)
    end

    readme = read(joinpath(project_root, "README.md"), String)
    @test occursin("Julia-first", readme)
    @test occursin("Python is not a supported API surface", readme)

    dockerfile = read(joinpath(project_root, "Dockerfile"), String)
    dockerignore = read(joinpath(project_root, ".dockerignore"), String)
    @test !occursin("pyproject.toml", dockerfile)
    @test !occursin("COPY python", dockerfile)
    @test !occursin("pip install", dockerfile)
    @test occursin("Pkg.instantiate", dockerfile)
    @test !occursin(".burst-sync", dockerignore)
    for local_path in (
        ".env", "LocalPreferences.toml", "lab-local/", "examples/outputs/",
        ".bg-shell/", ".pytest_cache/",
    )
        @test occursin(local_path, dockerignore)
    end

    notebook_code = Dict{String,String}()
    for name in (
        "02_multivariable_controls.ipynb",
        "03_multimode_mode_sum.ipynb",
        "04_reduced_basis_phase.ipynb",
    )
        notebook = JSON3.read(read(joinpath(project_root, "examples", name), String))
        code = join(String.(Iterators.flatten(
            cell.source for cell in notebook.cells if String(cell.cell_type) == "code"
        )))
        notebook_code[name] = code
        @test !occursin("maturity = :supported", code)
    end

    multimode_notebook = JSON3.read(read(
        joinpath(project_root, "examples", "03_multimode_mode_sum.ipynb"),
        String,
    ))
    multimode_cells = [cell for cell in multimode_notebook.cells
                       if String(cell.cell_type) == "code"]
    setup_module = Module(:FiberLabMultimodeNotebookSmoke)
    Core.eval(setup_module, :(using FiberLab))
    Base.include_string(
        setup_module,
        join(String.(multimode_cells[2].source)),
        "examples/03_multimode_mode_sum.ipynb:setup",
    )
    notebook_problem = getfield(setup_module, :problem)
    @test FiberLab.fiber_model(notebook_problem) isa FiberLab.AdjointModel

    fiberlab = joinpath(project_root, "fiberlab")
    @test success(pipeline(`bash -n $fiberlab`, stdout=devnull, stderr=devnull))

    missing_canonical_includes = String[]
    for name in readdir(joinpath(scripts_root, "canonical"))
        endswith(name, ".jl") || continue
        path = joinpath(scripts_root, "canonical", name)
        text = read(path, String)
        for match in eachmatch(
            r"include\(joinpath\(@__DIR__, \"\.\.\", \"([^\"]+)\", \"([^\"]+)\"\)\)",
            text,
        )
            target = joinpath(scripts_root, String(match.captures[1]), String(match.captures[2]))
            isfile(target) || push!(missing_canonical_includes, relpath(target, project_root))
        end
    end
    @test isempty(sort!(missing_canonical_includes))
end
