#!/usr/bin/env bash
set -euo pipefail
# Invoke only through a separately verified deploy SSH connection over Tailscale.
[[ ${SSH_CONNECTION%% *} == 100.* || ${SSH_CONNECTION%% *} == fd7a:* ]] || { echo 'Connect through Tailscale before lockdown' >&2; exit 1; }
tailscale ip -4 >/dev/null
while IFS= read -r rule; do
  if [[ "$rule" == ufw\ * && "$rule" != 'ufw allow in on tailscale0 to any port 22 proto tcp' && "$rule" != 'ufw allow 80/tcp' && "$rule" != 'ufw allow 443/tcp' ]]; then
    echo 'Unexpected existing UFW rule; review and remove it before lockdown' >&2
    exit 1
  fi
done < <(ufw show added)
cat > /etc/ssh/sshd_config.d/00-ghost-hardening.conf <<'SSH'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers deploy
SSH
/usr/sbin/sshd -t
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 to any port 22 proto tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
systemctl reload ssh
systemctl enable --now unattended-upgrades
