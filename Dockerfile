# syntax=docker/dockerfile:1.7

# hadolint global ignore=DL3008,DL3016,DL3002
# DL3008 (apt pin) / DL3016 (npm pin): image tracks latest patches on every
# push to main; pinning would freeze us to one build day.
# DL3002 (last USER should not be root): entrypoint briefly needs root to align
# the in-container `docker` group GID with /var/run/docker.sock, then drops to
# `coder` via gosu — same pattern as the upstream code-server image.

# -----------------------------------------------------------------------------
# cuda-code-server — GPU-accelerated VS Code (code-server) with CUDA, cuDNN,
# PyTorch, uv, Docker CLI, Node.js, and the Claude Code CLI preinstalled.
# Build matrix is CUDA × Python — see README for the full tag list.
# -----------------------------------------------------------------------------

ARG CUDA_VERSION=12.6.1
ARG UBUNTU_VERSION=22.04
FROM nvidia/cuda:${CUDA_VERSION}-cudnn-devel-ubuntu${UBUNTU_VERSION}

ARG PYTHON_VERSION=3.12
ARG TORCH_CUDA=cu126
ARG INSTALL_CLAUDE_CODE=true

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# pipefail so `curl | sh`-style installs fail loudly if the download fails.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# 1. OS packages — dev shell + apt-repo prep + gosu for privilege drop
# -----------------------------------------------------------------------------
# One big apt layer up-front: this group rarely changes, so it maximises cache
# hits on later, more-volatile layers (pip / npm installs).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release software-properties-common \
        tzdata locales sudo gosu \
        git git-lfs openssh-client \
        build-essential pkg-config \
        jq tmux htop less unzip ripgrep \
        vim nano \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 2. Python via deadsnakes PPA
# -----------------------------------------------------------------------------
# Ubuntu 22.04's distro Python is capped at 3.10; deadsnakes is the standard
# way to get 3.11 / 3.12. Alternative (pyenv, uv-managed Python) would be an
# extra layer of abstraction for marginal benefit in a fixed-matrix image.
RUN add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev \
        python${PYTHON_VERSION}-venv \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/local/bin/python \
    && ln -sf /usr/bin/python${PYTHON_VERSION} /usr/local/bin/python3 \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 3. Node.js 20 via NodeSource
# -----------------------------------------------------------------------------
# NodeSource: system-wide, stable, fast patch cadence. `nvm` would be per-user
# and awkward in a shared image.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 4. Docker CLI + compose/buildx plugins (no daemon — uses host socket)
# -----------------------------------------------------------------------------
# Docker's official apt repo: Ubuntu's distro `docker.io` is usually several
# releases behind and ships without the v2 compose plugin.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 5. uv — fast Python package manager
# -----------------------------------------------------------------------------
# Official install script: single static binary, fastest update cadence. A
# `pip install uv` bootstrap would work too but wastes a layer.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx \
    && rm -rf /root/.local /root/.cache

# -----------------------------------------------------------------------------
# 6. code-server
# -----------------------------------------------------------------------------
# Official install script: pins a known-good release and handles arch detection.
# Using Coder's published Docker image as a base was considered but would couple
# this image to their base-OS / toolchain choices instead of ours.
RUN curl -fsSL https://code-server.dev/install.sh | sh

# -----------------------------------------------------------------------------
# 7. Claude Code CLI (opt-out via INSTALL_CLAUDE_CODE=false build arg)
# -----------------------------------------------------------------------------
RUN if [ "${INSTALL_CLAUDE_CODE}" = "true" ]; then \
        npm install -g @anthropic-ai/claude-code; \
    fi

# -----------------------------------------------------------------------------
# 8. Non-root user `coder` (UID/GID 1000)
# -----------------------------------------------------------------------------
# UID 1000 is the Linux host-user default; bind-mounted files retain correct
# ownership. Passwordless sudo is intentional (dev ergonomics; see SECURITY.md
# — the container *is* the security boundary). The `docker` group GID is a
# placeholder; the entrypoint rewrites it at runtime to match the host socket.
RUN groupadd --gid 1000 coder \
    && useradd --uid 1000 --gid coder --create-home --shell /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder \
    && groupadd -f --gid 998 docker \
    && usermod -aG docker coder \
    && mkdir -p /home/coder/project \
    && chown -R coder:coder /home/coder

# -----------------------------------------------------------------------------
# 9. PyTorch + ML stack in the bundled venv at /home/coder/.venv
# -----------------------------------------------------------------------------
USER coder
WORKDIR /home/coder

ENV VIRTUAL_ENV=/home/coder/.venv \
    PATH=/home/coder/.venv/bin:${PATH}

# torch/torchvision/torchaudio from the CUDA-matched PyTorch wheel index.
# numpy/pandas/matplotlib/ipykernel → "useful out of the box" for ML dev and
# for .ipynb editing via VS Code's built-in Jupyter support.
# Jupyter*Lab* (the web UI) is intentionally omitted — saves ~500 MB on the
# image; users who want it can `uv pip install jupyterlab` themselves.
RUN uv venv --python /usr/bin/python${PYTHON_VERSION} "${VIRTUAL_ENV}" \
    && uv pip install --no-cache \
        --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
        --extra-index-url https://pypi.org/simple \
        torch torchvision torchaudio \
        numpy pandas matplotlib ipykernel

# Auto-activate the bundled venv for interactive shells (cosmetic: PATH is
# already set via ENV; this adds the `(.venv)` prompt prefix and VIRTUAL_ENV).
RUN { \
        echo ''; \
        echo '# cuda-code-server: auto-activate bundled venv for new shells'; \
        echo '[ -f /home/coder/.venv/bin/activate ] && source /home/coder/.venv/bin/activate'; \
    } >> /home/coder/.bashrc

# -----------------------------------------------------------------------------
# 10. Entrypoint — runs as root to align GIDs, then drops to `coder`
# -----------------------------------------------------------------------------
USER root
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

LABEL org.opencontainers.image.title="cuda-code-server" \
      org.opencontainers.image.description="GPU-accelerated VS Code server with CUDA, cuDNN, PyTorch, and Claude Code CLI preinstalled." \
      org.opencontainers.image.source="https://github.com/harshpatel333/cuda-code-server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Harsh Patel"

WORKDIR /home/coder/project
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fsSL http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["code-server", "--bind-addr", "0.0.0.0:8080", "--disable-telemetry", "/home/coder/project"]
