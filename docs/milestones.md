# pq-menubar Milestones

## M0 - Foundation (in progress)
- Create macOS 15+ Swift package with `PQCore` and `PQMenuBarApp` targets.
- Define user data root at `~/.pq-menubar/` with `data/`, `saves/`, `logs/`, `mods/`.
- Add canonical JSON save/log structures.
- Add background simulation runtime with low-impact scheduling.
- Add menubar shell (compact mode placeholder + summary popover + dashboard window).

## M1 - Parity Spine Port
- Port the `Simulation.tick` and `dequeue` behavior from `pq-cli` into `PQCore`.
- Keep deterministic RNG injectable and seedable.
- Add event model (`GameEvent`) and text renderer for parity messaging.
- Add snapshot-based regression harness for seed + ticks.

## M2 - Data-Driven Content
- Move all classes/races/monsters/items/spells/messages into JSON under `~/.pq-menubar/data/`.
- Support base bundled data + user override layer from `mods/`.
- Add schema validation and startup diagnostics surfaced in dashboard `Data/Mods` tab.

## M3 - Save/Import/Export
- Canonical save file format: JSON.
- Add `Import Character...` for `.json` and `.pkl`.
- Add `Export Character...` for `.json` and optional `.pkl`.
- Implement `.pkl` conversion bridge (Python helper) for manual compatibility.

## M4 - Menubar + Dashboard UX
- Menubar status: icon + level + tiny progress bar with percent.
- First click: summary popover.
- Second click opens persistent dashboard utility window.
- Dashboard tabs: Overview, Log, Character, Data/Mods, Settings.

## M5 - Performance + Sleep/Wake
- Ensure true pause on sleep; resume on wake with no catch-up.
- Keep app non-disruptive (`accessory` policy, background QoS, timer tolerance).
- Add `Low CPU mode` toggle to reduce tick/update cadence.

## M6 - Polish
- Replace placeholder icon with provided SVG assets.
- Add integration tests for save/load/import/export.
- Package local app build flow; signing/notarization deferred.
