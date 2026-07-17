# Compatibility aliases for transitional scripts; renderers live in FiberLab.
if !(@isdefined _VISUALIZATION_ADAPTER_LOADED)
const _VISUALIZATION_ADAPTER_LOADED = true

using FiberLab
using PyPlot

const wrap_phase = FiberLab.wrap_phase
const compute_group_delay = FiberLab.compute_group_delay
const compute_instantaneous_frequency = FiberLab.compute_instantaneous_frequency
const plot_phase_diagnostic = FiberLab.plot_phase_diagnostic
const plot_spectral_evolution = FiberLab.plot_spectral_evolution
const plot_temporal_evolution = FiberLab.plot_temporal_evolution
const plot_combined_evolution = FiberLab.plot_combined_evolution
const plot_merged_evolution = FiberLab.plot_merged_evolution
const plot_optimization_result_v2 = FiberLab.plot_optimization_result_v2
const propagate_and_plot_evolution = FiberLab.propagate_and_plot_evolution
const _format_power_watts = FiberLab._format_power_watts

end
