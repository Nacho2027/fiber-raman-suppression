# Container

Use Docker when you want the same Linux/headless environment on any host.

```bash
make docker-build
make docker-test
```

`make docker-test` runs `make doctor` inside the image. It is a setup check,
not a replacement for physics validation.

To run one command manually:

```bash
docker run --rm fiber-raman-suppression:dev julia -t auto --project=. scripts/canonical/optimize_raman.jl --list
```

Do not use the container as a way to hide large local runs on a small machine.
Heavy sweeps still belong on burst.
