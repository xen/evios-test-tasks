# Deployment verification — 2026-10-19

VPS: Hetzner `ghost-test`, 95.217.219.81, Tailscale 100.76.172.36, Ubuntu 26.04.1 ARM64. Host ED25519 fingerprint was confirmed by the user after their reinstall: `SHA256:jJP16VAsoSTZ/l1yLb57n95BY+SiBOHVLX/Hj6iSy5k`.

## Verified

- Ghost 6.71.0, Ghost CLI 1.33.7, Node 22.23.3, MySQL 8.4.11, cloudflared 2026.10.1.
- Separate deploy SSH over Tailscale and passwordless administrative sudo. Firewall applied only after that connection succeeded. Public root bootstrap is no longer available.
- Effective sshd config: PermitRootLogin no, PasswordAuthentication no, KbdInteractiveAuthentication no, AllowUsers deploy.
- UFW active: default deny incoming, allow outgoing; only incoming allowance is TCP 22 on tailscale0 for IPv4 and IPv6.
- Ghost service User=deploy. nginx 127.0.0.1:8080, Ghost 127.0.0.1:2368, MySQL 127.0.0.1:3306 and 33060. cloudflared metrics 127.0.0.1:20241.
- Dedicated Cloudflare tunnel `3c5fb28c-9a5b-4baa-9d42-3348432bab7c` (`ghost-test`), four registered encrypted QUIC connections. Only this tunnel credential copied to the VPS; account management certificate remains local.
- Proxied DNS record `ghost.dzen.dev` routes to `ghost-test`. Existing unrelated records/tunnels were not changed by the deployment. Screenshot: [Cloudflare DNS](evidence/cloudflare-dns.png).
- Public Cloudflare HTTPS `/` and `/ghost/` return 200 with certificate verification enabled. HTTP returns 301 to https://ghost.dzen.dev/. Setup API returns `{"setup":[{"status":true}]}`. Owner password authentication over the private/local connection returned HTTP 201; staff device verification remains enabled.
- From the control Mac, public IPv4 TCP 22/80/443/2368/3306/8080 are unavailable. Private deploy SSH continues to work.
- Bash syntax, Python compilation, nginx config and cloudflared ingress validation passed. The combined deployment script was rerun successfully against this VPS, preserving the database and owner. The final revision keeps cloudflared stopped until owner setup completes, including when DNS already exists.
- First real reboot restored Ghost, nginx, MySQL, cloudflared and Tailscale automatically, with private SSH and public HTTPS working again.

Raw check output: [verification.txt](evidence/verification.txt).

## Evidence limits

The Mac's DNS resolver cached NXDOMAIN from before DNS creation (SOA negative cache TTL up to 1800 seconds). Cloudflare 1.1.1.1 and Google 8.8.8.8 already returned 104.21.79.240 / 172.67.172.4. HTTP checks from the Mac therefore explicitly used the observed Cloudflare edge IP (`verify.py --edge-ip 104.21.79.240`), preserving the real domain/SNI and TLS certificate verification. This is a diagnostic override, not application routing. Browser navigation on the Mac initially failed due to that stale DNS cache; no successful browser rendering is claimed. Ordinary DNS-based curl from the VPS returned 200.

External IPv6 probes are inconclusive because the Mac has no IPv6 route. The VPS has `2a01:4f9:c013:3307::1`, UFW IPv6 policy is enabled and loopback bindings were inspected, but an independent IPv6 connection test is still needed to fully satisfy that acceptance criterion.

The first reboot exposed a cloud-init race: metadata discovery referenced enp1s0 while udev renamed it to eth0. A small systemd drop-in waits for the current udev event queue before cloud-init's local stage; no addresses or routing were changed. The final reboot result is recorded below.

SMTP/reset email/newsletters, external backup restore, and a clean-slate all-in-one installation on another VPS have not been verified. Account setup and Cloudflare DNS/tunnel creation remain documented prerequisites of the one-command server deployment.

## Final OS reboot

After installing OS updates and kernel `7.0.0-38-generic`, a second real reboot completed successfully. `cloud-init status --long` returned `done`, with `errors: []` and no recoverable errors; `systemctl --failed` was empty. All five services were active and private SSH worked. The udev ordering drop-in resolved the observed startup race on this VPS. Its mechanism uses the documented [udevadm settle](https://www.freedesktop.org/software/systemd/man/262/udevadm.html) event-queue wait before the [cloud-init local stage](https://docs.cloud-init.io/en/latest/explanation/boot.html).
