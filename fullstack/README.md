# Role-aware FastAPI application

RBAC implementation on the [Full Stack FastAPI Template](https://github.com/fastapi/full-stack-fastapi-template), with PostgreSQL, SQLModel, FastAPI, React, TanStack Router/Query, and TypeScript. Original MIT licence: [LICENSE](LICENSE). Exact upstream revision: [source provenance](../docs/upstream.md).

## Run locally

Requirements: Docker Compose v2, [uv](https://docs.astral.sh/uv/), Python 3.14 (installed by uv if needed), [Bun](https://bun.sh/) 1.3+, Make. This tested development setup binds services to loopback and uses separate ports from a default template installation.

From the repository root:

```sh
cd fullstack
cp .env.example .env
cp frontend/.env.example frontend/.env.local
make install
make db
make migrate
make seed
```

In two terminals, from `fullstack/`:

```sh
make backend
```

```sh
make frontend
```

Open **http://127.0.0.1:5174**. API documentation: http://127.0.0.1:8001/docs. PostgreSQL: `127.0.0.1:55433`. The `.env.example` values are for disposable local use only. `make seed` creates the following accounts:

| Account | Role | Password from example configuration |
| --- | --- | --- |
| admin@example.com | admin | evios-local-only |
| manager@example.com | manager | evios-demo-password |
| member@example.com | member | evios-demo-password |

The admin identity/password use `FIRST_SUPERUSER` and `FIRST_SUPERUSER_PASSWORD`; other demo accounts use `DEMO_PASSWORD`. Seeding is repeatable, preserves existing accounts/passwords, and fails explicitly if a demo account has an unexpected role or inactive status. New signups always receive `member`. Mail delivery is disabled in the example configuration; optional SMTP settings remain available from the template.

To stop the local database while preserving data: `docker compose -f compose.local.yml stop`.

## Permission matrix

| Action / surface | admin | manager | member |
| --- | --- | --- | --- |
| List users, `GET /api/v1/users/`, Users page `/admin` | Yes | Yes | No |
| Read another user's profile, `GET /api/v1/users/{id}` | Yes | Yes | No |
| Create user / assign role, `POST /api/v1/users/` | Yes | No | No |
| Update or delete another user, `PATCH/DELETE /api/v1/users/{id}` | Yes | No | No |
| Metrics, `GET /api/v1/metrics/`, page `/metrics` | Yes | Yes | No |
| Read/update own profile, `GET/PATCH /api/v1/users/me` | Yes | Yes | Yes |
| Change own password | Yes | Yes | Yes |
| Delete own account | No | Yes | Yes |
| Own items: list/read/create/update/delete | Yes | Yes | Yes |
| Access others' items (existing template admin behavior) | Yes | No | No |
| Send test email / preview recovery email (template utilities) | Yes | No | No |

Settings in the template are personal profile/password/account settings, available to all roles. It has no global settings endpoint, so none was invented. Administrative operations are admin-only. Metrics are real current user/item totals, without analytics infrastructure.

## Authorization approach

`backend/app/permissions.py` defines roles and the small role-to-permissions mapping. `require_permission()` in `api/deps.py` produces FastAPI dependencies; user listing, user management, and metrics declare the relevant dependency. Authentication loads the current active user from PostgreSQL for each request. JWTs identify the user and do not carry roles; a role change or deactivation therefore applies to existing tokens immediately. Missing/invalid authentication returns 401; authorization denial returns 403. Ownership checks on personal resources stay in their resource handlers, with the template's admin access preserved.

The `role` column is a non-null VARCHAR with a PostgreSQL CHECK constraint and Python enum validation. The migration upgrades existing `is_superuser=true` users to `admin` and all others to `member`, then removes the boolean. Downgrading maps admins to true and members/managers to false, so the manager distinction is lost on downgrade. Register/self-update schemas reject privilege fields, and administrative schemas reject unknown roles and legacy fields. There is one source of authority: no boolean compatibility alias. The template's unauthenticated development-only `/private/users/` route was removed; test fixtures use normal signup.

`UserPublic.permissions`, including the `/users/me` response, exposes the server-computed capability list. The generated OpenAPI client types it, and the frontend's `can()` helper uses it for navigation, create buttons and user-action menus. Managers get a read-only Users table. The protected layout refreshes current capabilities into the same Query cache used by the sidebar and action controls before navigation; child route guards use that snapshot and render an explicit Access denied page on direct unauthorized navigation. API 403 responses retain the session; authentication 401 responses clear it. Login/logout clear the query cache so another account cannot inherit cached user data. UI hiding improves usability; the API remains authoritative even if a client bypasses it.

## Tests and checks

Use a separate disposable database: the inherited backend fixtures delete users and items at teardown. Do not point them at the demo database or a production database.

```sh
# From fullstack/, with the local database running. Run createdb once.
docker compose -f compose.local.yml exec -T db createdb -U postgres evios_test
TEST_DATABASE_URL=postgresql://postgres:evios-local-only@127.0.0.1:55433/evios_test make test
make check
```

`make test` migrates the chosen test database before running pytest. The focused `backend/tests/api/routes/test_rbac.py` covers allowed/denied role combinations, own profile/items, manager read-only access, privilege injection, safe signup, invalid/null roles, existing-token role changes/deactivation, anonymous access, and removal of the development bypass. Existing template backend tests remain adapted to the new role contract. Regression tests also cover invalid/null profile updates, malformed JWT subjects and item ownership for all three roles.

The existing browser admin tests use normal signup and the current role selector/Forbidden behavior. They also verify hidden admin account-deletion controls and admin → manager → member navigation within one session:

```sh
cd frontend
bunx playwright install chromium
PLAYWRIGHT_BASE_URL=http://127.0.0.1:5174 VITE_API_URL=http://127.0.0.1:8001 \
  bunx playwright test tests/admin.spec.ts --project=chromium --workers=1 --reporter=line
```

To run the complete Chromium suite, including email password recovery, also provide a local Mailpit instance. Configure the backend with `SMTP_HOST`, `SMTP_PORT`, `SMTP_TLS=False`, and `EMAILS_FROM_EMAIL`, and restart it. Set `MAILPIT_HOST` to that same Mailpit instance's HTTP URL. SMTP remains disabled in the default example configuration.

```sh
# frontend/, with the app and local Mailpit running:
PLAYWRIGHT_BASE_URL=http://127.0.0.1:5174 VITE_API_URL=http://127.0.0.1:8001 \
  MAILPIT_HOST=http://127.0.0.1:8025 \
  bunx playwright test --project=chromium --workers=1 --reporter=line
```

Keep the app and seeded demo accounts running for browser tests. They create test accounts in the demo database. `make check` runs Ruff, mypy, ty, TypeScript and the Vite production build. `make client` regenerates the OpenAPI client after API/schema changes. Generated frontend output is ignored by git.

## Scope and trade-offs

No external policy engine, dynamic role editor, global settings product, or extensive analytics system was added. Adding a role requires a backend enum/policy/schema migration and updating the role selector; frontend authorization conditions use capabilities. The existing `/admin` URL is retained as the Users route and supports managers. User-list pagination stays at the template's first 100 rows.

The assignment suggests a one-hour timebox. Actual work and verification are recorded in [verification notes](../docs/verification.md); no claim is made that unrelated prior template exploration was part of the timed implementation. Ghost work is explicitly deferred in the repository root.
