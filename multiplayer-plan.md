# Multiplayer / Realms Plan v2 (Decision-Locked)

## 1. Objective
Build multiplayer/realms for PQ Menubar with:
- all player interaction in-app (new `Multiplayer` tab),
- server connector + admin dashboard on your domain,
- character-based guild membership + governance,
- anti-cheat visibility and moderation tools.

## 2. Confirmed Hosting / Domains
- API host: `https://api.progressquest.me`
- Admin host: `https://admin.progressquest.me`
- Shared backend stack and DB for both.
- Deployment target: shared hosting-compatible (PHP + MySQL + cron).

## 3. Findings From OG PQ (`/pq`)
Legacy client already implemented online protocol concepts:
- realm list fetch + realm option flags,
- online character create (`cmd=create`),
- periodic brag/report (`cmd=b`),
- guild update (`cmd=guild`),
- lightweight signature based on passkey (`LFSR`),
- Ctrl-G guild action.

This validates your multiplayer direction and gives protocol inspiration, but we should implement a modern API/auth model.

## 4. Locked Product Decisions (from your answers)

### 4.1 Realm model
- Start with **one global realm**.
- Future realm rollout: “coming soon” + progress presentation is planned.

### 4.2 Account/auth
- v1 auth: email + password + verification code.
- v1: no password reset.

### 4.3 Character and guild scope
- One account can have multiple characters.
- App can run one active character at a time.
- Guild membership is **character-based**.

### 4.4 Governance defaults
- Presence timeout default: 24h.
- Vote duration default: 3 days.

### 4.5 Anti-cheat policy
- On suspicious check-in: accept + flag (not hard reject),
- Expose flagged items in admin dashboard triage queue.

### 4.6 Delivery priority
- Prioritize **(B) account + guild basics first** for gameplay tuning.
- Keep **(A) check-ins/anti-cheat** planned and pinned for next phase.

### 4.7 Admin surface
- v1 includes a small but broad admin dashboard:
  - accounts, characters, guilds, motions/votes, check-ins, flags, settings/timers.

## 5. Multiplayer Architecture

### 5.1 Components
- Menubar app client
- API (`api.progressquest.me`) JSON endpoints
- Admin UI (`admin.progressquest.me`) authenticated web app
- MySQL database
- Cron workers (PHP CLI) for scheduled governance and housekeeping

### 5.2 Client sync model
- For online characters only:
  - lifecycle events call API (create/join/vote/presence/etc.)
  - periodic check-ins every 10 minutes (pinned for phase after guild basics)
  - milestone check-ins on level/quest/act/save/close (same pinned phase)

## 6. Data Model (v1)

### 6.1 Character (local app)
Add immutable multiplayer fields:
- `networkMode: "offline" | "online"`
- `networkLocked: true`
- `realmId: string?`
- `accountId: string?`
- `serverCharacterId: string?`

Rules:
- Online/offline choice made at creation.
- No conversion after creation.

### 6.2 Server entities
- `accounts`
- `account_verifications`
- `realms`
- `characters`
- `guilds`
- `guild_members`
- `guild_rules`
- `guild_motions`
- `guild_votes`
- `guild_presence`
- `guild_logs`
- `character_checkins` (phase A pinned)
- `checkin_flags` (phase A pinned)

## 7. Guild + Governance Model

### 7.1 Guild creation and constraints
- creator becomes chief,
- chief max guilds: 4,
- Mudslinger’s Law enforced,
- guild name/alignment immutable once members > 0.

### 7.2 Governance settings
- `majorityType`: 50%, 60%, 66.7%, 75%
- `majorityBasis`: absolute vs present
- `quorumEnabled` + `quorumPercent`
- `noConfidenceEnabled`

### 7.3 Governance runtime
- member presence toggle (`present`) with 24h expiry,
- motion lifecycle: proposed -> discussion -> voting_open -> passed/failed -> applied,
- no-confidence flow includes nomination and succession checks.

### 7.4 Idle procedural guild logs
- data-driven term banks for parliamentary/bureaucratic flavor,
- generated entries on scheduled meeting ticks,
- visible in Multiplayer tab + admin.

## 8. API Contract (v1 baseline)

Base URL: `https://api.progressquest.me/api/v1`

### 8.1 Account
- `POST /account/register`
- `POST /account/verify`
- `POST /account/login`

### 8.2 Character / realm
- `POST /characters/create-online`
- `GET /realms` (single realm initially)

