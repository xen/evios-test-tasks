# Evios — completed test assignments

Submission by Mikhail Kashkin. Both assignments are included in this repository; the Ghost deployment is live at **https://ghost.dzen.dev**.

## 1. Fullstack FastAPI: role-based access control

[Implementation and local setup](fullstack/README.md) · [verification](docs/verification.md) · [original brief](docs/assignment-fullstack.md)

Implemented admin/manager/member roles, server-side authorization, role-aware React navigation and actions, a database migration, demo accounts and tests. JWTs identify users; permissions are read from the database on each request, so role changes and account deactivation affect existing sessions. Managers have read-only user access and metrics; members have access to their own profile and items. Direct unauthorized navigation shows Access denied, and unauthorized API requests return 403.

Recorded validation: **76 backend tests**, **13 Chromium admin tests**, Ruff, mypy, ty, TypeScript/Vite build, migration upgrade/downgrade, and installation from a clean Git clone. Screenshots and exact boundaries are in the verification report. The application is supplied for local execution; there is no public FastAPI demo deployment.

## 2. Ghost on Hetzner: one-command shell deployment

[Live blog](https://ghost.dzen.dev) · [standalone deploy.sh](ghost/deploy.sh) · [public Gist](https://gist.github.com/xen/ec539e3ef29698d73088b686c1cc6b5e) · [setup and operation](ghost/README.md) · [verification](ghost/verification.md)

A self-contained **POSIX sh** script installs the complete stack on Ubuntu 24.04/26.04 ARM64 or AMD64: deploy user/keys/sudo, Tailscale, firewall, Node.js 22, MySQL, Ghost, nginx, certbot, systemd services and certificate renewal. It generates credentials on the VPS, claims the owner before public application access, verifies a separate deploy SSH connection over Tailscale, and only then disables root/password SSH and blocks public port 22.

Public web traffic uses direct IPv4 HTTPS through nginx and Let's Encrypt. Cloudflare supplies DNS only; its former tunnel was removed at the owner's request. Administrative SSH uses Tailscale. The script requires an existing VPS, trusted bootstrap SSH access, a DNS A record and a preauthorized Tailscale auth key for a new node. See the deployment README for the bootstrap boundary and exact command.

Verified on the supplied VPS: complete installer rerun, private SSH, public port restrictions, Ghost/admin HTTPS, HTTP redirect, owner setup protection, certificate renewal simulation, and browser rendering. A second clean VPS and fresh Tailscale enrollment were not provisioned for this final script; those paths are documented rather than claimed as independently tested.

## AI conversation and provenance

The requested [AI conversation copy](ai/conversation.md) and [structured dialogue](ai/messages.json) contain the visible user/assistant exchange through their export time. Tool payloads, internal instructions, private reasoning and secret files are excluded. Plans and acceptance criteria are in [docs/specs](docs/specs/).

The fullstack template's upstream revision and MIT licence are recorded in [source provenance](docs/upstream.md) and [fullstack/LICENSE](fullstack/LICENSE). Example application passwords are explicitly disposable local demo credentials. Live Ghost and database credentials are not published. Git history was scanned with Gitleaks before public release; no leaks were found.
