# Fullstack FastAPI — role-based access control

Implementation of the [Evios Fullstack Developer test assignment](docs/assignment-fullstack.md) using FastAPI, PostgreSQL, SQLModel, React and TypeScript.

[Local setup and permission matrix](fullstack/README.md) · [Verification results](docs/verification.md) · [Specification](docs/specs/2026-10-19-evios.md)

Implemented admin/manager/member roles, server-side authorization, role-aware navigation and actions, database migration, demo accounts and tests. Permissions are read from the database on each request, so role changes and account deactivation affect existing sessions. Managers have read-only user access and metrics; members can manage their own profile and items. Unauthorized API requests return 403; direct unauthorized navigation shows Access denied.

Recorded validation: **76 backend tests**, **13 Chromium admin tests**, Ruff, mypy, ty, TypeScript/Vite production build, migration upgrade/downgrade, and installation from a clean Git clone. Exact checks, screenshots and limitations are in the verification report.

The [AI conversation](ai/conversation.md) and [structured dialogue](ai/messages.json) cover this assignment through its review and merge. Internal instructions, tool payloads, private reasoning and secret files are excluded.

The template's upstream revision and MIT licence are recorded in [source provenance](docs/upstream.md) and [fullstack/LICENSE](fullstack/LICENSE). Example passwords are disposable local demo credentials. Git history was scanned with Gitleaks before public release; no leaks were found.
