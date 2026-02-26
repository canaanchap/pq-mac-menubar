# Build Quickstart

## One-time setup
1. Run:
   ```bash
   ./scripts/dev-setup.sh
   ```
2. If you see Swift SDK/toolchain mismatch errors, switch developer dir:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
   or back to CLT:
   ```bash
   sudo xcode-select -s /Library/Developer/CommandLineTools
   ```

## Normal build loop
1. Build with workspace-local caches:
   ```bash
   ./scripts/dev-build.sh
   ```
2. Run app from package:
   ```bash
   ./scripts/dev-build.sh && swift run PQMenuBarApp
   ```

## Refresh bundled game data from pq-cli source
```bash
./scripts/export_pqcli_data.py
```

This rewrites:
- `Sources/PQMenuBarApp/Resources/data/default-data.json`

## Notes
- Local cache paths are under `.build/` to avoid sandbox/home-cache restrictions.
- Legacy import/export supports `.pkl` and `.pqw` through the Python bridge.
