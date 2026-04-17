"""
Long-Fiber Optimization Checkpointing (Phase 16 / Session F)

Provides overnight-safe checkpoint/resume for L-BFGS Raman-suppression runs at
L ≥ 100 m, where wall-time per run is 2-4 h and a mid-run crash or preemption
would otherwise lose all progress.

Four public pieces:

  mutable struct CheckpointBuf
      x_last        :: Vector{Float64}
      f_last        :: Float64
      g_last        :: Vector{Float64}
      iter          :: Int
      last_ckpt_s   :: Float64   # wall-clock of last checkpoint write
      config_hash   :: UInt64    # identifies the problem config
      t_start       :: Float64   # wall-clock at optimization start (s)
  end

  longfiber_make_fg!(buf, problem_cg)
      -> closure suitable for `Optim.only_fg!`

  longfiber_checkpoint_cb(buf, out_dir; every=5, time_gate_s=600)
      -> callback `state -> Bool` for `Optim.Options(callback=...)`.
         Saves a JLD2 every `every` iterations OR every `time_gate_s` seconds,
         whichever hits first. Returns `false` so the optimizer keeps running.

  longfiber_resume_from_ckpt(out_dir; expected_config_hash=nothing)
      -> NamedTuple(x, f, g, iter, elapsed, config_hash, path)
         Loads the highest-iter `ckpt_iter_*.jld2` in `out_dir`. When
         `expected_config_hash` is given and mismatches, raises an error.

JLD2 schema per checkpoint file:
    Dict("x" => x_last, "f" => f_last, "g" => g_last,
         "iter" => iter, "elapsed" => now_seconds - t_start,
         "config_hash" => config_hash, "saved_at" => now())

Include guard: `_LONGFIBER_CHECKPOINT_JL_LOADED`.
"""

try
    using Revise
catch
end

using Printf
using Logging
using Dates
using JLD2

if !(@isdefined _LONGFIBER_CHECKPOINT_JL_LOADED)
const _LONGFIBER_CHECKPOINT_JL_LOADED = true

# ─────────────────────────────────────────────────────────────────────────────
# CheckpointBuf struct — holds the most recent (x, f, g) seen by fg!
# ─────────────────────────────────────────────────────────────────────────────

"""
    CheckpointBuf(n_params; config_hash=UInt64(0))

Allocate a checkpoint buffer for an `n_params`-dimensional optimization.
`config_hash` identifies the problem: resume refuses to run if the hash
differs from the stored one.
"""
mutable struct CheckpointBuf
    x_last      :: Vector{Float64}
    f_last      :: Float64
    g_last      :: Vector{Float64}
    iter        :: Int
    last_ckpt_s :: Float64
    config_hash :: UInt64
    t_start     :: Float64
end

function CheckpointBuf(n_params::Integer; config_hash::UInt64 = UInt64(0))
    @assert n_params > 0 "n_params must be positive"
    return CheckpointBuf(
        zeros(Float64, n_params),
        Inf,
        zeros(Float64, n_params),
        0,
        time(),
        config_hash,
        time(),
    )
end

"""
    longfiber_config_hash(; Nt, time_window, L, P, fiber_id, reltol)

Deterministic hash of a problem configuration. Use the returned UInt64 in
`CheckpointBuf(n; config_hash=...)` and pass the same value to
`longfiber_resume_from_ckpt(...; expected_config_hash=...)`.
"""
function longfiber_config_hash(; Nt, time_window, L, P, fiber_id, reltol)
    return hash((Nt, float(time_window), float(L), float(P),
                 string(fiber_id), float(reltol)))
end

# ─────────────────────────────────────────────────────────────────────────────
# longfiber_make_fg! — closure that tees (x, f, g) into a CheckpointBuf
# ─────────────────────────────────────────────────────────────────────────────

