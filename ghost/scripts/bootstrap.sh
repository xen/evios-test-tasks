#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run as root' >&2; exit 1; }
[[ -s /root/.ssh/authorized_keys ]] || { echo 'Root authorized_keys is empty' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ufw sudo openssh-server ca-certificates curl gnupg unattended-upgrades
if ! id -u deploy >/dev/null 2>&1; then useradd --create-home --shell /bin/bash deploy; fi
usermod -aG sudo deploy
passwd -l deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
printf '%s\n' 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy
visudo -cf /etc/sudoers.d/deploy
cat > /etc/ssh/sshd_config.d/00-ghost-hardening.conf <<'SSH'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
SSH
install -d -m 755 /run/sshd
sshd -t
systemctl reload ssh
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh -o /root/install-tailscale.sh
  sh /root/install-tailscale.sh
fi
systemctl enable --now tailscaled
