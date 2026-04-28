"""Researcher-facing command line app for the fiber research engine.

This module is intentionally a thin command router. Julia remains the single
source of truth for validation, physics dispatch, solver execution, and
artifact contracts.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Callable, Iterable

from . import cli as engine


def _split_csv(value: str | None) -> tuple[str, ...] | None:
    if value is None:
        return None
    parts = tuple(part.strip() for part in value.split(",") if part.strip())
    return parts if parts else None


def _common_kwargs(args: argparse.Namespace) -> dict[str, object]:
    return {
        "repo_root": Path(args.repo_root),
        "threads": args.threads,
    }


def _emit(result: engine.CommandResult) -> int:
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def _call(args: argparse.Namespace, func: Callable[..., engine.CommandResult], *values: object) -> int:
    result = func(*values, **_common_kwargs(args))
    return _emit(result)


def _validate(args: argparse.Namespace) -> int:
    checks: Iterable[Callable[..., engine.CommandResult]] = (
        engine.validate_all_experiments,
        engine.validate_all_sweeps,
        engine.validate_objective_extensions,
        engine.validate_variable_extensions,
    )
    status = 0
    for check in checks:
        status = max(status, _emit(check(**_common_kwargs(args))))
    return status


def _extensions(args: argparse.Namespace) -> int:
    status = _emit(engine.validate_objective_extensions(**_common_kwargs(args)))
    status = max(status, _emit(engine.validate_variable_extensions(**_common_kwargs(args))))
    return status


def _objectives(args: argparse.Namespace) -> int:
    if args.validate:
        return _call(args, engine.validate_objective_extensions)
    return _call(args, engine.objectives)


def _variables(args: argparse.Namespace) -> int:
    if args.validate:
        return _call(args, engine.validate_variable_extensions)
    return _call(args, engine.variables)


def _ready(args: argparse.Namespace) -> int:
    if args.ready_command == "config":
        return _call(args, engine.lab_ready_config, args.spec)
    if args.ready_command == "latest":
        result = engine.lab_ready_latest(
            args.spec,
            require_export=args.require_export,
            **_common_kwargs(args),
        )
        return _emit(result)
    if args.ready_command == "run":
        result = engine.lab_ready_run(
            args.path,
            require_export=args.require_export,
            **_common_kwargs(args),
        )
        return _emit(result)
    raise ValueError(f"Unknown ready command: {args.ready_command}")


def _sweep(args: argparse.Namespace) -> int:
    if args.sweep_command == "list":
        return _call(args, engine.list_sweeps)
    if args.sweep_command == "validate":
        return _call(args, engine.validate_all_sweeps)
    if args.sweep_command == "plan":
        return _call(args, engine.dry_run_sweep, args.spec)
    if args.sweep_command == "run":
        return _call(args, engine.execute_sweep, args.spec)
    if args.sweep_command == "latest":
        return _call(args, engine.latest_sweep, args.spec)
    raise ValueError(f"Unknown sweep command: {args.sweep_command}")


def _explore(args: argparse.Namespace) -> int:
    if args.explore_command == "list":
        return _call(args, engine.explore_list)
    if args.explore_command == "plan":
        return _call(args, engine.explore_plan, args.spec)
    if args.explore_command == "run":
        result = engine.explore_run(
            args.spec,
            local_smoke=args.local_smoke,
            heavy_ok=args.heavy_ok,
            dry_run=args.dry_run,
            **_common_kwargs(args),
        )
        return _emit(result)
    if args.explore_command == "compare":
        result = engine.explore_compare(
            *args.roots,
            csv=args.csv,
            kind=args.kind,
            config_id=args.config_id,
            regime=args.regime,
            objective=args.objective,
            solver=args.solver,
            fiber=args.fiber,
            complete_images=args.complete_images,
            lab_ready=args.lab_ready,
            export_ready=args.export_ready,
            contains=args.contains,
            top=args.top,
            **_common_kwargs(args),
        )
        return _emit(result)
    raise ValueError(f"Unknown explore command: {args.explore_command}")


def _scaffold(args: argparse.Namespace) -> int:
    if args.scaffold_command == "objective":
        result = engine.scaffold_objective(
            args.kind,
            regime=args.regime,
            directory=args.directory,
            description=args.description,
            variables=_split_csv(args.variables),
            regularizers=_split_csv(args.regularizers),
            force=args.force,
            **_common_kwargs(args),
        )
        return _emit(result)
    if args.scaffold_command == "variable":
        result = engine.scaffold_variable(
            args.kind,
            regime=args.regime,
            directory=args.directory,
            description=args.description,
            units=args.units,
            bounds=args.bounds,
            parameterizations=_split_csv(args.parameterizations),
            objectives=_split_csv(args.objectives),
            force=args.force,
            **_common_kwargs(args),
        )
        return _emit(result)
    raise ValueError(f"Unknown scaffold command: {args.scaffold_command}")


def _index(args: argparse.Namespace) -> int:
    result = engine.index_results(
        *args.roots,
        compare=args.compare,
        compare_sweeps=args.compare_sweeps,
        csv=args.csv,
        kind=args.kind,
        config_id=args.config_id,
        regime=args.regime,
        objective=args.objective,
        solver=args.solver,
        fiber=args.fiber,
        complete_images=args.complete_images,
        lab_ready=args.lab_ready,
        export_ready=args.export_ready,
        contains=args.contains,
        top=args.top,
        **_common_kwargs(args),
    )
    return _emit(result)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fiberlab",
        description="Thin lab-facing CLI for configurable fiber-optic optimization workflows.",
    )
    parser.add_argument(
        "--repo-root",
        default=str(engine.REPO_ROOT),
        help="Repository root containing Project.toml and scripts/.",
    )
    parser.add_argument(
        "--threads",
        default="auto",
        help="Julia thread count passed as `julia -t`; default: auto.",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_command(name: str, handler: Callable[[argparse.Namespace], int], help_text: str) -> argparse.ArgumentParser:
        subparser = subparsers.add_parser(name, help=help_text)
        subparser.set_defaults(handler=handler)
        return subparser

    add_command("configs", lambda args: _call(args, engine.list_experiments), "List approved experiment configs.")
    add_command("capabilities", lambda args: _call(args, engine.capabilities), "Show supported regimes, variables, objectives, and artifacts.")
    add_command("validate", _validate, "Validate experiment, sweep, objective, and variable contracts without compute.")
    add_command("extensions", _extensions, "Validate objective and variable research-extension contracts.")

    plan = add_command("plan", lambda args: _call(args, engine.dry_run_experiment, args.spec), "Dry-run one experiment config.")
    plan.add_argument("spec")

    run = add_command("run", lambda args: _call(args, engine.run_experiment, args.spec), "Run one supported experiment config.")
    run.add_argument("spec")

    latest = add_command("latest", lambda args: _call(args, engine.latest_experiment, args.spec), "Inspect the latest completed run for a config.")
    latest.add_argument("spec")

    layout = add_command("layout", lambda args: _call(args, engine.control_layout, args.spec), "Inspect optimizer-vector layout for a config.")
    layout.add_argument("spec")

    artifacts = add_command("artifacts", lambda args: _call(args, engine.artifact_plan, args.spec), "Inspect expected outputs for a config.")
    artifacts.add_argument("spec")

    compute = add_command("compute-plan", lambda args: _call(args, engine.compute_plan, args.spec), "Print provider-neutral compute guidance for a config.")
    compute.add_argument("spec")

    objectives = add_command("objectives", _objectives, "List or validate objective contracts.")
    objectives.add_argument("--validate", action="store_true", help="Validate objective extension contracts instead of listing them.")

    variables = add_command("variables", _variables, "List or validate variable/control contracts.")
    variables.add_argument("--validate", action="store_true", help="Validate variable extension contracts instead of listing them.")

    ready = add_command("ready", _ready, "Run lab-readiness checks.")
    ready_sub = ready.add_subparsers(dest="ready_command", required=True)
    ready_config = ready_sub.add_parser("config", help="Check one config before running.")
    ready_config.add_argument("spec")
    ready_latest = ready_sub.add_parser("latest", help="Check the latest completed run for a config.")
    ready_latest.add_argument("spec")
    ready_latest.add_argument("--require-export", action="store_true")
    ready_run = ready_sub.add_parser("run", help="Check a completed run directory or artifact path.")
    ready_run.add_argument("path")
    ready_run.add_argument("--require-export", action="store_true")

    sweep = add_command("sweep", _sweep, "Plan, run, or inspect experiment sweeps.")
    sweep_sub = sweep.add_subparsers(dest="sweep_command", required=True)
    sweep_sub.add_parser("list", help="List approved sweep configs.")
    sweep_sub.add_parser("validate", help="Validate every approved sweep config.")
    for name, help_text in (
        ("plan", "Dry-run one sweep."),
        ("run", "Execute one supported sweep."),
        ("latest", "Inspect the latest completed sweep output."),
    ):
        sweep_command = sweep_sub.add_parser(name, help=help_text)
        sweep_command.add_argument("spec")

    explore = add_command("explore", _explore, "Plan or run explicitly experimental playground workflows.")
    explore_sub = explore.add_subparsers(dest="explore_command", required=True)
    explore_sub.add_parser("list", help="List configs available for exploratory planning.")
    explore_plan = explore_sub.add_parser("plan", help="Inspect one config as an exploratory playground candidate.")
    explore_plan.add_argument("spec")
    explore_run = explore_sub.add_parser("run", help="Run or dry-run an explicitly experimental workflow.")
    explore_run.add_argument("spec")
    explore_run.add_argument("--local-smoke", action="store_true", help="Allow executable experimental local smoke configs.")
    explore_run.add_argument("--heavy-ok", action="store_true", help="Allow heavy/dedicated exploratory workflows.")
    explore_run.add_argument("--dry-run", action="store_true", help="Show explore policy and plan without launching compute.")
    explore_compare = explore_sub.add_parser("compare", help="Compare exploratory result runs.")
    explore_compare.add_argument("roots", nargs="*")
    explore_compare.add_argument("--csv", action="store_true")
    explore_compare.add_argument("--kind")
    explore_compare.add_argument("--config-id")
    explore_compare.add_argument("--regime")
    explore_compare.add_argument("--objective")
    explore_compare.add_argument("--solver")
    explore_compare.add_argument("--fiber")
    explore_compare.add_argument("--complete-images", action="store_true")
    explore_compare.add_argument("--lab-ready", action="store_true")
    explore_compare.add_argument("--export-ready", action="store_true")
    explore_compare.add_argument("--contains")
    explore_compare.add_argument("--top", type=int)

    scaffold = add_command("scaffold", _scaffold, "Create planning-only objective or variable extension files.")
    scaffold_sub = scaffold.add_subparsers(dest="scaffold_command", required=True)
    objective = scaffold_sub.add_parser("objective", help="Scaffold a planning-only objective extension.")
    objective.add_argument("kind")
    objective.add_argument("--regime")
    objective.add_argument("--dir", dest="directory")
    objective.add_argument("--description")
    objective.add_argument("--variables")
    objective.add_argument("--regularizers")
    objective.add_argument("--force", action="store_true")
    variable = scaffold_sub.add_parser("variable", help="Scaffold a planning-only variable/control extension.")
    variable.add_argument("kind")
    variable.add_argument("--regime")
    variable.add_argument("--dir", dest="directory")
    variable.add_argument("--description")
    variable.add_argument("--units")
    variable.add_argument("--bounds")
    variable.add_argument("--parameterizations")
    variable.add_argument("--objectives")
    variable.add_argument("--force", action="store_true")

    index = add_command("index", _index, "Render the shared run/sweep result index.")
    index.add_argument("roots", nargs="*")
    index.add_argument("--compare", action="store_true")
    index.add_argument("--compare-sweeps", action="store_true")
    index.add_argument("--csv", action="store_true")
    index.add_argument("--kind")
    index.add_argument("--config-id")
    index.add_argument("--regime")
    index.add_argument("--objective")
    index.add_argument("--solver")
    index.add_argument("--fiber")
    index.add_argument("--complete-images", action="store_true")
    index.add_argument("--lab-ready", action="store_true")
    index.add_argument("--export-ready", action="store_true")
    index.add_argument("--contains")
    index.add_argument("--top", type=int)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