### 8.3 Guild
- `POST /guilds/create`
- `POST /guilds/join`
- `POST /guilds/leave`
- `GET /guilds/:id`

### 8.4 Governance
- `POST /guilds/:id/motions/create`
- `POST /guilds/:id/motions/:motionId/vote`
- `POST /guilds/:id/presence`
- `GET /guilds/:id/motions`

### 8.5 Check-ins (pinned phase)
- `POST /characters/:id/checkin`
- `GET /characters/:id/checkin-status`

## 9. Menubar App UX Plan

### 9.1 Character creation updates
- Add `Online Multiplayer` toggle (immutable decision warning).
- If online selected:
  - require login/verify,
  - require realm selection,
  - create online character server-side.

### 9.2 New `Multiplayer` tab
Sections:
- Account
- Realm
- Guild
- Governance
- Guild logs

### 9.3 Notifications
Toasts for:
- account verification status,
- guild join/create outcomes,
- vote outcomes,
- flagged check-in status (when phase A lands).

## 10. Admin Dashboard (`admin.progressquest.me`)

### 10.1 Required tabs (v1)
- Accounts
- Characters
- Guilds
- Governance (motions/votes/presence)
- Check-ins / Flags (initial shell if phase A not enabled yet)
- Config / Data dictionaries
- Scheduler / Timers

### 10.2 Admin controls
- inspect and edit account/public-name state,
- inspect guild membership and governance config,
- inspect and resolve flagged check-ins,
- tune timing defaults (vote duration, presence expiry),
- manage data-driven dictionaries (alignments, guild types, procedure terms).

## 11. Anti-Cheat Strategy

### 11.1 Phase A (pinned next)
- 10-minute check-ins + milestone check-ins,
- conservative progression envelope,
- accept + flag on anomalies,
- admin queue for review.

### 11.2 Phase B (later)
- deterministic replay verification against seed/checkpoint hash.

## 12. Phased Implementation Roadmap

### Phase 0 (schema + UX shell)
- Add immutable online character fields in app.
- Add Multiplayer tab shell.
- Add API client scaffolding.

### Phase 1 (B-priority: account + guild basics)
- account register/verify/login,
- one global realm selection,
- online character creation,
- guild create/join/profile,
- chief/membership rule enforcement.

### Phase 2 (governance v1)
- motions, votes, majority/quorum/no-confidence,
- presence toggle + expiry,
- procedural guild logs.

### Phase 3 (A pinned: check-ins + anti-cheat envelope)
- periodic + milestone check-ins,
- flagging pipeline + admin triage queue.

### Phase 4 (hardening)
- deterministic verification (optional later),
- moderation/reporting polish.

## 13. Risks / Mitigations
- Shared hosting cron limits: keep workers idempotent and short.
- Governance complexity: ship narrow defaults first.
- Irreversible online mode confusion: explicit creation warning + confirmation.
- No password reset in v1: clearly communicate in registration UI.

## 14. Implementation Notes for Next Draft
When you’re ready to start coding, next doc revision should add:
- exact request/response JSON schemas,
- DB table DDL,
- app-side persistence keys and migration plan,
- multiplayer tab wireframes/states,
- error taxonomy and retry policy.

## 15. API Request/Response Schemas (v1 Draft)

Base URL: `https://api.progressquest.me/api/v1`

Conventions:
- `Content-Type: application/json`
- Success envelope:
```json
{
  "ok": true,
  "data": { }
}
```
- Error envelope:
```json
{
  "ok": false,
  "error": {
    "code": "STRING_CODE",
    "message": "Human readable message",
    "details": { }
  }
}
```

### 15.1 `POST /account/register`
Request:
```json
{
  "email": "user@example.com",
  "password": "plain_password_for_v1_over_tls",
  "wantsNews": true,
  "publicName": "Display Name"
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "accountId": "acc_01J...",
    "verificationRequired": true,
    "verificationDelivery": "email"
  }
}
```

### 15.2 `POST /account/verify`
Request:
```json
{
  "email": "user@example.com",
  "code": "123456"
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "accountId": "acc_01J...",
    "verified": true
  }
}
```

### 15.3 `POST /account/login`
Request:
```json
{
  "email": "user@example.com",
  "password": "plain_password_for_v1_over_tls"
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "accountId": "acc_01J...",
    "sessionToken": "sess_...",
    "publicName": "Display Name",
    "verified": true,
    "expiresAt": "2026-03-07T00:00:00Z"
  }
}
```

