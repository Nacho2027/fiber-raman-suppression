# ══════════════════════════════════════════════════════════════════════════════
# Fiber Raman Suppression — convenience targets
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

.PHONY: help check-tools docs-check install install-julia test test-slow test-full acceptance lab-ready doctor playground-smoke mmf-frontlayer-smoke longfiber-frontlayer-smoke golden-smoke prune-smoke optimize sweep report docker-build docker-test clean

.DEFAULT_GOAL := help

help:
	@echo "Fiber Raman Suppression — common tasks"
	@echo ""
	@echo "  make install     Install Julia deps"
	@echo "  make docs-check  Verify agent/human documentation maps and links"
	@echo "  make test        Fast Julia regression tier (simulation-free)"
	@echo "  make acceptance  Research-engine acceptance harness"
	@echo "  make lab-ready   Local lab-readiness gate for supported workflows"
	@echo "  make doctor      Verify tools, docs, and fast Julia tests"
	@echo "  make playground-smoke Run generated playground bundle end-to-end"
	@echo "  make mmf-frontlayer-smoke Run executable MMF front-layer smoke"
	@echo "  make longfiber-frontlayer-smoke Run executable long-fiber front-layer smoke"
	@echo "  make golden-smoke Run the end-to-end lab handoff smoke test"
	@echo "  make prune-smoke Keep newest SMOKE_KEEP golden-smoke runs; delete older smoke outputs"
	@echo "  make test-slow   Slow tier (~5 min; use suitable compute)"
	@echo "  make test-full   Full tier (~20 min; use suitable compute)"
	@echo "  make optimize    Canonical SMF-28 optimization (~5 min)"
	@echo "  make sweep       Full (L, P) parameter sweep (~2–3 h; use suitable compute)"
	@echo "  make report      Regenerate report cards + presentation figures from JLD2"
	@echo "  make docker-build Build a reproducible Linux/headless container"
	@echo "  make docker-test  Run make doctor inside the container"
	@echo "  make clean       Remove generated PNGs + report cards (preserves JLD2 payloads)"
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
	TEST_TIER=fast $(JL) test/runtests.jl

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
	$(JL) -t auto -e 'using Test; const _ROOT = pwd(); include("test/core/test_playground_contract_runner.jl")'
	TEST_TIER=fast $(JL) -t auto test/runtests.jl
	@echo ""
	@echo "Local lab-readiness gate passed for the supported front-layer surface."
	@echo "Generated playground bundle smoke passed."
	@echo "For a real export handoff artifact check, also run: make golden-smoke"
	@echo "For milestone physics/numerics closure on suitable compute, run: make test-slow or make test-full"

doctor: check-tools docs-check test

playground-smoke:
	$(JL) -t auto -e 'using Test; const _ROOT = pwd(); include("test/core/test_playground_contract_runner.jl")'

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

optimize:
	$(JL) -t auto scripts/canonical/optimize_raman.jl

sweep:
	@echo ""
	@echo "⚠  make sweep: heavy job (2–3 h wall). Prefer launching it on a"
	@echo "    workstation, cluster node, or cloud VM with enough CPU time and memory:"
	@echo ""
	@echo "      julia -t auto --project=. scripts/canonical/run_sweep.jl"
	@echo ""
	@echo "    See docs/guides/quickstart-sweep.md for the full recipe."
	@echo "    Press Ctrl-C within 3 seconds to abort this run."
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
	@echo "Removed: presentation PNGs, report cards, SWEEP_REPORT.md"
	@echo "Kept:    results/raman/**/*.jld2 and *.json (expensive to regenerate)"
