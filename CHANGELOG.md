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

### Added
- Multiplayer guild config system (server-managed dictionaries):
  - `GET /api/v1/guilds/config`
  - `GET/POST /api/v1/admin/config/alignment*`
  - `GET/POST /api/v1/admin/config/type*`
- Character-to-guild status API:
  - `POST /api/v1/characters/guild-status`
- Guild abandonment workflow:
  - chief-only leave when sole member now transitions guild to `pending_abandonment`
  - admin approval endpoints:
    - `GET /api/v1/admin/guilds/pending-abandonment`
    - `POST /api/v1/admin/guilds/approve-abandonment`
- Guild create now accepts governance fields:
  - `majorityType`, `majorityBasis`, `quorumEnabled`, `quorumPercent`, `noConfidenceEnabled`

### Changed
- API bootstrap now auto-ensures multiplayer config tables/columns and default dictionary seeds.
- Guild list/join now enforces guild status (`active` only).
- Guild profile payload now includes:
  - `status`, abandonment timestamps, and full governance rule snapshot.
- Admin panel now includes:
  - alignment/type dictionary editing
  - pending-abandonment queue + approve action
- App Multiplayer tab reworked:
  - `Guildhall` section with auto profile load from selected guild.
  - character-scoped guild lookup to prevent stale cross-character guild display.
  - governance fields wired into guild creation UI + API call.
  - added placeholder idle guild progress section and beta toggles for governance/procedural panels.
- Smoke harness expanded to include:
  - guild config endpoint
  - character guild-status
  - chief abandonment request + admin approval flow

### Added
- Admin API listing endpoints:
  - `GET /api/v1/admin/characters`
  - `GET /api/v1/admin/guilds`
- Admin API dictionary management endpoints:
  - `POST /api/v1/admin/config/alignment/create|toggle|delete`
  - `POST /api/v1/admin/config/type/create|toggle|delete`

### Changed
- Admin dashboard UI redesigned for direct operations and cross-linking:
  - Accounts rows now provide `Characters` and `Force Verify` actions.
  - Characters rows can jump to owner/account workflows.
  - Guild rows can jump to alignment/type config sections.
  - Alignment/type config now uses simple add + activate/deactivate + delete flows (server-managed sort).
  - Pending-abandonment approval actions available inline.
- Multiplayer tab layout update:
  - `Guild Activity + Progress` moved to top and merged.
  - Added multiplayer sync progress bar and realm-rank window (3 above / current / 3 below placeholder model).
  - Moved realm/server/tracking details into `Connector`.
  - Consolidated guild controls into `Guildhall`.
  - Renamed guild create action to `Petition to Create Guild`.
  - Create controls now hidden when current character already has a loaded guild.
- Task progress reset behavior:
  - main Overview task bar and mini menubar task bar now animate upward but snap directly to `0` on wrap (no backward tween).

### Performance
- Runtime tick safety improvements:
  - clamped per-tick elapsed time to prevent large sleep/wake catch-up bursts from doing heavy work in one tick.
  - capped in-memory runtime event buffer to avoid unbounded growth over long sessions.
- Overview `Plot Development` rendering now caps completed-act rows to a recent window instead of rendering the full historical act list.
- Dashboard tab render throttling:
  - non-selected tabs now render a lightweight placeholder so hidden tabs do not keep expensive SwiftUI trees active.
  - reduces background layout/observation churn from hidden `Multiplayer`, `Character + Log`, and `Settings` content.
- Portrait decode optimization:
  - portrait image is now cached when `portraitImageURL` changes.
  - removed repeated disk decode (`NSImage(contentsOf:)`) during view body recomputation.
- UI publish throttling:
  - simulation still ticks at runtime cadence, but AppState only publishes UI state at a controlled interval unless a milestone transition occurs.
  - milestone transitions (pause/start, task wrap/change, quest/act/level changes, character switch) still publish immediately.
- Roster publish throttling:
  - active character updates no longer republish the entire roster every simulation tick.
  - roster now republishes on milestones or at a bounded interval to avoid persistent SwiftUI invalidation pressure.
- Runtime cadence tuning:
  - normal tick scheduler reduced from `0.1s` to `0.25s` (and low CPU from `0.5s` to `1.0s`), while simulation progression remains elapsed-time based.
  - paused runtime now short-circuits tick work.
- Overview list render optimization:
  - replaced per-update list auto-scroll behavior with one-time scroll-to-bottom when Overview becomes active.
  - kept bounded recent slices for `Plot Development`, `Inventory`, and `Quests` to reduce layout churn.
- Dashboard visibility-aware UI throttling:
  - when the full Dashboard window is not visible, AppState now publishes UI snapshots at a slower interval.
  - keeps background simulation intact while reducing render pressure from hidden/non-focused UI.
- Overview text rendering optimization:
  - removed global `.textSelection(.enabled)` from the frequently updating Overview tree to reduce selection/layout overhead.
