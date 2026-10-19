# Ghost deployment result

Live: https://ghost.dzen.dev. Admin: https://ghost.dzen.dev/ghost/.

`deploy.sh` is a single, self-contained **POSIX sh** installer. It contains no Python or embedded JavaScript and needs no other files from this repository. jq handles JSON; Ghost runs on Node.js. Certbot brings its normal distribution-managed Python dependencies; the deployment code itself is shell only.

## New VPS installation

Requirements on the control machine: sh, OpenSSH, curl, and access to your Tailscale network. The VPS must be dedicated Ubuntu 24.04/26.04 (ARM64/AMD64), with a provisioned SSH public key and a trusted host key already in the control machine's known_hosts. The same key must work for the deploy user copied from root. Create a DNS-only A record pointing your domain to the VPS public IPv4, without an AAAA record. Supply a preauthorized, preferably single-use Tailscale auth key in a local file with mode 0600. Ensure your tailnet policy allows the control machine to reach the new server's TCP 22.

[Public Gist](https://gist.github.com/xen/ec539e3ef29698d73088b686c1cc6b5e). Download and inspect `deploy.sh`, then run locally:

```sh
BOOTSTRAP_TARGET=root@YOUR_VPS_IP \
DOMAIN=blog.example.com \
OWNER_EMAIL=owner@example.com \
TS_AUTHKEY_FILE=./tailscale.key \
sh deploy.sh
```

No password, auth key or API token is embedded in the script or put into process arguments. The auth key is uploaded into a private staging directory and passed to Tailscale through a file. Successful installation removes staged secrets/files. On failure, the root/sudo-protected stage is retained for diagnosis; do not publish it. Revoke unused auth keys after a failed enrollment.

The installer creates deploy, installs all packages and Node/Ghost, configures MySQL credentials, claims the Ghost owner privately, obtains the HTTPS certificate, enables systemd services/renewal, and applies firewall policy. SSH host checking stays enabled. A separate deploy connection over the assigned Tailscale IP must succeed with the original server's verified host key before the script disables public/root/password SSH. Unknown firewall rules or conflicting Ghost/database configuration produce an explicit error.

**Bootstrap boundary:** the script does not create or pay for a VPS. Initial control uses the specified trusted SSH endpoint, which may already be reachable through a tunnel. If a fresh provider image initially exposes public root SSH, that connection is used only for installation and is closed after the verified Tailscale handover. If policy forbids public SSH even during bootstrap, provision initial tunnel access via the provider console/cloud-init and point BOOTSTRAP_TARGET at that private endpoint. The script never opens public SSH. Final administrative access is exclusively through Tailscale.

## Existing VPS / repeat deployment

```sh
BOOTSTRAP_TARGET=deploy@100.76.172.36 \
DOMAIN=ghost.dzen.dev OWNER_EMAIL=test@example.com \
sh ghost/deploy.sh
```

An already connected Tailscale node needs no new auth key. Existing deploy keys, database credentials, owner password and content are preserved. The pinned versions are Ghost 6.71.0 and Ghost CLI 1.33.7; an existing Ghost installation is not automatically upgraded. Updates/restarts cause a brief interruption. Do not run this dedicated-server installer on a shared host.

For a newly claimed owner, credentials are saved only in `/root/ghost-owner.json` on the VPS (mode 0600). The database password is in `/var/www/ghost/config.production.json` (deploy, 0600). Existing demo owner credentials remain in the original private local credential file; they are not in this repository. Use a real accessible OWNER_EMAIL for a new installation. Staff device verification remains enabled; SMTP/reset/device-verification email delivery is not configured by this task.

## Verification and maintenance

```sh
# Control-machine checks; shellcheck is required only for the local static tests.
sh ghost/scripts/test.sh
DOMAIN=ghost.dzen.dev ORIGIN_IP=95.217.219.81 \
SSH_TARGET=deploy@100.76.172.36 sh ghost/scripts/verify.sh
ssh deploy@100.76.172.36 'sudo certbot renew --dry-run --run-deploy-hooks'
```

The verifier checks actual IPv4-only DNS, HTTPS/admin/setup, HTTP→HTTPS, public TCP 22/2368/3306/8080 denial, private SSH, effective sshd configuration and services. Evidence: [verification.md](verification.md).

nginx exposes IPv4 80/443, Ghost/MySQL remain loopback, UFW denies other incoming traffic and permits SSH only on tailscale0. HTTP-01 remains available on port 80 for certbot; a renewal hook validates and reloads nginx. ACME registration has no contact email. Deploy has administrative sudo by the supplied initial-server recipe. Recover lost Tailscale access through the Hetzner console; there is no automatic public SSH fallback.

Before upgrades, back up MySQL, `/var/www/ghost/content`, and protected configuration outside the VPS. External backups, monitoring, newsletters and SMTP are outside this test. The observed Ubuntu/Hetzner cloud-init interface-rename race is handled with a small udev-ordering drop-in and was verified by reboot on the supplied VPS.
