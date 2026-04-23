# ═══════════════════════════════════════════════════════════════════════════════
# Compatibility shim for the canonical deterministic-environment helpers.
#
# The implementation now lives in `src/runtime/determinism.jl` and is exposed
# through the `MultiModeNoise` package. This file remains include-able so older
# scripts and tests keep working.
# ═══════════════════════════════════════════════════════════════════════════════

using MultiModeNoise: deterministic_environment_status, ensure_deterministic_environment
