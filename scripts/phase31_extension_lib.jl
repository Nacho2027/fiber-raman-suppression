#!/usr/bin/env julia

# scripts/phase31_extension_lib.jl — Phase 31 follow-up path helpers

using LinearAlgebra

"""
Load rows from a Phase 31 sweep JLD2 file if it exists, else return an empty
vector. Kept side-effect free so unit tests can exercise selection logic
without touching the heavy optimization driver.
"""
function p31x_load_rows(path::AbstractString)
    if !isfile(path)
        return Dict{String,Any}[]
    end
    return JLD2.load(path, "rows")
end

"""
Select a unique reduced-basis Phase 31 row by `(branch, kind, N_phi)`.
Throws if zero or multiple matches are found so path specs cannot silently
pick the wrong seed.
"""
function p31x_find_basis_row(rows::AbstractVector,
                              branch::AbstractString,
                              kind::Symbol,
                              N_phi::Integer)
    matches = Dict{String,Any}[
        r for r in rows
        if get(r, "branch", "") == branch &&
           get(r, "kind", "") == String(kind) &&
           get(r, "N_phi", -1) == Int(N_phi)
    ]
    length(matches) == 1 && return matches[1]
    if isempty(matches)
        error("no Phase 31 row for branch=$branch kind=$kind N_phi=$N_phi")
    end
    error("multiple Phase 31 rows for branch=$branch kind=$kind N_phi=$N_phi")
end

"""
Project a full-grid phase vector onto a basis using the same least-squares
projection used by `continuation_upsample`, but without needing an existing
coarse basis. This is the cross-family warm-start primitive for follow-up
paths such as linear -> cubic -> full-grid.
"""
function p31x_project_phi_to_basis(phi_vec::AbstractVector{<:Real},
                                    B::AbstractMatrix{<:Real})
    @assert size(B, 1) == length(phi_vec) "basis row count must match phi length"
    G = Symmetric(B' * B)
    rhs = B' * phi_vec
    return vec(G \ rhs)
end

"""
Normalize a path step spec into a compact string label used in tags/results.
"""
function p31x_step_label(step::NamedTuple)
    if step.mode == :basis
        return "$(String(step.kind))_N$(lpad(step.N_phi, 3, '0'))"
    elseif step.mode == :full
        return "full_grid"
    else
        error("unknown path step mode $(step.mode)")
    end
end

"""
Path program for the follow-up comparison. The `seed` field points at either
Phase 31 sweep rows or zero-init, and `steps` lists any extra optimization
steps to execute before the mandatory full-grid refinement.
"""
function p31x_default_path_program()
    return [
        (
            name = "full_zero",
            description = "zero -> full-grid baseline",
            seed = (mode = :zero,),
            steps = [
                (mode = :full,),
            ],
        ),
        (
            name = "cubic32_full",
            description = "Phase31 cubic N=32 optimum -> full-grid",
            seed = (mode = :phase31_row, branch = "A", kind = :cubic, N_phi = 32),
            steps = [
                (mode = :full,),
            ],
        ),
        (
            name = "linear64_full",
            description = "Phase31 linear N=64 optimum -> full-grid",
            seed = (mode = :phase31_row, branch = "A", kind = :linear, N_phi = 64),
            steps = [
                (mode = :full,),
            ],
        ),
        (
            name = "cubic128_full",
            description = "Phase31 best cubic N=128 optimum -> full-grid",
            seed = (mode = :phase31_row, branch = "A", kind = :cubic, N_phi = 128),
            steps = [
                (mode = :full,),
            ],
        ),
        (
            name = "linear64_cubic128_full",
            description = "linear N=64 seed -> cubic N=128 refinement -> full-grid",
            seed = (mode = :phase31_row, branch = "A", kind = :linear, N_phi = 64),
            steps = [
                (mode = :basis, kind = :cubic, N_phi = 128),
                (mode = :full,),
            ],
        ),
    ]
end
