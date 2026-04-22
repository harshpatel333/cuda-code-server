#!/usr/bin/env bash
# sshd-setup.sh — prepare host keys, authorized_keys, and start sshd.
#
# Invoked by the entrypoint when ENABLE_SSHD=true. Runs as root.

set -euo pipefail

HOST_KEY_DIR=/home/coder/.ssh/host_keys
AUTH_KEYS_FILE=/home/coder/.ssh/authorized_keys
SSHD_PORT="${SSH_PORT:-2222}"

info() { printf 'sshd-setup: %s\n' "$*" >&2; }

# --- 1. Host keys: generate once, persist on the /home/coder volume. --------
# Keeping keys on the persistent volume means reconnects don't trigger the
# "host key changed" warning after container recreation. Deleting the home
# volume regenerates the keys (expected, a clean-slate event).
mkdir -p "$HOST_KEY_DIR"
for keytype in ed25519 rsa; do
    keyfile="${HOST_KEY_DIR}/ssh_host_${keytype}_key"
    if [ ! -f "$keyfile" ]; then
        info "generating ${keytype} host key"
        ssh-keygen -q -t "$keytype" -N '' -f "$keyfile" -C "cuda-code-server host key"
    fi
    chown root:root "$keyfile" "${keyfile}.pub"
    chmod 0600 "$keyfile"
    chmod 0644 "${keyfile}.pub"
done

# --- 2. Authorized keys: merge the SSH_AUTHORIZED_KEYS env var. --------------
# Idempotent: duplicate lines are skipped. Users can also edit the file
# directly from the code-server terminal.
mkdir -p "$(dirname "$AUTH_KEYS_FILE")"
touch "$AUTH_KEYS_FILE"
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
    info "merging SSH_AUTHORIZED_KEYS env var into authorized_keys"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        grep -qxF "$line" "$AUTH_KEYS_FILE" 2>/dev/null || echo "$line" >> "$AUTH_KEYS_FILE"
    done <<< "$SSH_AUTHORIZED_KEYS"
fi
chown coder:coder /home/coder/.ssh "$AUTH_KEYS_FILE"
chmod 0700 /home/coder/.ssh
chmod 0600 "$AUTH_KEYS_FILE"

# --- 3. Runtime dir for privilege-separated sshd. ----------------------------
mkdir -p /run/sshd
chmod 0755 /run/sshd

# --- 4. Launch sshd in the foreground; caller backgrounds with &. ------------
info "starting sshd on port ${SSHD_PORT}"
exec /usr/sbin/sshd -D -e -p "$SSHD_PORT"
