#!/bin/sh
# Ghost on a fresh Ubuntu VPS. POSIX sh; no Python or embedded JS.
# Run on the control machine; dependencies: sh, ssh, scp, mktemp, curl.
# BOOTSTRAP_TARGET=root@VPS DOMAIN=blog.example.com OWNER_EMAIL=owner@example.com \
# TS_AUTHKEY_FILE=./tailscale.key sh deploy.sh
set -eu
fail() { printf '%s\n' "Error: $*" >&2; exit 1; }
validate_domain() {
    case "$1" in ''|*[!a-z0-9.-]*|.*|*..*|*.) fail 'Invalid DOMAIN';; esac
    case "$1" in *.*) ;; *) fail 'DOMAIN must be a fully qualified hostname';; esac
}
validate_email() {
    case "$1" in ''|*[!A-Za-z0-9@._+-]*) fail 'Invalid OWNER_EMAIL';; esac
    case "$1" in *@*.*) ;; *) fail 'OWNER_EMAIL must be an email address';; esac
}
server_install() {
    [ "$(id -u)" = 0 ] || fail 'Server installer requires root/sudo'
    domain=$1 owner_email=$2 stage=$3
    validate_domain "$domain"; validate_email "$owner_email"
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "$ID" = ubuntu ] || fail 'Requires Ubuntu'
    case "$VERSION_ID" in 24.04|26.04) ;; *) fail 'Requires Ubuntu 24.04 or 26.04';; esac
    case "$(dpkg --print-architecture)" in arm64|amd64) ;; *) fail 'Requires ARM64 or AMD64';; esac
    # Refuse a partially created database, before installing or modifying services.
    if command -v mysql >/dev/null 2>&1 && [ ! -f /var/www/ghost/config.production.json ]; then
        existing=$(mysql -Nse "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='ghost'")
        [ -z "$existing" ] || fail 'Existing ghost DB without configuration; refusing to overwrite'
    fi
    # Existing deploy installations keep their keys. A fresh user receives root's key.
    if ! id deploy >/dev/null 2>&1; then
        [ -s /root/.ssh/authorized_keys ] || fail 'Provision a root SSH public key first'
        useradd --create-home --shell /bin/bash deploy
        install -d -m700 -o deploy -g deploy /home/deploy/.ssh
        install -m600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
    fi
    [ -s /home/deploy/.ssh/authorized_keys ] || fail 'Deploy SSH key is missing'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    apt-get install -y sudo ufw openssh-server ca-certificates curl gnupg jq openssl unattended-upgrades dnsutils
    usermod -aG sudo deploy
    passwd -l deploy
    printf '%s\n' 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy
    chmod 440 /etc/sudoers.d/deploy
    visudo -cf /etc/sudoers.d/deploy
    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh -o "$stage/install-tailscale.sh"
        sh "$stage/install-tailscale.sh"
    fi
    systemctl enable --now tailscaled
    if ! tailscale status --json | jq -e '.BackendState == "Running"' >/dev/null; then
        [ -s "$stage/tailscale.key" ] || fail 'New server requires TS_AUTHKEY_FILE (preauthorized key)'
        tailscale up --auth-key="file:$stage/tailscale.key" --hostname=ghost-blog --accept-dns=false --timeout=120s
    fi
    [ ! -f "$stage/tailscale.key" ] || unlink "$stage/tailscale.key"
    # ACME requires the actual origin IPv4, with no proxy/AAAA record.
    origin=$(ip -4 -o addr show scope global | awk '$2 != "tailscale0" {split($4,a,"/"); print a[1]; exit}')
    [ -n "$origin" ] || fail 'No public origin IPv4'
    dns_a=$(dig @1.1.1.1 +short A "$domain")
    [ "$dns_a" = "$origin" ] || fail "Create a DNS-only A record $domain -> $origin before installation"
    [ -z "$(dig @1.1.1.1 +short AAAA "$domain")" ] || fail 'Remove the website AAAA record before installation'
    # No public Ghost setup: only the loopback app starts before owner creation.
    # Prevent Debian postinst scripts from starting nginx with a public welcome site.
    [ ! -e /usr/sbin/policy-rc.d ] || fail 'Existing policy-rc.d: review installation policy first'
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
    chmod 755 /usr/sbin/policy-rc.d
    trap 'unlink /usr/sbin/policy-rc.d' EXIT HUP INT TERM
    apt-get install -y nginx mysql-server unzip certbot
    unlink /usr/sbin/policy-rc.d
    trap - EXIT HUP INT TERM
    [ ! -L /etc/nginx/sites-enabled/default ] || unlink /etc/nginx/sites-enabled/default
    install -d -m755 /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
    printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' > /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
    node --version | grep -q '^v22\.' || fail 'Node 22 is required'
    npm install --global ghost-cli@1.33.7
    install -d -m755 -o deploy -g deploy /var/www/ghost
    if [ ! -L /var/www/ghost/current ]; then
        runuser -u deploy -- sh -c 'cd /var/www/ghost && ghost install 6.71.0 --no-setup --no-start --no-prompt --no-color'
    fi
    systemctl enable --now mysql
    umask 077
    config=/var/www/ghost/config.production.json
    if [ -f "$config" ]; then
        jq -e --arg url "https://$domain" '.url == $url and .server.host == "127.0.0.1" and .server.port == 2368 and .database.client == "mysql" and .database.connection.database == "ghost"' "$config" >/dev/null || fail 'Existing Ghost configuration conflicts with requested deployment'
    else
        db_password=$(openssl rand -hex 32)
        # SQL and JSON secrets use stdin/files, never process arguments or stdout.
        mysql <<SQL
