# Changelog

## 2026-03-06

### Added
- Multiplayer backend scaffold with MySQL schema and route skeleton under `backend/api` and `backend/admin`.
- Implemented API account endpoints:
  - `POST /api/v1/account/register`
  - `POST /api/v1/account/verify`
  - `POST /api/v1/account/login`
  - `POST /api/v1/account/session`
- Added DreamHost/shared-hosting runtime config fallback:
  - `backend/api/config/runtime.example.php`
  - `backend/api/src/bootstrap.php` now loads `config/runtime.php` if present.

### Changed
- Menubar app Multiplayer account flow now supports live API calls for register/verify/login/session checks.
- Character creation now supports immutable online/offline multiplayer mode in both menu and dashboard flows.
- Multiplayer tab visibility now depends on character mode (online-only).
- Settings tab reorganized:
  - `Character Roster` and `Gameplay` side-by-side.
  - Scrollable roster list with selection state.
  - Added gray globe indicator for online characters.
  - Added delete confirmation for selected character.
  - Reordered gameplay controls and display toggles.
- Menubar label behavior:
  - Added `Show Character's Name Instead?` toggle.
  - Name toggle can override level label behavior.

### Fixed
- Verified status no longer appears as active when user is not logged in.
- Account Settings button is disabled when no account exists.
- API route handling supports both `/public` and root-style deployments for `index.php`.

### Notes
- Multiplayer account `wantsNews` toggle is still local-only until server-side account settings update endpoint is implemented.

## 2026-03-09

### Added
- API admin handlers and routes:
  - `POST /api/v1/admin/login`
  - `POST /api/v1/admin/logout`
  - `GET /api/v1/admin/session`
  - `GET /api/v1/admin/accounts`
  - `POST /api/v1/admin/force-verify`
  - `GET /api/v1/admin/realms`
  - `POST /api/v1/admin/realms/create`
- Minimal admin dashboard shell for `admin.progressquest.me`:
  - login
  - accounts list/search
  - force verify by email
  - realm create/list
- Smoke test harness script:
  - `backend/scripts/smoke-admin-api.sh`

### Changed
- `GET /api/v1/realms` now reads from DB and auto-seeds default realm from env values.
- Default realm config switched to `realm_goobland_1` / `Goobland`.
- Runtime config templates now include admin credentials and allowed admin UI origin.
- Added CORS handling in API entrypoint for admin UI browser requests.

### Database
- Migration updated with:
  - `admin_sessions` table
  - index: `accounts(email, verified)`
  - index: `guild_members(guild_id, status)`
  - index: `guild_logs(guild_id, created_at)`
