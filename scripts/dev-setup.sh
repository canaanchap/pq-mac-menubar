#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Checking toolchain"
if ! command -v xcode-select >/dev/null 2>&1; then
  echo "xcode-select not found; install Xcode command line tools." >&2
  exit 1
fi

DEVELOPER_DIR_CURRENT="$(xcode-select -p || true)"
echo "Current developer dir: ${DEVELOPER_DIR_CURRENT}"

echo "==> Suggested fix for SDK/toolchain mismatch"
echo "If build fails with Swift SDK mismatch, run one of:"
echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
echo "  sudo xcode-select -s /Library/Developer/CommandLineTools"
echo "Then re-run: ./scripts/dev-build.sh"

echo "==> Preparing local cache paths in workspace"
mkdir -p .build/.module-cache .build/.swiftpm-cache .build/.clang-cache

echo "Setup complete."
