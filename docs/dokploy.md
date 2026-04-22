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
