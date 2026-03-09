<?php
declare(strict_types=1);

$candidateRoots = [
    __DIR__,        // when deployed at domain root
    dirname(__DIR__) // when deployed from /public
];

$loaded = false;
foreach ($candidateRoots as $root) {
    $bootstrap = $root . '/src/bootstrap.php';
    $router = $root . '/src/router.php';
    if (is_file($bootstrap) && is_file($router)) {
        require_once $bootstrap;
        require_once $router;
        $loaded = true;
        break;
    }
}

if (!$loaded) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'ok' => false,
        'error' => [
            'code' => 'BOOTSTRAP_NOT_FOUND',
            'message' => 'Could not locate src/bootstrap.php and src/router.php.',
            'details' => [],
        ],
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$uri = $_SERVER['REQUEST_URI'] ?? '/';
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$allowedOrigin = env_value('PQ_ADMIN_UI_ORIGIN', 'https://admin.progressquest.me');
if ($origin !== '' && $origin === $allowedOrigin) {
    header('Access-Control-Allow-Origin: ' . $allowedOrigin);
    header('Access-Control-Allow-Headers: Content-Type, Authorization');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
}

if ($method === 'OPTIONS') {
    http_response_code(204);
    exit;
}

try {
    $route = route_request($method, $uri);
    http_response_code($route['status']);
    header('Content-Type: application/json');
    echo json_encode($route['body'], JSON_UNESCAPED_SLASHES);
} catch (RuntimeException $e) {
    $code = $e->getMessage();
    if ($code === 'INVALID_JSON_BODY') {
        http_response_code(400);
        header('Content-Type: application/json');
        echo json_encode(json_error('INVALID_JSON_BODY', 'Request body must be valid JSON.')['body'], JSON_UNESCAPED_SLASHES);
        exit;
    }
    if ($code === 'DB_NOT_CONFIGURED') {
        http_response_code(500);
        header('Content-Type: application/json');
        echo json_encode(json_error('DB_NOT_CONFIGURED', 'Database is not configured on server.')['body'], JSON_UNESCAPED_SLASHES);
        exit;
    }

    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(json_error('RUNTIME_ERROR', 'Unexpected runtime error.', ['reason' => $e->getMessage()])['body'], JSON_UNESCAPED_SLASHES);
} catch (Throwable $e) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(json_error('UNEXPECTED_ERROR', 'Unexpected server error.', ['reason' => $e->getMessage()])['body'], JSON_UNESCAPED_SLASHES);
}
