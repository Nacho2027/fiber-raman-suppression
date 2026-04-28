# Portable Install Plan

- Track the Julia manifest and record tool versions with `.julia-version` and
  `.python-version`.
- Add `pyproject.toml` so the Python wrapper is installable without manual
  `PYTHONPATH`.
- Add a Dockerfile and `.dockerignore` for a reproducible Linux/headless setup.
- Extend the Makefile with Python install/tests, a `doctor` target, and Docker
  build/test targets.
- Update human docs to separate generic install, Docker, and Rivera Lab burst
  compute workflow.
- Run lightweight verification and record any local host limitations.
