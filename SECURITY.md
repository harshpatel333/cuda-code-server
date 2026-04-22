# Security Policy

## Supported versions

Only the latest minor release is actively supported.

| Version | Supported |
|---|---|
| latest minor | Yes |
| older minor | No |

Older tags remain pullable, but fixes are only backported on a case-by-case basis and only for severe issues.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Email: **h.patel686r@gmail.com**

Include:

- A description of the issue and its impact.
- Steps to reproduce (or a minimal PoC).
- The affected image tag(s).
- Relevant versions of the host environment (Docker, NVIDIA driver, kernel).

Acknowledgement within 72 hours. Fixes are developed privately; once a fix ships, a public advisory will be published via GitHub Security Advisories.

## Known trade-offs

This image is a **development environment**, not a hardened runtime. The trade-offs below are deliberate — understand them before exposing the image:

- **code-server with a weak password on the public internet is effectively remote code execution.** Use a strong, random password. Strongly prefer placing the service behind a VPN, an IP allowlist, or an auth-aware reverse proxy (Traefik + Authelia, Cloudflare Tunnel with Access, tailscale serve, etc.) rather than exposing it directly.
- **Mounting the Docker socket** (`/var/run/docker.sock`) makes the container effectively root on the host. The socket mount is documented as optional in the deployment examples; enable it only if you trust every user with access to the code-server instance.
- **Passwordless `sudo` inside the container is intentional.** A user who has already authenticated to code-server has a shell as `coder`; passwordless sudo just saves them a step. The real security boundary is the container, not the user inside it.

## Not in scope for v0.1

Planned for later minor releases:

- Signed images via [cosign](https://github.com/sigstore/cosign).
- SBOM publishing alongside images.
- [Trivy](https://github.com/aquasecurity/trivy) / [Grype](https://github.com/anchore/grype) vulnerability scans in CI (non-blocking, informational).

These are tracked in `CHANGELOG.md` under the Roadmap notes.