"""
    longfiber_make_fg!(buf::CheckpointBuf, cost_and_grad)

Return a closure suitable for `Optim.only_fg!`.

`cost_and_grad` MUST be a function `x :: Vector{Float64} -> (f::Float64, g::Vector{Float64})`
evaluating cost and gradient on the flat parameter vector. The closure records
`x`, `f`, `g` into `buf` and also increments `buf.iter`. The caller's Optim
callback (e.g. `longfiber_checkpoint_cb`) then reads the buffer to decide
whether to write a checkpoint.

Usage:
```julia
buf = CheckpointBuf(length(vec(φ0)); config_hash = hash_val)
fg! = longfiber_make_fg!(buf, x -> my_cost_and_grad(x, ...))
cb  = longfiber_checkpoint_cb(buf, out_dir; every=5)
result = Optim.optimize(Optim.only_fg!(fg!), vec(φ0), Optim.LBFGS(),
    Optim.Options(iterations=100, callback=cb, store_trace=true))
```
"""
function longfiber_make_fg!(buf::CheckpointBuf, cost_and_grad)
    return (F, G, x) -> begin
        f, g = cost_and_grad(x)
        # copy into buffer BEFORE writing to G, so a checkpoint captures the
        # exact (x, f, g) the optimizer saw.
        buf.x_last .= x
        buf.f_last = f
        buf.g_last .= g
        buf.iter  += 1
        if G !== nothing
            G .= g
        end
        return f
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# longfiber_checkpoint_cb — Optim.Options callback
# ─────────────────────────────────────────────────────────────────────────────

"""
    longfiber_checkpoint_cb(buf, out_dir; every=5, time_gate_s=600)

Return a callback `state -> Bool` suitable for `Optim.Options(callback=...)`.

Writes a JLD2 file at `joinpath(out_dir, @sprintf("ckpt_iter_%04d.jld2", buf.iter))`
when either:
 - `buf.iter % every == 0` (iteration stride), or
 - `time() - buf.last_ckpt_s > time_gate_s` (wall-clock gate), or
 - this is the first iteration (to capture starting point).

Always returns `false`, i.e. never requests the optimizer to stop.

Creates `out_dir` if missing.
"""
function longfiber_checkpoint_cb(buf::CheckpointBuf, out_dir::AbstractString;
                                  every::Integer = 5, time_gate_s::Real = 600.0)
    @assert every > 0 "every must be positive"
    @assert time_gate_s > 0 "time_gate_s must be positive"
    mkpath(out_dir)

    return state -> begin
        now_s  = time()
        iter   = buf.iter
        stride_hit = (iter > 0 && iter % every == 0)
        time_hit   = (now_s - buf.last_ckpt_s > time_gate_s)
        first_hit  = (state.iteration == 0 && iter <= 1)

        if stride_hit || time_hit || first_hit
            elapsed = now_s - buf.t_start
            fpath   = joinpath(out_dir, @sprintf("ckpt_iter_%04d.jld2", iter))
            JLD2.jldsave(fpath;
                x           = copy(buf.x_last),
                f           = buf.f_last,
                g           = copy(buf.g_last),
                iter        = iter,
                elapsed     = elapsed,
                config_hash = buf.config_hash,
                saved_at    = now(),
            )
            buf.last_ckpt_s = now_s
            @info @sprintf("checkpoint iter=%d f=%.6e elapsed=%.1fs -> %s",
                iter, buf.f_last, elapsed, fpath)
        end
        return false
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# longfiber_resume_from_ckpt — find highest-iter ckpt and load (x, f, g, iter)
# ─────────────────────────────────────────────────────────────────────────────

"""
    longfiber_resume_from_ckpt(out_dir; expected_config_hash=nothing)
        -> NamedTuple(x, f, g, iter, elapsed, config_hash, path)

Scan `out_dir` for `ckpt_iter_*.jld2` files, pick the one with the highest
`iter`, and return its contents. If `expected_config_hash` is given and the
file's `config_hash` does NOT match, throws `ErrorException`.

Raises `ErrorException` when no checkpoints are found in the directory.
"""
function longfiber_resume_from_ckpt(out_dir::AbstractString;
                                     expected_config_hash::Union{Nothing, UInt64} = nothing)
    @assert isdir(out_dir) "checkpoint dir not found: $out_dir"

    pattern = r"^ckpt_iter_(\d+)\.jld2$"
    best_iter = -1
    best_path = ""
    for entry in readdir(out_dir)
        m = match(pattern, entry)
        if m !== nothing
            it = parse(Int, m.captures[1])
            if it > best_iter
                best_iter = it
                best_path = joinpath(out_dir, entry)
            end
        end
    end
    best_iter >= 0 || error("no ckpt_iter_*.jld2 files in $out_dir")

    d = JLD2.load(best_path)
    got_hash = UInt64(d["config_hash"])

    if expected_config_hash !== nothing && got_hash != expected_config_hash
        error(@sprintf("checkpoint config_hash mismatch in %s: got 0x%x, expected 0x%x — refusing to resume",
            best_path, got_hash, expected_config_hash))
    end

    @info @sprintf("resuming from %s (iter=%d, f=%.6e, elapsed=%.1fs)",
        best_path, d["iter"], d["f"], d["elapsed"])

    return (
        x           = Vector{Float64}(d["x"]),
        f           = Float64(d["f"]),
        g           = Vector{Float64}(d["g"]),
        iter        = Int(d["iter"]),
        elapsed     = Float64(d["elapsed"]),
        config_hash = got_hash,
        path        = best_path,
    )
