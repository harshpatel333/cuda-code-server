# Using cuda-code-server

A detailed reference for the workflow inside the container once it's running. The README has the compact version; this doc is the full tour.

## Table of contents

1. [Accessing the IDE in the browser](#1-accessing-the-ide-in-the-browser)
2. [Connecting from local VS Code](#2-connecting-from-local-vs-code)
3. [Connecting from Cursor, Windsurf, and other VS Code forks](#3-connecting-from-cursor-windsurf-and-other-vs-code-forks)
4. [The integrated terminal](#4-the-integrated-terminal)
5. [Installing extensions](#5-installing-extensions)
6. [Working with your code](#6-working-with-your-code)
7. [Git and SSH auth](#7-git-and-ssh-auth)
8. [Running ML workloads — quick verification](#8-running-ml-workloads--quick-verification)
9. [Installing project-specific dependencies](#9-installing-project-specific-dependencies)
10. [Jupyter and notebooks](#10-jupyter-and-notebooks)
11. [Persistence and backups](#11-persistence-and-backups)
12. [Updating the image](#12-updating-the-image)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Accessing the IDE in the browser

Navigate to your deployed URL (or `http://<host>:8080` for plain Docker) and enter `PASSWORD`. You're now in a full VS Code — extensions install, the integrated terminal is a real bash shell inside the container, keyboard shortcuts work.

**One gotcha — browser shortcut collisions.** In a browser tab:

- <kbd>Ctrl</kbd>+<kbd>W</kbd> closes the tab.
- <kbd>Ctrl</kbd>+<kbd>N</kbd> opens a new browser window.
- <kbd>Ctrl</kbd>+<kbd>T</kbd> opens a new browser tab.

Two fixes, either works:

- **Install as a PWA.** Chrome / Edge address bar → the Install icon → *Install cuda-code-server*. Opens in a standalone window with no browser keybindings stealing yours.
- **Rebind in code-server.** <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd> → *Preferences: Open Keyboard Shortcuts* → reassign the conflicting bindings.

## 2. Connecting from local VS Code

The browser IDE is the fastest path for casual work — install it as a PWA and it behaves like a native app. For deeper workflows (Microsoft-exclusive extensions like Pylance or Copilot, SSH-agent forwarding, native window chrome), use **Remote-SSH**.

The image ships with `openssh-server` baked in, off by default. Enable it with three env vars on your deployment:

```yaml
environment:
  ENABLE_SSHD: "true"
  SSH_PORT: "2222"                                             # optional, 2222 is the default
  SSH_AUTHORIZED_KEYS: "ssh-ed25519 AAAAC3Nz... you@laptop"
```

Then expose port `2222` — the mechanism depends on your deployment target (Dokploy: direct host port or Traefik TCP entrypoint; Kubernetes: `Service` of type `NodePort` / `LoadBalancer`; plain Docker: `-p 2222:2222`).

Connect from local VS Code:

1. Install the **Remote - SSH** extension.
2. Add to `~/.ssh/config`:

   ```
   Host cuda-code-server
     HostName your-deployment.example.com
     Port 2222
     User coder
     IdentityFile ~/.ssh/id_ed25519
   ```

3. <kbd>F1</kbd> → *Remote-SSH: Connect to Host...* → `cuda-code-server`.
4. *File → Open Folder* → `/home/coder/project`.

Full walk-through (Cursor, Windsurf, plain `ssh`, Dokploy TCP exposure, `~/.ssh/config` template, key rotation, troubleshooting): **[docs/remote-ssh.md](./remote-ssh.md)**.

## 3. Connecting from Cursor, Windsurf, and other VS Code forks

Same as VS Code — Cursor and Windsurf both ship compatible Remote-SSH extensions. Same `~/.ssh/config` entry, same connect flow. One caveat: Cursor's marketplace is Open VSX (same as code-server), so Microsoft-exclusive extensions aren't available in Cursor even over Remote-SSH. Free equivalents (Pyright, clangd, Continue) work fine.

Per-fork specifics in **[docs/remote-ssh.md](./remote-ssh.md)**.

## 4. The integrated terminal

Open with <kbd>Ctrl</kbd>+<kbd>\`</kbd> (backtick). It's a real interactive bash shell, running as the `coder` user inside the container.

- **Python venv auto-activates.** `/home/coder/.venv` is both on `PATH` (baked in via Dockerfile `ENV`) and `source`d at shell start (via `.bashrc`). `python` and `pip` are the venv's. Deactivate with `deactivate`.
- **`sudo` is passwordless.** Install system packages with `sudo apt install <pkg>` — but know that the root filesystem is ephemeral; on container recreation those packages are gone. For persistent system changes, use a child Dockerfile (§12 below).
- **`docker` CLI** works against the host daemon if you mounted `/var/run/docker.sock`. Test with `docker ps`. If it says permission denied, the entrypoint's GID fixup didn't take hold — open a fresh terminal, or see §13.
- **`gh` and `claude`** are on PATH. `gh auth login` for GitHub; `claude` to launch the Claude Code CLI.

## 5. Installing extensions

Extensions install from **Open VSX**, not the Microsoft marketplace. code-server uses Open VSX for licensing reasons — Microsoft explicitly disallows non-Microsoft VS Code distributions from using their marketplace.

Most popular extensions are on Open VSX. The UX is identical: <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>X</kbd>, search, install.

**Microsoft-exclusive extensions and their Open VSX substitutes:**

| Microsoft-only | Free alternative on Open VSX |
|---|---|
| Pylance | [Pyright](https://open-vsx.org/extension/ms-pyright/pyright) (same engine, MIT-licensed) |
| C/C++ IntelliSense | [clangd](https://open-vsx.org/extension/llvm-vs-code-extensions/vscode-clangd) |
| Remote-Containers | You're already running in a container — the Dev Containers workflow isn't needed here |
| GitHub Copilot (Microsoft build) | [Continue](https://open-vsx.org/extension/Continue/continue), [Cline](https://open-vsx.org/extension/saoudrizwan/claude-dev) — both capable AI coding assistants |

**Sideloading a VSIX** (for extensions you have as a `.vsix` file):

```bash
# Downloaded .vsix from a GitHub Release or the extension author's site:
curl -LO 'https://example.com/my-extension.vsix'
code-server --install-extension ./my-extension.vsix

# Then reload the IDE:
#   Ctrl+Shift+P → "Developer: Reload Window"
```

**Persistence.** Installed extensions live under `/home/coder/.local/share/code-server/extensions`. They persist across container restarts only if `/home/coder` is on a volume (it should be — see §11).

## 6. Working with your code

Three patterns, in order of preference:

### Clone inside the container

```bash
cd ~/project
git clone git@github.com:you/your-repo.git
cd your-repo
```

First-time: you'll need SSH or HTTPS credentials — see §7.

### Bind-mount a host directory into `/home/coder/project`

Good if you want code to live on the host filesystem so it survives container deletion independent of the named `project` volume. In `docker-compose.yml`:

```yaml
volumes:
  - /path/on/host:/home/coder/project
```

Watch for file ownership: if the host user's UID ≠ 1000, bind-mounted files may appear as `nobody:nogroup` inside the container. Either align the host user to UID 1000, or add a `chown` step in a child Dockerfile.

### Drag-and-drop upload

Drag files from your desktop into the VS Code file explorer in the browser. Fine for one-off uploads; not great for Git workflows. Uses the browser's File API — no need for `scp` or `rsync`.

## 7. Git and SSH auth

Inside the container, `git` works but has no credentials out of the box. Two options:

### SSH keys (recommended for browser-only users)

```bash
# Generate a key:
ssh-keygen -t ed25519 -C "coder@cuda-code-server" -f ~/.ssh/id_ed25519 -N ''

# Print the public key so you can paste it into GitHub:
cat ~/.ssh/id_ed25519.pub
```

Go to GitHub → Settings → *SSH and GPG keys* → *New SSH key*, paste, save.

Test:

```bash
ssh -T git@github.com
# should say: "Hi <you>! You've successfully authenticated..."
```

`~/.ssh` persists on the `home` volume; the key survives container recreation.

### HTTPS via `gh` CLI

```bash
gh auth login
# pick "GitHub.com", HTTPS, and "Login with a web browser"
```

`gh` stores credentials in `~/.config/gh` (also on the home volume). After this, `gh repo clone <owner>/<repo>` and plain `git clone https://github.com/...` both work.

### SSH agent forwarding (Remote-SSH users only)

If you connect from local VS Code via Remote-SSH, the host's `ssh-agent` is forwarded — `git` inside the container uses your laptop's keys. Not available in pure browser mode.

## 8. Running ML workloads — quick verification

In the terminal:

```bash
# GPU visible?
nvidia-smi

# PyTorch sees CUDA?
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count())"

# Actually run on the GPU:
python -c "import torch; x = torch.randn(1000, 1000).cuda(); print((x @ x).sum().item())"
```

A short end-to-end smoke test — MNIST-shaped MLP on GPU, three training epochs:

```python
import torch, torch.nn as nn, torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset

device = torch.device("cuda")

# Fake MNIST-shaped data so we don't need torchvision datasets on disk.
X = torch.randn(1024, 784, device=device)
y = torch.randint(0, 10, (1024,), device=device)
loader = DataLoader(TensorDataset(X, y), batch_size=64, shuffle=True)

model = nn.Sequential(nn.Linear(784, 128), nn.ReLU(), nn.Linear(128, 10)).to(device)
opt = torch.optim.Adam(model.parameters(), lr=1e-3)

for epoch in range(3):
    for xb, yb in loader:
        opt.zero_grad()
        loss = F.cross_entropy(model(xb), yb)
        loss.backward()
        opt.step()
    print(f"epoch {epoch} loss={loss.item():.4f}")

print("done — ran on", next(model.parameters()).device)
```

If this finishes and prints `cuda:0` for the device, the full stack is healthy.

## 9. Installing project-specific dependencies

The bundled venv (`/home/coder/.venv`) has the common ML libs (torch, numpy, pandas, matplotlib, ipykernel). For real project work, create a per-project venv so your dependency graph is reproducible:

```bash
cd ~/project/your-repo
uv venv                       # creates .venv here, fast
source .venv/bin/activate
uv pip install -r requirements.txt
```

`uv` is fast at this — cold `uv pip install` of a typical requirements.txt is 5–20× faster than `pip`.

Other toolchains (Poetry, Pipenv, plain pip, conda) work too — the base tooling is all there. Pick whatever your project already uses.

For installing torch into a project venv, remember to pass the CUDA-matched index:

```bash
uv pip install --index-url https://download.pytorch.org/whl/cu126 torch
```

## 10. Jupyter and notebooks

**The recommended path: VS Code's built-in Jupyter support.** Open a `.ipynb` file in the IDE. VS Code auto-discovers the container's Python kernels — select the bundled one at `/home/coder/.venv/bin/python` (shown as `.venv` in the kernel picker) or any project-specific venv you've created. No separate server, no port forwarding, full notebook UX inside the IDE.

**If you want `jupyter lab` specifically** (e.g., because you have existing JupyterLab workflows):

```bash
uv pip install jupyterlab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token=''
```

Then expose port 8888 in your deployment (add `"8888:8888"` to `ports:` in compose, or add a Service + Ingress in Kubernetes). Remember: `--NotebookApp.token=''` means no auth, so gate it behind your reverse proxy's auth layer or restrict it to localhost.

## 11. Persistence and backups

### What IS persistent

Anything under `/home/coder`, if the directory is a named or bind-mounted volume. Specifically:

- `/home/coder/.local/share/code-server/` — installed extensions, keybindings, user settings.
- `/home/coder/.config/` — app configs (`gh` auth, git config, etc.).
- `/home/coder/.ssh/` — SSH keys (so `git clone git@github.com:...` keeps working).
- `/home/coder/.bash_history`, `/home/coder/.venv/` — shell history and the bundled venv.
- `/home/coder/project/` — your code (typically a separate volume).

### What is NOT persistent

Everything else:

- `/tmp`, `/var/tmp`, `/root`.
- System packages installed via `sudo apt install …` at runtime.
- Modified system configs (`/etc/*`).
- Internal `code-server` state outside `/home/coder`.

For persistent system-level changes, extend via a child Dockerfile:

```dockerfile
FROM ghcr.io/harshpatel333/cuda-code-server:12.6-py312
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libgl1 \
    && rm -rf /var/lib/apt/lists/*
USER coder
```

Build locally or push to your own registry, then use that image.

### Backups

**Ad-hoc tarball of a named volume** (works for Docker Compose / plain `docker run`):

```bash
VOLUME=cuda-code-server-project
docker run --rm \
  -v "${VOLUME}:/data" \
  -v "$(pwd):/backup" \
  alpine \
  tar czf "/backup/${VOLUME}-$(date +%F).tar.gz" -C /data .
```

Restore into an empty volume:

```bash
docker volume create cuda-code-server-project
docker run --rm \
  -v cuda-code-server-project:/data \
  -v "$(pwd):/backup" \
  alpine \
  tar xzf /backup/cuda-code-server-project-YYYY-MM-DD.tar.gz -C /data
```

For **Dokploy**, enable host-level volume snapshots via the Dokploy Volumes tab. For **Kubernetes**, use a CSI driver that supports snapshots (Longhorn, Rook-Ceph, cloud-provider CSIs).

## 12. Updating the image

### Plain Docker

```bash
docker pull ghcr.io/harshpatel333/cuda-code-server:12.6-py312
docker stop cuda-code-server && docker rm cuda-code-server
docker run -d \
  --name cuda-code-server \
  --gpus all \
  -e PASSWORD="$PASSWORD" \
  -p 8080:8080 \
  -v cuda-code-server-home:/home/coder \
  -v cuda-code-server-project:/home/coder/project \
  ghcr.io/harshpatel333/cuda-code-server:12.6-py312
```

### Docker Compose

```bash
docker compose pull
docker compose up -d
```

### Dokploy

Change the `image:` tag in the compose file. Click *Redeploy*.

### Kubernetes

Edit the tag in the Deployment manifest and `kubectl apply -f deployment.yaml`. The `strategy: Recreate` in the manifest ensures the old pod releases the `ReadWriteOnce` PVCs before the new pod claims them.

Persistent volumes (`home`, `project`) survive every update. Breaking changes between versions are called out in [CHANGELOG.md](../CHANGELOG.md).

## 13. Troubleshooting

### `nvidia-smi` works on the host but not in the container

The NVIDIA Container Toolkit isn't installed or configured on the host. Install and restart Docker:

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

Canonical reference: [NVIDIA docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

### `docker ps` in the container says "permission denied on /var/run/docker.sock"

The entrypoint normally aligns the in-container `docker` group GID with the host socket's GID at startup. If it didn't work (e.g., you overrode `USER` in compose, or the socket wasn't mounted at first boot), fix manually:

```bash
sudo groupmod -g "$(stat -c '%g' /var/run/docker.sock)" docker
newgrp docker       # or: open a fresh terminal
```

### Extensions I need aren't in the Open VSX marketplace

Three options, in order of effort:

- **Use a free alternative** from the table in §5.
- **Sideload a VSIX**: download the `.vsix` (from the extension's GitHub Releases or the author's site), then `code-server --install-extension ./*.vsix` in the terminal.
- **Fall back to Remote-SSH from local VS Code** against a version of the container with `sshd` exposed — desktop VS Code can use the Microsoft marketplace.

### PyTorch cannot find CUDA

You're running a mismatched CUDA-and-torch pair. The image pairs:

- CUDA 12.6.1 with `cu126` PyTorch wheels.
- CUDA 12.4.1 with `cu124` PyTorch wheels.

If you installed torch yourself and bypassed the correct index, reinstall:

```bash
uv pip install --index-url https://download.pytorch.org/whl/cu126 --force-reinstall torch
```

### code-server HTTP 401 loop after password change

Open a new browser window in incognito / private mode, or clear the cookies for the domain. The old session cookie is no longer valid.

### Build in CI hits a timeout

Individual matrix cells take 15–30 min cold, 5–10 min warm. If CI is timing out, it's usually the PyTorch wheel download (~2 GB). Check network egress from the runner, and verify `cache-from: type=gha` is producing hits on the second build — the first "warm" build will still be slow, but the second should hit cache and finish quickly.

### Everything is slow right after deploy

The bundled venv creation runs at image-build time, not container start — so "slow on first run" usually means either (a) the image pull is still in progress (6 GB — several minutes on slow links), or (b) the GPU is pinned by another container. Check:

```bash
nvidia-smi              # is the GPU occupied?
docker stats            # CPU / memory saturated?
docker logs <container> # crash-looping?
```

---

If none of the above covers your issue: open a bug report using the template at `.github/ISSUE_TEMPLATE/bug_report.yml`. Include the image tag, deployment target, container logs, and host environment.
