# Ghost verification — 2026-10-19

Current architecture: direct IPv4 nginx HTTPS with certbot; SSH only through Tailscale. This supersedes the initial Cloudflare Tunnel deployment at the user's explicit request.

## Confirmed current state

- DNS-only A record: `ghost.dzen.dev` → `95.217.219.81`; no AAAA answer from authoritative Cloudflare DNS, 1.1.1.1, or the local resolver after cache flush.
- Ordinary DNS-based `curl -4 https://ghost.dzen.dev/` returns 200 with certificate verification enabled, without an address override. `/ghost/` returns 200. HTTP returns 301 to the same HTTPS hostname. Owner setup reports completed.
- Chrome visibly rendered the Ghost home page after macOS DNS cache refresh: [screenshot](evidence/ghost-direct-https.png).
- Let's Encrypt certificate issuer YE2; valid until 2027-01-17. Certbot 4.0.0 HTTP-01 webroot issuance succeeded. `certbot renew --dry-run --run-deploy-hooks` succeeded, including nginx config validation/reload. `certbot.timer` active and enabled.
- nginx listens on 0.0.0.0:80 and 443. Ghost 6.71.0 runs as deploy on 127.0.0.1:2368, MySQL 8.4.11 on loopback. Node 22.23.3, Ghost CLI 1.33.7.
- Public web ports are open as requested. Public IPv4 TCP 22/2368/3306/8080 are unavailable. Private `ssh deploy@100.76.172.36` works. UFW default deny incoming, explicit public 80/443 and TCP 22 only on tailscale0.
- Effective SSH settings: root login off, password and keyboard-interactive authentication off, AllowUsers deploy. User-confirmed server ED25519 fingerprint: `SHA256:jJP16VAsoSTZ/l1yLb57n95BY+SiBOHVLX/Hj6iSy5k`.
- Cloudflare tunnel `ghost-test` (`3c5fb28c-9a5b-4baa-9d42-3348432bab7c`) deleted. CLI tunnel list now contains only the unrelated existing `vchat` tunnel. On the VPS, cloudflared package/service/configuration/tunnel credential and its service account were removed. No old ingress remains on port 8080.
- Repeated deployments preserve existing data/owner. Bash syntax, Python compilation and nginx validation passed. Raw current checks: [verification.txt](evidence/verification.txt).

## Previous OS checks and limits

Two real reboots were performed during the original stack setup. The second boot ran updated kernel 7.0.0-38-generic, cloud-init reported done with no errors, no systemd failures, and Ghost/nginx/MySQL/Tailscale recovered. A udev ordering drop-in resolved an observed cloud-init interface-rename race. The direct-ingress migration separately verified service restart and certbot timer enablement; a further full reboot was not required for these nginx/DNS changes.

Initial local NXDOMAIN and old IPv6 cache entries were observed, not assumed. After DNS migration and the user's macOS cache flush, dscacheutil returned only 95.217.219.81 and real browser navigation worked. IPv6 website access is intentionally absent in this revision; no external IPv6 reachability claim is made.

Clean-slate one-command deployment on another VPS, SMTP/reset or device-verification email, newsletters and external backup restore remain unverified. ACME account has no contact email; renewal relies on the active timer. See [README](README.md) for prerequisites and operation.
