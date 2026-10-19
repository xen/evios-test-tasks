#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[[ $(uname -m) == aarch64 ]] || { echo 'This deployment targets ARM64' >&2; exit 1; }
apt-get update
apt-get install -y nginx mysql-server python3 unzip certbot
install -d -m755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
printf '%s\n' 'deb [arch=arm64,amd64 signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
[[ $(node -p 'process.versions.node.split(".")[0]') == 22 ]]
npm install --global ghost-cli@1.33.7
install -d -m755 -o deploy -g deploy /var/www/ghost
systemctl enable --now mysql
# Remove the distribution's publicly listening welcome site before starting nginx.
rm -f /etc/nginx/sites-enabled/default
systemctl stop nginx
