function build_GRIN(lambda, Nx, spatial_window, radius, core_NA, alpha)
    # Sellmeier equation coefficients for silicon
    a1 = 0.6961663
    a2 = 0.4079426
    a3 = 0.8974794
    b1 = 0.0684043
    b2 = 0.1162414
    b3 = 9.896161

    # Calculate the refractive index (n) of silicon (si) at the given wavelength using Sellmeier equation
    nsi = sqrt(1 + a1 * (lambda^2) / (lambda^2 - b1^2) + a2 * (lambda^2) / (lambda^2 - b2^2) + a3 * (lambda^2) / (lambda^2 - b3^2))

    # Core and cladding indices
    nco = nsi # core index with the added difference
    ncl = sqrt.(nco .^ 2 - core_NA .^ 2) # cladding index

    # Generate spatial grid
    dx = spatial_window / Nx
    x = collect(-Nx/2:Nx/2-1) * dx

    # Create meshgrid equivalent in Julia
    X, Y = meshgrid(x, x)

    # GRIN profile calculation
    epsilon = max.(ncl, nco .- (nco - ncl) .* (sqrt.(X .^ 2 + Y .^ 2) / radius) .^ alpha) .^ 2

    return epsilon, x, dx
end

function get_params(f0, c0, nx, spatial_window, radius, core_NA, alpha, M, Nt, Δt, β_order; Δf=1)
    points = 2 * β_order + 1
    half_p = (points - 1) ÷ 2
    offsets = collect(-half_p:half_p)  # Symmetric stencil [-M, ..., M]
    stencil_points = f0 .+ Δf .* offsets
    β_f = zeros((length(stencil_points), M))

    for (i, f) in enumerate(stencil_points)
        λ = c0 / (f * 1e12) * 1e6 # μm
        eps, x, dx = build_GRIN(λ, nx, spatial_window, radius, core_NA, alpha)
        _, _, neff = solve_for_fiber_modes(λ, 0., M, dx, dx, eps)
        β_f[i, :] = 2π * neff / (λ * 1e-6)
    end

    ∂nβ∂fn = zeros(β_order, M)
    for n in 1:β_order
        # Get coefficients for nth derivative (step=1.0)
        method = central_fdm(points, n)
        coeffs = method.coefs
        # Apply coefficients and scale by h^n
        ∂nβ∂fn[n, :] = sum(coeffs .* β_f, dims=1) / (2 * π * Δf / 1e-12)^n
    end

    βn_ω = [β_f[β_order+1, :]' .- β_f[β_order+1, 1]; ∂nβ∂fn[1, :]' .- ∂nβ∂fn[1, 1]; ∂nβ∂fn[2:end, :]]

    Dω = hcat([(2 * π * fftfreq(Nt, 1 / Δt) * 1e12) .^ n / factorial(n) for n in 0:β_order]...) * βn_ω

    λ0 = c0 / f0 / 1e12
    eps, x, dx = build_GRIN(λ0 * 1e6, nx, spatial_window, radius, core_NA, alpha)
    _, ϕ, neff = solve_for_fiber_modes(λ0 * 1e6, 0., M, dx, dx, eps)
    modes = reshape(ϕ, (nx, nx, M))
    dx_SI = dx * 1e-6
    SK = compute_overlap_tensor(modes, dx_SI)
    n2 = 2.3e-20
    ω0 = 2 * π * f0 * 1e12
    γ = SK * n2 * ω0 / c0

    return βn_ω, Dω, γ, ϕ, x
end

function solve_for_fiber_modes(λ, guess, nmodes, dx, dy, eps) #scalar only for now
    nx, ny = size(eps)

    n = dx * ones(1, nx * ny)
    s = dx * ones(1, nx * ny)
    e = dx * ones(1, nx * ny)
    w = dx * ones(1, nx * ny)
    p = dx * ones(1, nx * ny)
    q = dx * ones(1, nx * ny)

    ep = reshape(eps, (1, nx * ny))

    an = 2 ./ n ./ (n + s)
    as = 2 ./ s ./ (n + s)
    ae = 2 ./ e ./ (e + w)
    aw = 2 ./ w ./ (e + w)
    ap = ep .* (2π / λ)^2 - an - as - ae - aw

    ii = reshape(collect(1:nx*ny), (nx, ny))

    iall = reshape(ii, (1, nx * ny))
    inth = reshape(ii[1:nx, 2:ny], (1, nx * (ny - 1)))
    is = reshape(ii[1:nx, 1:(ny-1)], (1, nx * (ny - 1)))
    ie = reshape(ii[2:nx, 1:ny], (1, (nx - 1) * ny))
    iw = reshape(ii[1:(nx-1), 1:ny], (1, (nx - 1) * ny))

    K = hcat(iall, iw, ie, is, inth)[1, :]
    J = hcat(iall, ie, iw, inth, is)[1, :]
    V = hcat(ap[iall], ae[iw], aw[ie], an[is], as[inth])[1, :]

    A = sparse(K, J, V)

    d, v = eigs(A; nev=nmodes, which=:LR, maxiter=1000)

    neff = λ * sqrt.(d) / (2 * π)

    return d, v, neff
end

function compute_overlap_tensor(modes, dx_SI)
    M = size(modes)[3]
    SK = zeros(M, M, M, M)

    @tullio SK[i, j, k, l] = modes[m, n, i] * modes[m, n, j] * modes[m, n, k] * modes[m, n, l]

    SK = SK / dx_SI^2
    return SK
end