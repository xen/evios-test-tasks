# Verification — 2026-10-19

Latest acceptance audit and fixes: [2026-10-19 audit](acceptance-audit-2026-10-19.md). The results below preserve the original implementation run; the audit contains the current 88 backend / 66 full-suite browser checks.

Scope: first assignment, role-aware Fullstack FastAPI application. Ghost is deferred at the user's request; the designated VPS was inspected read-only and was not modified.

Detailed implementation plan and acceptance criteria: [Russian specification](specs/2026-10-19-evios.md).

## Automated checks actually run

| Check | Result |
| --- | --- |
| Untouched template CRUD baseline | 10 passed |
| Full backend pytest suite on isolated `evios_test`, clean-checkout configuration | 76 passed in 5.93 s |
| Existing Playwright admin suite, Chromium, one worker | 13 passed in 14.4 s, including authentication setup |
| Ruff checks and formatting | Passed |
| mypy, 21 application source files | Passed |
| ty application checks | Passed |
| TypeScript and Vite production build | Passed |
| OpenAPI client regeneration | Passed, no tracked client drift |
| Repeat `make install` and `make seed` | Passed |
| Fresh local Git clone, lockfile installation and complete `make check` | Passed; no pre-existing dependencies or generated frontend |
| Source whitespace / patch checks | `git diff --check` passed |

The clean-checkout run exposed an inherited recovery-email test relying on local sender configuration. Email calls in recovery/user-creation tests now mock the route-local sender and assert the destination, so no SMTP service is needed. All 76 backend tests passed with the documented example configuration.

Backend tests report one upstream Starlette TestClient deprecation warning about httpx. No test was skipped to obtain the result. The full unrelated frontend suite and an external production deployment of this application were not run.

Commands are documented in [the application README](../fullstack/README.md). Tests ran against a separate database; demo data was preserved.

## Migration and removed route

On a separate `evios_migration` database, applied the upstream schema through `fe56fa70289e`, inserted an existing administrator (`is_superuser=true`) and member (`false`), and applied the new migration. Results were `admin` and `member`. A direct SQL update to an unknown role failed the database CHECK. Downgrade recovered true/false, and a second upgrade succeeded.

Both GET and POST to `/api/v1/private/users/` returned **404**, `application/json`, with no `Location`, under the production application with built frontend enabled. The removed endpoint is also covered by the development API test. No catch-all compatibility endpoint was introduced.

## Browser checks actually observed

- Admin: Users table, Add User, role badges and user actions. Existing browser tests created an admin and member, edited a user, deleted a user and checked form validation.
- Manager: Users and Metrics navigation visible; user table visible with no create/edit/delete controls; Metrics returned actual totals (7 users, 0 items at capture time).
- Member: Users/Metrics navigation hidden; direct `/admin` and `/metrics` display Access denied and remain on the requested route. The user remains signed in and can open personal Settings.
- Login/logout was performed between roles in the same browser session.
- Mobile viewport 390 × 844: denial message and action remained readable; personal Settings remained accessible.

Screenshots contain only local demo accounts. They are supporting evidence of the recorded run, not a claim about a deployed production instance.

| Evidence | Screenshot |
| --- | --- |
| Untouched dashboard baseline | [baseline-dashboard.png](screenshots/baseline-dashboard.png) |
| Admin user-management controls | [admin-users.png](screenshots/admin-users.png) |
| Manager read-only user list | [manager-users.png](screenshots/manager-users.png) |
| Manager metrics | [manager-metrics.png](screenshots/manager-metrics.png) |
| Member denied metrics | [member-metrics-denied.png](screenshots/member-metrics-denied.png) |
| Member denied Users route | [member-users-denied.png](screenshots/member-users-denied.png) |
| Mobile denial | [member-mobile-denied.png](screenshots/member-mobile-denied.png) |
| Mobile own profile | [member-profile-mobile.png](screenshots/member-profile-mobile.png) |

## Submission boundaries

The source baseline and implementation are separate commits. The source template's MIT licence remains in `fullstack/LICENSE`. Real `.env` files, database contents, browser auth state and credentials are excluded. Only the explicitly marked demo credentials in `.env.example` are included.

The visible AI dialogue is exported in [conversation.md](../ai/conversation.md) and structured [messages.json](../ai/messages.json), through the export timestamp. Internal instructions, tool payloads, private reasoning and unrelated historical conversations are excluded. The exporter is included for reproducibility.

Repository: [xen/evios-test-tasks](https://github.com/xen/evios-test-tasks). GitHub visibility was checked as PRIVATE. No reviewer was invited and no application was submitted.
