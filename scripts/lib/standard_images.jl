# Compatibility alias for transitional scripts; implementation lives in FiberLab.
if !(@isdefined _STANDARD_IMAGES_ADAPTER_LOADED)
const _STANDARD_IMAGES_ADAPTER_LOADED = true

using FiberLab

const save_standard_set = FiberLab.save_standard_set

end
