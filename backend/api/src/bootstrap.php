<?php
declare(strict_types=1);

// Optional local runtime config fallback (useful on shared hosting where env vars are limited).
// File format:
// <?php return ['PQ_DB_HOST' => 'db.example.com', ...];
$runtimeConfigFile = __DIR__ . '/../config/runtime.php';
if (is_file($runtimeConfigFile)) {
    $runtime = require $runtimeConfigFile;
    if (is_array($runtime)) {
        foreach ($runtime as $k => $v) {
            if (!is_string($k)) {
                continue;
            }
            if (!is_scalar($v) && $v !== null) {
                continue;
            }
            $value = $v === null ? '' : (string)$v;
            $_ENV[$k] = $value;
            $_SERVER[$k] = $value;
            putenv($k . '=' . $value);
        }
    }
}

function env_value(string $key, ?string $default = null): ?string {
    $v = $_ENV[$key] ?? $_SERVER[$key] ?? getenv($key);
    if ($v === false || $v === null || $v === '') {
        return $default;
    }
    return (string)$v;
}

function json_success(array $data = []): array {
    return ['ok' => true, 'data' => $data];
}

function json_error(string $code, string $message, array $details = [], int $status = 400): array {
    return [
        'status' => $status,
        'body' => [
            'ok' => false,
            'error' => [
                'code' => $code,
                'message' => $message,
                'details' => (object)$details,
            ],
        ],
    ];
}

function parse_json_body(): array {
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        throw new RuntimeException('INVALID_JSON_BODY');
    }
    return $decoded;
}

function env_bool(string $key, bool $default = false): bool {
    $v = env_value($key);
    if ($v === null) {
        return $default;
    }
    $normalized = strtolower(trim($v));
    return in_array($normalized, ['1', 'true', 'yes', 'on'], true);
}

function db(): PDO {
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $host = env_value('PQ_DB_HOST', '127.0.0.1');
    $port = env_value('PQ_DB_PORT', '3306');
    $name = env_value('PQ_DB_NAME', '');
    $user = env_value('PQ_DB_USER', '');
    $pass = env_value('PQ_DB_PASS', '');

    if ($name === '' || $user === '') {
        throw new RuntimeException('DB_NOT_CONFIGURED');
    }

    $dsn = "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);

    return $pdo;
}

function now_utc(): string {
    return gmdate('Y-m-d H:i:s');
}

function uid26(): string {
    $alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    $bytes = random_bytes(26);
    $out = '';
    for ($i = 0; $i < 26; $i++) {
        $out .= $alphabet[ord($bytes[$i]) % strlen($alphabet)];
    }
    return $out;
}

function secure_token(int $bytes = 32): string {
    return bin2hex(random_bytes($bytes));
}

function token_hash(string $raw): string {
    return hash('sha256', $raw);
}

function email_is_valid(string $email): bool {
    return (bool)filter_var($email, FILTER_VALIDATE_EMAIL);
}

function bearer_token_from_request(): ?string {
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if ($header === '') {
        $header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    }
    if ($header === '' && function_exists('getallheaders')) {
        $all = getallheaders();
        if (is_array($all)) {
            foreach ($all as $k => $v) {
                if (strcasecmp((string)$k, 'Authorization') === 0) {
                    $header = (string)$v;
                    break;
                }
            }
        }
    }
    if ($header === '') {
        return null;
    }
    if (!preg_match('/^Bearer\s+(.+)$/i', $header, $m)) {
        return null;
    }
    return trim($m[1]);
}

