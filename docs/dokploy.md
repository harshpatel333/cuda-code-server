# Deploying cuda-code-server on Dokploy

End-to-end guide for the project's primary deployment target. Covers going from a fresh Dokploy install to a working HTTPS code-server with GPU access.

**Short version.** Paste `examples/dokploy/docker-compose.yml` into a Dokploy Compose service (Raw provider), set `PASSWORD` in the Environment tab, add your domain in the Domains tab, deploy.

## Prerequisites

**On the Dokploy host:**

1. A GPU plus the NVIDIA driver. `nvidia-smi` must work for `root` on the host.
2. The [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed and configured for Docker. Quick sanity check on the host:
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.6.1-base-ubuntu22.04 nvidia-smi
   ```
   If that prints the GPU table, the container runtime is wired up correctly.
3. Swarm mode enabled. A normal Dokploy installation already enables it.

**In DNS:**

4. A subdomain (e.g., `code.example.com`) with an A/AAAA record pointing at the Dokploy host's public IP.

## Step-by-step

1. **Create a project** in Dokploy → *Create Project*.
2. **Add a Compose service**:
   - Type: *Compose*
   - Provider: *Raw*
   - Paste the contents of `examples/dokploy/docker-compose.yml`.
3. **Environment tab**:
   - `PASSWORD` → a strong random value. Generate one with `openssl rand -base64 24`. This is what you'll type into the browser login.
   - `TZ` → your timezone, e.g., `America/New_York`.
   - Do **not** hard-code these in the compose file. Dokploy injects them at deploy time.
4. **Domains tab**:
   - Host: `code.example.com`
   - Service: `devcontainer` (matches the compose service name)
   - Port: `8080`
   - Enable *HTTPS* — Dokploy requests a Let's Encrypt cert on your behalf. Certificate resolver: `letsencrypt`.
5. **Deploy**. First boot pulls ~6 GB; allow 5–15 min on a cold host.
6. When the deploy turns green, open `https://code.example.com`, enter `PASSWORD`, and you're in the IDE.

## Gotchas (read before you deploy)

- **`dokploy-network` must be declared `external: true`.** The bundled compose file does this. If you modify it and drop the block, deploys fail with a network-not-found error.
- **Volume naming uses `${COMPOSE_PROJECT_NAME}`.** Dokploy sets this automatically per service. The `name:` fields in the bundled compose prefix volumes with it, so redeploying under a different service name doesn't collide — but it also leaves the old volumes orphaned. Clean them up from Dokploy's Volumes UI when you're sure.
- **GPU scheduling in Swarm mode.** Swarm needs `deploy.resources.reservations.devices`, which the bundled file has. On a multi-GPU host where you want to pin a single device, replace `count: all` with `device_ids: ['0']`.
- **Docker socket GID mismatch.** The entrypoint inside the image reads `/var/run/docker.sock`'s GID and updates the in-container `docker` group to match. If `docker ps` in the code-server terminal still says `permission denied`, open a fresh terminal (the group takes effect at shell start) or run `newgrp docker`.
- **Password rotation.** Change `PASSWORD` in the Environment tab and redeploy. Existing browser sessions are invalidated when the container restarts.

## Post-deploy verification

Open the integrated terminal in code-server (<kbd>Ctrl</kbd>+<kbd>\`</kbd>) and run:

```bash
# Is the GPU visible inside the container?
nvidia-smi

# Does PyTorch see CUDA?
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count())"

# Actually run on the GPU:
python -c "import torch; x = torch.randn(1000, 1000).cuda(); print((x @ x).sum().item())"

# Is the host Docker socket wired up?
docker ps
```

All four should succeed. If `nvidia-smi` works on the host but not in the container, the NVIDIA Container Toolkit step from the prerequisites is the culprit — fix it on the host, then redeploy.

## Resource tuning

**Pin specific GPUs** (one-GPU-per-user on a multi-GPU host):

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          device_ids: ['0']        # or ['0', '1'] for multiple
          capabilities: [gpu]
```

**Cap memory** (prevents a runaway notebook from pushing the host into swap):

```yaml
deploy:
  resources:
    limits:
      memory: 32G
    reservations:
      memory: 8G
```

## Enabling Remote-SSH (optional)

The image bundles `openssh-server`. Turning it on lets you connect from VS Code Desktop, Cursor, or Windsurf via the Remote-SSH extension — useful for Microsoft-exclusive extensions (Pylance, Copilot, C/C++ IntelliSense) that the browser IDE's Open VSX marketplace doesn't have.

This section is the Dokploy-specific walk-through; for per-editor setup and the full `~/.ssh/config` template, see [`docs/remote-ssh.md`](./remote-ssh.md).

### 1. Pick a DNS hostname for SSH

Your main domain (e.g. `code.example.com`) already points at the Dokploy host for HTTPS. For SSH you have two reasonable choices:

- **Separate subdomain (recommended):** `ssh.code.example.com` → A/AAAA record to the same Dokploy host IP. Lets you firewall and scope SSH independently of HTTPS, and reads nicely in `~/.ssh/config`.
- **Same domain, non-standard port:** connect to `code.example.com:2222`. Fewer DNS records, slightly noisier config.

Add the A record at your DNS provider before redeploying — the host already resolves, it just needs a new label.

### 2. Expose port 2222 on the Dokploy host

Dokploy's Traefik routes HTTP through ports 80/443 by default, but SSH is TCP. Simplest path: bypass Traefik and map port 2222 directly on the host via a `ports:` block in the compose file. Update `examples/dokploy/docker-compose.yml` (or the compose you pasted into Dokploy's Raw provider) so the service has:

