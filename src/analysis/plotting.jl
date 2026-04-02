"""
    plot_fiber(x, u_xy, x0, r; vmin=nothing, vmax=nothing, cbarlabel=nothing)

Plot a 2D fiber spatial mode profile using `pcolormesh`, with a white circle
overlay showing the fiber core boundary.

# Arguments
- `x`: 1D spatial grid [μm]
- `u_xy`: 2D mode profile data, shape (nx, nx)
- `x0`: axis limit (plots from -x0 to +x0) [μm]
- `r`: core radius for boundary circle [μm]
- `vmin`, `vmax`: colormap limits (optional)
- `cbarlabel`: colorbar label string (optional)
"""
function plot_fiber(x, u_xy, x0, r; vmin=nothing, vmax=nothing, cbarlabel=nothing)
    pcolormesh(x, x, u_xy, cmap="viridis", rasterized=true, vmin=vmin, vmax=vmax)
    colorbar(label=cbarlabel)

    xlim(-x0, x0)
    ylim(-x0, x0)

    plot(r*cos.(LinRange(0,2*π,100)), r*sin.(LinRange(0,2*π,100)), "white")

    xlabel("x (μm)")
    ylabel("y (μm)")
end
