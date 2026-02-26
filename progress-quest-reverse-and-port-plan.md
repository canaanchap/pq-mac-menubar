# Reverse + Understand + Port Progress Quest (via `pq-cli`)

## High-level: reverse it, understand it, then port it (starting from `pq-cli`)

1) **Get it running exactly as-is**
- Build/run `pq-cli` and confirm you can start a character, let it “tick,” and see logs change over time.
- Do *not* refactor yet. Your goal is a baseline you can trust.

2) **Identify the “spine” of execution**
- Find the main loop / tick function (the thing that advances time and decides “what happens next”).
- Write down: what inputs does it read (time, RNG, state), what outputs does it produce (state changes + log lines).

3) **Map the state (your Rosetta Stone)**
- Locate the core structs/records/classes that represent:
  - Character (level/xp/stats/class)
  - Inventory/equipment
  - Location / dungeon / encounter context
  - Timers/cooldowns
  - RNG seed/state (if present)
  - Flags/conditions (poisoned, resting, etc.)
- Make a one-page “State Map” doc: field names + meanings + ranges.

4) **Catalog the data tables**
- Find where lists live: classes, races, monsters, items, zones, name fragments, etc.
- Determine which are “pure data” vs “data with rules” (e.g., item tables that also imply drop logic).

5) **Trace the major subsystems (follow the tick)**
Work outward from the tick and map each subsystem as a black box:
- Encounter selection
- Combat resolution
- Loot/drop generation
- XP/leveling
- Shopping/gear decisions
- Rest/heal/mana regen

For each: write “Given state X and RNG Y, it does Z and emits messages M.”

6) **Make it observable (light instrumentation)**
- Add a debug flag that prints:
  - tick count / time
  - event chosen (combat/rest/shop/etc.)
  - key deltas (hp, xp, gold, items)
  - RNG rolls used (optional but *hugely* helpful)
- This turns “mystery behavior” into “auditable behavior.”

7) **Lock in determinism (so you can trust changes)**
- If possible, make RNG seedable and log the seed.
- Create 3–5 “golden runs”:
  - same seed + N ticks => same final summary + maybe same last 20 log lines
- This becomes your regression test suite.

8) **Build a glossary of messages**
- Centralize how messages are formed (format strings + tokens).
- Note which messages are purely cosmetic and which reveal logic branches you must preserve.

9) **Only then: start extracting**
- Once you can answer “what happens on a tick and why,” you’re ready to lift the logic into a clean core.

---

## Port structure that keeps you sane (steps only)

1) Create a Swift package with two targets:
   - `PQCore` (pure logic)
   - `PQCLI` (temporary: wires `PQCore` to the existing CLI-style output)

2) In `PQCore`, define **data-only** models first:
   - `GameState`, `Character`, `Inventory`, `Equipment`, `Location`, `Timers`, etc.

3) Add a single entry point for simulation:
   - `TickEngine.tick(state:inout GameState, rng:inout RNG) -> [GameEvent]`

4) Implement `RNG` as an injected dependency:
   - seedable
   - no global randomness inside subsystems

5) Move data tables into `PQCore` as read-only structures:
   - `Classes`, `Monsters`, `Items`, `Zones`
   - keep IDs stable (don’t rely on array order unless the original did)

6) Port subsystems one at a time behind small interfaces:
   - `EncounterSystem`
   - `CombatSystem`
   - `LootSystem`
   - `ProgressionSystem`
   - `TownSystem` (shop/repair/etc. if applicable)

7) Add **event logging as data**, not strings:
   - `enum GameEvent { case fought(...), foundItem(...), leveledUp(...) }`

8) Add a `TextRenderer` layer:
   - `GameEvent` -> string output
   - (this is where “faithful” phrasing lives)

9) Implement save/load last (but design for it early):
   - `SaveCodec.encode(GameState) -> Data`
   - `SaveCodec.decode(Data) -> GameState`

10) Build regression tests from your golden runs:
   - seed + ticks => final snapshot hash
   - (optionally) last N `GameEvent`s match

11) Only after `PQCore` is stable:
   - replace `PQCLI` with `PQMenuBarApp` using SwiftUI, keeping the same `PQCore` API.
