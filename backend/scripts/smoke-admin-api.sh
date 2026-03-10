#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this script." >&2
  exit 1
fi

API_BASE="${API_BASE:-https://api.progressquest.me/api/v1}"
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASS="${ADMIN_PASS:-}"
TEST_EMAIL="${TEST_EMAIL:-smoke-$(date +%s)@example.com}"
TEST_PASSWORD="${TEST_PASSWORD:-testpass123}"
TEST_PUBLIC_NAME="${TEST_PUBLIC_NAME:-SmokeTester}"

if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
  echo "Set ADMIN_USER and ADMIN_PASS env vars first." >&2
  exit 1
fi
if [[ "$ADMIN_USER" == "YOUR_ADMIN_USER" || "$ADMIN_PASS" == "YOUR_ADMIN_PASS" ]]; then
  echo "Replace placeholder admin credentials with real values." >&2
  exit 1
fi

echo "==> Health"
curl -sS "$API_BASE/health" | jq .

echo "==> Register test account"
curl -sS -X POST "$API_BASE/account/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\",\"publicName\":\"$TEST_PUBLIC_NAME\",\"wantsNews\":true}" | jq .

echo "==> Admin login"
ADMIN_TOKEN="$(curl -sS -X POST "$API_BASE/admin/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" | jq -r '.data.token' | tr -d '\r\n')"

if [[ -z "$ADMIN_TOKEN" || "$ADMIN_TOKEN" == "null" ]]; then
  echo "Failed to get admin token." >&2
  exit 1
fi
echo "Token acquired."

echo "==> Force verify test account"
curl -sS -X POST "$API_BASE/admin/force-verify" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d "{\"email\":\"$TEST_EMAIL\"}" | jq .

echo "==> Login verified test account"
LOGIN_JSON="$(curl -sS -X POST "$API_BASE/account/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")"
echo "$LOGIN_JSON" | jq .
SESSION_TOKEN="$(echo "$LOGIN_JSON" | jq -r '.data.sessionToken')"
if [[ -z "$SESSION_TOKEN" || "$SESSION_TOKEN" == "null" ]]; then
  echo "Failed to get user session token after force verify." >&2
  exit 1
fi

echo "==> Admin accounts list"
curl -sS "$API_BASE/admin/accounts?limit=20" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq .

echo "==> Admin realms list (should include Goobland seed)"
curl -sS "$API_BASE/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq .

echo "==> User session check"
curl -sS -X POST "$API_BASE/account/session" \
  -H "Content-Type: application/json" \
  -d "{\"sessionToken\":\"$SESSION_TOKEN\"}" | jq .

echo "==> Done."
