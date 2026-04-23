"""
Shared helpers for describing scalar optimization objective surfaces.

The returned objects are NamedTuples so existing script code can continue using
dot access and serializing selected fields into trust reports / result payloads.
"""

if !(@isdefined _OBJECTIVE_SURFACE_JL_LOADED)
const _OBJECTIVE_SURFACE_JL_LOADED = true

"""
    active_linear_terms(base_terms, regularizer_terms) -> Vector{String}

Build the ordered terms for a linear objective surface. `regularizer_terms` is
an iterable of `(enabled, label)` pairs.
"""
function active_linear_terms(base_terms, regularizer_terms)
    terms = String.(collect(base_terms))
    for (enabled, label) in regularizer_terms
        enabled && push!(terms, String(label))
    end
    return terms
end

"""
    build_objective_surface_spec(; objective_label, log_cost, linear_terms,
                                  leading_fields=NamedTuple(),
                                  trailing_fields=NamedTuple())

Build the common objective-surface metadata fields while allowing callers to add
path-specific fields before or after the common block.
"""
function build_objective_surface_spec(;
    objective_label::AbstractString,
    log_cost::Bool,
    linear_terms,
    leading_fields::NamedTuple = NamedTuple(),
    trailing_fields::NamedTuple = NamedTuple(),
)
    linear_surface = join(String.(collect(linear_terms)), " + ")
    scalar_surface = log_cost ? "10*log10(" * linear_surface * ")" : linear_surface

    common = (
        objective_label = String(objective_label),
        log_cost = log_cost,
        scale = log_cost ? "dB" : "linear",
        scalar_surface = scalar_surface,
        pre_log_linear_surface = linear_surface,
        regularizers_chained_into_surface = true,
    )
    return merge(leading_fields, common, trailing_fields)
end

end # include guard
