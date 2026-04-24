# Configurable Front-Layer Context

## Task

Design a concrete front-layer architecture that can turn the repo into a
configurable research engine without building a giant framework or obscuring the
physics.

## Files reviewed

- `AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `scripts/README.md`
- `docs/README.md`
- `docs/architecture/{repo-navigation,codebase-visual-map,output-format}.md`
- `docs/guides/{adding-a-fiber-preset,adding-an-optimization-variable}.md`
- `docs/synthesis/recent-phase-synthesis-29-34.md`
- `agent-docs/current-agent-context/{INDEX,METHODOLOGY,MULTIVAR,LONGFIBER}.md`
- `agent-docs/multi-session-roadmap/SESSION-PROMPTS.md`
- `scripts/lib/{common,raman_optimization,canonical_runs}.jl`
- `scripts/workflows/optimize_raman.jl`
- `scripts/research/{multivar/mmf/longfiber}/*`
- `src/{MultiModeNoise.jl,io/results.jl}`

## Repo facts that matter for this design

1. The repo already has a TOML-based canonical run surface for approved
   single-mode runs and sweeps.
2. The main missing piece is not low-level simulation code. It is one stable
   run-description contract that can sit above single-mode, long-fiber,
   multimode, and multivar paths.
3. The setup layer is currently split by regime:
   - `setup_raman_problem(...)`
   - `setup_longfiber_problem(...)`
   - `setup_mmf_raman_problem(...)`
4. Optimization-variable handling is also split by path:
   - phase-only single-mode
   - amplitude-only single-mode
   - multivar single-mode
   - shared-phase multimode
5. Artifact writing is already converging toward a real contract:
   - canonical payload + sidecar
   - manifest row
   - trust report
   - standard images

## Design implication

The right next step is a thin front layer with explicit contracts:

- normalized experiment spec
- common problem bundle
- control-layout contract
- objective-surface contract
- artifact-bundle contract

The design should use strong named options and capability checks rather than
arbitrary user-defined formulas.
