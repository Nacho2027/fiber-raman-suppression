using FFTW
using LinearAlgebra

const DET_VERSION = "1.0.0"
const DET_PHASE = "15-01"
const _DETERMINISM_APPLIED = Ref(false)

"""
    ensure_deterministic_environment(; force::Bool=false, verbose::Bool=false)

Pin FFTW and BLAS thread counts to deterministic settings. Safe to call more
than once; the pins are process-global and idempotent by default.
"""
function ensure_deterministic_environment(; force::Bool=false, verbose::Bool=false)
    if _DETERMINISM_APPLIED[] && !force
        return nothing
    end
    FFTW.set_num_threads(1)
    LinearAlgebra.BLAS.set_num_threads(1)
    _DETERMINISM_APPLIED[] = true
    if verbose
        @info "Deterministic environment applied" FFTW_threads=1 BLAS_threads=1 planner_flags="ESTIMATE (via src/simulation/*.jl patch)" version=DET_VERSION
    else
        @debug "Deterministic environment applied" FFTW_threads=1 BLAS_threads=1 planner_flags="ESTIMATE (via src/simulation/*.jl patch)" version=DET_VERSION
    end
    return nothing
end

"""
    deterministic_environment_status()

Return a summary of the currently active deterministic-environment pins.
"""
function deterministic_environment_status()
    return (
        applied      = _DETERMINISM_APPLIED[],
        fftw_threads = FFTW.get_num_threads(),
        blas_threads = LinearAlgebra.BLAS.get_num_threads(),
        version      = DET_VERSION,
        phase        = DET_PHASE,
    )
end
