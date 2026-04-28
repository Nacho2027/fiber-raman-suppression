# Portable Install Context

The portability audit found that the maintained Julia command surface was
documented, but the repo still had several machine-specific setup assumptions:

- `Manifest.toml` existed locally but was ignored by git, while docs described
  a pinned manifest.
- The Python notebook wrapper under `python/fiber_research_engine` had tests
  but no package metadata, so imports required `PYTHONPATH=python`.
- No Docker reference environment existed for clean Linux/headless setup.
- The docs mixed generic install guidance with the Rivera Lab
  `claude-code-host` / `fiber-raman-burst` workflow.

Official references checked during the pass:

- Docker Hub official `julia` image tags include `1.12.6-bookworm`.
- Setuptools documentation recommends `pyproject.toml` with a build-system
  section and explicit package discovery for non-trivial layouts.
