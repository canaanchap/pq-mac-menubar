<?php
declare(strict_types=1);

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
