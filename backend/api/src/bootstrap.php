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
