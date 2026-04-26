import unittest
from pathlib import Path
from unittest.mock import patch

from fiber_research_engine.cli import (
    INDEX_RESULTS,
    REFINE_AMP_ON_PHASE,
    RUN_EXPERIMENT,
    RUN_EXPERIMENT_SWEEP,
    capabilities,
    dry_run_amp_on_phase_refinement,
    dry_run_experiment,
    dry_run_sweep,
    index_results,
    index_results_csv,
    julia_cli_args,
    refine_amp_on_phase,
    run_julia_cli,
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
    def test_dry_run_sweep_delegates_to_sweep_cli(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "sweep plan\n"
        run_mock.return_value.stderr = ""

        result = dry_run_sweep("my_sweep", repo_root=Path("/tmp/repo"))

        self.assertEqual(result.stdout, "sweep plan\n")
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[-3:], (RUN_EXPERIMENT_SWEEP, "--dry-run", "my_sweep"))

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
    def test_failed_command_raises_when_check_enabled(self, run_mock):
        run_mock.return_value.returncode = 2
        run_mock.return_value.stdout = ""
        run_mock.return_value.stderr = "bad config"

        with self.assertRaisesRegex(RuntimeError, "bad config"):
            run_julia_cli(RUN_EXPERIMENT, "--dry-run", "bad", repo_root=Path("/tmp/repo"))


if __name__ == "__main__":
    unittest.main()
