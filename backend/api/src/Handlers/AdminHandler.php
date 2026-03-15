<?php
declare(strict_types=1);

final class AdminHandler {
    public static function login(array $body): array {
        $username = trim((string)($body['username'] ?? ''));
        $password = (string)($body['password'] ?? '');
        $configuredUser = env_value('PQ_ADMIN_USER', 'admin');
        $configuredPass = env_value('PQ_ADMIN_PASS', '');

        if ($configuredPass === '') {
            return json_error('ADMIN_NOT_CONFIGURED', 'Admin credentials are not configured on server.', [], 500);
        }
        if (!hash_equals($configuredUser, $username) || !hash_equals($configuredPass, $password)) {
            return json_error('ADMIN_LOGIN_INVALID', 'Invalid admin credentials.', [], 401);
        }

        $now = now_utc();
        $expiresAt = gmdate('Y-m-d H:i:s', time() + 60 * 60 * 8);
        $raw = secure_token(32);

        $pdo = db();
        $insert = $pdo->prepare('
            INSERT INTO admin_sessions (username, session_token_hash, expires_at, revoked_at, created_at)
            VALUES (?, ?, ?, NULL, ?)
        ');
        $insert->execute([$configuredUser, token_hash($raw), $expiresAt, $now]);

        return [
            'status' => 200,
            'body' => json_success([
                'token' => $raw,
                'expiresAt' => gmdate('c', strtotime($expiresAt)),
                'username' => $configuredUser,
            ]),
        ];
    }

    public static function logout(): array {
        $token = bearer_token_from_request();
        if ($token === null || $token === '') {
            return json_error('ADMIN_AUTH_REQUIRED', 'Missing admin bearer token.', [], 401);
        }
        $pdo = db();
        $stmt = $pdo->prepare('UPDATE admin_sessions SET revoked_at = ? WHERE session_token_hash = ? AND revoked_at IS NULL');
        $stmt->execute([now_utc(), token_hash($token)]);
        return ['status' => 200, 'body' => json_success(['loggedOut' => true])];
    }

    public static function session(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $token = bearer_token_from_request();
        $pdo = db();
        $stmt = $pdo->prepare('
            SELECT username, expires_at
            FROM admin_sessions
            WHERE session_token_hash = ? AND revoked_at IS NULL
            LIMIT 1
        ');
        $stmt->execute([token_hash((string)$token)]);
        $row = $stmt->fetch();
        if (!$row) {
            return json_error('ADMIN_SESSION_NOT_FOUND', 'Admin session not found.', [], 401);
        }
        return [
            'status' => 200,
            'body' => json_success([
                'username' => (string)$row['username'],
                'expiresAt' => gmdate('c', strtotime((string)$row['expires_at'])),
            ]),
        ];
    }

    public static function accounts(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }

        $q = trim((string)($_GET['q'] ?? ''));
        $limit = (int)($_GET['limit'] ?? 100);
        $limit = max(1, min(500, $limit));

        $pdo = db();
        if ($q !== '') {
            $like = '%' . $q . '%';
            $stmt = $pdo->prepare('
                SELECT account_uid, email, public_name, wants_news, verified, created_at, updated_at
                FROM accounts
                WHERE email LIKE ? OR public_name LIKE ?
                ORDER BY created_at DESC
                LIMIT ' . $limit
            );
            $stmt->execute([$like, $like]);
        } else {
            $stmt = $pdo->query('
                SELECT account_uid, email, public_name, wants_news, verified, created_at, updated_at
                FROM accounts
                ORDER BY created_at DESC
                LIMIT ' . $limit
            );
        }
        $rows = $stmt->fetchAll() ?: [];
        $accounts = array_map(static function (array $row): array {
            return [
                'accountId' => (string)$row['account_uid'],
                'email' => (string)$row['email'],
                'publicName' => (string)$row['public_name'],
                'wantsNews' => ((int)$row['wants_news']) === 1,
                'verified' => ((int)$row['verified']) === 1,
                'createdAt' => gmdate('c', strtotime((string)$row['created_at'])),
                'updatedAt' => gmdate('c', strtotime((string)$row['updated_at'])),
            ];
        }, $rows);

        return ['status' => 200, 'body' => json_success(['accounts' => $accounts])];
    }

    public static function forceVerify(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }

        $email = strtolower(trim((string)($body['email'] ?? '')));
        $accountId = trim((string)($body['accountId'] ?? ''));
        if ($email === '' && $accountId === '') {
            return json_error('VALIDATION_TARGET_REQUIRED', 'Provide email or accountId.', [], 422);
        }

        $pdo = db();
        $now = now_utc();
        if ($email !== '') {
            $stmt = $pdo->prepare('UPDATE accounts SET verified = 1, updated_at = ? WHERE email = ?');
            $stmt->execute([$now, $email]);
        } else {
            $stmt = $pdo->prepare('UPDATE accounts SET verified = 1, updated_at = ? WHERE account_uid = ?');
            $stmt->execute([$now, $accountId]);
        }

        if ($stmt->rowCount() < 1) {
            return json_error('ACCOUNT_NOT_FOUND', 'No matching account found.', [], 404);
        }
        return ['status' => 200, 'body' => json_success(['verified' => true])];
    }