end

end  # include guard

# ─────────────────────────────────────────────────────────────────────────────
# Unit test: 10-dim quadratic with interrupt/resume via Optim.LBFGS
# (runs only when executed as a main script — NOT on `include`)
# ─────────────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    using Optim
    using LinearAlgebra
    @info "longfiber_checkpoint unit test"

    # Trivial convex problem: f(x) = ½‖x - x*‖²; optimum at x*.
    n = 10
    x_star = collect(1.0:n)
    cg = x -> begin
        d = x .- x_star
        return 0.5 * sum(abs2, d), copy(d)
    end

    tmpdir = mktempdir(prefix = "ckpt_test_")
    config_hash = longfiber_config_hash(Nt = 10, time_window = 1.0, L = 0.0,
        P = 0.0, fiber_id = "test", reltol = 0.0)

    # ── Reference run (uninterrupted, 5 iter) ─────────────────────────────────
    buf_ref = CheckpointBuf(n; config_hash = config_hash)
    fg_ref  = longfiber_make_fg!(buf_ref, cg)
    cb_ref  = longfiber_checkpoint_cb(buf_ref, tmpdir; every = 1, time_gate_s = 1e9)
    res_ref = Optim.optimize(
        Optim.only_fg!(fg_ref), zeros(n), Optim.LBFGS(),
        Optim.Options(iterations = 5, callback = cb_ref, store_trace = true),
    )
    f_ref = Optim.minimum(res_ref)
    x_ref = Optim.minimizer(res_ref)
    @info @sprintf("reference: f=%.3e, ‖x-x*‖=%.3e, iters=%d",
        f_ref, norm(x_ref .- x_star), buf_ref.iter)

    # ── Interrupted run: stop at iter 3, then resume ──────────────────────────
    tmpdir2 = mktempdir(prefix = "ckpt_test_resume_")
    buf_a = CheckpointBuf(n; config_hash = config_hash)
    fg_a  = longfiber_make_fg!(buf_a, cg)
    cb_a  = longfiber_checkpoint_cb(buf_a, tmpdir2; every = 1, time_gate_s = 1e9)
    try
        Optim.optimize(
            Optim.only_fg!(fg_a), zeros(n), Optim.LBFGS(),
            Optim.Options(iterations = 3, callback = cb_a, store_trace = true),
        )
    catch e
        @warn "interrupted run threw: $e"
    end

    resume = longfiber_resume_from_ckpt(tmpdir2; expected_config_hash = config_hash)
    @info @sprintf("resume: iter=%d, f=%.3e, ‖x_resume-x*‖=%.3e",
        resume.iter, resume.f, norm(resume.x .- x_star))

    # Restart from loaded x; run another 5-3=2 iterations to match the
    # reference's total of 5 iterations.
    buf_b = CheckpointBuf(n; config_hash = config_hash)
    buf_b.iter = resume.iter     # continue the counter for naming
    fg_b  = longfiber_make_fg!(buf_b, cg)
    cb_b  = longfiber_checkpoint_cb(buf_b, tmpdir2; every = 1, time_gate_s = 1e9)
    res_b = Optim.optimize(
        Optim.only_fg!(fg_b), copy(resume.x), Optim.LBFGS(),
        Optim.Options(iterations = 5 - resume.iter, callback = cb_b, store_trace = true),
    )
    f_resumed = Optim.minimum(res_b)
    x_resumed = Optim.minimizer(res_b)
    Δf = abs(f_resumed - f_ref) / max(abs(f_ref), 1e-20)
    @info @sprintf("resumed total: f=%.3e, ‖x-x*‖=%.3e, Δf/f_ref=%.2e",
        f_resumed, norm(x_resumed .- x_star), Δf)

    # Hash mismatch test — should throw.
    got_err = false
    try
        longfiber_resume_from_ckpt(tmpdir2; expected_config_hash = UInt64(0xdeadbeef))
    catch e
        got_err = true
    end
    @assert got_err "hash mismatch did NOT raise — resume guard is broken"

    @assert Δf < 1e-6 "resumed run diverged from reference: Δf/f_ref = $Δf"
    @info "longfiber_checkpoint unit test: PASSED"

    rm(tmpdir; recursive = true, force = true)
    rm(tmpdir2; recursive = true, force = true)
end