```yaml
services:
  devcontainer:
    # ... existing config ...
    expose:
      - "8080"
    ports:
      - "2222:2222"      # Remote-SSH (bypasses Traefik; firewall on the host)
```

Open port 2222 on the host firewall, restricted to your laptop's IP whenever possible:

```bash
sudo ufw allow from <your-laptop-ip>/32 to any port 2222 proto tcp
# Or for an office / VPN range:
sudo ufw allow from 10.0.0.0/8 to any port 2222 proto tcp
```

SSH key auth is strong, but narrowing the reachable population is defence in depth.

If you'd rather keep everything behind Traefik (TCP entrypoint + `HostSNI` router), see `docs/remote-ssh.md § Dokploy Option B` — more invasive but doesn't require a separate host-port hole.

### 3. Set the SSH env vars

In Dokploy's *Environment* tab on the service, add:

| Key | Value |
|---|---|
| `ENABLE_SSHD` | `true` |
| `SSH_AUTHORIZED_KEYS` | Paste the contents of `~/.ssh/id_ed25519.pub` (one key per line for multiple) |
| `SSH_PORT` | `2222` (optional — `2222` is the default) |

Click *Redeploy*.

### 4. Verify the connection

From your laptop:

```bash
ssh -p 2222 coder@ssh.code.example.com
# Expected:
# Welcome to ... (ubuntu 22.04)
# (.venv) coder@<container-id>:~/project$
```

First connection prompts for host-key verification — compare the fingerprint to what the container reports. From the code-server browser terminal:

```bash
ssh-keygen -l -f /home/coder/.ssh/host_keys/ssh_host_ed25519_key.pub
```

Once verified, it's trusted in `~/.ssh/known_hosts` and future connections are silent.

### 5. Wire up VS Code Desktop / Cursor / Windsurf

Add to local `~/.ssh/config`:

```
Host cuda-code-server
  HostName ssh.code.example.com
  Port 2222
  User coder
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 60
  ServerAliveCountMax 5
  ForwardAgent yes          # optional — lets `git push` on the remote use local keys
```

Then in VS Code Desktop or Cursor:

1. Install the **Remote - SSH** extension.
2. <kbd>F1</kbd> → *Remote-SSH: Connect to Host...* → `cuda-code-server`.
3. *File → Open Folder* → `/home/coder/project`.

You now have a native IDE window that executes everything — terminal, GPU, extensions — inside the Dokploy-hosted container. VS Code Desktop specifically can also use the Microsoft marketplace (Pylance, Copilot, etc.) over this connection.

### 6. Adding and removing keys later

- **Add** — append a line to the `SSH_AUTHORIZED_KEYS` env var in Dokploy and redeploy (keys merge idempotently — duplicates are skipped). Or just edit `~/.ssh/authorized_keys` in the browser terminal.
- **Remove** — `SSH_AUTHORIZED_KEYS` is append-only by design so a mid-session redeploy can't lock you out. To remove a key, edit `/home/coder/.ssh/authorized_keys` directly and delete the line.

### 7. Rotate host keys (if ever needed)

```bash
# From the code-server terminal:
sudo rm -rf /home/coder/.ssh/host_keys
# Then in Dokploy: Redeploy — new host keys generate on boot.
```

Clients get a "host key changed" warning on next connect; clear the stale known_hosts entry:

```bash
ssh-keygen -R '[ssh.code.example.com]:2222'
```

## Updating the image

1. Edit the `image:` tag in the compose file (e.g., `12.6-py312` → `0.2-12.6-py312`).
2. Click *Redeploy* in Dokploy.

Persistent volumes (`home`, `project`) survive the redeploy. If a new image introduces a breaking change (called out in `CHANGELOG.md`), roll back by reverting the tag and redeploying — volumes are untouched.

## Backups

Dokploy's host-level volume backup tools cover `home` and `project` if you've enabled them. For ad-hoc backups, SSH to the host and run:

```bash
VOLUME=$(docker volume ls --format '{{.Name}}' | grep cuda-code-server-project)
docker run --rm -v "$VOLUME:/data" -v "$(pwd):/backup" alpine \
  tar czf "/backup/project-backup-$(date +%F).tar.gz" -C /data .
```

Restoring is the mirror operation (`tar xzf` into a fresh volume before the first deploy).
