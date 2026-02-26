# Implementation Plan (Draft + Active Work)

## What exists now
- `Package.swift` with:
  - `PQCore` library target
  - `PQMenuBarApp` executable target (macOS 15+)
- Core model/runtime scaffolding:
  - `GameState`, `Character`, `GameEvent`
  - Tick loop placeholder (`TickEngine`)
  - JSON save store (`~/.pq-menubar/saves/current.json`)
  - JSONL event logs (`~/.pq-menubar/logs/events-YYYY-MM-DD.jsonl`)
  - Data directory bootstrap (`data/`, `saves/`, `logs/`, `mods/`)
- Menubar app shell:
  - Accessory app policy (non-dock, low-priority posture)
  - Summary popover
  - Dashboard window with tabs (Overview/Log/Character/Data-Mods/Settings)
  - Low CPU mode toggle
  - Sleep/wake pause + resume hooks
- Legacy bridge scaffolding:
  - Python helper placeholder for `pkl <-> json` conversion

## Next milestones to code (immediate)
1. Replace placeholder tick logic with parity `pq-cli` tick/dequeue logic in `PQCore`.
2. Add deterministic RNG and seed plumbing in `PQCore`.
3. Add JSON data-table loader and schema validators from `~/.pq-menubar/data`.
4. Implement real import/export flows in UI:
   - Import `.json` + `.pkl`
   - Export `.json` + optional `.pkl`
5. Implement dashboard second-click opening behavior from the status item.
6. Add compact status rendering with tiny inline progress bar.
7. Add feature flags for post-parity behavior changes.

## Known gaps
- Build verification currently blocked in this environment by Swift SDK/toolchain mismatch.
- `convert_pkl.py` is intentionally placeholder and not yet mapped to `pq-cli` object schema.
- Menubar second-click -> dashboard flow is not yet wired.
- Real roster management and character switching are not yet implemented.
