# cuda-code-server

**GPU-accelerated VS Code in a browser — CUDA 12.4 / 12.6, PyTorch, `uv`, and Claude Code preinstalled, ready to deploy on Dokploy.**

[![Build status](https://github.com/harshpatel333/cuda-code-server/actions/workflows/build.yml/badge.svg)](https://github.com/harshpatel333/cuda-code-server/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Docker Hub pulls](https://img.shields.io/docker/pulls/harshpatel333/cuda-code-server)](https://hub.docker.com/r/harshpatel333/cuda-code-server)
[![GHCR](https://img.shields.io/badge/GHCR-published-blue?logo=github)](https://github.com/harshpatel333/cuda-code-server/pkgs/container/cuda-code-server)
[![CUDA 12.4 | 12.6](https://img.shields.io/badge/CUDA-12.4%20%7C%2012.6-76B900?logo=nvidia)](#image-variants)
[![Python 3.11 | 3.12](https://img.shields.io/badge/Python-3.11%20%7C%203.12-3776AB?logo=python)](#image-variants)

`cuda-code-server` gives you a browser-based VS Code IDE that can actually see your GPU. Pull the image, run it with `--gpus all`, and `torch.cuda.is_available()` returns `True` on the first try. The image bundles CUDA 12.6.1 (or 12.4.1), cuDNN, PyTorch + torchvision + torchaudio, the Claude Code CLI, `uv`, Node.js 20, and the Docker CLI — so a fresh container is a complete ML development environment, not a shell you have to spend an afternoon outfitting.

Primary deploy target is [Dokploy](https://dokploy.com). Plain `docker run`, Docker Compose, and Kubernetes are all first-class too.

## Table of contents

- [Quick start](#quick-start)
- [Image variants](#image-variants)
- [Deploy on Dokploy](#deploy-on-dokploy-primary-target) (primary target)
- [Deploy with Docker Compose](#deploy-with-docker-compose)
- [Deploy on Kubernetes](#deploy-on-kubernetes)
- [Connecting and using](#connecting-and-using)
- [What's inside](#whats-inside)
- [Configuration](#configuration)
- [Building from source](#building-from-source)
- [Verifying GPU access](#verifying-gpu-access)
- [FAQ](#faq)
- [Contributing](#contributing)
- [Related projects](#related-projects)
- [License](#license)

## Quick start

**Prerequisites:** Docker 23+ and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) on the host. A quick host-side sanity check:

```bash
docker run --rm --gpus all nvidia/cuda:12.6.1-base-ubuntu22.04 nvidia-smi
```

If that prints the GPU table, the runtime is wired up. Now run cuda-code-server:

```bash
PASSWORD=$(openssl rand -base64 24)
echo "Save this password: $PASSWORD"

docker run -d \
  --name cuda-code-server \
  --gpus all \
  -e PASSWORD="$PASSWORD" \
  -p 8080:8080 \
  -v cuda-code-server-home:/home/coder \
  -v cuda-code-server-project:/home/coder/project \
  ghcr.io/harshpatel333/cuda-code-server:latest
```

Open `http://localhost:8080`, enter the password. In the integrated terminal (<kbd>Ctrl</kbd>+<kbd>\`</kbd>):

```bash
nvidia-smi
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count())"
```

Both should succeed. You now have a GPU-enabled VS Code.

## Image variants

Every variant is published to **both** registries (GHCR and Docker Hub) on every push to `main` and every `v*` tag.

| CUDA | Python | PyTorch wheel index | Tag | Notes |
|---|---|---|---|---|
| 12.6.1 | 3.12 | [`cu126`](https://download.pytorch.org/whl/cu126) | `12.6-py312` | **Default** — also tagged `:latest`. |
| 12.6.1 | 3.11 | `cu126` | `12.6-py311` | Use for libraries not yet on 3.12. |
| 12.4.1 | 3.12 | `cu124` | `12.4-py312` | Older CUDA — required for some drivers / libraries. |
| 12.4.1 | 3.11 | `cu124` | `12.4-py311` | The conservative combo. |

Additional tag shapes published on `v*` releases:

- `0.1.0-12.6-py312` — exact semver + variant (pin for reproducibility).
- `0.1-12.6-py312` — major.minor + variant (gets minor-version bugfixes).
- `sha-<short>-12.6-py312` — immutable SHA reference.

Pull examples:

```bash
docker pull ghcr.io/harshpatel333/cuda-code-server:latest
docker pull ghcr.io/harshpatel333/cuda-code-server:12.4-py311
docker pull docker.io/harshpatel333/cuda-code-server:0.1-12.6-py312
```

## Deploy on Dokploy (primary target)

Short version: paste [`examples/dokploy/docker-compose.yml`](./examples/dokploy/docker-compose.yml) into a Dokploy *Compose → Raw* service, set `PASSWORD` in the Environment tab, add your domain in the Domains tab, deploy. No Traefik labels needed — Dokploy wires them from the GUI.

Full step-by-step walkthrough (prereqs, gotchas, verification, GPU pinning, updating): **[docs/dokploy.md](./docs/dokploy.md)**.

## Deploy with Docker Compose

For a dev box on a trusted network (no reverse proxy). Copy [`examples/docker-compose/docker-compose.yml`](./examples/docker-compose/docker-compose.yml) and run:

```bash
curl -LO https://raw.githubusercontent.com/harshpatel333/cuda-code-server/main/examples/docker-compose/docker-compose.yml

PASSWORD=$(openssl rand -base64 24) docker compose up -d
echo "PASSWORD=$PASSWORD"
```

Port 8080 is exposed directly on the host. For anything internet-facing, front it with a TLS + auth layer — see [SECURITY.md](./SECURITY.md).

## Deploy on Kubernetes

[`examples/kubernetes/deployment.yaml`](./examples/kubernetes/deployment.yaml) includes a Deployment + Service + two PVCs (20 GiB home, 100 GiB project), plus a commented-out Ingress block for cert-manager setups.

Prerequisites: the [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin) on the cluster and a default StorageClass supporting `ReadWriteOnce`.

```bash
kubectl create secret generic cuda-code-server \
  --from-literal=password="$(openssl rand -base64 24)"

kubectl apply -f https://raw.githubusercontent.com/harshpatel333/cuda-code-server/main/examples/kubernetes/deployment.yaml
```

## Connecting and using

The full reference is [docs/usage.md](./docs/usage.md). Compact version below.

### Browser

Open the deployed URL, enter `PASSWORD`. The tab is a full VS Code — extensions install, the integrated terminal is a real bash shell inside the container, keyboard shortcuts work. Gotcha: <kbd>Ctrl</kbd>+<kbd>W</kbd> closes the browser tab — fix by installing the page as a PWA (Chromium address bar → *Install*) or by rebinding the shortcut in code-server settings.

### Local VS Code / Cursor / Windsurf

Using the browser IDE (installed as a PWA) is the fastest path for most users. If you specifically need Remote-SSH from desktop VS Code or a fork (Cursor, Windsurf, etc.), expose an `sshd` sidecar in your deployment and connect to it — covered in `docs/usage.md`.

### Integrated terminal

- Runs as the `coder` user (passwordless `sudo` is intentional — see [SECURITY.md](./SECURITY.md)).
- The Python venv at `/home/coder/.venv` auto-activates (torch, numpy, pandas, matplotlib, ipykernel preinstalled).
- `docker` CLI works against the host daemon if the socket is mounted — try `docker ps`.
- `gh` and `claude` are on `PATH`.

### Extensions

code-server installs from the [Open VSX](https://open-vsx.org/) registry (not Microsoft's marketplace — a licensing constraint). Most popular extensions are there. For Microsoft-exclusive ones: **Pyright** replaces Pylance, **clangd** replaces C/C++ IntelliSense, **Continue** or **Cline** for AI pair-programming. VSIX sideloading works too — see `docs/usage.md`.

Extensions persist across container restarts **only** if `/home/coder` is on a persistent volume.

### Git and SSH auth

Inside the container, `git` works but has no credentials. Either `gh auth login` (stores HTTPS token in `~/.config/gh`, which is on the persistent volume) or generate a key with `ssh-keygen -t ed25519` and add the public key to GitHub — `~/.ssh` is also persistent.

### Jupyter / notebooks

Open a `.ipynb` file in VS Code — the built-in Jupyter support uses the container's kernel (`ipykernel` is preinstalled). No separate server needed. If you want JupyterLab specifically: `uv pip install jupyterlab` into a project venv, run `jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token=''` with port 8888 exposed.

## What's inside

This table reflects the **default** build (CUDA 12.6.1, Python 3.12). The other matrix cells differ only in CUDA and Python minor version.

| Component | Version / source | How it was installed |
|---|---|---|
| Base image | `nvidia/cuda:12.6.1-cudnn-devel-ubuntu22.04` | `FROM` |
| CUDA Toolkit | 12.6.1 | from base image |
| cuDNN | from base image (devel variant) | included |
| Python | 3.12 (or 3.11) | [deadsnakes PPA](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa) |
| PyTorch + torchvision + torchaudio | latest on `cu126` (or `cu124`) | `uv pip install --index-url https://download.pytorch.org/whl/cu126 …` |
| NumPy, pandas, matplotlib | latest on PyPI | `uv pip install` |
| `ipykernel` | latest on PyPI | `uv pip install` — backs VS Code's Jupyter support |
| [`uv`](https://github.com/astral-sh/uv) | latest | Astral's official install script, system-wide |
| Node.js | 20.x | [NodeSource](https://github.com/nodesource/distributions) apt |
| Docker CLI + Compose + Buildx | latest stable | [Docker's official apt repo](https://docs.docker.com/engine/install/ubuntu/) |
| [`code-server`](https://github.com/coder/code-server) | latest stable | Coder's official install script |
| [Claude Code CLI](https://www.anthropic.com/claude-code) | latest on npm | `npm install -g @anthropic-ai/claude-code` (opt out with `--build-arg INSTALL_CLAUDE_CODE=false`) |
| Shell tools | git, git-lfs, build-essential, openssh-client, jq, tmux, htop, vim, nano, ripgrep, unzip, sudo, gosu | distro apt |

Persistent paths — mount these as volumes for a durable environment:

| Path | Contents |
|---|---|
| `/home/coder` | settings, VS Code extensions, `.venv`, SSH keys, `gh` auth, shell history |
| `/home/coder/project` | your code (default working directory inside the IDE) |

## Configuration

Environment variables. All are read by the container at startup.

| Variable | Required | Purpose |
|---|---|---|
| `PASSWORD` | yes (or `HASHED_PASSWORD`) | Browser login password for code-server. |
| `HASHED_PASSWORD` | alternative | argon2id hash; takes precedence over `PASSWORD`. |
| `SUDO_PASSWORD` | no | Sudo password inside the container. Unset = passwordless (recommended for dev). |
| `TZ` | no | Timezone (e.g., `America/New_York`). Default `UTC`. |
| `CODE_SERVER_ARGS` | no | Extra args appended to the default `code-server` command. |
| `NVIDIA_VISIBLE_DEVICES` | no | Standard NVIDIA runtime var. Set to `all` for all GPUs. |
| `NVIDIA_DRIVER_CAPABILITIES` | no | Standard NVIDIA runtime var. Typical: `compute,utility`. |

Generate a hashed password (argon2id):

```bash
echo -n "your-password" | argon2 "$(openssl rand -hex 8)" -e
```

Rotate a password: change `PASSWORD` in your compose / k8s / docker-run config, restart the container.

## Building from source

Default variant:

```bash
git clone https://github.com/harshpatel333/cuda-code-server
cd cuda-code-server

docker build \
  --build-arg CUDA_VERSION=12.6.1 \
  --build-arg PYTHON_VERSION=3.12 \
  --build-arg TORCH_CUDA=cu126 \
  -t cuda-code-server:local .
```

Expect ~15–30 min on a cold cache, ~5–10 min warm. Final image is ~14 GB uncompressed.

Without the Claude Code CLI:

```bash
docker build --build-arg INSTALL_CLAUDE_CODE=false -t cuda-code-server:local-noclaude .
```

Other matrix cells: set `CUDA_VERSION=12.4.1 TORCH_CUDA=cu124` for the older-CUDA variants, `PYTHON_VERSION=3.11` for the older-Python variants.

## Verifying GPU access

In the integrated terminal:

```bash
nvidia-smi
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count())"
python -c "import torch; x = torch.randn(1000, 1000).cuda(); print((x @ x).sum().item())"
```

All three should succeed. If `nvidia-smi` works on the host but not in the container, the NVIDIA Container Toolkit is missing or misconfigured on the host. On Ubuntu:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Canonical reference: [NVIDIA Container Toolkit install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

## FAQ

### `nvidia-smi` works on the host but not in the container

The NVIDIA Container Toolkit isn't installed or configured on the host. See [Verifying GPU access](#verifying-gpu-access) above.

### PyTorch cannot find CUDA

You're running a mismatched CUDA-and-torch pair. This image pairs 12.6.1 with `cu126` wheels, 12.4.1 with `cu124`. If you installed torch yourself over the bundled venv, reinstall with the correct index: `uv pip install --index-url https://download.pytorch.org/whl/cu126 --force-reinstall torch`.

### `docker ps` in the container says "permission denied on /var/run/docker.sock"

The entrypoint normally fixes this automatically by aligning the in-container `docker` group GID with the host socket's GID. If it didn't (e.g., you overrode `USER` in compose), open a fresh terminal — or run `sudo groupmod -g "$(stat -c '%g' /var/run/docker.sock)" docker && newgrp docker`.

### Which tag should I use?

For reproducible deployments, pin a tag with version + variant, e.g., `0.1-12.6-py312`. For a dev box that tracks updates, `latest` (or just the variant, `12.6-py312`) is fine.

### Can I add my own extensions, libraries, or system packages?

Yes — with different persistence guarantees:

- **VS Code extensions** — install from the in-browser marketplace; they persist on the `home` volume.
- **Python packages** — `uv pip install <pkg>` inside the venv (persistent), or create a project-specific venv with `uv venv` in `/home/coder/project`.
- **System packages** — `sudo apt install <pkg>` works but is **not** persistent (root filesystem is ephemeral). For persistent system-level changes, extend this image:

  ```dockerfile
  FROM ghcr.io/harshpatel333/cuda-code-server:12.6-py312
  USER root
  RUN apt-get update && apt-get install -y ffmpeg libgl1 && rm -rf /var/lib/apt/lists/*
  USER coder
  ```

### Is this safe to put on the public internet?

Only with a strong random password **and** an auth-aware reverse proxy (or a VPN / IP allowlist). code-server with a weak password exposed on the internet is effectively remote code execution. See [SECURITY.md](./SECURITY.md).

### How do I update?

Pull the new tag, recreate the container with the same volume mounts. Persistent volumes (`home`, `project`) survive. Breaking changes are called out per-version in [CHANGELOG.md](./CHANGELOG.md).

### How do I remove the bundled Claude Code CLI?

Build your own variant with `--build-arg INSTALL_CLAUDE_CODE=false`, or run `sudo npm uninstall -g @anthropic-ai/claude-code` at runtime (non-persistent — reinstalled on the next image pull).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Short version: bug fixes and small additions are welcome; project-specific tooling (R, Julia, particular Jupyter kernels) belongs in a child Dockerfile rather than the base image.

Security issues: private email per [SECURITY.md](./SECURITY.md), not GitHub issues.

## Related projects

- [code-server](https://github.com/coder/code-server) — the browser-based VS Code this image wraps.
- [Dokploy](https://dokploy.com) — the self-hosted PaaS this image targets as primary deploy.
- [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit) — makes `--gpus all` work.
- [`uv`](https://github.com/astral-sh/uv) — the Python package manager baked in.
- [Dev Containers spec](https://containers.dev/) — related specification for VS Code containerised development.

## License

[MIT](./LICENSE). Copyright © 2026 Harsh Patel.

## Acknowledgments

Built on top of [code-server](https://github.com/coder/code-server), [NVIDIA CUDA base images](https://hub.docker.com/r/nvidia/cuda), and the broader NVIDIA Container Toolkit ecosystem. Dokploy deployment patterns draw on community templates from the Dokploy Discord.

---

<sub>Keywords: GPU Docker container, CUDA code-server, VS Code GPU, remote ML development, Dokploy GPU, self-hosted development environment, PyTorch Docker, cuDNN code-server, browser IDE GPU, CUDA development container, Claude Code Docker, uv Docker, NVIDIA Container Toolkit, code-server GPU, self-hosted VS Code, devcontainer GPU.</sub>
