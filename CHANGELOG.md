# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

Initial v0.1.0 feature set:

- Build matrix of 4 variants: CUDA **12.6.1** and **12.4.1** × Python **3.11** and **3.12**.
- Base image: `nvidia/cuda:<version>-cudnn-devel-ubuntu22.04` (cuDNN + `nvcc` included for compiling custom kernels).
- Bundled tooling: PyTorch + torchvision + torchaudio (matched to CUDA), NumPy / pandas / matplotlib, Node.js 20 + npm, Docker CLI + Compose plugin, `uv` Python package manager, `code-server`, Claude Code CLI (`@anthropic-ai/claude-code`), plus a standard dev shell (git, git-lfs, jq, tmux, htop, build-essential, SSH client, etc.).
- Non-root `coder` user (UID/GID 1000) with passwordless sudo and `docker` group membership.
- Python virtualenv at `/home/coder/.venv`, auto-activated in `.bashrc` for new shells.
- Entrypoint enforces `PASSWORD` / `HASHED_PASSWORD` and auto-fixes `docker.sock` GID mismatch between host and container.
- OCI image labels, healthcheck on `/healthz`, `EXPOSE 8080`.
- GitHub Actions workflow: parallel matrix build on PR/push/tag, GHCR + Docker Hub dual publishing, metadata-driven tags (`<cuda>-py<python>`, `latest`, semver variants, SHA-pinned), Docker Hub README sync on `main`.
- Deployment examples: Dokploy (Raw compose), plain Docker Compose, Kubernetes.
- Documentation: `README.md`, `docs/usage.md` (connecting, extensions, persistence, troubleshooting), `docs/dokploy.md` (step-by-step guide).

### Roadmap (not in v0.1.0 — tracked as follow-ups)

- Ubuntu 24.04 variants.
- `linux/arm64` platform.
- Cosign signing + SBOM generation.
- Trivy / Grype scans in CI (non-blocking).
- Helm chart for Kubernetes.
- `devcontainer.json` so the repo itself opens in Codespaces.
- Optional specializations: `-jupyter`, `-tensorflow`.
- Pre-built `INSTALL_CLAUDE_CODE=false` variant.

[Unreleased]: https://github.com/harshpatel333/cuda-code-server/commits/main