### 15.4 `GET /realms`
Response:
```json
{
  "ok": true,
  "data": {
    "realms": [
      {
        "realmId": "realm_global_1",
        "name": "<your realm name>",
        "status": "active",
        "supportsGuilds": true
      }
    ]
  }
}
```

### 15.5 `POST /characters/create-online`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "realmId": "realm_global_1",
  "character": {
    "characterId": "local-uuid",
    "name": "Whizcraed",
    "race": "Low Elf",
    "characterClass": "Mage Illusioner",
    "networkMode": "online",
    "networkLocked": true,
    "seed": "optional_seed_or_rng_state"
  }
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "serverCharacterId": "char_01J...",
    "realmId": "realm_global_1",
    "createdAt": "2026-03-07T00:00:00Z"
  }
}
```

### 15.6 `POST /guilds/create`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "serverCharacterId": "char_01J...",
  "realmId": "realm_global_1",
  "guild": {
    "formalName": "Parliament of Heroic Paperwork",
    "shortTag": "PHP",
    "alignmentCode": "neutral",
    "typeCode": "guild",
    "motto": "By memo and by sword"
  },
  "rules": {
    "majorityType": "three_fifths_60",
    "majorityBasis": "present",
    "quorumEnabled": true,
    "quorumPercent": 40,
    "noConfidenceEnabled": true
  }
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "guildId": "gld_01J...",
    "chiefCharacterId": "char_01J..."
  }
}
```

### 15.7 `POST /guilds/join`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "serverCharacterId": "char_01J...",
  "guildId": "gld_01J..."
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "guildId": "gld_01J...",
    "memberState": "active"
  }
}
```

### 15.8 `POST /guilds/leave`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "serverCharacterId": "char_01J...",
  "guildId": "gld_01J..."
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "guildId": "gld_01J...",
    "memberState": "left"
  }
}
```

### 15.9 `GET /guilds/:id`
Response:
```json
{
  "ok": true,
  "data": {
    "guild": {
      "guildId": "gld_01J...",
      "formalName": "Parliament of Heroic Paperwork",
      "shortTag": "PHP",
      "alignmentCode": "neutral",
      "typeCode": "guild",
      "motto": "By memo and by sword",
      "chiefCharacterId": "char_01J...",
      "memberCount": 12,
      "rules": {
        "majorityType": "three_fifths_60",
        "majorityBasis": "present",
        "quorumEnabled": true,
        "quorumPercent": 40,
        "noConfidenceEnabled": true
      }
    },
    "members": [
      {
        "serverCharacterId": "char_...",
        "characterName": "Whizcraed",
        "present": true,
        "lastPresentAt": "2026-03-07T00:00:00Z"
      }
    ]
  }
}
```

### 15.10 `POST /guilds/:id/motions/create`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "proposerCharacterId": "char_01J...",
  "motionType": "rule_change",
  "title": "Raise quorum to 50%",
  "payload": {
    "quorumPercent": 50
  },
  "votingWindowHours": 72
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "motionId": "mot_01J...",
    "state": "voting_open",
    "closesAt": "2026-03-10T00:00:00Z"
  }
}
```

### 15.11 `POST /guilds/:id/motions/:motionId/vote`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "voterCharacterId": "char_01J...",
  "choice": "yes"
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "motionId": "mot_01J...",
    "totals": {
      "yes": 7,
      "no": 2,
      "abstain": 1
    }
  }
}
```

