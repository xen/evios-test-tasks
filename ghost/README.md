# Ghost on Hetzner through tunnels

Live blog: https://ghost.dzen.dev — admin: https://ghost.dzen.dev/ghost/.

Dedicated Hetzner ARM64 VPS, Ubuntu 26.04.1. Ghost 6.71.0 runs as `deploy` through systemd, Node 22, MySQL 8.4, nginx. nginx/Ghost/MySQL listen on loopback. Cloudflare terminates HTTPS and reaches nginx through its encrypted outbound tunnel. OpenSSH is key-only, root login disabled, UFW denies incoming traffic except SSH over `tailscale0`. Public TCP 22/80/443 are closed.

## One-command server deployment

This is deployment onto an existing VPS, not paid cloud provisioning. Prerequisites are explicit: a dedicated Ubuntu 26.04 ARM64 VPS, `deploy` with key-based SSH and passwordless sudo, enrolled in your Tailscale network, verified SSH host key, and a locally managed Cloudflare tunnel credential JSON. The control machine needs Bash, Python 3, OpenSSH, and access to the tailnet. The templates target `ghost.dzen.dev` and tunnel `3c5fb28c-9a5b-4baa-9d42-3348432bab7c`; change both before using another deployment.

```bash
GHOST_SSH_TARGET=deploy@100.76.172.36 \
TUNNEL_CREDENTIALS="$HOME/.cloudflared/3c5fb28c-9a5b-4baa-9d42-3348432bab7c.json" \
./ghost/deploy.sh
```

The script installs the stack, configures Ghost and its database, claims the owner before publishing, installs nginx/cloudflared systemd services, and applies the firewall through an already verified private SSH connection. Re-running preserves the existing database, owner password and content. It does not upgrade an existing Ghost version automatically. A database without its matching configuration causes an explicit failure; investigate rather than overwrite.

First enrollment requires identity approval in Tailscale. For a fresh VPS use `scripts/bootstrap.sh` from the Hetzner console (or an existing trusted bootstrap SSH connection), authorize `tailscale up --hostname=ghost-test --accept-dns=false`, then separately test `deploy` SSH over its Tailscale address. The server script runs all deployment steps over that private connection. Public SSH is not required for steady-state deployment or maintenance. Never close bootstrap access before the private connection works.

Cloudflare account setup is a separate prerequisite: create a dedicated named tunnel (`cloudflared tunnel create ghost-test`) and add a **proxied CNAME** `ghost.dzen.dev` → `<tunnel UUID>.cfargotunnel.com` in the correct `dzen.dev` zone. Do this after the owner is claimed. Account credentials are never copied to the server; only this tunnel's JSON is installed, owned by the non-login `cloudflared` user, mode 0600. Existing tunnels and other DNS records are untouched. The actual deployment's DNS was configured in the authenticated Cloudflare dashboard because the locally cached management certificate belongs to another zone.

## Access and verification

```bash
ssh deploy@100.76.172.36
GHOST_SSH_TARGET=deploy@100.76.172.36 python3 ghost/scripts/verify.py
```

Run verification from outside the VPS. It checks public HTTPS/admin/setup status, HTTP→HTTPS, public TCP ports for IPv4/IPv6, and services/private SSH. No-route IPv6 results are explicitly inconclusive. A real reboot was also performed; see `verification.md`.

Owner email is `test@example.com`; its randomly generated password is stored only in ignored `ghost/.secrets/owner.json` on the control machine. The database password is generated on the VPS in `/var/www/ghost/config.production.json` (deploy, mode 0600). Neither secret is in Git. Do not delete the local owner file before transferring credentials securely. This reserved test email cannot receive password resets. SMTP, newsletters, external backups and monitoring are outside this test deployment; email delivery has not been verified.

## Maintenance and recovery

Use `sudo journalctl -u ghost`, `-u nginx`, `-u cloudflared`, and `-u tailscaled`; `sudo nginx -t`; `sudo systemctl restart ghost`. Before a Ghost upgrade, back up MySQL (`sudo mysqldump --single-transaction ghost`) and `/var/www/ghost/content` plus the protected configuration. Store backups outside the VPS; none were provisioned by this task. Deploy has administrative sudo by the user's initial-server recipe.

If Tailscale access fails, use the Hetzner web console to inspect `tailscaled` and UFW; do not open public SSH as an automatic fallback. Cloudflare Tunnel failure makes the blog unavailable until the tunnel recovers. To retire this test, stop the Ghost/tunnel services and remove only its DNS record and dedicated tunnel; preserve data unless deletion is explicitly requested.

On this Hetzner image, `templates/cloud-init-local.conf` prevents metadata discovery racing the udev interface rename. It waits for queued udev events before cloud-init's local stage. The correction was verified by a second real reboot: cloud-init completed without errors, no systemd failures, updated kernel `7.0.0-38-generic` running.

For stale local DNS, the verifier accepts an **explicit diagnostic** override, for example `python3 ghost/scripts/verify.py --edge-ip 104.21.79.240` after independently observing that address from a public resolver. This keeps domain/SNI and certificate validation, and prints that local DNS was not tested. It is never applied automatically. Existing UFW rules outside the declared Tailscale SSH allowance cause deployment to fail for review instead of leaving an accidental public allowance.
