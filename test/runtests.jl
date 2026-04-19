# ═══════════════════════════════════════════════════════════════════════════════
# test/runtests.jl — tier dispatcher
# ═══════════════════════════════════════════════════════════════════════════════
# Selects one of three test tiers via the TEST_TIER environment variable.
#
#   TEST_TIER=fast  → ≤30 s, simulation-free (default; `make test`)
#   TEST_TIER=slow  → ~5 min, burst-VM territory (`make test-slow`)
#   TEST_TIER=full  → ~20 min, all regression tests + cross-process bit-identity
#                     (`make test-full`)
#
# This file is a pure dispatcher — each tier file owns its own testset blocks.
# ═══════════════════════════════════════════════════════════════════════════════

const _VALID_TIERS = ("fast", "slow", "full")

tier = lowercase(get(ENV, "TEST_TIER", "fast"))

if !(tier in _VALID_TIERS)
    throw(ArgumentError("TEST_TIER=$tier unrecognized; valid: $(join(_VALID_TIERS, ", "))"))
end

@info "Running test tier: $tier"
include(joinpath(@__DIR__, "tier_$(tier).jl"))
