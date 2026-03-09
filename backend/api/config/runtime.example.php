<?php
declare(strict_types=1);

// Copy to runtime.php and fill in real values on the server.
// Do NOT commit runtime.php with real credentials.
return [
    'PQ_REALM_ID' => 'realm_goobland_1',
    'PQ_REALM_NAME' => 'Goobland',
    'PQ_DB_HOST' => 'db.progressquest.me',
    'PQ_DB_PORT' => '3306',
    'PQ_DB_NAME' => 'pq_multiplayer',
    'PQ_DB_USER' => 'pq_multi_user',
    'PQ_DB_PASS' => 'replace_me',
    'PQ_DEBUG_RETURN_VERIFY_CODE' => 'true',
    'PQ_ADMIN_USER' => 'admin',
    'PQ_ADMIN_PASS' => 'replace_me_admin',
    'PQ_ADMIN_UI_ORIGIN' => 'https://admin.progressquest.me',
];