CREATE DATABASE ghost;
CREATE USER 'ghost'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL ON ghost.* TO 'ghost'@'localhost';
SQL
        printf '%s' "$db_password" | jq -Rs --arg url "https://$domain" '{url:$url,server:{host:"127.0.0.1",port:2368},database:{client:"mysql",connection:{host:"127.0.0.1",user:"ghost",password:.,database:"ghost"}},logging:{transports:["stdout"]},paths:{contentPath:"/var/www/ghost/content"}}' > "$config"
        unset db_password
    fi
    chown deploy:deploy "$config"; chmod 600 "$config"
    cat > /etc/systemd/system/ghost.service <<'UNIT'
[Unit]
Description=Ghost blog
After=network.target mysql.service
Requires=mysql.service
[Service]
Type=simple
User=deploy
Group=deploy
WorkingDirectory=/var/www/ghost
Environment=NODE_ENV=production
ExecStart=/usr/bin/node /var/www/ghost/current/index.js
Restart=on-failure
RestartSec=5
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
[Install]
WantedBy=multi-user.target
UNIT
    install -d /etc/systemd/system/cloud-init-local.service.d
    printf '[Service]\nExecStartPre=/usr/bin/udevadm settle --timeout=30\n' > /etc/systemd/system/cloud-init-local.service.d/10-udev.conf
    systemctl daemon-reload
    systemctl enable --now ghost
    systemctl restart ghost
    ready=false
    attempt=0
    while [ "$attempt" -lt 60 ]; do
        attempt=$((attempt + 1))
        if curl -fsS -H "Host: $domain" -H 'X-Forwarded-Proto: https' http://127.0.0.1:2368/ghost/api/admin/authentication/setup/ > "$stage/setup.json"; then ready=true; break; fi
        sleep 2
    done
    [ "$ready" = true ] || fail 'Ghost did not become ready'
    if ! jq -e '.setup[0].status == true' "$stage/setup.json" >/dev/null; then
        owner_file=/root/ghost-owner.json
        if [ ! -f "$owner_file" ]; then
            openssl rand -hex 32 | tr -d '\n' | jq -Rs --arg email "$owner_email" '{email:$email,password:.}' > "$owner_file"
        fi
        jq -e --arg email "$owner_email" '.email == $email' "$owner_file" >/dev/null || fail 'Saved owner credentials conflict'
        jq '{setup:[{name:"Administrator",email:.email,password:.password,blogTitle:"Ghost"}]}' "$owner_file" > "$stage/owner-request.json"
        curl -fsS -H "Host: $domain" -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' --data-binary "@$stage/owner-request.json" http://127.0.0.1:2368/ghost/api/admin/authentication/setup/ > "$stage/owner-response.json" || fail 'Owner setup failed; response is in private stage directory'
    fi
    [ ! -f "$stage/owner-request.json" ] || unlink "$stage/owner-request.json"
    [ ! -f "$stage/owner-response.json" ] || unlink "$stage/owner-response.json"
    install -d -m755 /var/www/letsencrypt/.well-known/acme-challenge
    cat > /etc/nginx/sites-available/ghost-http <<NGINX
server {
 listen 0.0.0.0:80;
 server_name $domain;
 server_tokens off;
 if (\$host != $domain) { return 404; }
 location ^~ /.well-known/acme-challenge/ { root /var/www/letsencrypt; try_files \$uri =404; }
 location / { return 301 https://$domain\$request_uri; }
}
NGINX
    ln -sf /etc/nginx/sites-available/ghost-http /etc/nginx/sites-enabled/ghost-http
    nginx -t
    ufw allow 80/tcp; ufw allow 443/tcp
    systemctl enable --now nginx
    systemctl reload nginx
    certbot certonly --webroot -w /var/www/letsencrypt -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring
    cat > /etc/nginx/sites-available/ghost <<NGINX
server {
 listen 0.0.0.0:443 ssl;
 server_name $domain;
 ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
 ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
 ssl_protocols TLSv1.2 TLSv1.3;
 server_tokens off;
 client_max_body_size 50m;
 if (\$host != $domain) { return 404; }
 location / {
  proxy_pass http://127.0.0.1:2368;
  proxy_set_header Host $domain;
  proxy_set_header X-Forwarded-Proto https;
  proxy_set_header X-Forwarded-For \$remote_addr;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_http_version 1.1;
 }
}
NGINX
    ln -sf /etc/nginx/sites-available/ghost /etc/nginx/sites-enabled/ghost
    nginx -t; systemctl reload nginx
    install -d /etc/letsencrypt/renewal-hooks/deploy
    printf '#!/bin/sh\nset -eu\n/usr/sbin/nginx -t\n/usr/bin/systemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx
    systemctl enable --now certbot.timer unattended-upgrades
    printf '%s\n' 'Server installation completed; controller must verify private SSH before lockdown.'
}
finalize() {
    [ "$(id -u)" = 0 ] || fail 'Finalize requires sudo'
    peer=${SSH_CONNECTION%% *}
    case "$peer" in 100.*|fd7a:*) ;; *) fail 'Finalize must run over a verified Tailscale SSH connection';; esac
    # Unknown firewall policy is an explicit error; never reset unrelated rules.
    ufw show added | while IFS= read -r rule; do
        case "$rule" in
            'ufw allow in on tailscale0 to any port 22 proto tcp'|'ufw allow 80/tcp'|'ufw allow 443/tcp') ;;
            ufw\ *) fail 'Unexpected existing firewall rule; review before lockdown';;
        esac
    done
    cat > /etc/ssh/sshd_config.d/00-ghost-hardening.conf <<'SSH'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers deploy