    public static function realmsList(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        ensure_default_realm_seeded();

        $pdo = db();
        $stmt = $pdo->query('
            SELECT realm_uid, name, status, supports_guilds, created_at, updated_at
            FROM realms
            ORDER BY created_at ASC
        ');
        $rows = $stmt->fetchAll() ?: [];
        $realms = array_map(static function (array $row): array {
            return [
                'realmId' => (string)$row['realm_uid'],
                'name' => (string)$row['name'],
                'status' => (string)$row['status'],
                'supportsGuilds' => ((int)$row['supports_guilds']) === 1,
                'createdAt' => gmdate('c', strtotime((string)$row['created_at'])),
                'updatedAt' => gmdate('c', strtotime((string)$row['updated_at'])),
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['realms' => $realms])];
    }

    public static function realmsCreate(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }

        $realmId = trim((string)($body['realmId'] ?? ''));
        $name = trim((string)($body['name'] ?? ''));
        $status = trim((string)($body['status'] ?? 'active'));
        $supportsGuilds = (bool)($body['supportsGuilds'] ?? true);
        if ($realmId === '' || $name === '') {
            return json_error('VALIDATION_REALM_FIELDS', 'realmId and name are required.', [], 422);
        }
        if (!in_array($status, ['active', 'coming_soon', 'disabled'], true)) {
            return json_error('VALIDATION_REALM_STATUS', 'Invalid realm status.', [], 422);
        }

        $pdo = db();
        $now = now_utc();
        try {
            $stmt = $pdo->prepare('
                INSERT INTO realms (realm_uid, name, status, supports_guilds, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            ');
            $stmt->execute([$realmId, $name, $status, $supportsGuilds ? 1 : 0, $now, $now]);
        } catch (Throwable $e) {
            return json_error('REALM_CREATE_FAILED', 'Failed to create realm.', ['reason' => $e->getMessage()], 409);
        }
        return ['status' => 201, 'body' => json_success(['realmId' => $realmId, 'name' => $name])];
    }

    public static function alignmentList(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $pdo = db();
        $stmt = $pdo->query('
            SELECT code, display_name, alignment_value, include_flag, sort_order, created_at, updated_at
            FROM guild_alignment_options
            ORDER BY sort_order ASC, display_name ASC
        ');
        $rows = $stmt->fetchAll() ?: [];
        $items = array_map(static function (array $row): array {
            return [
                'code' => (string)$row['code'],
                'displayName' => (string)$row['display_name'],
                'alignmentValue' => (int)$row['alignment_value'],
                'include' => ((int)$row['include_flag']) === 1,
                'sortOrder' => (int)$row['sort_order'],
                'createdAt' => gmdate('c', strtotime((string)$row['created_at'])),
                'updatedAt' => gmdate('c', strtotime((string)$row['updated_at'])),
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['alignments' => $items])];
    }

    public static function alignmentUpsert(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        $displayName = trim((string)($body['displayName'] ?? ''));
        $alignmentValue = (int)($body['alignmentValue'] ?? 0);
        $include = (bool)($body['include'] ?? true);
        $sortOrder = (int)($body['sortOrder'] ?? 0);
        if ($code === '' || $displayName === '') {
            return json_error('VALIDATION_ALIGNMENT_FIELDS', 'code and displayName are required.', [], 422);
        }
        $pdo = db();
        $now = now_utc();
        $stmt = $pdo->prepare('
            INSERT INTO guild_alignment_options (code, display_name, alignment_value, include_flag, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
              display_name = VALUES(display_name),
              alignment_value = VALUES(alignment_value),
              include_flag = VALUES(include_flag),
              sort_order = VALUES(sort_order),
              updated_at = VALUES(updated_at)
        ');
        $stmt->execute([$code, $displayName, $alignmentValue, $include ? 1 : 0, $sortOrder, $now, $now]);
        return ['status' => 200, 'body' => json_success(['updated' => true, 'code' => $code])];
    }

    public static function alignmentCreate(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        $displayName = trim((string)($body['displayName'] ?? ''));
        $alignmentValue = (int)($body['alignmentValue'] ?? 0);
        if ($code === '' || $displayName === '') {
            return json_error('VALIDATION_ALIGNMENT_FIELDS', 'code and displayName are required.', [], 422);
        }

        $pdo = db();
        $existsStmt = $pdo->prepare('SELECT 1 FROM guild_alignment_options WHERE code = ? LIMIT 1');
        $existsStmt->execute([$code]);
        if ($existsStmt->fetchColumn()) {
            return json_error('DUPLICATE_ALIGNMENT_CODE', 'Alignment code already exists.', [], 409);
        }

        $sortOrder = self::nextSortOrder($pdo, 'guild_alignment_options');
        $now = now_utc();
        $stmt = $pdo->prepare('
            INSERT INTO guild_alignment_options (code, display_name, alignment_value, include_flag, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, 1, ?, ?, ?)
        ');
        $stmt->execute([$code, $displayName, $alignmentValue, $sortOrder, $now, $now]);
        return ['status' => 201, 'body' => json_success(['created' => true, 'code' => $code])];
    }

    public static function alignmentToggle(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        $include = (bool)($body['include'] ?? false);
        if ($code === '') {
            return json_error('VALIDATION_ALIGNMENT_CODE', 'code is required.', [], 422);
        }
        $stmt = db()->prepare('UPDATE guild_alignment_options SET include_flag = ?, updated_at = ? WHERE code = ?');
        $stmt->execute([$include ? 1 : 0, now_utc(), $code]);
        if ($stmt->rowCount() < 1) {
            return json_error('ALIGNMENT_NOT_FOUND', 'Alignment code not found.', [], 404);
        }
        return ['status' => 200, 'body' => json_success(['updated' => true, 'code' => $code, 'include' => $include])];
    }

    public static function alignmentDelete(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        if ($code === '') {
            return json_error('VALIDATION_ALIGNMENT_CODE', 'code is required.', [], 422);
        }
        $stmt = db()->prepare('DELETE FROM guild_alignment_options WHERE code = ?');
        $stmt->execute([$code]);
        if ($stmt->rowCount() < 1) {
            return json_error('ALIGNMENT_NOT_FOUND', 'Alignment code not found.', [], 404);
        }
        return ['status' => 200, 'body' => json_success(['deleted' => true, 'code' => $code])];
    }

    public static function typeList(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $pdo = db();
        $stmt = $pdo->query('
            SELECT code, display_name, include_flag, sort_order, created_at, updated_at
            FROM guild_type_options
            ORDER BY sort_order ASC, display_name ASC
        ');
        $rows = $stmt->fetchAll() ?: [];
        $items = array_map(static function (array $row): array {
            return [
                'code' => (string)$row['code'],
                'displayName' => (string)$row['display_name'],
                'include' => ((int)$row['include_flag']) === 1,
                'sortOrder' => (int)$row['sort_order'],
                'createdAt' => gmdate('c', strtotime((string)$row['created_at'])),
                'updatedAt' => gmdate('c', strtotime((string)$row['updated_at'])),
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['types' => $items])];
    }

    public static function typeUpsert(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        $displayName = trim((string)($body['displayName'] ?? ''));
        $include = (bool)($body['include'] ?? true);
        $sortOrder = (int)($body['sortOrder'] ?? 0);
        if ($code === '' || $displayName === '') {
            return json_error('VALIDATION_TYPE_FIELDS', 'code and displayName are required.', [], 422);
        }
        $pdo = db();
        $now = now_utc();
        $stmt = $pdo->prepare('
            INSERT INTO guild_type_options (code, display_name, include_flag, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
              display_name = VALUES(display_name),
              include_flag = VALUES(include_flag),
              sort_order = VALUES(sort_order),
              updated_at = VALUES(updated_at)
        ');
        $stmt->execute([$code, $displayName, $include ? 1 : 0, $sortOrder, $now, $now]);
        return ['status' => 200, 'body' => json_success(['updated' => true, 'code' => $code])];
    }

    public static function typeCreate(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        $displayName = trim((string)($body['displayName'] ?? ''));
        if ($code === '' || $displayName === '') {
            return json_error('VALIDATION_TYPE_FIELDS', 'code and displayName are required.', [], 422);
        }

        $pdo = db();
        $existsStmt = $pdo->prepare('SELECT 1 FROM guild_type_options WHERE code = ? LIMIT 1');
        $existsStmt->execute([$code]);
        if ($existsStmt->fetchColumn()) {
            return json_error('DUPLICATE_TYPE_CODE', 'Type code already exists.', [], 409);
        }

        $sortOrder = self::nextSortOrder($pdo, 'guild_type_options');
        $now = now_utc();
        $stmt = $pdo->prepare('
            INSERT INTO guild_type_options (code, display_name, include_flag, sort_order, created_at, updated_at)
            VALUES (?, ?, 1, ?, ?, ?)
        ');
        $stmt->execute([$code, $displayName, $sortOrder, $now, $now]);
        return ['status' => 201, 'body' => json_success(['created' => true, 'code' => $code])];
    }

    public static function typeToggle(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        $include = (bool)($body['include'] ?? false);
        if ($code === '') {
            return json_error('VALIDATION_TYPE_CODE', 'code is required.', [], 422);
        }
        $stmt = db()->prepare('UPDATE guild_type_options SET include_flag = ?, updated_at = ? WHERE code = ?');
        $stmt->execute([$include ? 1 : 0, now_utc(), $code]);
        if ($stmt->rowCount() < 1) {
            return json_error('TYPE_NOT_FOUND', 'Type code not found.', [], 404);
        }
        return ['status' => 200, 'body' => json_success(['updated' => true, 'code' => $code, 'include' => $include])];
    }

    public static function typeDelete(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $code = trim((string)($body['code'] ?? ''));
        if ($code === '') {
            return json_error('VALIDATION_TYPE_CODE', 'code is required.', [], 422);
        }
        $stmt = db()->prepare('DELETE FROM guild_type_options WHERE code = ?');
        $stmt->execute([$code]);
        if ($stmt->rowCount() < 1) {
            return json_error('TYPE_NOT_FOUND', 'Type code not found.', [], 404);
        }
        return ['status' => 200, 'body' => json_success(['deleted' => true, 'code' => $code])];
    }

    public static function characters(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $q = trim((string)($_GET['q'] ?? ''));
        $accountId = trim((string)($_GET['accountId'] ?? ''));
        $limit = max(1, min(300, (int)($_GET['limit'] ?? 150)));
        $pdo = db();
        if ($accountId !== '') {
            $sql = '
                SELECT c.character_uid, c.name, c.race, c.class_name, c.network_mode, c.realm_id, c.created_at, c.updated_at,
                       a.account_uid, a.email, a.public_name
                FROM characters c
                JOIN accounts a ON a.id = c.account_id
                WHERE a.account_uid = ?
                ORDER BY c.created_at DESC
                LIMIT ' . $limit;
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$accountId]);
        } else if ($q !== '') {
            $like = '%' . $q . '%';
            $sql = '
                SELECT c.character_uid, c.name, c.race, c.class_name, c.network_mode, c.realm_id, c.created_at, c.updated_at,
                       a.account_uid, a.email, a.public_name
                FROM characters c
                JOIN accounts a ON a.id = c.account_id
                WHERE c.name LIKE ? OR a.email LIKE ? OR a.public_name LIKE ?
                ORDER BY c.created_at DESC
                LIMIT ' . $limit;
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$like, $like, $like]);
        } else {
            $sql = '
                SELECT c.character_uid, c.name, c.race, c.class_name, c.network_mode, c.realm_id, c.created_at, c.updated_at,
                       a.account_uid, a.email, a.public_name
                FROM characters c
                JOIN accounts a ON a.id = c.account_id
                ORDER BY c.created_at DESC
                LIMIT ' . $limit;
            $stmt = $pdo->query($sql);
        }
        $rows = $stmt->fetchAll() ?: [];
        $items = array_map(static function (array $row): array {
            return [
                'characterId' => (string)$row['character_uid'],
                'name' => (string)$row['name'],
                'race' => (string)$row['race'],
                'className' => (string)$row['class_name'],
                'networkMode' => (string)$row['network_mode'],
                'realmRef' => (string)$row['realm_id'],
                'createdAt' => gmdate('c', strtotime((string)$row['created_at'])),
                'updatedAt' => gmdate('c', strtotime((string)$row['updated_at'])),
                'ownerAccountId' => (string)$row['account_uid'],
                'ownerEmail' => (string)$row['email'],
                'ownerPublicName' => (string)$row['public_name'],
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['characters' => $items])];
    }

    public static function guilds(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $q = trim((string)($_GET['q'] ?? ''));
        $limit = max(1, min(300, (int)($_GET['limit'] ?? 150)));
        $pdo = db();
        if ($q !== '') {
            $like = '%' . $q . '%';
            $sql = '
                SELECT g.guild_uid, g.formal_name, g.short_tag, g.alignment_code, g.type_code, g.status, g.motto, r.realm_uid, c.name AS chief_name, c.character_uid AS chief_character_uid,
                       COUNT(gm.id) AS active_members
                FROM guilds g
                JOIN realms r ON r.id = g.realm_id
                JOIN characters c ON c.id = g.chief_character_id
                LEFT JOIN guild_members gm ON gm.guild_id = g.id AND gm.status = "active"
                WHERE g.formal_name LIKE ? OR g.short_tag LIKE ? OR g.alignment_code LIKE ? OR g.type_code LIKE ?
                GROUP BY g.id
                ORDER BY g.created_at DESC
                LIMIT ' . $limit;
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$like, $like, $like, $like]);
        } else {
            $sql = '
                SELECT g.guild_uid, g.formal_name, g.short_tag, g.alignment_code, g.type_code, g.status, g.motto, r.realm_uid, c.name AS chief_name, c.character_uid AS chief_character_uid,
                       COUNT(gm.id) AS active_members
                FROM guilds g
                JOIN realms r ON r.id = g.realm_id
                JOIN characters c ON c.id = g.chief_character_id
                LEFT JOIN guild_members gm ON gm.guild_id = g.id AND gm.status = "active"
                GROUP BY g.id
                ORDER BY g.created_at DESC
                LIMIT ' . $limit;
            $stmt = $pdo->query($sql);
        }
        $rows = $stmt->fetchAll() ?: [];
        $items = array_map(static function (array $row): array {
            return [
                'guildId' => (string)$row['guild_uid'],
                'formalName' => (string)$row['formal_name'],
                'shortTag' => (string)$row['short_tag'],
                'alignmentCode' => (string)$row['alignment_code'],
                'typeCode' => (string)$row['type_code'],
                'status' => (string)$row['status'],
                'motto' => (string)($row['motto'] ?? ''),
                'realmId' => (string)$row['realm_uid'],
                'chiefCharacterId' => (string)$row['chief_character_uid'],
                'chiefName' => (string)$row['chief_name'],
                'activeMembers' => (int)$row['active_members'],
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['guilds' => $items])];
    }

    public static function pendingAbandonmentList(): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $pdo = db();
        $stmt = $pdo->query('
            SELECT g.guild_uid, g.formal_name, g.short_tag, g.status, g.abandonment_requested_at, c.name AS requester_name
            FROM guilds g
            LEFT JOIN characters c ON c.id = g.abandonment_requested_by
            WHERE g.status = "pending_abandonment"
            ORDER BY g.abandonment_requested_at ASC
        ');
        $rows = $stmt->fetchAll() ?: [];
        $items = array_map(static function (array $row): array {
            return [
                'guildId' => (string)$row['guild_uid'],
                'formalName' => (string)$row['formal_name'],
                'shortTag' => (string)$row['short_tag'],
                'status' => (string)$row['status'],
                'requestedAt' => $row['abandonment_requested_at'] ? gmdate('c', strtotime((string)$row['abandonment_requested_at'])) : null,
                'requestedBy' => (string)($row['requester_name'] ?? ''),
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['guilds' => $items])];
    }

    public static function approveAbandonment(array $body): array {
        $auth = require_admin_session_or_error();
        if ($auth !== null) {
            return $auth;
        }
        $guildId = trim((string)($body['guildId'] ?? ''));
        if ($guildId === '') {
            return json_error('VALIDATION_GUILD_ID', 'guildId is required.', [], 422);
        }

        $pdo = db();
        $stmt = $pdo->prepare('SELECT id, status FROM guilds WHERE guild_uid = ? LIMIT 1');
        $stmt->execute([$guildId]);
        $guild = $stmt->fetch();
        if (!$guild) {
            return json_error('GUILD_NOT_FOUND', 'Guild not found.', [], 404);
        }
        if ((string)$guild['status'] !== 'pending_abandonment') {
            return json_error('GUILD_NOT_PENDING_ABANDONMENT', 'Guild is not pending abandonment.', [], 409);
        }

        $now = now_utc();
        try {
            $pdo->beginTransaction();
            $upGuild = $pdo->prepare('
                UPDATE guilds
                SET status = "abandoned", abandonment_approved_at = ?, updated_at = ?
                WHERE id = ?
            ');
            $upGuild->execute([$now, $now, (int)$guild['id']]);

            $upMembers = $pdo->prepare('
                UPDATE guild_members
                SET status = "left", left_at = ?
                WHERE guild_id = ? AND status = "active"
            ');
            $upMembers->execute([$now, (int)$guild['id']]);

            $log = $pdo->prepare('
                INSERT INTO guild_logs (guild_id, log_type, message, created_at)
                VALUES (?, "system", "Guild marked abandoned by admin.", ?)
            ');
            $log->execute([(int)$guild['id'], $now]);
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            return json_error('ABANDON_APPROVE_FAILED', 'Failed to approve abandonment.', ['reason' => $e->getMessage()], 500);
        }

        return ['status' => 200, 'body' => json_success(['approved' => true, 'guildId' => $guildId])];
    }

    private static function nextSortOrder(PDO $pdo, string $table): int {
        $stmt = $pdo->query('SELECT COALESCE(MAX(sort_order), 0) AS max_sort FROM ' . $table);
        $maxSort = (int)($stmt->fetch()['max_sort'] ?? 0);
        return $maxSort + 10;
    }
}
