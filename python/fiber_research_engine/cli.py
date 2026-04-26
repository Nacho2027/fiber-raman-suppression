"""Thin Python/Jupyter wrapper around the maintained Julia CLI.

The notebook surface should orchestrate and display results, not reimplement
the experiment engine. These helpers keep Python notebooks pointed at the same
validated backend used by the CLI.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
RUN_EXPERIMENT = "scripts/canonical/run_experiment.jl"
RUN_EXPERIMENT_SWEEP = "scripts/canonical/run_experiment_sweep.jl"
INDEX_RESULTS = "scripts/canonical/index_results.jl"
REFINE_AMP_ON_PHASE = "scripts/canonical/refine_amp_on_phase.jl"


@dataclass(frozen=True)
class CommandResult:
    """Captured command result returned to notebooks."""

    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


def _as_args(values: Iterable[str]) -> tuple[str, ...]:
    return tuple(str(value) for value in values)


def julia_cli_args(
    script: str,
    *args: str,
    repo_root: str | Path = REPO_ROOT,
    threads: str = "auto",
) -> tuple[str, ...]:
    """Build the Julia CLI command used by notebook helpers."""

    _ = Path(repo_root)
    return (
        "julia",
        "-t",
        str(threads),
        "--project=.",
        script,
        *_as_args(args),
    )


def run_julia_cli(
    script: str,
    *args: str,
    repo_root: str | Path = REPO_ROOT,
    threads: str = "auto",
    check: bool = True,
) -> CommandResult:
    """Run a maintained Julia CLI command and capture stdout/stderr."""

    root = Path(repo_root)
    cmd = julia_cli_args(script, *args, repo_root=root, threads=threads)
    completed = subprocess.run(
        cmd,
        cwd=root,
        check=False,
        text=True,
        capture_output=True,
    )
    result = CommandResult(
        args=cmd,
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )
    if check and completed.returncode != 0:
        raise RuntimeError(
            "Julia CLI command failed with exit code "
            f"{completed.returncode}: {' '.join(cmd)}\n{completed.stderr}"
        )
    return result


def list_experiments(**kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT, "--list", **kwargs)


def capabilities(**kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT, "--capabilities", **kwargs)


def objectives(**kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT, "--objectives", **kwargs)


def validate_all_experiments(**kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT, "--validate-all", **kwargs)


def dry_run_experiment(spec: str = "research_engine_poc", **kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT, "--dry-run", spec, **kwargs)


def run_experiment(spec: str, **kwargs) -> CommandResult:
    """Execute one supported experiment through the Julia front layer."""

    return run_julia_cli(RUN_EXPERIMENT, spec, **kwargs)


def list_sweeps(**kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT_SWEEP, "--list", **kwargs)


def validate_all_sweeps(**kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT_SWEEP, "--validate-all", **kwargs)


def dry_run_sweep(spec: str = "smf28_power_micro_sweep", **kwargs) -> CommandResult:
    return run_julia_cli(RUN_EXPERIMENT_SWEEP, "--dry-run", spec, **kwargs)


def index_results(
    *roots: str,
    compare: bool = False,
    csv: bool = False,
    kind: str | None = None,
    config_id: str | None = None,
    regime: str | None = None,
    objective: str | None = None,
    solver: str | None = None,
    fiber: str | None = None,
    complete_images: bool = False,
    lab_ready: bool = False,
    export_ready: bool = False,
    contains: str | None = None,
    top: int | None = None,
    **kwargs,
) -> CommandResult:
    """Render the shared Julia results/campaign index for notebooks."""

    args: list[str] = []
    if compare:
        args.append("--compare")
    if csv:
        args.append("--csv")
    if kind is not None:
        args.extend(("--kind", kind))
    if config_id is not None:
        args.extend(("--config-id", config_id))
    if regime is not None:
        args.extend(("--regime", regime))
    if objective is not None:
        args.extend(("--objective", objective))
    if solver is not None:
        args.extend(("--solver", solver))
    if fiber is not None:
        args.extend(("--fiber", fiber))
    if complete_images:
        args.append("--complete-images")
    if lab_ready:
        args.append("--lab-ready")
    if export_ready:
        args.append("--export-ready")
    if contains is not None:
        args.extend(("--contains", contains))
    if top is not None:
        args.extend(("--top", str(top)))
    args.extend(roots)
    return run_julia_cli(INDEX_RESULTS, *args, **kwargs)


def index_results_csv(*roots: str, **kwargs) -> CommandResult:
    """Render the shared results index as CSV for pandas/Excel workflows."""

    return index_results(*roots, csv=True, **kwargs)


def _amp_on_phase_refinement_args(
    *,
    tag: str | None = None,
    L: float | None = None,
    P: float | None = None,
    phase_iter: int | None = None,
    amp_iter: int | None = None,
    delta_bound: float | None = None,
    threshold_db: float | None = None,
    export: bool = False,
    dry_run: bool = False,
) -> tuple[str, ...]:
    args: list[str] = []
    if dry_run:
        args.append("--dry-run")
    if export:
        args.append("--export")
    option_values: tuple[tuple[str, object | None], ...] = (
        ("--tag", tag),
        ("--L", L),
        ("--P", P),
        ("--phase-iter", phase_iter),
        ("--amp-iter", amp_iter),
        ("--delta-bound", delta_bound),
        ("--threshold-db", threshold_db),
    )
    for option, value in option_values:
        if value is not None:
            args.extend((option, str(value)))
    return tuple(args)


def dry_run_amp_on_phase_refinement(
    *,
    tag: str | None = None,
    L: float | None = None,
    P: float | None = None,
    phase_iter: int | None = None,
    amp_iter: int | None = None,
    delta_bound: float | None = None,
    threshold_db: float | None = None,
    export: bool = False,
    repo_root: str | Path = REPO_ROOT,
    threads: str = "auto",
    check: bool = True,
) -> CommandResult:
    """Plan the optional amp-on-phase refinement without launching compute."""

    args = _amp_on_phase_refinement_args(
        dry_run=True,
        tag=tag,
        L=L,
        P=P,
        phase_iter=phase_iter,
        amp_iter=amp_iter,
        delta_bound=delta_bound,
        threshold_db=threshold_db,
        export=export,
    )
    return run_julia_cli(
        REFINE_AMP_ON_PHASE,
        *args,
        repo_root=repo_root,
        threads=threads,
        check=check,
    )


def refine_amp_on_phase(
    *,
    tag: str | None = None,
    L: float | None = None,
    P: float | None = None,
    phase_iter: int | None = None,
    amp_iter: int | None = None,
    delta_bound: float | None = None,
    threshold_db: float | None = None,
    export: bool = False,
    repo_root: str | Path = REPO_ROOT,
    threads: str = "auto",
    check: bool = True,
) -> CommandResult:
    """Run the optional amp-on-phase refinement through the canonical CLI."""

    args = _amp_on_phase_refinement_args(
        tag=tag,
        L=L,
        P=P,
        phase_iter=phase_iter,
        amp_iter=amp_iter,
        delta_bound=delta_bound,
        threshold_db=threshold_db,
        export=export,
    )
    return run_julia_cli(
        REFINE_AMP_ON_PHASE,
        *args,
        repo_root=repo_root,
        threads=threads,
        check=check,
    )