function require_admin_session_or_error(): ?array {
    $token = bearer_token_from_request();
    if ($token === null || $token === '') {
        return json_error('ADMIN_AUTH_REQUIRED', 'Missing admin bearer token.', [], 401);
    }

    $pdo = db();
    $stmt = $pdo->prepare('
        SELECT username, expires_at, revoked_at
        FROM admin_sessions
        WHERE session_token_hash = ?
        LIMIT 1
    ');
    $stmt->execute([token_hash($token)]);
    $row = $stmt->fetch();
    if (!$row) {
        return json_error('ADMIN_SESSION_NOT_FOUND', 'Admin session not found.', [], 401);
    }
    if ($row['revoked_at'] !== null) {
        return json_error('ADMIN_SESSION_REVOKED', 'Admin session revoked.', [], 401);
    }
    if (strtotime((string)$row['expires_at']) < time()) {
        return json_error('ADMIN_SESSION_EXPIRED', 'Admin session expired.', [], 401);
    }
    return null;
}

function ensure_default_realm_seeded(): void {
    $realmId = env_value('PQ_REALM_ID', 'realm_goobland_1');
    $realmName = env_value('PQ_REALM_NAME', 'Goobland');
    $now = now_utc();

    $pdo = db();
    $stmt = $pdo->prepare('SELECT id FROM realms WHERE realm_uid = ? LIMIT 1');
    $stmt->execute([$realmId]);
    if ($stmt->fetch()) {
        return;
    }
    $insert = $pdo->prepare('
        INSERT INTO realms (realm_uid, name, status, supports_guilds, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ');
    $insert->execute([$realmId, $realmName, 'active', 1, $now, $now]);
}

function ensure_multiplayer_config_seeded(): void {
    static $initialized = false;
    if ($initialized) {
        return;
    }

    $pdo = db();
    $now = now_utc();

    $pdo->exec('
        CREATE TABLE IF NOT EXISTS guild_alignment_options (
          id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
          code VARCHAR(40) NOT NULL UNIQUE,
          display_name VARCHAR(80) NOT NULL,
          alignment_value INT NOT NULL DEFAULT 0,
          include_flag TINYINT(1) NOT NULL DEFAULT 1,
          sort_order INT NOT NULL DEFAULT 0,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        )
    ');
    $pdo->exec('
        CREATE TABLE IF NOT EXISTS guild_type_options (
          id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
          code VARCHAR(40) NOT NULL UNIQUE,
          display_name VARCHAR(80) NOT NULL,
          include_flag TINYINT(1) NOT NULL DEFAULT 1,
          sort_order INT NOT NULL DEFAULT 0,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        )
    ');

    if (!table_has_column($pdo, 'guilds', 'status')) {
        $pdo->exec("ALTER TABLE guilds ADD COLUMN status ENUM('active','pending_abandonment','abandoned') NOT NULL DEFAULT 'active' AFTER immutable_on_membership");
    }
    if (!table_has_column($pdo, 'guilds', 'abandonment_requested_at')) {
        $pdo->exec('ALTER TABLE guilds ADD COLUMN abandonment_requested_at DATETIME DEFAULT NULL AFTER status');
    }
    if (!table_has_column($pdo, 'guilds', 'abandonment_requested_by')) {
        $pdo->exec('ALTER TABLE guilds ADD COLUMN abandonment_requested_by BIGINT UNSIGNED DEFAULT NULL AFTER abandonment_requested_at');
    }
    if (!table_has_column($pdo, 'guilds', 'abandonment_approved_at')) {
        $pdo->exec('ALTER TABLE guilds ADD COLUMN abandonment_approved_at DATETIME DEFAULT NULL AFTER abandonment_requested_by');
    }
    if (!table_has_column($pdo, 'guild_rules', 'quorum_percent')) {
        $pdo->exec('ALTER TABLE guild_rules ADD COLUMN quorum_percent TINYINT UNSIGNED DEFAULT NULL AFTER quorum_enabled');
    }

    $seedAlignments = [
        ['Neutral', 'Neutral', 0, 10],
        ['Good', 'Good', 1, 20],
        ['Evil', 'Evil', -1, 30],
    ];
    foreach ($seedAlignments as [$code, $display, $value, $sort]) {
        $check = $pdo->prepare('SELECT id FROM guild_alignment_options WHERE code = ? LIMIT 1');
        $check->execute([$code]);
        if ($check->fetch()) {
            continue;
        }
        $insert = $pdo->prepare('
            INSERT INTO guild_alignment_options (code, display_name, alignment_value, include_flag, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, 1, ?, ?, ?)
        ');
        $insert->execute([$code, $display, $value, $sort, $now, $now]);
    }

    $seedTypes = [
        ['Guild', 'Guild', 10],
        ['Clan', 'Clan', 20],
        ['Faction', 'Faction', 30],
        ['Band', 'Band', 40],
    ];
    foreach ($seedTypes as [$code, $display, $sort]) {
        $check = $pdo->prepare('SELECT id FROM guild_type_options WHERE code = ? LIMIT 1');
        $check->execute([$code]);
        if ($check->fetch()) {
            continue;
        }
        $insert = $pdo->prepare('
            INSERT INTO guild_type_options (code, display_name, include_flag, sort_order, created_at, updated_at)
            VALUES (?, ?, 1, ?, ?, ?)
        ');
        $insert->execute([$code, $display, $sort, $now, $now]);
    }

    $initialized = true;
}

function table_has_column(PDO $pdo, string $table, string $column): bool {
    $dbName = env_value('PQ_DB_NAME', '');
    if ($dbName === '') {
        return false;
    }
    $stmt = $pdo->prepare('
        SELECT 1
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?
        LIMIT 1
    ');
    $stmt->execute([$dbName, $table, $column]);
    return (bool)$stmt->fetchColumn();
}

function account_session_from_token(string $token): ?array {
    $pdo = db();
    $stmt = $pdo->prepare('
        SELECT s.account_id, s.expires_at, s.revoked_at, a.account_uid, a.email, a.public_name, a.wants_news, a.verified
        FROM account_sessions s
        JOIN accounts a ON a.id = s.account_id
        WHERE s.session_token_hash = ?
        LIMIT 1
    ');
    $stmt->execute([token_hash($token)]);
    $row = $stmt->fetch();
    if (!$row) {
        return null;
    }
    return $row;
}

function require_account_session_from_body(array $body): array {
    $token = trim((string)($body['sessionToken'] ?? ''));
    if ($token === '') {
        return ['error' => json_error('VALIDATION_SESSION_TOKEN', 'sessionToken is required.', [], 422)];
    }
    $row = account_session_from_token($token);
    if (!$row) {
        return ['error' => json_error('SESSION_NOT_FOUND', 'Session not found.', [], 404)];
    }
    if ($row['revoked_at'] !== null) {
        return ['error' => json_error('SESSION_REVOKED', 'Session revoked.', [], 401)];
    }
    if (strtotime((string)$row['expires_at']) < time()) {
        return ['error' => json_error('SESSION_EXPIRED', 'Session expired.', [], 401)];
    }
    return ['session' => $row];
}
