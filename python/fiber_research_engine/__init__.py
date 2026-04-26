"""Notebook-friendly helpers for the fiber research engine.

This package is intentionally thin. It delegates to the maintained Julia CLI
entry points so notebooks do not become a second implementation of validation,
solver dispatch, or artifact contracts.
"""

from .cli import (
    CommandResult,
    dry_run_amp_on_phase_refinement,
    capabilities,
    dry_run_experiment,
    dry_run_sweep,
    list_experiments,
    list_sweeps,
    objectives,
    refine_amp_on_phase,
    run_experiment,
    run_julia_cli,
    validate_all_experiments,
    validate_all_sweeps,
)

__all__ = [
    "CommandResult",
    "capabilities",
    "dry_run_amp_on_phase_refinement",
    "dry_run_experiment",
    "dry_run_sweep",
    "list_experiments",
    "list_sweeps",
    "objectives",
    "refine_amp_on_phase",
    "run_experiment",
    "run_julia_cli",
    "validate_all_experiments",
    "validate_all_sweeps",
]
