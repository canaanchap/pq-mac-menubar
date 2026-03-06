# Multiplayer Backend Scaffold

This scaffold targets:
- `api.progressquest.me` -> `backend/api/public`
- `admin.progressquest.me` -> `backend/admin/public`

## API
- Health endpoint: `GET /api/v1/health`
- Realms endpoint: `GET /api/v1/realms`
- Other routes are scaffolded and currently return `501 NOT_IMPLEMENTED`.

## Setup
1. Point web root for API vhost to `backend/api/public`.
2. Point web root for Admin vhost to `backend/admin/public`.
3. Apply SQL schema: `backend/api/migrations/001_init.sql`.
4. Configure env vars as needed:
   - `PQ_REALM_ID`
   - `PQ_REALM_NAME`

## Notes
- This is a skeleton only (routing + response contract shape + schema baseline).
- Auth, DB, and business logic handlers are intentionally not implemented yet.
