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
