# ══════════════════════════════════════════════════════════════════════════════
# Fiber Raman Suppression — convenience targets
#
# Run `make` (no args) for a short list, or see docs/README.md for the full
# story. See CLAUDE.md "Running Simulations — Compute Discipline" for the
# burst-VM workflow that belongs with `make sweep`.
# ══════════════════════════════════════════════════════════════════════════════

JULIA ?= julia
JL     = $(JULIA) --project=.

.PHONY: help install test test-slow test-full optimize sweep report clean

.DEFAULT_GOAL := help

help:
	@echo "Fiber Raman Suppression — common tasks"
	@echo ""
	@echo "  make install     Install Julia dependencies (one-time, ~2 min)"
	@echo "  make test        Fast regression tier (simulation-free, ≤30 s)"
	@echo "  make test-slow   Slow tier (~5 min; burst VM recommended)"
	@echo "  make test-full   Full tier (~20 min; burst VM)"
	@echo "  make optimize    Canonical SMF-28 optimization (~5 min)"
	@echo "  make sweep       Full (L, P) parameter sweep (~2–3 h; burst VM strongly recommended)"
	@echo "  make report      Regenerate report cards + presentation figures from JLD2"
	@echo "  make clean       Remove generated PNGs + report cards (preserves JLD2 payloads)"
	@echo ""
	@echo "Docs: docs/README.md"

install:
	$(JL) -e 'using Pkg; Pkg.instantiate()'

test:
	TEST_TIER=fast $(JL) test/runtests.jl

test-slow:
	TEST_TIER=slow $(JL) -t auto test/runtests.jl

test-full:
	TEST_TIER=full $(JL) -t auto test/runtests.jl

optimize:
	$(JL) -t auto scripts/raman_optimization.jl

sweep:
	@echo ""
	@echo "⚠  make sweep: heavy job (2–3 h wall). On the burst VM, launch it through"
	@echo "    the heavy-lock wrapper (Rule P5 in CLAUDE.md) — not this target:"
	@echo ""
	@echo "      burst-ssh \"cd fiber-raman-suppression && \\"
	@echo "                 ~/bin/burst-run-heavy <SESSION-TAG> \\"
	@echo "                 'julia -t auto --project=. scripts/run_sweep.jl'\""
	@echo ""
	@echo "    See docs/quickstart-sweep.md for the full recipe."
	@echo "    Press Ctrl-C within 3 seconds to abort this local run."
	@echo ""
	@sleep 3
	$(JL) -t auto scripts/run_sweep.jl

report:
	$(JL) scripts/generate_sweep_reports.jl
	$(JL) scripts/generate_presentation_figures.jl

clean:
	@rm -rf results/images/presentation/*.png
	@find results/raman -name 'report_card.png' -delete 2>/dev/null || true
	@find results/raman -name 'report.md' -delete 2>/dev/null || true
	@rm -f results/raman/sweeps/SWEEP_REPORT.md
	@echo "Removed: presentation PNGs, report cards, SWEEP_REPORT.md"
	@echo "Kept:    results/raman/**/*.jld2 and *.json (expensive to regenerate)"
