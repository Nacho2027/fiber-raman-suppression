# ══════════════════════════════════════════════════════════════════════════════
# FiberLab — convenience targets
#
# Run `make` (no args) for a short list, or see docs/README.md for the full
# story. Large runs should be launched on whatever workstation, cluster, or
# cloud VM has enough CPU time and memory for the configured grid.
# ══════════════════════════════════════════════════════════════════════════════

JULIA ?= julia
DOCKER ?= docker
DOCKER_IMAGE ?= fiber-raman-suppression:dev
SMOKE_KEEP ?= 3
JL     = $(JULIA) --project=.

.PHONY: help check-tools docs-check install install-julia test test-slow test-full acceptance lab-ready doctor mmf-frontlayer-smoke longfiber-frontlayer-smoke golden-smoke prune-smoke docker-build docker-test

.DEFAULT_GOAL := help

help:
	@echo "FiberLab — common tasks"
	@echo ""
	@echo "  make install     Install Julia deps"
	@echo "  make docs-check  Verify agent/human documentation maps and links"
	@echo "  make test        Local core regressions with small numerical solves"
	@echo "  make acceptance  Research-engine acceptance harness"
	@echo "  make lab-ready   Local lab-readiness gate for supported workflows"
	@echo "  make doctor      Verify tools, docs, and fast Julia tests"
	@echo "  make mmf-frontlayer-smoke Validate and plan the MMF front-layer config"
	@echo "  make longfiber-frontlayer-smoke Validate and plan the long-fiber front-layer config"
	@echo "  make golden-smoke Run the end-to-end lab handoff smoke test"
	@echo "  make prune-smoke Keep newest SMOKE_KEEP golden-smoke runs; delete older smoke outputs"
	@echo "  make test-slow   Slow tier (~5 min; use suitable compute)"
	@echo "  make test-full   Full tier (~20 min; use suitable compute)"
	@echo "  make docker-build Build a reproducible Linux/headless container"
	@echo "  make docker-test  Run make doctor inside the container"
	@echo ""
	@echo "Docs: docs/README.md"

check-tools:
	@command -v $(JULIA) >/dev/null || { echo "Missing Julia. Install Julia 1.12.x."; exit 1; }
	@command -v git >/dev/null || { echo "Missing git."; exit 1; }
	@command -v make >/dev/null || { echo "Missing make."; exit 1; }

docs-check:
	$(JL) scripts/dev/check_agent_docs.jl

install: check-tools install-julia

install-julia:
	$(JL) -e 'using Pkg; Pkg.instantiate()'

test:
	TEST_TIER=fast $(JL) -t auto test/runtests.jl

test-slow:
	TEST_TIER=slow $(JL) -t auto test/runtests.jl

test-full:
	TEST_TIER=full $(JL) -t auto test/runtests.jl

acceptance:
	$(JL) -e 'using Test; const _ROOT = pwd(); include("test/core/test_research_engine_acceptance.jl")'

lab-ready: check-tools acceptance
	$(JL) -t auto scripts/canonical/run_experiment.jl --validate-all
	$(JL) -t auto scripts/canonical/run_experiment_sweep.jl --validate-all
	$(JL) -t auto scripts/canonical/lab_ready.jl --config research_engine_export_smoke
	$(JL) -t auto -e 'using Test; const _ROOT = pwd(); include("test/core/test_experiment_front_layer.jl")'
	TEST_TIER=fast $(JL) -t auto test/runtests.jl
	@echo ""
	@echo "Local lab-readiness gate passed for the supported front-layer surface."
	@echo "For a real export handoff artifact check, also run: make golden-smoke"
	@echo "For milestone physics/numerics closure on suitable compute, run: make test-slow or make test-full"

doctor: check-tools docs-check test

mmf-frontlayer-smoke:
	$(JL) -t auto scripts/canonical/run_experiment.jl --dry-run grin50_mmf_phase_sum_poc

longfiber-frontlayer-smoke:
	$(JL) -t auto scripts/canonical/run_experiment.jl --dry-run smf28_longfiber_phase_poc

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

docker-build:
	$(DOCKER) build -t $(DOCKER_IMAGE) .

docker-test:
	$(DOCKER) run --rm $(DOCKER_IMAGE) make doctor
