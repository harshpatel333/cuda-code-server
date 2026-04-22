# Contributing

Thanks for your interest in cuda-code-server. This project aims to stay small and opinionated; contributions are welcome within the scope below.

## Scope

**In scope:**

- Bug fixes.
- New CUDA / Python matrix cells that are currently supported upstream by PyTorch.
- Documentation improvements — especially `docs/dokploy.md` and `docs/usage.md`.
- CI improvements (caching, build speed, reproducibility).
- Small additions to the base image that clear the "most ML users would want this" bar.

**Out of scope (v0.1.x):**

- User auth / SSO layers — the image is password-only by design; delegate TLS and auth to a reverse proxy.
- Multi-tenancy or workspace isolation — one container per user.
- Bundled VS Code extensions — users install their own; extensions persist on the home volume.
- Windows / Jetson / ARM64 — tracked as future work.
- Project-specific tooling (R, Julia, specific Jupyter kernels, etc.) — extend via a child Dockerfile.

If a feature is out of scope, extending via a child Dockerfile is encouraged. Open a discussion if you'd like pointers.

## Local development

Clone the repo and build one matrix cell:

```bash
docker build \
  --build-arg CUDA_VERSION=12.6.1 \
  --build-arg PYTHON_VERSION=3.12 \
  --build-arg TORCH_CUDA=cu126 \
  -t cuda-code-server:local .
```

Expect ~15–30 min and ~14 GB on a cold cache. Subsequent builds are much faster thanks to layer reuse.

Smoke test:

```bash
docker run --rm -d --name ccs-test \
  -e PASSWORD=test \
  -p 18080:8080 \
  cuda-code-server:local

curl -sI http://localhost:18080/healthz   # expect HTTP/1.1 200
docker stop ccs-test
```

For GPU tests, add `--gpus all` to `docker run` and verify inside the container:

```bash
nvidia-smi
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count())"
```

## Lint

```bash
docker run --rm -i hadolint/hadolint < Dockerfile
docker run --rm -v "$(pwd)":/work cytopia/yamllint -d relaxed /work/.github/workflows/build.yml
```

## Pull requests

- One topic per PR. Small PRs merge faster.
- Update `CHANGELOG.md` under `[Unreleased]`.
- If you change image contents, note the size impact in the PR description (`docker images` before vs after).
- CI runs a build on PRs but does **not** push to any registry. Review the workflow logs if the build fails.
- Breaking changes (removing a variant, renaming env vars, bumping the base image major) require at least a minor version bump — call them out explicitly in the PR description and CHANGELOG.

## Release process (maintainers)

1. Move the `[Unreleased]` entries into a new `[X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md`.
2. Commit: `git commit -am "chore: release vX.Y.Z"`.
3. Tag: `git tag vX.Y.Z`.
4. Push: `git push && git push --tags`.
5. CI builds the full matrix and publishes to GHCR + Docker Hub automatically.
6. Create a GitHub Release from the new tag with the changelog section as the body.

Semver rules:

- **Patch** — bugfixes, docs, CI tweaks, no image behavior change.
- **Minor** — new CUDA / Python variants, added tools, new env vars; backward compatible.
- **Major** — removed variants, breaking env var changes, base image changes.
