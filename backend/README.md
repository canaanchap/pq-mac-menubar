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
   - If env vars are unavailable on hosting, copy `backend/api/config/runtime.example.php` to
     `backend/api/config/runtime.php` and set values there.

## Notes
- This is a skeleton only (routing + response contract shape + schema baseline).
- Account auth and session lifecycle are implemented with MySQL persistence.
- Verification email send is not implemented yet; in dev, use `PQ_DEBUG_RETURN_VERIFY_CODE=true` to receive code in JSON.
