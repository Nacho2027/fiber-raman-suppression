"""
    build_GRIN(lambda, Nx, spatial_window, radius, core_NA, alpha) -> (epsilon, x, dx)

Construct a graded-index (GRIN) fiber refractive index profile on a 2D spatial grid.

Uses the Sellmeier equation for fused silica to compute the core refractive index
at the given wavelength, then builds the GRIN profile:
    n(r) = max(n_cl, n_co - (n_co - n_cl)·(r/a)^α)
where r = sqrt(x² + y²), a is the core radius, and α is the profile exponent
(α=2 gives a parabolic profile, the standard for GRIN multimode fibers).

# Arguments
- `lambda`: wavelength [μm]
- `Nx`: number of spatial grid points per dimension
- `spatial_window`: total grid extent [μm]
- `radius`: core radius [μm]
- `core_NA`: numerical aperture
- `alpha`: GRIN profile exponent (2.0 for parabolic)

# Returns
- `epsilon`: ε = n² dielectric constant profile, shape (Nx, Nx)
- `x`: 1D spatial grid [μm]
- `dx`: grid spacing [μm]

# Sellmeier coefficients
The coefficients (a1-a3, b1-b3) are for fused silica (SiO₂), valid from ~0.2-6.7 μm.
"""
function build_GRIN(lambda, Nx, spatial_window, radius, core_NA, alpha)
    # Sellmeier equation coefficients for fused silica (SiO₂)
    a1 = 0.6961663
    a2 = 0.4079426
    a3 = 0.8974794
    b1 = 0.0684043
    b2 = 0.1162414
    b3 = 9.896161

    # Refractive index of fused silica at the given wavelength via Sellmeier equation
    nsi = sqrt(1 + a1 * (lambda^2) / (lambda^2 - b1^2) + a2 * (lambda^2) / (lambda^2 - b2^2) + a3 * (lambda^2) / (lambda^2 - b3^2))

    # Core and cladding indices
    nco = nsi
    ncl = sqrt.(nco .^ 2 - core_NA .^ 2)

    # Generate spatial grid
    dx = spatial_window / Nx
    x = collect(-Nx/2:Nx/2-1) * dx

    X, Y = meshgrid(x, x)

    # GRIN profile: parabolic (α=2) or general power-law index variation
    epsilon = max.(ncl, nco .- (nco - ncl) .* (sqrt.(X .^ 2 + Y .^ 2) / radius) .^ alpha) .^ 2

    return epsilon, x, dx
end

"""
    get_params(f0, c0, nx, spatial_window, radius, core_NA, alpha, M, Nt, Δt, β_order; Δf=1)

Compute the full dispersion tensor and nonlinear coefficient γ for a GRIN multimode
fiber by solving the eigenvalue problem at multiple frequencies and using finite
differences to obtain β derivatives.

# Procedure
1. Build a symmetric frequency stencil around f0 with spacing Δf [THz]
2. At each stencil frequency, solve the eigenvalue problem for M fiber modes → β(f)
3. Apply central finite differences to β(f) to get β₁, β₂, ..., βₙ derivatives
4. Construct the dispersion operator D(ω) = Σₙ βₙ/n! · ωⁿ (referenced to mode 1)
5. Solve modes at f0 to get spatial mode profiles, compute overlap tensor γ_{ijkl}

# Arguments
- `f0`: center frequency [THz]
- `c0`: speed of light [m/s]
- `nx`: spatial grid points per dimension
- `spatial_window`: grid extent [μm]
- `radius`: core radius [μm]
- `core_NA`: numerical aperture
- `alpha`: GRIN exponent
- `M`: number of modes to solve for
- `Nt`: temporal grid points
- `Δt`: temporal step [ps]
- `β_order`: highest dispersion order
- `Δf`: frequency step for finite differences [THz] (default 1)

# Returns
- `βn_ω`: dispersion coefficients matrix, shape (β_order+1, M)
- `Dω`: dispersion operator, shape (Nt, M) [rad/m]
- `γ`: Kerr nonlinearity tensor, shape (M, M, M, M) [W⁻¹m⁻¹]
- `ϕ`: eigenvectors (spatial mode profiles), shape (nx*nx, M)
- `x`: spatial grid [μm]
"""
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

    # Finite-difference derivatives of β(f)
    ∂nβ∂fn = zeros(β_order, M)
    for n in 1:β_order
        method = central_fdm(points, n)
        coeffs = method.coefs
        ∂nβ∂fn[n, :] = sum(coeffs .* β_f, dims=1) / (2 * π * Δf / 1e-12)^n
    end

    # Reference to mode 1: subtract β₀ and β₁ of mode 1 so that mode 1 has zero
    # propagation constant offset and group velocity offset
    βn_ω = [β_f[β_order+1, :]' .- β_f[β_order+1, 1]; ∂nβ∂fn[1, :]' .- ∂nβ∂fn[1, 1]; ∂nβ∂fn[2:end, :]]

    # Build dispersion operator D(ω) = Σₙ βₙ/n! · ωⁿ
    Dω = hcat([(2 * π * fftfreq(Nt, 1 / Δt) * 1e12) .^ n / factorial(n) for n in 0:β_order]...) * βn_ω

    # Compute nonlinear coefficient tensor from mode overlap integrals
    λ0 = c0 / f0 / 1e12
    eps, x, dx = build_GRIN(λ0 * 1e6, nx, spatial_window, radius, core_NA, alpha)
    _, ϕ, neff = solve_for_fiber_modes(λ0 * 1e6, 0., M, dx, dx, eps)
    modes = reshape(ϕ, (nx, nx, M))
    dx_SI = dx * 1e-6
    SK = compute_overlap_tensor(modes, dx_SI)
    n2 = 2.3e-20  # nonlinear refractive index of silica [m²/W]
    ω0 = 2 * π * f0 * 1e12
    γ = SK * n2 * ω0 / c0

    return βn_ω, Dω, γ, ϕ, x
