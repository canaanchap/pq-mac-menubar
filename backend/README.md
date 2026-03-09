# Multiplayer Backend Scaffold

This scaffold targets:
- `api.progressquest.me` -> `backend/api/public`
- `admin.progressquest.me` -> `backend/admin/public`

## API
- Health endpoint: `GET /api/v1/health`
- Realms endpoint: `GET /api/v1/realms`
- Account endpoints (implemented):
  - `POST /api/v1/account/register`
  - `POST /api/v1/account/verify`
  - `POST /api/v1/account/login`
  - `POST /api/v1/account/session`
- Admin endpoints (implemented):
  - `POST /api/v1/admin/login`
  - `POST /api/v1/admin/logout`
  - `GET /api/v1/admin/session`
  - `GET /api/v1/admin/accounts`
  - `POST /api/v1/admin/force-verify`
  - `GET /api/v1/admin/realms`
  - `POST /api/v1/admin/realms/create`
- Other routes are scaffolded and currently return `501 NOT_IMPLEMENTED`.

## Setup
1. Point web root for API vhost to `backend/api/public`.
2. Point web root for Admin vhost to `backend/admin/public`.
3. Create MySQL DB and user.
4. Apply SQL schema: `backend/api/migrations/001_init.sql`.
5. Configure env vars as needed:
   - `PQ_REALM_ID`
   - `PQ_REALM_NAME`
   - `PQ_DB_HOST`
   - `PQ_DB_PORT`
   - `PQ_DB_NAME`
   - `PQ_DB_USER`
   - `PQ_DB_PASS`
   - `PQ_DEBUG_RETURN_VERIFY_CODE` (`true` only for development/testing)
   - `PQ_ADMIN_USER`
   - `PQ_ADMIN_PASS`
   - `PQ_ADMIN_UI_ORIGIN`
   - If env vars are unavailable on hosting, copy `backend/api/config/runtime.example.php` to
     `backend/api/config/runtime.php` and set values there.
6. Re-run migration updates after pulling new schema changes:
   - `backend/api/migrations/001_init.sql` now includes `admin_sessions` and indexes.

## Admin UI
- `backend/admin/public/index.php` provides a minimal admin shell with:
  - Admin login
  - Accounts list/search
  - Force verify by email
  - Realm create/list
- API target is `https://api.progressquest.me/api/v1`.
- For browser calls from `admin.progressquest.me`, set:
  - `PQ_ADMIN_UI_ORIGIN=https://admin.progressquest.me`

## Smoke Test Harness
- Script: `backend/scripts/smoke-admin-api.sh`
- Required env vars:
  - `ADMIN_USER`
  - `ADMIN_PASS`
- Optional:
  - `API_BASE`, `TEST_EMAIL`, `TEST_PASSWORD`, `TEST_PUBLIC_NAME`
- Example:
```bash
ADMIN_USER=admin ADMIN_PASS='secret' ./backend/scripts/smoke-admin-api.sh
```

## Notes
- This is a skeleton only (routing + response contract shape + schema baseline).
- Account auth and session lifecycle are implemented with MySQL persistence.
- Verification email send is not implemented yet; in dev, use `PQ_DEBUG_RETURN_VERIFY_CODE=true` to receive code in JSON.
- Default realm seed is environment-driven and now defaults to:
  - `realm_goobland_1` / `Goobland`