### 15.12 `POST /guilds/:id/presence`
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "serverCharacterId": "char_01J...",
  "present": true
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "present": true,
    "expiresAt": "2026-03-08T00:00:00Z"
  }
}
```

### 15.13 `POST /characters/:id/checkin` (Phase A pinned)
Headers:
- `Authorization: Bearer <sessionToken>`

Request:
```json
{
  "checkpointId": "chk_01J...",
  "sentAt": "2026-03-07T00:00:00Z",
  "runtimeSecondsDelta": 600,
  "snapshot": {
    "level": 12,
    "xpPosition": 1234,
    "xpMax": 14400,
    "act": 3,
    "questCount": 42,
    "gold": 12345,
    "inventoryCount": 19,
    "stateHash": "sha256:..."
  }
}
```
Response:
```json
{
  "ok": true,
  "data": {
    "accepted": true,
    "riskState": "yellow",
    "flagged": true,
    "flagReason": "xp_delta_over_envelope"
  }
}
```

## 16. MySQL DDL (v1 Draft)

```sql
CREATE TABLE accounts (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  account_uid CHAR(26) NOT NULL UNIQUE,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  verified TINYINT(1) NOT NULL DEFAULT 0,
  public_name VARCHAR(80) DEFAULT NULL,
  wants_news TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

CREATE TABLE account_verifications (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  account_id BIGINT UNSIGNED NOT NULL,
  code_hash VARCHAR(255) NOT NULL,
  expires_at DATETIME NOT NULL,
  used_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE account_sessions (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  account_id BIGINT UNSIGNED NOT NULL,
  session_token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE realms (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  realm_uid VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  status ENUM('active','coming_soon','disabled') NOT NULL DEFAULT 'active',
  supports_guilds TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

CREATE TABLE characters (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  character_uid CHAR(26) NOT NULL UNIQUE,
  account_id BIGINT UNSIGNED NOT NULL,
  realm_id BIGINT UNSIGNED NOT NULL,
  local_character_uuid CHAR(36) DEFAULT NULL,
  name VARCHAR(120) NOT NULL,
  race VARCHAR(80) NOT NULL,
  class_name VARCHAR(80) NOT NULL,
  network_mode ENUM('online') NOT NULL DEFAULT 'online',
  seed VARCHAR(128) DEFAULT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id),
  FOREIGN KEY (realm_id) REFERENCES realms(id)
);

CREATE TABLE guilds (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_uid CHAR(26) NOT NULL UNIQUE,
  realm_id BIGINT UNSIGNED NOT NULL,
  formal_name VARCHAR(160) NOT NULL,
  short_tag VARCHAR(24) NOT NULL,
  alignment_code VARCHAR(40) NOT NULL,
  type_code VARCHAR(40) NOT NULL,
  motto VARCHAR(255) DEFAULT NULL,
  chief_character_id BIGINT UNSIGNED NOT NULL,
  immutable_on_membership TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (realm_id) REFERENCES realms(id),
  FOREIGN KEY (chief_character_id) REFERENCES characters(id),
  UNIQUE KEY uq_guild_name_realm (realm_id, formal_name),
  UNIQUE KEY uq_guild_tag_realm (realm_id, short_tag)
);

CREATE TABLE guild_rules (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL UNIQUE,
  majority_type ENUM('functional_50','three_fifths_60','two_thirds_66_7','three_fourths_75') NOT NULL,
  majority_basis ENUM('absolute','present') NOT NULL,
  quorum_enabled TINYINT(1) NOT NULL DEFAULT 0,
  quorum_percent TINYINT UNSIGNED DEFAULT NULL,
  no_confidence_enabled TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id)
);

CREATE TABLE guild_members (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL,
  character_id BIGINT UNSIGNED NOT NULL,
  role ENUM('chief','member') NOT NULL DEFAULT 'member',
  status ENUM('active','left','kicked') NOT NULL DEFAULT 'active',
  joined_at DATETIME NOT NULL,
  left_at DATETIME DEFAULT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id),
  FOREIGN KEY (character_id) REFERENCES characters(id),
  UNIQUE KEY uq_guild_character (guild_id, character_id)
);

CREATE TABLE guild_presence (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL,
  character_id BIGINT UNSIGNED NOT NULL,
  present TINYINT(1) NOT NULL,
  updated_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id),
  FOREIGN KEY (character_id) REFERENCES characters(id),
  UNIQUE KEY uq_presence (guild_id, character_id)
);

CREATE TABLE guild_motions (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  motion_uid CHAR(26) NOT NULL UNIQUE,
  guild_id BIGINT UNSIGNED NOT NULL,
  proposer_character_id BIGINT UNSIGNED NOT NULL,
  motion_type VARCHAR(64) NOT NULL,
  title VARCHAR(200) NOT NULL,
  payload_json JSON DEFAULT NULL,
  state ENUM('proposed','discussion','voting_open','passed','failed','applied') NOT NULL,
  opens_at DATETIME NOT NULL,
  closes_at DATETIME NOT NULL,
  result_applied_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id),
  FOREIGN KEY (proposer_character_id) REFERENCES characters(id)
);

CREATE TABLE guild_votes (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  motion_id BIGINT UNSIGNED NOT NULL,
  voter_character_id BIGINT UNSIGNED NOT NULL,
  choice ENUM('yes','no','abstain') NOT NULL,
  voted_at DATETIME NOT NULL,
  FOREIGN KEY (motion_id) REFERENCES guild_motions(id),
  FOREIGN KEY (voter_character_id) REFERENCES characters(id),
  UNIQUE KEY uq_motion_voter (motion_id, voter_character_id)
);

