#!/bin/sh
# Run on the control machine, outside the VPS.
set -eu
: "${DOMAIN:=ghost.dzen.dev}"
: "${ORIGIN_IP:=95.217.219.81}"
: "${SSH_TARGET:?Set SSH_TARGET=deploy@your-tailscale-IP}"
case "$DOMAIN" in ''|*[!a-z0-9.-]*) exit 2;; esac
case "$ORIGIN_IP" in ''|*[!0-9.]*) exit 2;; esac
[ "$(dig +short A "$DOMAIN")" = "$ORIGIN_IP" ]
[ -z "$(dig +short AAAA "$DOMAIN")" ]
printf '%s\n' 'DNS: origin IPv4 only'
for path in / /ghost/; do
    status=$(curl -4 -fsSL --max-time 20 -o /dev/null -w '%{http_code}' "https://$DOMAIN$path")
    [ "$status" = 200 ]
    printf 'HTTPS %s: 200\n' "$path"
done
headers=$(curl -4 -sSI --max-time 20 "http://$DOMAIN/")
printf '%s\n' "$headers" | grep -q '301'
printf '%s\n' "$headers" | grep -iq "^location: https://$DOMAIN/"
curl -4 -fsS --max-time 20 "https://$DOMAIN/ghost/api/admin/authentication/setup/" | grep -q '"status":true'
for port in 22 2368 3306 8080; do
    connected=$(curl --noproxy '*' -s --connect-timeout 3 --max-time 3 -o /dev/null -w '%{remote_ip}' "telnet://$ORIGIN_IP:$port" || true)
    [ -z "$connected" ] || { printf 'Public TCP %s is open\n' "$port" >&2; exit 1; }
    printf 'Public TCP %s: blocked\n' "$port"
done
ssh -o BatchMode=yes -o ForwardAgent=no -o StrictHostKeyChecking=yes "$SSH_TARGET" 'set -e; sudo -n true; systemctl is-active ghost nginx mysql tailscaled certbot.timer; systemctl is-enabled ghost nginx mysql tailscaled certbot.timer; test "$(systemctl show ghost -p User --value)" = deploy; sudo nginx -t; sudo sshd -T | grep -E "^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers) "; sudo ufw status verbose'
ssh -o BatchMode=yes -o ForwardAgent=no -o StrictHostKeyChecking=yes "$SSH_TARGET" "sudo openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -issuer -dates"
