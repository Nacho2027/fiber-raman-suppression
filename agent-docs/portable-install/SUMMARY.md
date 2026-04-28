# Portable Install Summary

Implemented a portability pass for fresh-machine setup:

- `Manifest.toml` is no longer ignored, so the pinned Julia environment can be
  committed.
- Added `.julia-version` (`1.12.6`) and `.python-version` (`3.11`).
- Added `pyproject.toml` for the `fiber-research-engine` Python wrapper.
- Added `Dockerfile` and `.dockerignore` for the reference Linux/headless
  environment.
- Added Makefile targets:
  - `make install-julia`
  - `make install-python`
  - `make test-python`
  - `make doctor`
  - `make docker-build`
  - `make docker-test`
- Updated README and docs with native install, Docker, and generic-vs-lab
  compute guidance.

Verification notes:

- Julia package status works with the local manifest on Julia 1.12.6.
- `make test` passed on this host.
- `PYTHONPATH=python python3 -m unittest discover -s test/python -p test_fiber_research_engine_cli.py`
  passed as a fallback check for the wrapper code.
- `pyproject.toml` parses successfully with Python 3.11 `tomllib`.
- Local host is missing `python3.11-venv` / `ensurepip`; `make install-python`
  now fails early with an actionable Debian/Ubuntu package hint.
- Docker was installed on 2026-04-27 from Docker's official Debian apt
  repository. `docker run --rm hello-world` passed.
- First Docker build exposed a PyCall/libpython issue. The Dockerfile now
  creates `/opt/venv`, installs matplotlib there, installs `python3-dev`, and
  builds PyCall with `PYTHON=/opt/venv/bin/python`.
- A later Docker build exposed a source-copy/precompile ordering issue. The
  Dockerfile now installs dependencies first, then copies the full tree and
  precompiles the project after `src/` is present.
- `make docker-build` completed and produced `fiber-raman-suppression:dev`.
- `make docker-test` passed inside the container: fast Julia tests plus 19
  Python wrapper unit tests.
- The container exports `VENV=/opt/venv` so Makefile Python targets use the
  prebuilt virtual environment.
- `.dockerignore` excludes Docker metadata and local/generated state from the
  build context.

Triple-verification pass requested on 2026-04-27:

- Install/daemon check passed: `systemctl is-active docker containerd`,
  `docker --version`, `docker info`, and `docker run --rm hello-world`.
- Source hygiene check passed: `git diff --check` on the changed portability
  files and `pyproject.toml` parsing with Python `tomllib`.
- Fresh image check passed after the finalized `.dockerignore`: `make
  docker-build` rebuilt and exported `fiber-raman-suppression:dev`.
- Container doctor check passed after that rebuild: `make docker-test` ran
  fast Julia tests and 19 Python wrapper tests inside Docker.
- Direct container runtime check passed: `using MultiModeNoise; using PyPlot`,
  Python `import fiber_research_engine`, and `VENV=/opt/venv`.
- Host cross-check passed: `make test` completed the fast Julia tier locally.
- Because additional synced/user-side edits appeared during verification, the
  current working tree was also mounted into the verified image and `make
  doctor` was rerun there. That passed with 586 Julia fast-tier assertions and
  19 Python wrapper tests.
