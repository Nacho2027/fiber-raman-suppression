# Container Workflow

[← docs index](../README.md) · [installation](./installation.md)

The Docker image is the reference Linux/headless environment for the supported
install surface. It is useful when a laptop, workstation, or temporary VM should
run the same Julia/Python stack without host-specific Python or matplotlib
setup.

## Build

```bash
make docker-build
```

This builds `fiber-raman-suppression:dev` from `Dockerfile`. The image uses the
official `julia:1.12.6-bookworm` base, installs the small Linux system package
set needed by PyPlot/matplotlib, instantiates the Julia environment from
`Manifest.toml`, and installs the Python wrapper from `pyproject.toml`.

Override the image name if needed:

```bash
make docker-build DOCKER_IMAGE=my-raman:dev
```

## Verify

```bash
make docker-test
```

This runs `make doctor` inside the container: tool checks, the fast Julia test
tier, and the Python wrapper tests.

## Run A Canonical Optimization

```bash
docker run --rm \
  -v "$PWD/results:/workspace/fiber-raman-suppression/results" \
  fiber-raman-suppression:dev \
  make optimize
```

The bind mount keeps generated run artifacts on the host under `results/`.
The optimization is CPU-only and can take several minutes depending on the
machine.

## When To Use Native Install Instead

Use the native install path for routine development, local plotting inspection,
and the Rivera Lab burst-VM workflow. Use Docker for reproducible setup checks,
new machine onboarding, and disposable Linux runs.
