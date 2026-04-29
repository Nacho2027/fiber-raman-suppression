import io
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

from fiber_research_engine import app
from fiber_research_engine.cli import (
    INDEX_RESULTS,
    LAB_READY,
    RUN_EXPERIMENT,
    RUN_EXPERIMENT_SWEEP,
    SCAFFOLD_OBJECTIVE,
    SCAFFOLD_VARIABLE,
)


class FiberlabAppTests(unittest.TestCase):
    def _run_app(self, argv):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            status = app.main(argv)
        return status, stdout.getvalue(), stderr.getvalue()

    def test_playbook_command_prints_researcher_workflow_without_backend(self):
        status, stdout, stderr = self._run_app(["playbook"])

        self.assertEqual(status, 0)
        self.assertEqual(stderr, "")
        self.assertIn("Fiber Research Playground Playbook", stdout)
        self.assertIn("./fiberlab explore list", stdout)
        self.assertIn("docs/guides/researcher-playbook.md", stdout)
        self.assertIn("config-only", stdout)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_plan_command_delegates_to_experiment_dry_run(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "dry plan\n"
        run_mock.return_value.stderr = ""

        status, stdout, stderr = self._run_app(
            ["--repo-root", "/tmp/repo", "--threads", "2", "plan", "research_engine_temporal_width_smoke"]
        )

        self.assertEqual(status, 0)
        self.assertEqual(stdout, "dry plan\n")
        self.assertEqual(stderr, "")
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[-3:], (RUN_EXPERIMENT, "--dry-run", "research_engine_temporal_width_smoke"))
        self.assertEqual(called_args[2], "2")
        self.assertEqual(run_mock.call_args.kwargs["cwd"], Path("/tmp/repo"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_compute_plan_command_delegates_to_provider_neutral_backend(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Compute plan\n"
        run_mock.return_value.stderr = ""

        status, stdout, _ = self._run_app(["compute-plan", "smf28_longfiber_phase_poc"])

        self.assertEqual(status, 0)
        self.assertEqual(stdout, "Compute plan\n")
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--compute-plan", "smf28_longfiber_phase_poc"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_check_config_command_delegates_to_research_check_backend(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "Research Config Check\n"
        run_mock.return_value.stderr = ""

        status, stdout, _ = self._run_app(["check", "config", "research_engine_gain_tilt_smoke"])

        self.assertEqual(status, 0)
        self.assertEqual(stdout, "Research Config Check\n")
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--check", "research_engine_gain_tilt_smoke"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_explore_commands_route_to_playground_backend(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "explore\n"
        run_mock.return_value.stderr = ""

        status, stdout, _ = self._run_app(["explore", "list"])
        self.assertEqual(status, 0)
        self.assertEqual(stdout, "explore\n")
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "--list"))

        status, stdout, _ = self._run_app(["explore", "plan", "grin50_mmf_phase_sum_poc"])
        self.assertEqual(status, 0)
        self.assertEqual(stdout, "explore\n")
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--explore-plan", "grin50_mmf_phase_sum_poc"))

        status, stdout, _ = self._run_app(
            ["explore", "run", "research_engine_gain_tilt_smoke", "--local-smoke", "--dry-run"]
        )
        self.assertEqual(status, 0)
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], RUN_EXPERIMENT)
        self.assertIn("--explore-run", called_args)
        self.assertIn("--local-smoke", called_args)
        self.assertIn("--dry-run", called_args)
        self.assertIn("research_engine_gain_tilt_smoke", called_args)

        status, stdout, _ = self._run_app(
            [
                "explore",
                "compare",
                "results/raman/smoke",
                "--top",
                "3",
                "--objective",
                "gain_tilt",
                "--complete-images",
            ]
        )
        self.assertEqual(status, 0)
        compare_args = run_mock.call_args.args[0]
        self.assertEqual(compare_args[4], INDEX_RESULTS)
        self.assertIn("--compare", compare_args)
        self.assertIn("--top", compare_args)
        self.assertIn("3", compare_args)
        self.assertIn("--objective", compare_args)
        self.assertIn("gain_tilt", compare_args)
        self.assertIn("--complete-images", compare_args)
        self.assertIn("results/raman/smoke", compare_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_run_and_latest_commands_route_to_same_experiment_backend(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "ok\n"
        run_mock.return_value.stderr = ""

        self._run_app(["run", "research_engine_poc"])
        self.assertEqual(run_mock.call_args.args[0][-2:], (RUN_EXPERIMENT, "research_engine_poc"))

        self._run_app(["latest", "research_engine_poc"])
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT, "--latest", "research_engine_poc"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_sweep_plan_run_and_latest_route_to_sweep_backend(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "ok\n"
        run_mock.return_value.stderr = ""

        self._run_app(["sweep", "plan", "smf28_power_micro_sweep"])
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT_SWEEP, "--dry-run", "smf28_power_micro_sweep"))

        self._run_app(["sweep", "run", "smf28_power_micro_sweep"])
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT_SWEEP, "--execute", "smf28_power_micro_sweep"))

        self._run_app(["sweep", "latest", "smf28_power_micro_sweep"])
        self.assertEqual(run_mock.call_args.args[0][-3:], (RUN_EXPERIMENT_SWEEP, "--latest", "smf28_power_micro_sweep"))

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_ready_latest_supports_export_requirement(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "ready\n"
        run_mock.return_value.stderr = ""

        status, stdout, _ = self._run_app(["ready", "latest", "research_engine_export_smoke", "--require-export"])

        self.assertEqual(status, 0)
        self.assertEqual(stdout, "ready\n")
        called_args = run_mock.call_args.args[0]
        self.assertEqual(called_args[4], LAB_READY)
        self.assertIn("--latest", called_args)
        self.assertIn("research_engine_export_smoke", called_args)
        self.assertIn("--require-export", called_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_scaffold_commands_pass_research_metadata(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "created\n"
        run_mock.return_value.stderr = ""

        self._run_app(
            [
                "scaffold",
                "objective",
                "pulse_compression",
                "--regime",
                "single_mode",
                "--description",
                "Temporal objective.",
                "--variables",
                "phase,amplitude",
                "--regularizers",
                "gdd,boundary",
                "--dir",
                "/tmp/objectives",
                "--force",
            ]
        )
        objective_args = run_mock.call_args.args[0]
        self.assertEqual(objective_args[4], SCAFFOLD_OBJECTIVE)
        self.assertIn("phase,amplitude", objective_args)
        self.assertIn("gdd,boundary", objective_args)
        self.assertIn("--force", objective_args)

        self._run_app(
            [
                "scaffold",
                "variable",
                "mode_weights",
                "--units",
                "normalized",
                "--bounds",
                "simplex",
                "--parameterizations",
                "modal_basis",
                "--objectives",
                "mmf_sum,temporal_width",
            ]
        )
        variable_args = run_mock.call_args.args[0]
        self.assertEqual(variable_args[4], SCAFFOLD_VARIABLE)
        self.assertIn("mode_weights", variable_args)
        self.assertIn("normalized", variable_args)
        self.assertIn("simplex", variable_args)
        self.assertIn("modal_basis", variable_args)
        self.assertIn("mmf_sum,temporal_width", variable_args)

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_validate_command_runs_all_safe_validation_surfaces(self, run_mock):
        run_mock.return_value.returncode = 0
        run_mock.return_value.stdout = "validated\n"
        run_mock.return_value.stderr = ""

        status, stdout, _ = self._run_app(["validate"])

        self.assertEqual(status, 0)
        self.assertEqual(run_mock.call_count, 4)
        self.assertEqual(stdout, "validated\nvalidated\nvalidated\nvalidated\n")

    @patch("fiber_research_engine.cli.subprocess.run")
    def test_failed_backend_command_returns_nonzero_and_prints_stderr(self, run_mock):
        run_mock.return_value.returncode = 2
        run_mock.return_value.stdout = ""
        run_mock.return_value.stderr = "bad config"

        status, stdout, stderr = self._run_app(["plan", "bad_config"])

        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("bad config", stderr)


if __name__ == "__main__":
    unittest.main()
