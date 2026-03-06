<?php
declare(strict_types=1);

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
        return [
            'status' => 200,
            'body' => json_success([
                'realms' => [[
                    'realmId' => env_value('PQ_REALM_ID', 'realm_global_1'),
                    'name' => env_value('PQ_REALM_NAME', 'The One Global Realm'),
                    'status' => 'active',
                    'supportsGuilds' => true,
                ]],
            ]),
        ];
    }

    $stubRoutes = [
        'POST /api/v1/account/register',
        'POST /api/v1/account/verify',
        'POST /api/v1/account/login',
        'POST /api/v1/characters/create-online',
        'POST /api/v1/guilds/create',
        'POST /api/v1/guilds/join',
        'POST /api/v1/guilds/leave',
        'POST /api/v1/characters/checkin',
    ];

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
