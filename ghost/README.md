# Ghost on Hetzner with private SSH

Live blog: https://ghost.dzen.dev — admin: https://ghost.dzen.dev/ghost/.

Ghost 6.71.0 runs as Unix user `deploy` on a dedicated Ubuntu 26.04.1 ARM64 Hetzner VPS. Public web traffic reaches nginx directly over IPv4; nginx terminates TLS with a Let's Encrypt certificate managed by certbot and proxies to Ghost on 127.0.0.1:2368. MySQL 8.4 is local. Administrative SSH is key-only through Tailscale; public TCP 22 is blocked and root login is disabled.

The user explicitly replaced the original Cloudflare Tunnel web ingress with direct nginx/certbot on 2026-10-19. Cloudflare now supplies DNS only: A `ghost.dzen.dev` → `95.217.219.81`, proxy off, no AAAA record. The dedicated Ghost tunnel was deleted, and cloudflared plus its configuration were removed from the VPS. There is no alternate tunnel ingress. This still satisfies the assignment's no-public-SSH requirement: SSH uses Tailscale, while the blog is public over HTTPS.

## One-command deployment

Prerequisites: an existing dedicated Ubuntu 26.04 ARM64 VPS, `deploy` with key-based SSH/passwordless sudo, enrolled in Tailscale, a verified SSH host key, and a DNS-only A record pointing `ghost.dzen.dev` to that VPS with no AAAA record. Control machine: Bash, Python 3, OpenSSH, curl and tailnet access. Templates intentionally target this domain/server; edit them before another installation. Paid VPS provisioning, DNS account setup and Tailscale identity approval are separate prerequisites.

```bash
GHOST_SSH_TARGET=deploy@100.76.172.36 ./ghost/deploy.sh
```

The script configures the firewall, installs Node 22/MySQL/nginx/Ghost CLI/certbot, installs Ghost as deploy, generates its database credentials, claims the owner through private SSH before exposing the application, obtains the TLS certificate with HTTP-01 webroot validation, and enables automatic renewal. The timer runs certbot; a deploy hook checks and reloads nginx after successful renewal. ACME account registration has no contact email; expiry notices are not configured.

Re-running preserves the existing database, owner password and content; it does not automatically upgrade Ghost. A conflicting database/configuration or unexpected UFW rule causes explicit failure. This script targets a dedicated VPS and replaces its named Ghost nginx/systemd configuration. Updates cause a short service interruption. A clean-slate all-in-one run on a second VPS has not been tested; the actual installation and repeated combined deployments on this VPS were tested.

For first enrollment, run `scripts/bootstrap.sh` as root from the Hetzner console or an existing trusted bootstrap connection. Authorize `tailscale up --hostname=ghost-test --accept-dns=false`, verify a separate deploy SSH connection over the private address, then run the deploy script. Never close bootstrap access before that succeeds. Steady-state deployments require no public SSH.

## Access and checks

```bash
ssh deploy@100.76.172.36
GHOST_SSH_TARGET=deploy@100.76.172.36 python3 ghost/scripts/verify.py
ssh deploy@100.76.172.36 'sudo certbot renew --dry-run --run-deploy-hooks'
```

The verifier checks real DNS, public HTTPS/admin/setup, HTTP→HTTPS, blocked public application/SSH ports, private SSH, services, certificate dates and removal of cloudflared. Evidence and limitations: [verification.md](verification.md).

Owner email: `test@example.com`. Its random password is stored only in ignored `ghost/.secrets/owner.json` on the control machine. The database password remains in `/var/www/ghost/config.production.json`, owned by deploy with mode 0600. Neither secret is in Git. The reserved test email cannot receive reset or device-verification mail. SMTP, newsletters, external backups and monitoring are outside this test deployment; email delivery has not been verified. Staff device verification remains enabled.

## Maintenance and recovery

Use `sudo journalctl -u ghost`, `sudo nginx -t`, `sudo systemctl restart ghost`, `sudo certbot certificates`, and `sudo systemctl list-timers certbot.timer`. Before upgrading Ghost, back up MySQL with `sudo mysqldump --single-transaction ghost`, `/var/www/ghost/content`, and the protected configuration. External backups were not provisioned. Deploy has administrative sudo according to the user's initial-server recipe.

If Tailscale access fails, recover through the Hetzner console; there is no automatic public SSH fallback. Keep public port 80 available for certificate renewal; non-ACME HTTP requests redirect to HTTPS. nginx listens on IPv4 only. The VPS retains IPv6 networking for outbound traffic and Tailscale, but the website has no IPv6 listener or AAAA record.

A verified systemd drop-in waits for udev events before cloud-init's local stage, resolving the observed Hetzner image interface-rename race without changing network addresses. OS updates and kernel 7.0.0-38-generic were installed; a real reboot verified cloud-init and service recovery.
