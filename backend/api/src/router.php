<?php
declare(strict_types=1);

require_once __DIR__ . '/Handlers/AccountHandler.php';
require_once __DIR__ . '/Handlers/AdminHandler.php';
require_once __DIR__ . '/Handlers/GuildHandler.php';

function route_request(string $method, string $uri): array {
    $path = parse_url($uri, PHP_URL_PATH) ?? '/';

    if ($path === '/api/v1/health' && $method === 'GET') {
        return [
            'status' => 200,
            'body' => json_success([
                'service' => 'pq-multiplayer-api',
                'status' => 'ok',
                'time' => gmdate('c'),
            ]),
        ];
    }

    if ($path === '/api/v1/realms' && $method === 'GET') {
        ensure_default_realm_seeded();
        $pdo = db();
        $stmt = $pdo->query('
            SELECT realm_uid, name, status, supports_guilds
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
            ];
        }, $rows);
        return [
            'status' => 200,
            'body' => json_success([
                'realms' => $realms,
            ]),
        ];
    }

    if ($path === '/api/v1/account/register' && $method === 'POST') {
        return AccountHandler::register(parse_json_body());
    }

    if ($path === '/api/v1/account/verify' && $method === 'POST') {
        return AccountHandler::verify(parse_json_body());
    }

    if ($path === '/api/v1/account/login' && $method === 'POST') {
        return AccountHandler::login(parse_json_body());
    }

    if ($path === '/api/v1/account/session' && $method === 'POST') {
        return AccountHandler::session(parse_json_body());
    }

    if ($path === '/api/v1/account/settings' && $method === 'POST') {
        return AccountHandler::updateSettings(parse_json_body());
    }

    if ($path === '/api/v1/characters/create-online' && $method === 'POST') {
        return GuildHandler::createOnlineCharacter(parse_json_body());
    }

    if ($path === '/api/v1/guilds' && $method === 'GET') {
        return GuildHandler::listGuilds($_GET);
    }

    if ($path === '/api/v1/guilds/create' && $method === 'POST') {
        return GuildHandler::createGuild(parse_json_body());
    }

    if ($path === '/api/v1/guilds/join' && $method === 'POST') {
        return GuildHandler::joinGuild(parse_json_body());
    }

    if ($path === '/api/v1/guilds/leave' && $method === 'POST') {
        return GuildHandler::leaveGuild(parse_json_body());
    }

    if ($method === 'GET' && preg_match('#^/api/v1/guilds/([^/]+)$#', $path, $m)) {
        return GuildHandler::guildProfile($m[1]);
    }

    if ($method === 'GET' && preg_match('#^/api/v1/guilds/([^/]+)/logs$#', $path, $m)) {
        return GuildHandler::guildLogs($m[1]);
    }

    if ($path === '/api/v1/admin/login' && $method === 'POST') {
        return AdminHandler::login(parse_json_body());
    }

    if ($path === '/api/v1/admin/logout' && $method === 'POST') {
        return AdminHandler::logout();
    }

    if ($path === '/api/v1/admin/session' && $method === 'GET') {
        return AdminHandler::session();
    }

    if ($path === '/api/v1/admin/accounts' && $method === 'GET') {
        return AdminHandler::accounts();
    }

    if ($path === '/api/v1/admin/force-verify' && $method === 'POST') {
        return AdminHandler::forceVerify(parse_json_body());
    }

    if ($path === '/api/v1/admin/realms' && $method === 'GET') {
        return AdminHandler::realmsList();
    }

    if ($path === '/api/v1/admin/realms/create' && $method === 'POST') {
        return AdminHandler::realmsCreate(parse_json_body());
    }

    $stubRoutes = ['POST /api/v1/characters/checkin'];

    $routeKey = $method . ' ' . $path;
    if (in_array($routeKey, $stubRoutes, true) || preg_match('#^GET /api/v1/guilds/[^/]+$#', $routeKey) || preg_match('#^POST /api/v1/guilds/[^/]+/motions/create$#', $routeKey) || preg_match('#^POST /api/v1/guilds/[^/]+/motions/[^/]+/vote$#', $routeKey) || preg_match('#^POST /api/v1/guilds/[^/]+/presence$#', $routeKey)) {
        return [
            'status' => 501,
            'body' => [
                'ok' => false,
                'error' => [
                    'code' => 'NOT_IMPLEMENTED',
                    'message' => 'Route scaffold exists but is not implemented yet.',
                    'details' => ['route' => $routeKey],
                ],
            ],
        ];
    }

    return [
        'status' => 404,
        'body' => [
            'ok' => false,
            'error' => [
                'code' => 'NOT_FOUND',
                'message' => 'Route not found.',
                'details' => ['method' => $method, 'path' => $path],
            ],
        ],
    ];
}