SSH
    install -d -m755 /run/sshd
    /usr/sbin/sshd -t
    ufw default deny incoming; ufw default allow outgoing
    ufw allow in on tailscale0 to any port 22 proto tcp
    ufw allow 80/tcp; ufw allow 443/tcp
    ufw --force enable
    systemctl reload ssh
    printf '%s\n' 'Private SSH verified; public SSH closed.'
}
case "${1-}" in
    --server) shift; [ "$#" = 3 ] || fail 'Internal server arguments'; server_install "$@"; exit;;
    --finalize) finalize; exit;;
    '') ;;
    *) fail 'Usage: configure environment and run sh deploy.sh';;
esac
: "${BOOTSTRAP_TARGET:?Set BOOTSTRAP_TARGET=root@new-vps (or existing sudo user)}"
: "${DOMAIN:?Set DOMAIN to your DNS-only IPv4 hostname}"
: "${OWNER_EMAIL:?Set OWNER_EMAIL}"
validate_domain "$DOMAIN"; validate_email "$OWNER_EMAIL"
case "$BOOTSTRAP_TARGET" in *[!A-Za-z0-9@._-]*|'') fail 'Invalid BOOTSTRAP_TARGET';; esac
[ -f "$0" ] || fail 'Download the script before running it; do not pipe to sh'
# Initial host identity must already be trusted; no accept-new or disabled verification.
ssh_boot() { ssh -o BatchMode=yes -o ForwardAgent=no -o StrictHostKeyChecking=yes "$BOOTSTRAP_TARGET" "$@"; }
stage=$(ssh_boot 'mktemp -d /tmp/ghost-install.XXXXXXXX')
case "$stage" in *[!A-Za-z0-9/._-]*) fail "Unsafe stage directory";; esac
case "$stage" in /tmp/ghost-install.????????) ;; *) fail 'Unexpected stage directory';; esac
known=$(mktemp)
cleanup() { [ ! -f "$known" ] || unlink "$known"; }
trap cleanup EXIT HUP INT TERM
ssh_boot "cat > $stage/deploy.sh" < "$0"
if [ -n "${TS_AUTHKEY_FILE-}" ]; then
    [ -s "$TS_AUTHKEY_FILE" ] || fail 'TS_AUTHKEY_FILE is empty'
    ssh_boot "umask 077; cat > $stage/tailscale.key" < "$TS_AUTHKEY_FILE"
fi
remote_uid=$(ssh_boot "id -u")
elevate="sudo -n"
[ "$remote_uid" != 0 ] || elevate=""
ssh_boot "$elevate sh $stage/deploy.sh --server $DOMAIN $OWNER_EMAIL $stage"
tail_ip=$(ssh_boot 'sudo -n tailscale ip -4')
case "$tail_ip" in 100.*) ;; *) fail 'No valid Tailscale IPv4';; esac
host_key=$(ssh_boot 'sudo -n cat /etc/ssh/ssh_host_ed25519_key.pub')
printf '%s %s\n' "$tail_ip" "$host_key" > "$known"
ssh_private() { ssh -o BatchMode=yes -o ForwardAgent=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known" "deploy@$tail_ip" "$@"; }
# Separate control-machine connection verifies the actual deploy key, host key and sudo.
ssh_private 'sudo -n true'
ssh_private "sudo --preserve-env=SSH_CONNECTION sh $stage/deploy.sh --finalize"
ssh_private 'sudo -n true; systemctl is-active ghost nginx mysql tailscaled certbot.timer'
# Remove staged auth key, owner API response, and installer only after success.
ssh_private "sudo find $stage -maxdepth 1 -type f -delete; sudo rmdir $stage"
printf 'Deployment complete: https://%s\nSSH: ssh deploy@%s\n' "$DOMAIN" "$tail_ip"
printf '%s\n' 'If newly created, owner credentials are in /root/ghost-owner.json on the VPS (root-only).'
