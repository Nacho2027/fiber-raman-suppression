"""
Finalize long-fiber artifacts from an existing checkpoint.

This is an operational recovery path for completed long-fiber optimizations
whose VM result sync failed after checkpointing. It rebuilds the configured
problem, loads the highest checkpoint in `LF100_CKPT_DIR`, writes the normal
`*_opt_full_result.jld2` payload, and emits the mandatory standard image set.
It does not advance the optimizer.
"""

try
    using Revise
catch
end

using Printf
using LinearAlgebra
using Dates
using JLD2

include(joinpath(@__DIR__, "longfiber_optimize_100m.jl"))

function _latest_longfiber_checkpoint(out_dir::AbstractString;
        expected_config_hash::Union{Nothing, UInt64} = nothing)
    @assert isdir(out_dir) "checkpoint dir not found: $out_dir"

    pattern = r"^ckpt_iter_(\d+)(?:_final)?\.jld2$"
    best_iter = -1
    best_final = false
    best_path = ""

    for entry in readdir(out_dir)
        m = match(pattern, entry)
        m === nothing && continue
        iter = parse(Int, m.captures[1])
        is_final = endswith(entry, "_final.jld2")
        if iter > best_iter || (iter == best_iter && is_final && !best_final)
            best_iter = iter
            best_final = is_final
            best_path = joinpath(out_dir, entry)
        end
    end

    @assert !isempty(best_path) "no checkpoint files found in $out_dir"
    data = JLD2.load(best_path)
    config_hash = UInt64(data["config_hash"])
    if expected_config_hash !== nothing && config_hash != expected_config_hash
        error("checkpoint config hash mismatch for $best_path")
    end

    return (
        x = Vector{Float64}(data["x"]),
        f = Float64(data["f"]),
        g = Vector{Float64}(data["g"]),
        iter = Int(data["iter"]),
        elapsed = Float64(data["elapsed"]),
        config_hash = config_hash,
        path = best_path,
        is_final = get(data, "is_final", false) == true,
    )
end

function lf100_finalize_checkpoint()
    @info @sprintf("Finalizing long-fiber %.0f m checkpoint artifacts — start %s", LF100_L, now())
    prob = lf100_build_problem()
    ckpt = _latest_longfiber_checkpoint(LF100_CKPT_DIR;
        expected_config_hash = prob.config_hash)
    @info @sprintf("Loaded checkpoint iter=%d final=%s f=%.6f dB from %s",
        ckpt.iter, string(ckpt.is_final), ckpt.f, ckpt.path)

    phi_opt = reshape(ckpt.x, LF100_NT, 1)
    out_path = joinpath(LF100_RESULTS_DIR, "$(LF100_RUN_LABEL)_opt_full_result.jld2")
    JLD2.jldsave(out_path;
        phi_opt        = phi_opt,
        phi_warm       = prob.phi_warm,
        J_final        = ckpt.f,
        J_final_lin    = 10.0 ^ (ckpt.f / 10),
        trace_f        = Float64[ckpt.f],
        trace_g        = Float64[norm(ckpt.g)],
        trace_iter     = Int[ckpt.iter],
        n_iter         = ckpt.iter,
        converged      = false,
        g_residual     = norm(ckpt.g),
        wall_s         = ckpt.elapsed,
        config_hash    = prob.config_hash,
        recovered_from = ckpt.path,
        L_m            = LF100_L,
        P_cont_W       = LF100_P_CONT,
        Nt             = LF100_NT,
        time_window_ps = LF100_TIME_WIN,
        β_order        = LF100_BETA_ORDER,
        saved_at       = now(),
    )
    @info "saved $out_path"

    lf100_save_standard_images(prob, vec(phi_opt); tag = "F_$(LF100_RUN_LABEL)_opt",
        output_dir = joinpath(LF100_RESULTS_DIR, "standard_images_F_$(LF100_RUN_LABEL)_opt"))

    @info @sprintf("Long-fiber checkpoint finalization done at %s", now())
    return (checkpoint = ckpt, result_path = out_path)
end

if abspath(PROGRAM_FILE) == @__FILE__
    lf100_finalize_checkpoint()
end
