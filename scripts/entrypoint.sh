#!/usr/bin/env bash
# cuda-code-server entrypoint — preflight checks, then drop to `coder`.
#
# Runs as root so it can align /etc/group with /var/run/docker.sock's GID and
# then hand off to the unprivileged `coder` user via gosu.

set -euo pipefail

err()  { printf 'entrypoint: %s\n' "$*" >&2; }
info() { printf 'entrypoint: %s\n' "$*" >&2; }

# Must be root for the group fixup below. If someone overrode USER, just
# forward to the command and hope for the best.
if [ "$(id -u)" -ne 0 ]; then
    err "expected to run as root (got $(id -un)); USER may have been overridden."
    exec "$@"
fi

# --- 1. Password enforcement ------------------------------------------------
# code-server itself reads PASSWORD / HASHED_PASSWORD at startup. We fail fast
# here so users get a clear error instead of a silently-accessible service.
if [ -z "${PASSWORD:-}" ] && [ -z "${HASHED_PASSWORD:-}" ]; then
    cat >&2 <<'EOF'
entrypoint: ERROR — PASSWORD or HASHED_PASSWORD must be set.
Pick ONE of:
    docker run -e PASSWORD='...' ghcr.io/harshpatel333/cuda-code-server:latest
    docker run -e HASHED_PASSWORD='argon2id$...' ghcr.io/harshpatel333/cuda-code-server:latest
See README.md for rotation and hashed-password generation.
EOF
    exit 1
fi

# --- 2. Align in-container `docker` group GID to the host socket's GID ------
# Fixes "permission denied on /var/run/docker.sock" when the host's docker
# group GID differs from the placeholder GID baked into the image.
if [ -S /var/run/docker.sock ]; then
    host_gid="$(stat -c '%g' /var/run/docker.sock)"
    cur_gid="$(getent group docker | cut -d: -f3 || true)"
    if [ -n "${host_gid:-}" ] && [ "${host_gid}" != "${cur_gid:-}" ] && [ "${host_gid}" != "0" ]; then
        if getent group "$host_gid" >/dev/null 2>&1; then
            target="$(getent group "$host_gid" | cut -d: -f1)"
            info "socket GID ${host_gid} belongs to group '${target}'; adding coder to it."
            usermod -aG "$target" coder
        else
            info "aligning 'docker' group GID ${cur_gid:-<none>} -> ${host_gid}."
            groupmod -g "$host_gid" docker
        fi
    fi
fi

# --- 3. Append CODE_SERVER_ARGS to the command ------------------------------
# Lets users extend the default CMD via env var, e.g.
#   CODE_SERVER_ARGS="--cert --cert-host code.example.com"
if [ -n "${CODE_SERVER_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    extra=( ${CODE_SERVER_ARGS} )
    set -- "$@" "${extra[@]}"
fi

# --- 4. Drop to `coder` and exec --------------------------------------------
exec gosu coder "$@"