end

"""
    solve_for_fiber_modes(λ, guess, nmodes, dx, dy, eps) -> (d, v, neff)

Solve the scalar wave equation eigenvalue problem for fiber spatial modes using a
5-point finite-difference stencil on a 2D grid.

The scalar wave equation in 2D is:
    (∂²/∂x² + ∂²/∂y²)ψ + ε(x,y)·(2π/λ)²·ψ = β²·ψ

This is discretized into a sparse matrix eigenvalue problem A·ψ = β²·ψ, solved
for the `nmodes` largest eigenvalues (highest β, i.e., most-bound modes) using
ARPACK's Lanczos iteration.

# Arguments
- `λ`: wavelength [μm]
- `guess`: initial eigenvalue guess (unused, set to 0)
- `nmodes`: number of modes to solve for
- `dx`, `dy`: spatial grid spacing [μm]
- `eps`: dielectric constant ε(x,y) = n²(x,y), shape (nx, ny)

# Returns
- `d`: eigenvalues β² [μm⁻²], length nmodes
- `v`: eigenvectors (mode profiles), shape (nx*ny, nmodes)
- `neff`: effective refractive indices = λ·√(β²)/(2π), length nmodes
"""
function solve_for_fiber_modes(λ, guess, nmodes, dx, dy, eps) #scalar only for now
    nx, ny = size(eps)

    n = dx * ones(1, nx * ny)
    s = dx * ones(1, nx * ny)
    e = dx * ones(1, nx * ny)
    w = dx * ones(1, nx * ny)
    p = dx * ones(1, nx * ny)
    q = dx * ones(1, nx * ny)

    ep = reshape(eps, (1, nx * ny))

    # Five-point stencil coefficients for ∇²
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

"""
    compute_overlap_tensor(modes, dx_SI) -> Array{Float64, 4}

Compute the 4-index nonlinear overlap tensor S_{ijkl} from spatial mode profiles:

    S_{ijkl} = ∫∫ ψ_i(x,y) · ψ_j(x,y) · ψ_k(x,y) · ψ_l(x,y) dx dy

Discretized as a Tullio contraction over spatial indices (m,n), scaled by dx² for
the area element. The result is used to construct the Kerr nonlinearity tensor
γ_{ijkl} = n₂·ω₀/c · S_{ijkl}.

# Arguments
- `modes`: spatial mode profiles, shape (nx, ny, M)
- `dx_SI`: spatial grid spacing in SI units [m]
"""
function compute_overlap_tensor(modes, dx_SI)
    M = size(modes)[3]
    SK = zeros(M, M, M, M)

    @tullio SK[i, j, k, l] = modes[m, n, i] * modes[m, n, j] * modes[m, n, k] * modes[m, n, l]

    SK = SK / dx_SI^2
    return SK
end
