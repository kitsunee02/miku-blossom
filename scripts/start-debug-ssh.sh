#!/usr/bin/env bash
# Start a read-only SSH account bound only to the runner's Tailscale IPv4.
# The account has no sudo access and uses only normal world-readable workspace permissions.
set -euo pipefail

SSH_USER="ci-debug"
PUBLIC_KEY="${CI_SSH_PUBLIC_KEY:-}"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "::error::Missing CI_SSH_PUBLIC_KEY repository secret."
  exit 1
fi
if [[ "$PUBLIC_KEY" == *$'\n'* ]]; then
  echo "::error::CI_SSH_PUBLIC_KEY must contain exactly one public-key line."
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "::error::Tailscale CLI is missing; the Tailscale action did not complete."
  exit 1
fi

TAILSCALE_IP="$(sudo tailscale ip -4 | head -n 1)"
if [[ ! "$TAILSCALE_IP" =~ ^100\. ]]; then
  echo "::error::Could not obtain a valid Tailscale IPv4 address."
  exit 1
fi

sudo apt-get install -y -qq openssh-server >/dev/null

if ! id "$SSH_USER" >/dev/null 2>&1; then
  # Do not add this account to the runner group. It gets no sudo privileges
  # and no group-based write access to the build workspace.
  sudo useradd --create-home --shell /bin/bash "$SSH_USER"
fi

# Grant this account read/traverse access to the ROM workspace via ACLs only.
# The workspace is mounted before this script; src is created later by sync.sh.
# Parent paths need traversal, and the ROM root default ACL propagates to src
# and newly created content. This does not grant write access or sudo.
sudo apt-get install -y -qq acl >/dev/null
sudo setfacl -m "u:$SSH_USER:--x" /home/runner
sudo setfacl -m "u:$SSH_USER:--x" "$ROM_ROOT"
sudo setfacl -m "d:u:$SSH_USER:r-x" "$ROM_ROOT"

# Give PAM a valid account record, but use a fresh unguessable password.
# sshd below accepts public-key authentication only, so this password cannot be used for SSH.
RANDOM_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
printf '%s:%s\n' "$SSH_USER" "$RANDOM_PASSWORD" | sudo chpasswd
unset RANDOM_PASSWORD

HOME_DIR="$(getent passwd "$SSH_USER" | cut -d: -f6)"
if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
  echo "::error::Could not resolve the debug account home directory."
  exit 1
fi

TMP_KEY="$(mktemp)"
trap 'rm -f "$TMP_KEY"' EXIT
printf '%s\n' "$PUBLIC_KEY" > "$TMP_KEY"
if ! ssh-keygen -l -f "$TMP_KEY" >/dev/null 2>&1; then
  echo "::error::CI_SSH_PUBLIC_KEY is not a valid OpenSSH public key."
  exit 1
fi

sudo install -d -m 700 -o "$SSH_USER" -g "$SSH_USER" "$HOME_DIR/.ssh"
sudo install -m 600 -o "$SSH_USER" -g "$SSH_USER" "$TMP_KEY" "$HOME_DIR/.ssh/authorized_keys"

# Bind sshd only to the private Tailscale interface. Do not listen on the
# runner's public or ordinary network interfaces.
sudo install -d -m 755 /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/00-hsin-private-debug.conf >/dev/null <<EOF
AddressFamily inet
ListenAddress $TAILSCALE_IP
Port 22
PermitRootLogin no
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers $SSH_USER
PermitTTY yes
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
PermitUserEnvironment no
EOF

sudo mkdir -p /run/sshd
sudo /usr/sbin/sshd -t

# Ubuntu may use systemd socket activation. Stop and disable it (without masking),
# then run ssh.service directly so sshd honors the Tailscale-only ListenAddress.
# Masking ssh.socket can break ssh.service dependencies on some runner images.
sudo systemctl stop ssh.socket || true
sudo systemctl unmask ssh.socket || true
sudo systemctl disable ssh.socket || true
sudo systemctl stop ssh.service || true
sudo systemctl daemon-reload
sudo systemctl restart ssh.service
sudo systemctl is-active --quiet ssh.service

LISTENERS="$(sudo ss -H -lnt 'sport = :22' 2>&1 || true)"
echo "$LISTENERS"
if ! printf '%s\n' "$LISTENERS" | awk -v ip="$TAILSCALE_IP" '$4 == ip ":22" || index($4, ip) == 1 { found=1 } END { exit !found }'; then
  echo "::error::SSH is not listening on the Tailscale address. Diagnostic listener list above."
  sudo systemctl status ssh --no-pager || true
  sudo journalctl -u ssh --no-pager -n 60 || true
  exit 1
fi

{
  printf '%s\n' '## Private interactive terminal' ''
  printf -- '- Stage: `%s`\n' "$STAGE"
  printf -- '- Tailscale address: `%s`\n' "$TAILSCALE_IP"
  printf -- '- SSH account: `%s` (no sudo; workspace read access only)\n' "$SSH_USER"
  printf '%s\n' '- Connect from a device on the same tailnet:' ''
  printf '  `ssh -i ~/.ssh/miku-blossom-ci %s@%s`\n' "$SSH_USER" "$TAILSCALE_IP"
  printf '%s\n' '' 'This address is reachable only through your Tailscale network. The terminal closes when this stage ends.'
} >> "$GITHUB_STEP_SUMMARY"

echo "::notice title=Private SSH terminal::SSH is listening on the private Tailscale address $TAILSCALE_IP as $SSH_USER."
