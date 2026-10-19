#!/usr/bin/env bash
# One-command Ghost deployment over Tailscale; public web traffic uses nginx IPv4.
set -euo pipefail
cd "$(dirname "$0")"
: "${GHOST_SSH_TARGET:?Set GHOST_SSH_TARGET=deploy@your-tailscale-IP}"
SSH=(ssh -o BatchMode=yes -o ForwardAgent=no -o ConnectTimeout=15)
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo -n true; tailscale ip -4'
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo --preserve-env=SSH_CONNECTION bash -s' < scripts/lockdown.sh
"${SSH[@]}" "$GHOST_SSH_TARGET" 'sudo bash -s' < scripts/prerequisites.sh
"${SSH[@]}" "$GHOST_SSH_TARGET" 'cd /var/www/ghost && if test -L current; then test -f current/index.js; else ghost install 6.71.0 --no-setup --no-start --no-prompt --no-color; fi'
REMOTE=$("${SSH[@]}" "$GHOST_SSH_TARGET" 'mktemp -d /home/deploy/ghost-deploy.XXXXXXXX')
[[ "$REMOTE" =~ ^/home/deploy/ghost-deploy\.[A-Za-z0-9]{8}$ ]]
trap '"${SSH[@]}" "$GHOST_SSH_TARGET" "rm -rf -- $REMOTE"' EXIT
for file in scripts/configure.py templates/ghost.service templates/nginx-http.conf templates/nginx.conf templates/cloud-init-local.conf; do
  "${SSH[@]}" "$GHOST_SSH_TARGET" "cat > $REMOTE/$(basename "$file")" < "$file"
done
"${SSH[@]}" "$GHOST_SSH_TARGET" "sudo bash -s -- $REMOTE" <<'REMOTE_SCRIPT'
set -euo pipefail
stage=$1
python3 "$stage/configure.py"
install -m644 "$stage/ghost.service" /etc/systemd/system/ghost.service
install -d /etc/systemd/system/cloud-init-local.service.d
install -m644 "$stage/cloud-init-local.conf" /etc/systemd/system/cloud-init-local.service.d/10-udev.conf
systemctl daemon-reload
systemctl enable --now mysql ghost tailscaled
systemctl restart ghost
REMOTE_SCRIPT
for attempt in $(seq 1 60); do
  if "${SSH[@]}" "$GHOST_SSH_TARGET" 'curl -fsS -H "Host: ghost.dzen.dev" -H "X-Forwarded-Proto: https" http://127.0.0.1:2368/ghost/api/admin/authentication/setup/' > /dev/null; then break; fi
  [[ "$attempt" != 60 ]] || exit 1
  sleep 2
done
python3 scripts/claim-owner.py "$GHOST_SSH_TARGET"
# Owner is claimed before nginx starts exposing the application.
"${SSH[@]}" "$GHOST_SSH_TARGET" "sudo bash -s -- $REMOTE" <<'REMOTE_SCRIPT'
set -euo pipefail
stage=$1
install -d -m755 /var/www/letsencrypt/.well-known/acme-challenge
install -m644 "$stage/nginx-http.conf" /etc/nginx/sites-available/ghost-http
ln -sf /etc/nginx/sites-available/ghost-http /etc/nginx/sites-enabled/ghost-http
nginx -t
systemctl enable --now nginx
systemctl reload nginx
# DNS must already have a DNS-only A record pointing to this VPS; no AAAA.
certbot certonly --webroot -w /var/www/letsencrypt -d ghost.dzen.dev --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring
install -m644 "$stage/nginx.conf" /etc/nginx/sites-available/ghost
ln -sf /etc/nginx/sites-available/ghost /etc/nginx/sites-enabled/ghost
nginx -t
systemctl reload nginx
install -d /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nset -eu\n/usr/sbin/nginx -t\n/usr/bin/systemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
systemctl enable --now certbot.timer
systemctl is-active ghost nginx mysql tailscaled certbot.timer
REMOTE_SCRIPT
echo 'Deployment complete: https://ghost.dzen.dev. Run scripts/verify.py from outside the VPS.'
