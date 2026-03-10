<?php
declare(strict_types=1);

final class GuildHandler {
    public static function createOnlineCharacter(array $body): array {
        $auth = require_account_session_from_body($body);
        if (isset($auth['error'])) {
            return $auth['error'];
        }
        $session = $auth['session'];

        $realmId = trim((string)($body['realmId'] ?? env_value('PQ_REALM_ID', 'realm_goobland_1')));
        $localUUID = trim((string)($body['localCharacterUUID'] ?? ''));
        $name = trim((string)($body['name'] ?? ''));
        $race = trim((string)($body['race'] ?? ''));
        $className = trim((string)($body['className'] ?? ''));

        if ($localUUID === '' || $name === '' || $race === '' || $className === '') {
            return json_error('VALIDATION_CHARACTER_FIELDS', 'localCharacterUUID, name, race, className are required.', [], 422);
        }

        ensure_default_realm_seeded();
        $pdo = db();
        $realmStmt = $pdo->prepare('SELECT id, realm_uid FROM realms WHERE realm_uid = ? LIMIT 1');
        $realmStmt->execute([$realmId]);
        $realm = $realmStmt->fetch();
        if (!$realm) {
            return json_error('REALM_NOT_FOUND', 'Realm not found.', [], 404);
        }

        $existingStmt = $pdo->prepare('
            SELECT character_uid, realm_id, local_character_uuid, name, race, class_name
            FROM characters
            WHERE account_id = ? AND local_character_uuid = ?
            LIMIT 1
        ');
        $existingStmt->execute([(int)$session['account_id'], $localUUID]);
        $existing = $existingStmt->fetch();
        if ($existing) {
            return [
                'status' => 200,
                'body' => json_success([
                    'serverCharacterId' => (string)$existing['character_uid'],
                    'realmId' => (string)$realmId,
                    'name' => (string)$existing['name'],
                    'race' => (string)$existing['race'],
                    'className' => (string)$existing['class_name'],
                    'created' => false,
                ]),
            ];
        }

        $uid = uid26();
        $now = now_utc();
        $insert = $pdo->prepare('
            INSERT INTO characters (character_uid, account_id, realm_id, local_character_uuid, name, race, class_name, network_mode, seed, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, "online", NULL, ?, ?)
        ');
        $insert->execute([
            $uid,
            (int)$session['account_id'],
            (int)$realm['id'],
            $localUUID,
            $name,
            $race,
            $className,
            $now,
            $now,
        ]);

        return [
            'status' => 201,
            'body' => json_success([
                'serverCharacterId' => $uid,
                'realmId' => $realmId,
                'name' => $name,
                'race' => $race,
                'className' => $className,
                'created' => true,
            ]),
        ];
    }

    public static function listGuilds(array $query): array {
        ensure_default_realm_seeded();
        $realmId = trim((string)($query['realmId'] ?? env_value('PQ_REALM_ID', 'realm_goobland_1')));
        $pdo = db();
        $stmt = $pdo->prepare('
            SELECT g.guild_uid, g.formal_name, g.short_tag, g.alignment_code, g.type_code, g.motto,
                   COUNT(gm.id) AS member_count
            FROM guilds g
            LEFT JOIN guild_members gm ON gm.guild_id = g.id AND gm.status = "active"
            JOIN realms r ON r.id = g.realm_id
            WHERE r.realm_uid = ?
            GROUP BY g.id
            ORDER BY g.created_at DESC
            LIMIT 250
        ');
        $stmt->execute([$realmId]);
        $rows = $stmt->fetchAll() ?: [];
        $guilds = array_map(static function (array $row): array {
            return [
                'guildId' => (string)$row['guild_uid'],
                'formalName' => (string)$row['formal_name'],
                'shortTag' => (string)$row['short_tag'],
                'alignmentCode' => (string)$row['alignment_code'],
                'typeCode' => (string)$row['type_code'],
                'motto' => (string)($row['motto'] ?? ''),
                'memberCount' => (int)$row['member_count'],
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['guilds' => $guilds])];
    }

    public static function createGuild(array $body): array {
        $characterRow = self::requireOwnedCharacterFromBody($body);
        if (isset($characterRow['error'])) {
            return $characterRow['error'];
        }
        $character = $characterRow['character'];

        $formalName = trim((string)($body['formalName'] ?? ''));
        $shortTag = trim((string)($body['shortTag'] ?? ''));
        $alignmentCode = trim((string)($body['alignmentCode'] ?? 'Neutral'));
        $typeCode = trim((string)($body['typeCode'] ?? 'Guild'));
        $motto = trim((string)($body['motto'] ?? ''));

        if ($formalName === '' || $shortTag === '') {
            return json_error('VALIDATION_GUILD_FIELDS', 'formalName and shortTag are required.', [], 422);
        }

        $pdo = db();
        $chiefCountStmt = $pdo->prepare('
            SELECT COUNT(*) c
            FROM guild_members gm
            JOIN guilds g ON g.id = gm.guild_id
            WHERE gm.character_id = ? AND gm.role = "chief" AND gm.status = "active"
        ');
        $chiefCountStmt->execute([(int)$character['id']]);
        $chiefCount = (int)($chiefCountStmt->fetch()['c'] ?? 0);
        if ($chiefCount >= 4) {
            return json_error('CHIEF_LIMIT', 'Chief may manage at most 4 guilds.', [], 409);
        }

        $guildUid = uid26();
        $now = now_utc();
        try {
            $pdo->beginTransaction();
            $insertGuild = $pdo->prepare('
                INSERT INTO guilds (guild_uid, realm_id, formal_name, short_tag, alignment_code, type_code, motto, chief_character_id, immutable_on_membership, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
            ');
            $insertGuild->execute([
                $guildUid,
                (int)$character['realm_id'],
                $formalName,
                $shortTag,
                $alignmentCode,
                $typeCode,
                $motto,
                (int)$character['id'],
                $now,
                $now,
            ]);
            $guildId = (int)$pdo->lastInsertId();

            $insertMember = $pdo->prepare('
                INSERT INTO guild_members (guild_id, character_id, role, status, joined_at, left_at)
                VALUES (?, ?, "chief", "active", ?, NULL)
            ');
            $insertMember->execute([$guildId, (int)$character['id'], $now]);

            $insertRules = $pdo->prepare('
                INSERT INTO guild_rules (guild_id, majority_type, majority_basis, quorum_enabled, quorum_percent, no_confidence_enabled, created_at, updated_at)
                VALUES (?, "functional_50", "present", 0, NULL, 0, ?, ?)
            ');
            $insertRules->execute([$guildId, $now, $now]);

            $insertLog = $pdo->prepare('
                INSERT INTO guild_logs (guild_id, log_type, message, created_at)
                VALUES (?, "system", ?, ?)
            ');
            $insertLog->execute([$guildId, "Guild founded by " . (string)$character['name'] . ".", $now]);

            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            return json_error('GUILD_CREATE_FAILED', 'Failed to create guild.', ['reason' => $e->getMessage()], 409);
        }

        return [
            'status' => 201,
            'body' => json_success([
                'guildId' => $guildUid,
                'formalName' => $formalName,
                'shortTag' => $shortTag,
            ]),
        ];
    }

    public static function joinGuild(array $body): array {
        $characterRow = self::requireOwnedCharacterFromBody($body);
        if (isset($characterRow['error'])) {
            return $characterRow['error'];
        }
        $character = $characterRow['character'];
        $guildUid = trim((string)($body['guildId'] ?? ''));
        if ($guildUid === '') {
            return json_error('VALIDATION_GUILD_ID', 'guildId is required.', [], 422);
        }

        $pdo = db();
        $guildStmt = $pdo->prepare('SELECT id, realm_id FROM guilds WHERE guild_uid = ? LIMIT 1');
        $guildStmt->execute([$guildUid]);
        $guild = $guildStmt->fetch();
        if (!$guild) {
            return json_error('GUILD_NOT_FOUND', 'Guild not found.', [], 404);
        }
        if ((int)$guild['realm_id'] !== (int)$character['realm_id']) {
            return json_error('REALM_MISMATCH', 'Character and guild must be in same realm.', [], 409);
        }

        $now = now_utc();
        $existing = $pdo->prepare('
            SELECT id, status FROM guild_members
            WHERE guild_id = ? AND character_id = ?
            LIMIT 1
        ');
        $existing->execute([(int)$guild['id'], (int)$character['id']]);
        $member = $existing->fetch();
        if ($member) {
            if ($member['status'] === 'active') {
                return json_error('ALREADY_MEMBER', 'Character is already in guild.', [], 409);
            }
            $reactivate = $pdo->prepare('UPDATE guild_members SET status = "active", joined_at = ?, left_at = NULL WHERE id = ?');
            $reactivate->execute([$now, (int)$member['id']]);
        } else {
            $insert = $pdo->prepare('
                INSERT INTO guild_members (guild_id, character_id, role, status, joined_at, left_at)
                VALUES (?, ?, "member", "active", ?, NULL)
            ');
            $insert->execute([(int)$guild['id'], (int)$character['id'], $now]);
        }

        $log = $pdo->prepare('INSERT INTO guild_logs (guild_id, log_type, message, created_at) VALUES (?, "system", ?, ?)');
        $log->execute([(int)$guild['id'], (string)$character['name'] . " joined the guild.", $now]);

        return ['status' => 200, 'body' => json_success(['joined' => true, 'guildId' => $guildUid])];
    }

    public static function leaveGuild(array $body): array {
        $characterRow = self::requireOwnedCharacterFromBody($body);
        if (isset($characterRow['error'])) {
            return $characterRow['error'];
        }
        $character = $characterRow['character'];
        $guildUid = trim((string)($body['guildId'] ?? ''));
        if ($guildUid === '') {
            return json_error('VALIDATION_GUILD_ID', 'guildId is required.', [], 422);
        }

        $pdo = db();
        $guildStmt = $pdo->prepare('SELECT id FROM guilds WHERE guild_uid = ? LIMIT 1');
        $guildStmt->execute([$guildUid]);
        $guild = $guildStmt->fetch();
        if (!$guild) {
            return json_error('GUILD_NOT_FOUND', 'Guild not found.', [], 404);
        }

        $memberStmt = $pdo->prepare('
            SELECT id, role, status
            FROM guild_members
            WHERE guild_id = ? AND character_id = ?
            LIMIT 1
        ');
        $memberStmt->execute([(int)$guild['id'], (int)$character['id']]);
        $member = $memberStmt->fetch();
        if (!$member || $member['status'] !== 'active') {
            return json_error('NOT_MEMBER', 'Character is not an active member of this guild.', [], 409);
        }
        if ($member['role'] === 'chief') {
            return json_error('CHIEF_CANNOT_LEAVE', 'Chief cannot leave guild in v1.', [], 409);
        }

        $now = now_utc();
        $leave = $pdo->prepare('UPDATE guild_members SET status = "left", left_at = ? WHERE id = ?');
        $leave->execute([$now, (int)$member['id']]);
        $log = $pdo->prepare('INSERT INTO guild_logs (guild_id, log_type, message, created_at) VALUES (?, "system", ?, ?)');
        $log->execute([(int)$guild['id'], (string)$character['name'] . " left the guild.", $now]);

        return ['status' => 200, 'body' => json_success(['left' => true, 'guildId' => $guildUid])];
    }

    public static function guildProfile(string $guildUid): array {
        $pdo = db();
        $stmt = $pdo->prepare('
            SELECT g.id, g.guild_uid, g.formal_name, g.short_tag, g.alignment_code, g.type_code, g.motto, g.immutable_on_membership,
                   r.realm_uid, c.character_uid AS chief_character_uid, c.name AS chief_name
            FROM guilds g
            JOIN realms r ON r.id = g.realm_id
            JOIN characters c ON c.id = g.chief_character_id
            WHERE g.guild_uid = ?
            LIMIT 1
        ');
        $stmt->execute([$guildUid]);
        $guild = $stmt->fetch();
        if (!$guild) {
            return json_error('GUILD_NOT_FOUND', 'Guild not found.', [], 404);
        }

        $membersStmt = $pdo->prepare('
            SELECT c.character_uid, c.name, gm.role, gm.status, gm.joined_at
            FROM guild_members gm
            JOIN characters c ON c.id = gm.character_id
            WHERE gm.guild_id = ? AND gm.status = "active"
            ORDER BY gm.role DESC, gm.joined_at ASC
        ');
        $membersStmt->execute([(int)$guild['id']]);
        $membersRows = $membersStmt->fetchAll() ?: [];
        $members = array_map(static function (array $m): array {
            return [
                'characterId' => (string)$m['character_uid'],
                'name' => (string)$m['name'],
                'role' => (string)$m['role'],
                'status' => (string)$m['status'],
                'joinedAt' => gmdate('c', strtotime((string)$m['joined_at'])),
            ];
        }, $membersRows);

        return [
            'status' => 200,
            'body' => json_success([
                'guild' => [
                    'guildId' => (string)$guild['guild_uid'],
                    'formalName' => (string)$guild['formal_name'],
                    'shortTag' => (string)$guild['short_tag'],
                    'alignmentCode' => (string)$guild['alignment_code'],
                    'typeCode' => (string)$guild['type_code'],
                    'motto' => (string)($guild['motto'] ?? ''),
                    'realmId' => (string)$guild['realm_uid'],
                    'chiefCharacterId' => (string)$guild['chief_character_uid'],
                    'chiefName' => (string)$guild['chief_name'],
                    'immutableOnMembership' => ((int)$guild['immutable_on_membership']) === 1,
                    'memberCount' => count($members),
                    'members' => $members,
                ],
            ]),
        ];
    }

    public static function guildLogs(string $guildUid): array {
        $pdo = db();
        $guildStmt = $pdo->prepare('SELECT id FROM guilds WHERE guild_uid = ? LIMIT 1');
        $guildStmt->execute([$guildUid]);
        $guild = $guildStmt->fetch();
        if (!$guild) {
            return json_error('GUILD_NOT_FOUND', 'Guild not found.', [], 404);
        }
        $stmt = $pdo->prepare('
            SELECT log_type, message, created_at
            FROM guild_logs
            WHERE guild_id = ?
            ORDER BY created_at DESC
            LIMIT 100
        ');
        $stmt->execute([(int)$guild['id']]);
        $rows = $stmt->fetchAll() ?: [];
        $logs = array_map(static function (array $row): array {
            return [
                'type' => (string)$row['log_type'],
                'message' => (string)$row['message'],
                'createdAt' => gmdate('c', strtotime((string)$row['created_at'])),
            ];
        }, $rows);
        return ['status' => 200, 'body' => json_success(['logs' => $logs])];
    }

    private static function requireOwnedCharacterFromBody(array $body): array {
        $auth = require_account_session_from_body($body);
        if (isset($auth['error'])) {
            return ['error' => $auth['error']];
        }
        $session = $auth['session'];
        $serverCharacterId = trim((string)($body['serverCharacterId'] ?? ''));
        if ($serverCharacterId === '') {
            return ['error' => json_error('VALIDATION_SERVER_CHARACTER', 'serverCharacterId is required.', [], 422)];
        }
        $pdo = db();
        $stmt = $pdo->prepare('
            SELECT id, character_uid, account_id, realm_id, name
            FROM characters
            WHERE character_uid = ?
            LIMIT 1
        ');
        $stmt->execute([$serverCharacterId]);
        $character = $stmt->fetch();
        if (!$character) {
            return ['error' => json_error('CHARACTER_NOT_FOUND', 'Online character not found.', [], 404)];
        }
        if ((int)$character['account_id'] !== (int)$session['account_id']) {
            return ['error' => json_error('CHARACTER_ACCOUNT_MISMATCH', 'Character belongs to another account.', [], 403)];
        }
        return ['character' => $character, 'session' => $session];
    }
}
