import unittest
from pathlib import Path
from unittest.mock import patch

from fiber_research_engine.cli import (
    INDEX_RESULTS,
    LAB_READY,
    REFINE_AMP_ON_PHASE,
    RUN_EXPERIMENT,
    RUN_EXPERIMENT_SWEEP,
    SCAFFOLD_OBJECTIVE,
    SCAFFOLD_VARIABLE,
    artifact_plan,
    capabilities,
    compute_plan,
    control_layout,
    dry_run_amp_on_phase_refinement,
    dry_run_experiment,
    explore_compare,
    explore_list,
    explore_plan,
    explore_run,
    dry_run_sweep,
    execute_sweep,
    index_results,
    index_results_csv,
    julia_cli_args,
    lab_ready_config,
    lab_ready_latest,
    lab_ready_run,
    latest_experiment,
    latest_sweep,
    refine_amp_on_phase,
    run_julia_cli,
    scaffold_objective,
    scaffold_variable,
    validate_objective_extensions,
    validate_variable_extensions,
    variables,
)


class FiberResearchEngineCliTests(unittest.TestCase):
    def test_julia_cli_args_uses_project_and_threads(self):
        args = julia_cli_args(RUN_EXPERIMENT, "--dry-run", "research_engine_poc", threads="4")
        self.assertEqual(
            args,
            (
                "julia",
                "-t",
                "4",
                "--project=.",
                RUN_EXPERIMENT,
                "--dry-run",
                "research_engine_poc",
            ),
        )

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_dry_run_experiment_delegates_to_julia_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "plan\n"
        run_mock.return_value.stderr = ""

        result = dry_run_experiment("my_config", repo_root=Path("/tmp/repo"))

        self.assertEqual(result.stdout, "plan\n")
        run_mock.assert_called_once()
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[-3:], (RUN_EXPERIMENT, "--dry-run", "my_config"))
        self.assertEqual(run_mock.call_args.kwargs["cwd"], Path("/tmp/repo"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_explore_plan_and_run_delegate_to_explore_backend(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "explore\n"
        run_mock.return_value.stderr = ""

        plan = explore_plan("smf28_phase_amplitude_energy_poc", repo_root=Path("/tmp/repo"))
        self.assertEqual(plan.stdout, "explore\n")
        self.assertEqual(
            run_mock.call_args.args[0][-3:],
            (RUN_EXPERIMENT, "--explore-plan", "smf28_phase_amplitude_energy_poc"),
        )

        explore_run(
            "research_engine_gain_tilt_smoke",
            local_smoke=True,
            dry_run=True,
            repo_root=Path("/tmp/repo"),
        )
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], RUN_EXPERIMENT)
        self.assertIn("--explore-run", called_args)
        self.assertIn("--local-smoke", called_args)
        self.assertIn("--dry-run", called_args)
        self.assertIn("research_engine_gain_tilt_smoke", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_explore_list_and_compare_route_to_playground_discovery(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "explore list\n"
        run_mock.return_value.stderr = ""

        listing = explore_list(repo_root=Path("/tmp/repo"))
        self.assertEqual(listing.stdout, "explore list\n")
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "--list"))

        explore_compare(
            "results/raman/smoke",
            top=5,
            objective="gain_tilt",
            contains="smoke",
            complete_images=True,
            repo_root=Path("/tmp/repo"),
        )
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], INDEX_RESULTS)
        self.assertIn("--compare", called_args)
        self.assertIn("--top", called_args)
        self.assertIn("5", called_args)
        self.assertIn("--objective", called_args)
        self.assertIn("gain_tilt", called_args)
        self.assertIn("--contains", called_args)
        self.assertIn("smoke", called_args)
        self.assertIn("--complete-images", called_args)
        self.assertIn("results/raman/smoke", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_dry_run_sweep_delegates_to_sweep_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "sweep plan\n"
        run_mock.return_value.stderr = ""

        result = dry_run_sweep("my_sweep", repo_root=Path("/tmp/repo"))

        self.assertEqual(result.stdout, "sweep plan\n")
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[-3:], (RUN_EXPERIMENT_SWEEP, "--dry-run", "my_sweep"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_latest_experiment_delegates_to_latest_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "latest run\n"
        run_mock.return_value.stderr = ""

        result = latest_experiment("my_config", repo_root=Path("/tmp/repo"))

        self.assertEqual(result.stdout, "latest run\n")
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--latest", "my_config"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_execute_sweep_delegates_to_sweep_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "running sweep\n"
        run_mock.return_value.stderr = ""

        result = execute_sweep("my_sweep", repo_root=Path("/tmp/repo"))

        self.assertEqual(result.stdout, "running sweep\n")
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT_SWEEP, "--execute", "my_sweep"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_latest_sweep_delegates_to_sweep_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "latest sweep\n"
        run_mock.return_value.stderr = ""

        result = latest_sweep("my_sweep", repo_root=Path("/tmp/repo"))

        self.assertEqual(result.stdout, "latest sweep\n")
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT_SWEEP, "--latest", "my_sweep"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_dry_run_amp_on_phase_refinement_delegates_to_canonical_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "amp plan\n"
        run_mock.return_value.stderr = ""

        result = dry_run_amp_on_phase_refinement(
            tag="trial",
            L=2.0,
            P=0.30,
            delta_bound=0.10,
            export=True,
            repo_root=Path("/tmp/repo"),
        )

        self.assertEqual(result.stdout, "amp plan\n")
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], REFINE_AMP_ON_PHASE)
        self.assertIn("--dry-run", called_args)
        self.assertIn("--export", called_args)
        self.assertIn("--tag", called_args)
        self.assertIn("trial", called_args)
        self.assertIn("--L", called_args)
        self.assertIn("2.0", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_amp_on_phase_refinement_execute_path_has_no_dry_run_flag(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "running\n"
        run_mock.return_value.stderr = ""

        refine_amp_on_phase(tag="trial", amp_iter=3, repo_root=Path("/tmp/repo"))

        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], REFINE_AMP_ON_PHASE)
        self.assertNotIn("--dry-run", called_args)
        self.assertIn("--amp-iter", called_args)
        self.assertIn("3", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_capabilities_uses_safe_cli_path(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Experiment capabilities\n"
        run_mock.return_value.stderr = ""

        result = capabilities(repo_root=Path("/tmp/repo"))

        self.assertIn("Experiment capabilities", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "--capabilities"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_validate_objective_extensions_uses_cli_checklist(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Objective extension validation\n"
        run_mock.return_value.stderr = ""

        result = validate_objective_extensions(repo_root=Path("/tmp/repo"))

        self.assertIn("Objective extension validation", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "--validate-objectives"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_variables_uses_safe_cli_path(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Built-in optimization variable contracts\n"
        run_mock.return_value.stderr = ""

        result = variables(repo_root=Path("/tmp/repo"))

        self.assertIn("variable contracts", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "--variables"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_validate_variable_extensions_uses_cli_checklist(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Variable extension validation\n"
        run_mock.return_value.stderr = ""

        result = validate_variable_extensions(repo_root=Path("/tmp/repo"))

        self.assertIn("Variable extension validation", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "--validate-variables"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_control_layout_uses_safe_cli_path(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Control layout\n"
        run_mock.return_value.stderr = ""

        result = control_layout("my_config", repo_root=Path("/tmp/repo"))

        self.assertIn("Control layout", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--control-layout", "my_config"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_artifact_plan_uses_safe_cli_path(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Artifact plan\n"
        run_mock.return_value.stderr = ""

        result = artifact_plan("my_config", repo_root=Path("/tmp/repo"))

        self.assertIn("Artifact plan", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--artifact-plan", "my_config"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_compute_plan_uses_safe_cli_path(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Compute plan\n"
        run_mock.return_value.stderr = ""

        result = compute_plan("my_config", repo_root=Path("/tmp/repo"))

        self.assertIn("Compute plan", result.stdout)
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--compute-plan", "my_config"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_scaffold_objective_delegates_to_canonical_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Objective extension scaffold created\n"
        run_mock.return_value.stderr = ""

        result = scaffold_objective(
            "mode_coupling_planning",
            regime="single_mode",
            directory=Path("/tmp/objectives"),
            description="Mode coupling research objective.",
            variables=("phase", "amplitude"),
            regularizers=("gdd", "boundary"),
            force=True,
            repo_root=Path("/tmp/repo"),
        )

        self.assertIn("scaffold", result.stdout)
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], SCAFFOLD_OBJECTIVE)
        self.assertIn("mode_coupling_planning", called_args)
        self.assertIn("--regime", called_args)
        self.assertIn("single_mode", called_args)
        self.assertIn("--dir", called_args)
        self.assertIn("/tmp/objectives", called_args)
        self.assertIn("--description", called_args)
        self.assertIn("Mode coupling research objective.", called_args)
        self.assertIn("--variables", called_args)
        self.assertIn("phase,amplitude", called_args)
        self.assertIn("--regularizers", called_args)
        self.assertIn("gdd,boundary", called_args)
        self.assertIn("--force", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_scaffold_variable_delegates_to_canonical_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Variable extension scaffold created\n"
        run_mock.return_value.stderr = ""

        result = scaffold_variable(
            "gain_tilt_planning",
            regime="single_mode",
            directory=Path("/tmp/variables"),
            description="Gain tilt research variable.",
            units="dB",
            bounds="box constrained",
            parameterizations=("full_grid",),
            objectives=("raman_band",),
            force=True,
            repo_root=Path("/tmp/repo"),
        )

        self.assertIn("scaffold", result.stdout)
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], SCAFFOLD_VARIABLE)
        self.assertIn("gain_tilt_planning", called_args)
        self.assertIn("--regime", called_args)
        self.assertIn("single_mode", called_args)
        self.assertIn("--dir", called_args)
        self.assertIn("/tmp/variables", called_args)
        self.assertIn("--description", called_args)
        self.assertIn("Gain tilt research variable.", called_args)
        self.assertIn("--units", called_args)
        self.assertIn("dB", called_args)
        self.assertIn("--bounds", called_args)
        self.assertIn("box constrained", called_args)
        self.assertIn("--parameterizations", called_args)
        self.assertIn("full_grid", called_args)
        self.assertIn("--objectives", called_args)
        self.assertIn("raman_band", called_args)
        self.assertIn("--force", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_index_results_delegates_to_shared_julia_index(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Results Index\n"
        run_mock.return_value.stderr = ""

        result = index_results("results/raman/sweeps/front_layer", repo_root=Path("/tmp/repo"))

        self.assertIn("# Results Index", result.stdout)
        called_args = run_mock.call_args.args[0]
        self.assertEqual(
            called_args[-2:],
            (INDEX_RESULTS, "results/raman/sweeps/front_layer"),
        )

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_index_results_supports_filters_and_csv(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "kind,id\n"
        run_mock.return_value.stderr = ""

        result = index_results_csv(
            "results/raman",
            kind="run",
            config_id="smf28_phase_smoke",
            regime="single_mode",
            objective="raman_band",
            solver="lbfgs",
            fiber="SMF-28",
            complete_images=True,
            lab_ready=True,
            export_ready=True,
            contains="power",
            repo_root=Path("/tmp/repo"),
        )

        self.assertEqual(result.stdout, "kind,id\n")
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], INDEX_RESULTS)
        self.assertIn("--csv", called_args)
        self.assertIn("--kind", called_args)
        self.assertIn("run", called_args)
        self.assertIn("--config-id", called_args)
        self.assertIn("smf28_phase_smoke", called_args)
        self.assertIn("--regime", called_args)
        self.assertIn("single_mode", called_args)
        self.assertIn("--objective", called_args)
        self.assertIn("raman_band", called_args)
        self.assertIn("--solver", called_args)
        self.assertIn("lbfgs", called_args)
        self.assertIn("--fiber", called_args)
        self.assertIn("SMF-28", called_args)
        self.assertIn("--complete-images", called_args)
        self.assertIn("--lab-ready", called_args)
        self.assertIn("--export-ready", called_args)
        self.assertIn("--contains", called_args)
        self.assertIn("power", called_args)
        self.assertEqual(called_args[-1], "results/raman")

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_index_results_supports_comparison_ranking(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Results Comparison\n"
        run_mock.return_value.stderr = ""

        result = index_results(
            "results/raman",
            compare=True,
            lab_ready=True,
            top=3,
            repo_root=Path("/tmp/repo"),
        )

        self.assertIn("# Results Comparison", result.stdout)
        called_args = run_mock.call_args.args[0]
        self.assertIn("--compare", called_args)
        self.assertIn("--lab-ready", called_args)
        self.assertIn("--top", called_args)
        self.assertIn("3", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_index_results_supports_sweep_comparison(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Sweep Comparison\n"
        run_mock.return_value.stderr = ""

        result = index_results(
            "results/raman/sweeps/front_layer",
            compare_sweeps=True,
            csv=True,
            top=2,
            repo_root=Path("/tmp/repo"),
        )

        self.assertIn("# Sweep Comparison", result.stdout)
        called_args = run_mock.call_args.args[0]
        self.assertIn("--compare-sweeps", called_args)
        self.assertIn("--csv", called_args)
        self.assertIn("--top", called_args)
        self.assertIn("2", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_lab_ready_config_delegates_to_canonical_gate(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Lab Readiness Gate\n"
        run_mock.return_value.stderr = ""

        result = lab_ready_config("research_engine_smoke", repo_root=Path("/tmp/repo"))

        self.assertIn("Lab Readiness Gate", result.stdout)
        self.assertEqual(
            run_mock.call_args.args[0][-3:],
            (LAB_READY, "--config", "research_engine_smoke"),
        )

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_lab_ready_run_supports_export_requirement(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Lab Readiness Gate\n"
        run_mock.return_value.stderr = ""

        lab_ready_run("results/run", require_export=True, repo_root=Path("/tmp/repo"))

        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], LAB_READY)
        self.assertIn("--run", called_args)
        self.assertIn("results/run", called_args)
        self.assertIn("--require-export", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_lab_ready_latest_delegates_to_latest_gate(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "# Lab Readiness Gate\n"
        run_mock.return_value.stderr = ""

        lab_ready_latest("research_engine_poc", repo_root=Path("/tmp/repo"))

        self.assertEqual(
            run_mock.call_args.args[0][-3:],
            (LAB_READY, "--latest", "research_engine_poc"),
        )

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_failed_command_raises_when_check_enabled(self, run_mock):
        run_mock.return_value.returncode = 2
        run_mock.return_value.stdout = ""
        run_mock.return_value.stderr = "bad config"

        with self.assertRaisesRegex(RuntimeError, "bad config"):
            run_julia_cli(RUN_EXPERIMENT, "--dry-run", "bad", repo_root=Path("/tmp/repo"))


if __name__ == "__main__":
    unittest.main()
