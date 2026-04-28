# ══════════════════════════════════════════════════════════════════════════════
# Fiber Raman Suppression — convenience targets
#
# Run `make` (no args) for a short list, or see docs/README.md for the full
# story. See CLAUDE.md "Running Simulations — Compute Discipline" for the
# burst-VM workflow that belongs with `make sweep`.
# ══════════════════════════════════════════════════════════════════════════════

JULIA ?= julia
PYTHON ?= python3
DOCKER ?= docker
DOCKER_IMAGE ?= fiber-raman-suppression:dev
VENV ?= .venv
SMOKE_KEEP ?= 3
JL     = $(JULIA) --project=.
VENV_PYTHON = $(VENV)/bin/python

.PHONY: help check-tools check-python-venv install install-julia install-python test test-python test-slow test-full acceptance lab-ready doctor golden-smoke prune-smoke optimize sweep report docker-build docker-test clean

.DEFAULT_GOAL := help

help:
	@echo "Fiber Raman Suppression — common tasks"
	@echo ""
	@echo "  make install     Install Julia deps and Python wrapper"
	@echo "  make test        Fast Julia regression tier (simulation-free)"
	@echo "  make test-python Python wrapper unit tests"
	@echo "  make acceptance  Research-engine pre-demo acceptance harness"
	@echo "  make lab-ready   Local lab-readiness gate for supported workflows"
	@echo "  make doctor      Verify tools, Julia tests, and Python wrapper tests"
	@echo "  make golden-smoke Run the end-to-end lab handoff smoke test"
	@echo "  make prune-smoke Keep newest SMOKE_KEEP golden-smoke runs; delete older smoke outputs"
	@echo "  make test-slow   Slow tier (~5 min; burst VM recommended)"
	@echo "  make test-full   Full tier (~20 min; burst VM)"
	@echo "  make optimize    Canonical SMF-28 optimization (~5 min)"
	@echo "  make sweep       Full (L, P) parameter sweep (~2–3 h; burst VM strongly recommended)"
	@echo "  make report      Regenerate report cards + presentation figures from JLD2"
	@echo "  make docker-build Build a reproducible Linux/headless container"
	@echo "  make docker-test  Run make doctor inside the container"
	@echo "  make clean       Remove generated PNGs + report cards (preserves JLD2 payloads)"
	@echo ""
	@echo "Docs: docs/README.md"

check-tools:
	@command -v $(JULIA) >/dev/null || { echo "Missing Julia. Install Julia 1.12.x."; exit 1; }
	@command -v $(PYTHON) >/dev/null || { echo "Missing Python. Install Python 3.10+."; exit 1; }
	@command -v git >/dev/null || { echo "Missing git."; exit 1; }
	@command -v make >/dev/null || { echo "Missing make."; exit 1; }

check-python-venv:
	@$(PYTHON) -c 'import ensurepip' >/dev/null 2>&1 || { \
		echo "Missing Python venv/ensurepip support."; \
		echo "Debian/Ubuntu: sudo apt install python3-venv python3-pip"; \
		echo "macOS/Homebrew Python includes this support by default."; \
		exit 1; \
	}

install: check-tools check-python-venv install-julia install-python

install-julia:
	$(JL) -e 'using Pkg; Pkg.instantiate()'

install-python: check-python-venv
	$(PYTHON) -m venv $(VENV)
	$(VENV_PYTHON) -m pip install --upgrade pip
	$(VENV_PYTHON) -m pip install -e .

test:
	TEST_TIER=fast $(JL) test/runtests.jl

test-python:
	@if [ ! -x "$(VENV_PYTHON)" ]; then \
		echo "Missing $(VENV_PYTHON). Run: make install-python"; \
		exit 1; \
	fi
	$(VENV_PYTHON) -m unittest discover -s test/python -p test_fiber_research_engine_cli.py

test-slow:
	TEST_TIER=slow $(JL) -t auto test/runtests.jl

test-full:
	TEST_TIER=full $(JL) -t auto test/runtests.jl

acceptance:
	$(JL) -e 'using Test; const _ROOT = pwd(); include("test/core/test_research_engine_acceptance.jl")'
	PYTHONPATH=python $(PYTHON) -m unittest discover -s test/python

lab-ready: check-tools acceptance
	$(JL) -t auto scripts/canonical/run_experiment.jl --validate-all
	$(JL) -t auto scripts/canonical/run_experiment_sweep.jl --validate-all
	$(JL) -t auto scripts/canonical/lab_ready.jl --config research_engine_export_smoke
	TEST_TIER=fast $(JL) -t auto test/runtests.jl
	@echo ""
	@echo "Local lab-readiness gate passed for the supported front-layer surface."
	@echo "For a real generated artifact check, also run: make golden-smoke"
	@echo "For milestone physics/numerics closure on burst, run: make test-slow or make test-full"

doctor: check-tools test test-python

golden-smoke:
	$(JL) -t auto scripts/canonical/lab_ready.jl --config research_engine_export_smoke
	$(JL) -t auto scripts/canonical/run_experiment.jl research_engine_export_smoke
	$(JL) -t auto scripts/canonical/lab_ready.jl --latest research_engine_export_smoke --require-export

prune-smoke:
	@keep="$(SMOKE_KEEP)"; \
	case "$$keep" in ''|*[!0-9]*) echo "SMOKE_KEEP must be a nonnegative integer"; exit 1;; esac; \
	if [ ! -d results/raman/smoke ]; then \
		echo "No smoke result directory found."; \
		exit 0; \
	fi; \
	old_runs="$$(ls -td results/raman/smoke/smf28_phase_export_smoke_* 2>/dev/null | tail -n +$$((keep + 1)))"; \
	if [ -z "$$old_runs" ]; then \
		echo "No golden-smoke runs to prune; keeping newest $$keep."; \
	else \
		printf '%s\n' "$$old_runs"; \
		printf '%s\n' "$$old_runs" | xargs rm -rf; \
		echo "Pruned older golden-smoke runs; kept newest $$keep."; \
	fi

optimize:
	$(JL) -t auto scripts/canonical/optimize_raman.jl

sweep:
	@echo ""
	@echo "⚠  make sweep: heavy job (2–3 h wall). On the burst VM, launch it through"
	@echo "    the heavy-lock wrapper (Rule P5 in CLAUDE.md) — not this target:"
	@echo ""
	@echo "      burst-ssh \"cd fiber-raman-suppression && \\"
	@echo "                 ~/bin/burst-run-heavy <SESSION-TAG> \\"
	@echo "                 'julia -t auto --project=. scripts/canonical/run_sweep.jl'\""
	@echo ""
	@echo "    See docs/guides/quickstart-sweep.md for the full recipe."
	@echo "    Press Ctrl-C within 3 seconds to abort this local run."
	@echo ""
	@sleep 3
	$(JL) -t auto scripts/canonical/run_sweep.jl

report:
	$(JL) scripts/canonical/generate_reports.jl

docker-build:
	$(DOCKER) build -t $(DOCKER_IMAGE) .

docker-test:
	$(DOCKER) run --rm $(DOCKER_IMAGE) make doctor

clean:
	@rm -rf results/images/presentation/*.png
	@find results/raman -name 'report_card.png' -delete 2>/dev/null || true
	@find results/raman -name 'report.md' -delete 2>/dev/null || true
	@rm -f results/raman/sweeps/SWEEP_REPORT.md
	@rm -rf build dist *.egg-info python/*.egg-info
	@echo "Removed: presentation PNGs, report cards, SWEEP_REPORT.md"
	@echo "Kept:    results/raman/**/*.jld2 and *.json (expensive to regenerate)"
