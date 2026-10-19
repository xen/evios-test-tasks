#!/usr/bin/env bash
# Reproducible deployment over an already enrolled Tailscale SSH connection.
set -euo pipefail
cd "$(dirname "$0")"
: "${GHOST_SSH_TARGET:?Set GHOST_SSH_TARGET=deploy@your-tailscale-IP}"
: "${TUNNEL_CREDENTIALS:?Set TUNNEL_CREDENTIALS to the ghost-test tunnel JSON file}"
[[ -s "$TUNNEL_CREDENTIALS" ]]
export TUNNEL_CREDENTIALS
python3 - <<'PY'
import json, os
with open(os.environ['TUNNEL_CREDENTIALS']) as f:
    credential = json.load(f)
if credential.get('TunnelID') != '3c5fb28c-9a5b-4baa-9d42-3348432bab7c':
    raise SystemExit('Credential belongs to a different tunnel')
PY
SSH=(ssh -o BatchMode=yes -o ForwardAgent=no -o ConnectTimeout=15)
# Configure known_hosts in advance; never disable host-key verification.
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo -n true; tailscale ip -4'
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo --preserve-env=SSH_CONNECTION bash -s' < scripts/lockdown.sh
# Keep an existing DNS record from exposing owner setup on a fresh installation.
"${SSH[@]}" "$GHOST_SSH_TARGET" 'if systemctl cat cloudflared.service >/dev/null 2>&1; then sudo systemctl stop cloudflared; fi'
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo bash -s' < scripts/prerequisites.sh
"${SSH[@]}" "$GHOST_SSH_TARGET" 'cd /var/www/ghost && if test -L current; then test -f current/index.js; else ghost install 6.71.0 --no-setup --no-start --no-prompt --no-color; fi'
# Stage inputs in a private directory; secrets are sent over SSH stdin only.
REMOTE=$({ "${SSH[@]}" "$GHOST_SSH_TARGET" 'mktemp -d /home/deploy/ghost-deploy.XXXXXXXX'; })
[[ "$REMOTE" =~ ^/home/deploy/ghost-deploy\.[A-Za-z0-9]{8}$ ]]
trap '"${SSH[@]}" "$GHOST_SSH_TARGET" "rm -rf -- $REMOTE"' EXIT
for file in scripts/configure.py templates/ghost.service templates/nginx.conf templates/cloudflared.service templates/cloudflared.yml templates/cloud-init-local.conf; do
  "${SSH[@]}" "$GHOST_SSH_TARGET" "cat > $REMOTE/$(basename "$file")" < "$file"
done
"${SSH[@]}" "$GHOST_SSH_TARGET" "umask 077; cat > $REMOTE/tunnel.json" < "$TUNNEL_CREDENTIALS"
"${SSH[@]}" "$GHOST_SSH_TARGET" "sudo bash -s -- $REMOTE" <<'REMOTE_SCRIPT'
set -euo pipefail
stage=$1
python3 "$stage/configure.py"
if ! command -v cloudflared >/dev/null; then
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/download/2026.10.1/cloudflared-linux-arm64.deb -o "$stage/cloudflared.deb"
  dpkg -i "$stage/cloudflared.deb"
fi
id cloudflared >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin cloudflared
install -d -m750 -o root -g cloudflared /etc/cloudflared
install -m600 -o cloudflared -g cloudflared "$stage/tunnel.json" /etc/cloudflared/tunnel.json
install -m640 -g cloudflared "$stage/cloudflared.yml" /etc/cloudflared/config.yml
install -m644 "$stage/ghost.service" /etc/systemd/system/ghost.service
install -m644 "$stage/cloudflared.service" /etc/systemd/system/cloudflared.service
install -d /etc/systemd/system/cloud-init-local.service.d
install -m644 "$stage/cloud-init-local.conf" /etc/systemd/system/cloud-init-local.service.d/10-udev.conf
install -m644 "$stage/nginx.conf" /etc/nginx/sites-available/ghost
ln -sf /etc/nginx/sites-available/ghost /etc/nginx/sites-enabled/ghost
nginx -t
cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate
systemctl daemon-reload
systemctl enable --now mysql ghost nginx tailscaled
systemctl restart ghost nginx
REMOTE_SCRIPT
for attempt in $(seq 1 60); do
  if "${SSH[@]}" "$GHOST_SSH_TARGET" 'curl -fsS -H "Host: ghost.dzen.dev" -H "X-Forwarded-Proto: https" http://127.0.0.1:2368/ghost/api/admin/authentication/setup/' > /dev/null; then break; fi
  [[ "$attempt" != 60 ]] || exit 1
  sleep 2
done
python3 scripts/claim-owner.py "$GHOST_SSH_TARGET"
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo systemctl enable --now cloudflared; sudo systemctl restart cloudflared'
for attempt in $(seq 1 30); do
  if "${SSH[@]}" "$GHOST_SSH_TARGET" 'curl -fsS http://127.0.0.1:20241/ready' > /dev/null; then break; fi
  [[ "$attempt" != 30 ]] || exit 1
  sleep 2
done
"${SSH[@]}" "$GHOST_SSH_TARGET" 'systemctl is-active ghost nginx cloudflared tailscaled; curl -fsS -H "Host: ghost.dzen.dev" http://127.0.0.1:8080/ghost/api/admin/authentication/setup/'
echo 'Server deployment complete. Configure the documented Cloudflare CNAME, then run scripts/verify.py.'