CREATE TABLE guild_logs (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL,
  log_type ENUM('system','governance','procedural') NOT NULL,
  message TEXT NOT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id)
);

CREATE TABLE character_checkins (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  checkin_uid CHAR(26) NOT NULL UNIQUE,
  character_id BIGINT UNSIGNED NOT NULL,
  sent_at DATETIME NOT NULL,
  runtime_seconds_delta INT UNSIGNED NOT NULL,
  snapshot_json JSON NOT NULL,
  accepted TINYINT(1) NOT NULL,
  risk_state ENUM('green','yellow','red') NOT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id)
);

CREATE TABLE checkin_flags (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  checkin_id BIGINT UNSIGNED NOT NULL,
  flag_code VARCHAR(80) NOT NULL,
  severity ENUM('low','medium','high') NOT NULL,
  reviewed TINYINT(1) NOT NULL DEFAULT 0,
  review_note TEXT DEFAULT NULL,
  created_at DATETIME NOT NULL,
  reviewed_at DATETIME DEFAULT NULL,
  FOREIGN KEY (checkin_id) REFERENCES character_checkins(id)
);
```

## 17. App-Side Data Structures and Migration

### 17.1 New local files
- `~/.pq-menubar/network/account.json`
- `~/.pq-menubar/network/session.json`
- `~/.pq-menubar/network/checkpoint-queue.jsonl`
- `~/.pq-menubar/network/guild-cache.json`
- `~/.pq-menubar/network/realm-cache.json`

### 17.2 Character model extensions (local save)
Add fields to character save JSON:
```json
{
  "networkMode": "offline",
  "networkLocked": false,
  "realmId": null,
  "accountId": null,
  "serverCharacterId": null,
  "lastCheckinAt": null,
  "lastAcceptedCheckpointId": null,
  "cheatRiskState": null
}
```

For online character created in v1:
```json
{
  "networkMode": "online",
  "networkLocked": true,
  "realmId": "realm_global_1",
  "accountId": "acc_01J...",
  "serverCharacterId": "char_01J..."
}
```

### 17.3 Migration behavior
- Existing characters default to:
  - `networkMode = offline`
  - `networkLocked = false`
- On first save after migration, fields are materialized.
- No auto-conversion to online.

### 17.4 Immutable-mode enforcement
- Creation UI sets mode.
- If `networkLocked = true`, block mode edits in all settings screens.
- API client rejects attempts to call online endpoints for offline chars.

### 17.5 Retry / queue behavior (for pinned check-in phase)
- Failed check-ins appended to `checkpoint-queue.jsonl`.
- Background flusher retries with exponential backoff.
- Queue is per online character; preserve order.

## 18. Error Taxonomy and Retry Policy

### 18.1 API error codes
- `AUTH_INVALID_CREDENTIALS`
- `AUTH_NOT_VERIFIED`
- `AUTH_SESSION_EXPIRED`
- `REALM_NOT_FOUND`
- `CHARACTER_MODE_LOCKED`
- `CHARACTER_NAME_CONFLICT`
- `GUILD_RULE_VIOLATION`
- `GUILD_MUDSLINGER_VIOLATION`
- `GOVERNANCE_INVALID_MOTION`
- `CHECKIN_ENVELOPE_EXCEEDED`
- `CHECKIN_REPLAY_DETECTED`
- `RATE_LIMITED`
- `INTERNAL_ERROR`

### 18.2 Client behavior by class
- 4xx auth/business errors: no retry; show actionable message.
- 409 conflicts: reload relevant resource and prompt user.
- 429/5xx/network timeout: retry with backoff.

### 18.3 Retry defaults
- initial delay: 3s
- backoff: x2
- max delay: 5m
- max attempts per item: 12
- then keep queued + surface warning in Multiplayer tab.

## 19. Open Implementation Assumptions

1. v1 passwords are sent to API over TLS and hashed server-side (Argon2id/Bcrypt).
2. `sessionToken` is opaque random and stored hashed in DB.
3. Email verification code length: 6 digits, 15-minute expiry.
4. Presence expiration worker runs every 15 minutes via cron.
5. Motion state transition worker runs every 5 minutes via cron.

If any of these differ from your hosting constraints, adjust before coding starts.
