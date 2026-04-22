# Remote-SSH with cuda-code-server

This image bundles `openssh-server`, so VS Code Desktop, Cursor, Windsurf, and any other VS Code fork can attach via **Remote-SSH** and feel as native as a local folder. The browser IDE keeps working too — SSH is an additional connection, not a replacement.

## How it works

- `sshd` is installed in the image but **not started by default**.
- Set `ENABLE_SSHD=true` and sshd launches alongside code-server (in the background, as root) on port `2222`.
- Auth is **public-key only**. No password auth, no root login; only the `coder` user is allowed.
- Your public keys come from `SSH_AUTHORIZED_KEYS` (env var, set at deploy time) or a direct edit of `/home/coder/.ssh/authorized_keys` from the code-server terminal.
- Host keys are generated on first boot and stored under `/home/coder/.ssh/host_keys/`, which is on the persistent home volume — reconnects don't trigger "host key changed" warnings after container recreation.

## Table of contents

1. [Enable the SSH daemon](#1-enable-the-ssh-daemon)
2. [Expose the SSH port (by deployment target)](#2-expose-the-ssh-port-by-deployment-target)
3. [Supply your public key](#3-supply-your-public-key)
4. [Connect from VS Code Desktop](#4-connect-from-vs-code-desktop)
5. [Connect from Cursor](#5-connect-from-cursor)
6. [Connect from Windsurf and other VS Code forks](#6-connect-from-windsurf-and-other-vs-code-forks)
7. [Plain `ssh` from the terminal](#7-plain-ssh-from-the-terminal)
8. [Recommended `~/.ssh/config`](#8-recommended-sshconfig)
9. [Multiple keys, rotation, and host keys](#9-multiple-keys-rotation-and-host-keys)
10. [Remote-SSH vs. Dev Containers](#10-remote-ssh-vs-dev-containers)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Enable the SSH daemon

Three environment variables control sshd. All are optional.

| Variable | Default | Purpose |
|---|---|---|
| `ENABLE_SSHD` | `false` | Set to `"true"` to start sshd on container boot. |
| `SSH_PORT` | `2222` | Port sshd listens on inside the container. |
| `SSH_AUTHORIZED_KEYS` | — | Newline-separated public keys to accept. Merged idempotently into `authorized_keys` on each boot. |

Example (Docker Compose):

```yaml
environment:
  ENABLE_SSHD: "true"
  SSH_AUTHORIZED_KEYS: "ssh-ed25519 AAAAC3Nz... you@laptop"
```

For multiple keys, use a YAML block scalar:

```yaml
environment:
  ENABLE_SSHD: "true"
  SSH_AUTHORIZED_KEYS: |
    ssh-ed25519 AAAAC3Nz... you@laptop
    ssh-ed25519 BBBBC3Nz... you@desktop
    ssh-rsa CCCC... teammate@workstation
```

In Kubernetes, use a multi-line literal in the env value (or source from a ConfigMap).

## 2. Expose the SSH port (by deployment target)

Enabling sshd inside the container is half the job. The port also has to be reachable from your IDE.

### Plain `docker run`

```bash
docker run -d \
  --gpus all \
  --name cuda-code-server \
  -e PASSWORD="$PASSWORD" \
  -e ENABLE_SSHD=true \
  -e SSH_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)" \
  -p 8080:8080 \
  -p 2222:2222 \
  -v cuda-code-server-home:/home/coder \
  -v cuda-code-server-project:/home/coder/project \
  ghcr.io/harshpatel333/cuda-code-server:latest
```

### Docker Compose

Uncomment the SSH-related lines in `examples/docker-compose/docker-compose.yml`:

```yaml
environment:
  ENABLE_SSHD: "true"
  SSH_AUTHORIZED_KEYS: "ssh-ed25519 AAAAC3Nz... you@laptop"
ports:
  - "8080:8080"
  - "2222:2222"
```

### Dokploy

Dokploy routes HTTP through Traefik, but the default configuration has no TCP entrypoint. You have two options.

**Option A — direct host port mapping (simplest).** Add `ports:` to the service, bypassing Traefik. The host firewall is what gates access; restrict to specific source IPs if the host is public.

```yaml
services:
  devcontainer:
    # ... existing config ...
    expose:
      - "8080"
    ports:
      - "2222:2222"
    environment:
      ENABLE_SSHD: "true"
      SSH_AUTHORIZED_KEYS: "ssh-ed25519 AAAA... you@laptop"
```

Then open port 2222 on the host's firewall:

```bash
# Ubuntu + ufw:
sudo ufw allow from <your-ip> to any port 2222 proto tcp

# Or cloud firewall rules (AWS SG, GCP firewall rule, etc.)
```

**Option B — Traefik TCP entrypoint.** If you'd rather keep everything behind Traefik, add a TCP entrypoint to Dokploy's Traefik config (edit `docker-compose.traefik.yml` in Dokploy's install dir, add an `--entrypoints.ssh.address=:2222` arg and expose 2222 on the Traefik container), then add TCP router labels to the service:

```yaml
labels:
  traefik.enable: "true"
  traefik.tcp.routers.cuda-code-server-ssh.rule: "HostSNI(`*`)"
  traefik.tcp.routers.cuda-code-server-ssh.entrypoints: "ssh"
  traefik.tcp.services.cuda-code-server-ssh.loadbalancer.server.port: "2222"
```

Use Option A unless you specifically want Traefik in the SSH path.

### Kubernetes

The bundled `examples/kubernetes/deployment.yaml` has a commented-out `Service` for SSH. Uncomment it, and the matching `containerPort: 2222` on the Deployment.

Cloud clusters typically use `type: LoadBalancer`; on-prem / single-node clusters use `type: NodePort`. For a stable SSH endpoint:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cuda-code-server-ssh
spec:
  selector:
    app: cuda-code-server
  type: LoadBalancer         # or NodePort on bare metal
  ports:
    - name: ssh
      port: 2222
      targetPort: 2222
```

## 3. Supply your public key

### Find it

```bash
cat ~/.ssh/id_ed25519.pub      # modern default
# or:
cat ~/.ssh/id_rsa.pub          # older installs
```

If you don't have one:

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
```

### Inject via the env var (easiest)

Set `SSH_AUTHORIZED_KEYS` to the contents of your `.pub` file. The key is merged into `/home/coder/.ssh/authorized_keys` on every container start — adding it later just appends.

### Or edit manually

From the browser IDE terminal:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys    # paste your public key(s), one per line
chmod 600 ~/.ssh/authorized_keys
```

The `authorized_keys` file lives on the persistent `home` volume — it survives container recreation.

## 4. Connect from VS Code Desktop

1. Install the [Remote - SSH extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) in VS Code Desktop.
2. Add an entry to `~/.ssh/config` (see [§8](#8-recommended-sshconfig) for the full template):

   ```
   Host cuda-code-server
     HostName your-deployment.example.com
     Port 2222
     User coder
     IdentityFile ~/.ssh/id_ed25519
   ```

3. <kbd>F1</kbd> → *Remote-SSH: Connect to Host...* → `cuda-code-server`.
4. First connection asks you to verify the host fingerprint. Print the container's fingerprint from the browser terminal and compare:

   ```bash
   ssh-keygen -l -f /home/coder/.ssh/host_keys/ssh_host_ed25519_key.pub
   ```

5. Once connected, *File → Open Folder* → `/home/coder/project`.

You now have a full VS Code window that behaves like local while executing everything (terminal, extensions, Python interpreter, GPU) inside the container.

**Microsoft marketplace is available.** Because VS Code Desktop is the Microsoft build, extensions like Pylance, Remote-Containers, C/C++ IntelliSense, and Copilot (the MS extension) work when connected via Remote-SSH — even though the browser IDE can't use them.

## 5. Connect from Cursor

Cursor ships a Remote-SSH extension that's API-compatible with VS Code's.

1. Open Cursor → *Extensions* → search `Remote - SSH` → install.
2. Same `~/.ssh/config` entry as above.
3. <kbd>Cmd/Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd> → *Remote-SSH: Connect to Host*.
4. Cursor's AI features (Composer, Chat, autocomplete) work against the remote workspace — they're client-side UI over remote files.

Cursor's extension marketplace is Open VSX, same as code-server. Microsoft-exclusive extensions are unavailable even over Remote-SSH; free equivalents (Pyright, clangd, Continue) work fine.

## 6. Connect from Windsurf and other VS Code forks

Windsurf (Codeium) has a Remote-SSH extension in its marketplace. Same `~/.ssh/config` entry, same connect flow. Any VS Code fork that supports Remote-SSH (or Remote-Tunnels, which uses similar plumbing) works — the container-side doesn't care which client is talking to it.

## 7. Plain `ssh` from the terminal

```bash
ssh -p 2222 coder@your-deployment.example.com
```

Lands you in `/home/coder/project` with the bundled venv auto-activated and all the tooling on `PATH`. Useful for quick tasks, log tails, and running training jobs under `tmux` that survive client disconnects.

## 8. Recommended `~/.ssh/config`

```
Host cuda-code-server
  HostName your-deployment.example.com
  Port 2222
  User coder
  IdentityFile ~/.ssh/id_ed25519
  # Keep notebooks / long training runs alive through idle proxies.
  ServerAliveInterval 60
  ServerAliveCountMax 5
  # Optional: agent forwarding so `git push` on the remote uses local keys.
  ForwardAgent yes
  # Optional: pin the known-host line explicitly if you're on a shared machine.
  # UserKnownHostsFile ~/.ssh/known_hosts_cuda-code-server
```

For a local docker run:

```
Host cuda-code-server-local
  HostName localhost
  Port 2222
  User coder
  IdentityFile ~/.ssh/id_ed25519
```

## 9. Multiple keys, rotation, and host keys

### Add a new key

Append a line to `/home/coder/.ssh/authorized_keys` (directly from the terminal, or update the `SSH_AUTHORIZED_KEYS` env var and restart the container). Existing keys keep working.

### Remove a key

Edit `/home/coder/.ssh/authorized_keys` and delete the line. **Important:** `SSH_AUTHORIZED_KEYS` is append-only by design — removing a key from the env var and restarting does **not** delete it from `authorized_keys`. You must edit the file.

Rationale: a mid-session container restart shouldn't lock you out if someone bumps the env var on you.

### Rotate host keys

```bash
sudo rm -rf /home/coder/.ssh/host_keys
# Restart the container. Fresh keys generate on boot.
```

Clients will get "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" on the next connect — update their `known_hosts`:

```bash
ssh-keygen -R '[your-host]:2222'
```

Then reconnect.

## 10. Remote-SSH vs. Dev Containers

- **Remote-SSH** (this doc) — your editor connects to an **already-running** container on a server. Perfect for this image's deploy model (Dokploy, compose, k8s).
- **Dev Containers** (`devcontainer.json` + Dev Containers extension) — your editor **launches** a container from an image or Dockerfile, usually locally. Great for per-project isolation on a laptop with a GPU.

Both work with this image. If you're mainly running on a remote GPU box, use Remote-SSH. If you're on a GPU laptop and want a project-scoped environment, a `devcontainer.json` pointing at `ghcr.io/harshpatel333/cuda-code-server:12.6-py312` gets you a proper Dev Container experience.

A minimal `.devcontainer/devcontainer.json` for your own project:

```json
{
  "name": "cuda-code-server",
  "image": "ghcr.io/harshpatel333/cuda-code-server:12.6-py312",
  "runArgs": ["--gpus", "all"],
  "remoteUser": "coder",
  "containerEnv": {
    "PASSWORD": "not-used-in-dev-containers"
  },
  "forwardPorts": [],
  "workspaceFolder": "/home/coder/project"
}
```

Drop that in your project repo's `.devcontainer/` directory and open the folder in VS Code Desktop with the Dev Containers extension installed.

## 11. Troubleshooting

### `ssh_exchange_identification: Connection closed by remote host`

`sshd` isn't running. Confirm `ENABLE_SSHD=true` from the browser terminal:

```bash
env | grep ENABLE_SSHD
```

Then check container logs for the startup line:

```bash
docker logs <container> 2>&1 | grep sshd-setup
```

### `Permission denied (publickey)`

Your public key isn't in `/home/coder/.ssh/authorized_keys`. From the browser terminal:

```bash
cat ~/.ssh/authorized_keys
ssh-keygen -l -f ~/.ssh/authorized_keys     # fingerprints
```

Compare to the local key you're connecting with:

```bash
ssh-keygen -l -f ~/.ssh/id_ed25519.pub
```

If they don't match, append the right key.

### `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`

You recreated the container and deleted the home volume, or rotated host keys. Remove the stale known_hosts entry:

```bash
ssh-keygen -R '[your-deployment.example.com]:2222'
```

Then reconnect and accept the new fingerprint.

### VS Code / Cursor hangs at "Setting up SSH host…"

Usually the first-time install of the remote VS Code server, over a slow link. Check the Remote-SSH output panel — it downloads a ~100 MB bundle into `~/.vscode-server` (or `~/.cursor-server`) inside the container. Safe to wait; persists in the home volume after the first install.

### `Connection timed out`

The port isn't reachable from your client:

- **Dokploy** — did you allow port 2222 on the host firewall? Did you remember to add `ports: ["2222:2222"]` or the Traefik TCP route?
- **Kubernetes** — is the NodePort / LoadBalancer service accessible? `kubectl get svc cuda-code-server-ssh`.
- **Plain Docker** — `docker ps` to confirm the `0.0.0.0:2222->2222/tcp` mapping.

### `client_loop: send disconnect: Broken pipe`

Idle proxy / NAT killed the connection. The server-side `ClientAliveInterval 60` in the bundled sshd config should cover most cases. Add client-side keepalives too:

```
Host cuda-code-server
  ServerAliveInterval 60
  ServerAliveCountMax 5
```

### sshd starts but can't read host keys

Happens if a manual edit of `/home/coder/.ssh/host_keys/` left bad ownership or perms. Fix:

```bash
sudo chown -R root:root /home/coder/.ssh/host_keys/*
sudo chmod 0600 /home/coder/.ssh/host_keys/ssh_host_*_key
sudo chmod 0644 /home/coder/.ssh/host_keys/ssh_host_*_key.pub
```

Or delete and regenerate:

```bash
sudo rm -rf /home/coder/.ssh/host_keys
# Restart the container — `sshd-setup.sh` regenerates on boot.
```

---

If none of this covers your issue, open a bug report with `docker logs <container> 2>&1 | tail -100`, your `~/.ssh/config` entry, and the output of `ssh -vvv …` from the client.
