"""
Compatibility shim for canonical manifest helpers.

The implementation now lives in `src/io/results.jl` and is exported by the
package. Older include-based workflows keep using the historical function names
defined here.
"""

if !(@isdefined _MANIFEST_IO_JL_LOADED)
const _MANIFEST_IO_JL_LOADED = true

using FiberLab: read_run_manifest, upsert_run_manifest_entry!,
                      write_run_manifest, update_run_manifest_entry

read_manifest(args...; kwargs...) = read_run_manifest(args...; kwargs...)
upsert_manifest_entry!(args...; kwargs...) = upsert_run_manifest_entry!(args...; kwargs...)
write_manifest(args...; kwargs...) = write_run_manifest(args...; kwargs...)
update_manifest_entry(args...; kwargs...) = update_run_manifest_entry(args...; kwargs...)

end # include guard
