<?php
declare(strict_types=1);

final class AccountHandler {
    public static function register(array $body): array {
        $email = strtolower(trim((string)($body['email'] ?? '')));
        $password = (string)($body['password'] ?? '');
        $publicName = trim((string)($body['publicName'] ?? ''));
        $wantsNews = (bool)($body['wantsNews'] ?? false);

        if (!email_is_valid($email)) {
            return json_error('VALIDATION_EMAIL', 'A valid email is required.');
        }
        if (strlen($password) < 8) {
            return json_error('VALIDATION_PASSWORD', 'Password must be at least 8 characters.');
        }
        if ($publicName === '') {
            return json_error('VALIDATION_PUBLIC_NAME', 'Public name is required.');
        }

        $pdo = db();

        $stmt = $pdo->prepare('SELECT id FROM accounts WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        if ($stmt->fetch()) {
            return json_error('ACCOUNT_EXISTS', 'An account already exists for this email.', [], 409);
        }

        $now = now_utc();
        $accountUid = uid26();
        $passwordHash = password_hash($password, PASSWORD_DEFAULT);
        $verificationCode = sprintf('%06d', random_int(0, 999999));
        $verificationHash = password_hash($verificationCode, PASSWORD_DEFAULT);
        $expiresAt = gmdate('Y-m-d H:i:s', time() + 60 * 30);

        $pdo->beginTransaction();
        try {
            $insert = $pdo->prepare('
                INSERT INTO accounts (account_uid, email, password_hash, verified, public_name, wants_news, created_at, updated_at)
                VALUES (?, ?, ?, 0, ?, ?, ?, ?)
            ');
            $insert->execute([
                $accountUid,
                $email,
                $passwordHash,
                $publicName,
                $wantsNews ? 1 : 0,
                $now,
                $now,
            ]);
            $accountId = (int)$pdo->lastInsertId();

            $verifyInsert = $pdo->prepare('
                INSERT INTO account_verifications (account_id, code_hash, expires_at, used_at, created_at)
                VALUES (?, ?, ?, NULL, ?)
            ');
            $verifyInsert->execute([$accountId, $verificationHash, $expiresAt, $now]);

            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            return json_error('ACCOUNT_REGISTER_FAILED', 'Failed to create account.', ['reason' => $e->getMessage()], 500);
        }

        $data = [
            'accountId' => $accountUid,
            'email' => $email,
            'publicName' => $publicName,
            'verified' => false,
            'verificationRequired' => true,
            'verificationExpiresAt' => gmdate('c', strtotime($expiresAt)),
        ];

        if (env_bool('PQ_DEBUG_RETURN_VERIFY_CODE', false)) {
            $data['verificationCodeForDebug'] = $verificationCode;
        }

        return [
            'status' => 201,
            'body' => json_success($data),
        ];
    }

    public static function verify(array $body): array {
        $email = strtolower(trim((string)($body['email'] ?? '')));
        $code = trim((string)($body['code'] ?? ''));

        if (!email_is_valid($email)) {
            return json_error('VALIDATION_EMAIL', 'A valid email is required.');
        }
        if ($code === '') {
            return json_error('VALIDATION_CODE', 'Verification code is required.');
        }

        $pdo = db();

        $stmt = $pdo->prepare('SELECT id, account_uid FROM accounts WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $account = $stmt->fetch();
        if (!$account) {
            return json_error('ACCOUNT_NOT_FOUND', 'Account not found.', [], 404);
        }

        $verificationStmt = $pdo->prepare('
            SELECT id, code_hash, expires_at, used_at
            FROM account_verifications
            WHERE account_id = ?
            ORDER BY id DESC
            LIMIT 1
        ');
        $verificationStmt->execute([(int)$account['id']]);
        $verification = $verificationStmt->fetch();
        if (!$verification) {
            return json_error('VERIFY_CODE_NOT_FOUND', 'No verification code exists for this account.', [], 404);
        }
        if ($verification['used_at'] !== null) {
            return json_error('VERIFY_CODE_USED', 'This verification code has already been used.', [], 409);
        }
        if (strtotime((string)$verification['expires_at']) < time()) {
            return json_error('VERIFY_CODE_EXPIRED', 'Verification code has expired.', [], 409);
        }
        if (!password_verify($code, (string)$verification['code_hash'])) {
            return json_error('VERIFY_CODE_INVALID', 'Verification code is invalid.', [], 401);
        }

        $now = now_utc();
        $pdo->beginTransaction();
        try {
            $markUsed = $pdo->prepare('UPDATE account_verifications SET used_at = ? WHERE id = ?');
            $markUsed->execute([$now, (int)$verification['id']]);

            $verifyAccount = $pdo->prepare('UPDATE accounts SET verified = 1, updated_at = ? WHERE id = ?');
            $verifyAccount->execute([$now, (int)$account['id']]);

            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            return json_error('VERIFY_FAILED', 'Failed to verify account.', ['reason' => $e->getMessage()], 500);
        }

        return [
            'status' => 200,
            'body' => json_success([
                'accountId' => (string)$account['account_uid'],
                'verified' => true,
            ]),
        ];
    }

    public static function login(array $body): array {
        $email = strtolower(trim((string)($body['email'] ?? '')));
        $password = (string)($body['password'] ?? '');

        if (!email_is_valid($email)) {
            return json_error('VALIDATION_EMAIL', 'A valid email is required.');
        }
        if ($password === '') {
            return json_error('VALIDATION_PASSWORD', 'Password is required.');
        }

        $pdo = db();

        $stmt = $pdo->prepare('
            SELECT id, account_uid, email, password_hash, verified, public_name, wants_news
            FROM accounts
            WHERE email = ?
            LIMIT 1
        ');
        $stmt->execute([$email]);
        $account = $stmt->fetch();
        if (!$account || !password_verify($password, (string)$account['password_hash'])) {
            return json_error('LOGIN_INVALID', 'Invalid email or password.', [], 401);
        }
        if ((int)$account['verified'] !== 1) {
            return json_error('ACCOUNT_NOT_VERIFIED', 'Account is not verified yet.', [], 403);
        }

        $rawToken = secure_token(32);
        $tokenHash = token_hash($rawToken);
        $now = now_utc();
        $expiresAt = gmdate('Y-m-d H:i:s', time() + 60 * 60 * 24 * 14);

        try {
            $insert = $pdo->prepare('
                INSERT INTO account_sessions (account_id, session_token_hash, expires_at, revoked_at, created_at)
                VALUES (?, ?, ?, NULL, ?)
            ');
            $insert->execute([
                (int)$account['id'],
                $tokenHash,
                $expiresAt,
                $now,
            ]);
        } catch (Throwable $e) {
            return json_error('SESSION_CREATE_FAILED', 'Failed to create session.', ['reason' => $e->getMessage()], 500);
        }

        return [
            'status' => 200,
            'body' => json_success([
                'sessionToken' => $rawToken,
                'expiresAt' => gmdate('c', strtotime($expiresAt)),
                'account' => [
                    'accountId' => (string)$account['account_uid'],
                    'email' => (string)$account['email'],
                    'publicName' => (string)$account['public_name'],
                    'wantsNews' => ((int)$account['wants_news']) === 1,
                    'verified' => true,
                ],
            ]),
        ];
    }

    public static function session(array $body): array {
        $token = trim((string)($body['sessionToken'] ?? ''));
        if ($token === '') {
            return json_error('VALIDATION_SESSION_TOKEN', 'sessionToken is required.');
        }

        $pdo = db();
        $stmt = $pdo->prepare('
            SELECT s.expires_at, s.revoked_at, a.account_uid, a.email, a.public_name, a.wants_news, a.verified
            FROM account_sessions s
            JOIN accounts a ON a.id = s.account_id
            WHERE s.session_token_hash = ?
            LIMIT 1
        ');
        $stmt->execute([token_hash($token)]);
        $row = $stmt->fetch();
        if (!$row) {
            return json_error('SESSION_NOT_FOUND', 'Session not found.', [], 404);
        }
        if ($row['revoked_at'] !== null) {
            return json_error('SESSION_REVOKED', 'Session revoked.', [], 401);
        }
        if (strtotime((string)$row['expires_at']) < time()) {
            return json_error('SESSION_EXPIRED', 'Session expired.', [], 401);
        }

        return [
            'status' => 200,
            'body' => json_success([
                'expiresAt' => gmdate('c', strtotime((string)$row['expires_at'])),
                'account' => [
                    'accountId' => (string)$row['account_uid'],
                    'email' => (string)$row['email'],
                    'publicName' => (string)$row['public_name'],
                    'wantsNews' => ((int)$row['wants_news']) === 1,
                    'verified' => ((int)$row['verified']) === 1,
                ],
            ]),
        ];
    }
}
