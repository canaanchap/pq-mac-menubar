# Modding Instructions (v1)

This app supports drop-in JSON mods from:

- `~/.pq-menubar/mods/`

Each mod file must be named after a top-level key from `default-data.json`, for example:

- `monsters.json`
- `titles.json`
- `weapons.json`
- `classes.json`

The file content must be a top-level JSON array.

## Behavior

For each entry in your mod array:

- `include` (optional, default `true`)
  - `false` means remove/omit this entry from runtime data.
- `mask` (optional, default `false`)
  - `true` means replace existing matching entry by name/value.

If neither `mask` nor `include: false` is used:

- New entries are appended only if they do not already exist.
- Existing matching entries are left unchanged.

## Matching Rules

- Object lists (like `monsters`, `weapons`, `classes`) match by `name` (case-insensitive).
- String lists (like `titles`, `spells`, `itemAttrib`) match by string value (case-insensitive).

## JSON Notes

- Use valid JSON booleans: `true` / `false` (lowercase).
- Do not use `TRUE` / `FALSE`.

## Examples

### 1) Add-only monster mod (`monsters.json`)

```json
[
  {
    "name": "Moakum",
    "level": 999,
    "item": "frenum"
  },
  {
    "name": "New Monster",
    "level": 12,
    "item": "jaw"
  }
]
```

Result:
- `Moakum` unchanged if already present.
- `New Monster` added if not present.

### 2) Replace existing monster + add new (`mask: true`)

```json
[
  {
    "name": "Moakum",
    "level": 999,
    "item": "frenum",
    "mask": true
  },
  {
    "name": "New Monster",
    "level": 12,
    "item": "jaw"
  }
]
```

Result:
- Existing `Moakum` replaced.
- `New Monster` added if missing.

### 3) Remove/omit an entry (`include: false`)

For object list:

```json
[
  {
    "name": "Moakum",
    "include": false
  }
]
```

For string list (example `titles.json`):

```json
[
  {
    "value": "Destroyer",
    "include": false
  }
]
```

## Supported Keys

- `spells`
- `offenseAttrib`
- `defenseAttrib`
- `offenseBad`
- `defenseBad`
- `shields`
- `armors`
- `weapons`
- `specials`
- `itemAttrib`
- `itemOfs`
- `boringItems`
- `monsters`
- `races`
- `classes`
- `titles`
- `impressiveTitles`
- `primeStats`
- `equipmentTypes`

## Reloading Mods

- Use the in-app **Reload Data (+Mods)** button in Settings.
- Mods are also loaded at app startup.

