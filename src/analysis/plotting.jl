function plot_fiber(x, u_xy, x0, r; vmin=nothing, vmax=nothing, cbarlabel=nothing)
    pcolormesh(x, x, u_xy, cmap="viridis", rasterized=true, vmin=vmin, vmax=vmax) # vmin/max: min/max values for colors
    colorbar(label=cbarlabel)

    xlim(-x0, x0)
    ylim(-x0, x0)
    
    plot(r*cos.(LinRange(0,2*π,100)), r*sin.(LinRange(0,2*π,100)), "white")

    xlabel("x (μm)")
    ylabel("y (μm)")
end