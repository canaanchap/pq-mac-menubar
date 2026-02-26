#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p .build/.module-cache .build/.swiftpm-cache .build/.clang-cache

export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/.module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/.clang-cache"
export SWIFTPM_ENABLE_PLUGINS=0

# Local package cache to avoid inaccessible home cache paths.
swift build \
  --scratch-path "$ROOT_DIR/.build" \
  --cache-path "$ROOT_DIR/.build/.swiftpm-cache" \
  "$@"
