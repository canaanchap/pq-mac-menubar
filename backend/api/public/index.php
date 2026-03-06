<?php
declare(strict_types=1);

require_once __DIR__ . '/../src/bootstrap.php';
require_once __DIR__ . '/../src/router.php';

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$uri = $_SERVER['REQUEST_URI'] ?? '/';

$route = route_request($method, $uri);
http_response_code($route['status']);
header('Content-Type: application/json');
echo json_encode($route['body'], JSON_UNESCAPED_SLASHES);
