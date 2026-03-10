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

### Follow-up fixes
- Added account settings API endpoint:
  - `POST /api/v1/account/settings` (session-token scoped `wantsNews` update).
- Improved admin web login behavior:
  - login/session failure now surfaces explicit error text.
- Smoke harness now blocks placeholder credentials (`YOUR_ADMIN_USER` / `YOUR_ADMIN_PASS`) with clear failure output.
- App Multiplayer settings UX updated:
  - hide email/password login fields when already logged in.
  - show compact logged-in header: `Account: <display_name> (<email>)`.
  - keep verified indicator only inside Account Settings sheet (not main settings pane).
  - expose latest debug verification code in Validation Report section.
- Added online-character ownership protection:
  - online characters store owner account ID at creation/sign-in reconciliation.
  - mismatch warning shown and surfaced when loading/using a character under wrong account.

### Additional fixes
- Apache/PHP bearer token compatibility hardening:
  - `.htaccess` now forwards `Authorization` to PHP environment.
  - API token parser now checks `HTTP_AUTHORIZATION`, `REDIRECT_HTTP_AUTHORIZATION`, and `getallheaders()`.
- Fixed XP level-up timing:
  - leveling now triggers immediately when XP reaches threshold on the same kill resolution tick (no extra-kill delay).
- Multiplayer tab layout updates:
  - moved session info into `Connector`.
  - renamed section to `Online Multiplayer Character Sheet`.
  - added online-specific placeholder blocks for guild/governance forthcoming systems.
- Smoke harness token extraction now strips CR/LF to avoid malformed bearer header values.

## 2026-03-10

### Added
- Guild and online-character API endpoints:
  - `POST /api/v1/characters/create-online`
  - `GET /api/v1/guilds`
  - `POST /api/v1/guilds/create`
  - `POST /api/v1/guilds/join`
  - `POST /api/v1/guilds/leave`
  - `GET /api/v1/guilds/:id`
  - `GET /api/v1/guilds/:id/logs`
- New backend handler:
  - `backend/api/src/Handlers/GuildHandler.php`
- Multiplayer app-side guild wiring:
  - online character registration on demand
  - guild directory fetch
  - create/join/leave/load profile
  - guild activity log fetch
- Expanded Multiplayer tab placeholder sections for future governance and procedural systems.
- Admin panel placeholders expanded to include all planned areas (Characters, Guilds, Governance, Check-ins/Flags, Config, Scheduler).

### Changed
- `TickEngine` XP progression now levels immediately when threshold is reached in the same kill resolution tick.
- Multiplayer tab structure updated:
  - session moved under Connector
  - section renamed to `Online Multiplayer Character Sheet`
  - added guild management controls and activity feed placeholders
- Ownership guardrails reinforced:
  - server-side guild APIs enforce character/account ownership
  - app-side warning/eligibility handling for mismatched account ownership.
- Smoke harness extended to exercise online character creation + guild create/profile/logs.
