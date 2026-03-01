#!/usr/bin/env python3
"""Bridge script for pq-cli/object pickle <-> pq-menubar JSON.

Usage:
  python3 convert_pkl.py import <input.pkl|input.pqw> <output.json>
  python3 convert_pkl.py export <input.json> <output.pkl|output.pqw>
"""

from __future__ import annotations

import json
import pickle
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PQCLI_ROOT = ROOT / "pq-cli"
if str(PQCLI_ROOT) not in sys.path:
    sys.path.insert(0, str(PQCLI_ROOT))


def _stat_values(stats: Any) -> dict[str, int]:
    result: dict[str, int] = {}
    try:
        for stat, value in stats:
            key = getattr(stat, "value", str(stat))
            result[str(key)] = int(value)
    except Exception:
        # Fallback for unknown structure
        result = dict(getattr(stats, "_values", {}))
    return result


def _convert_player(player: Any) -> dict[str, Any]:
    task = getattr(player, "task", None)
    quest_book = getattr(player, "quest_book", None)

    inventory = getattr(player, "inventory", None)
    inv_items = []
    if inventory is not None:
        for item in getattr(inventory, "_items", []):
            inv_items.append({"name": item.name, "quantity": int(item.quantity)})

    spells = []
    spell_book = getattr(player, "spell_book", None)
    if spell_book is not None:
        for spell in getattr(spell_book, "_spells", []):
            spells.append({"name": spell.name, "level": int(spell.level)})

    equipment = {}
    eq = getattr(player, "equipment", None)
    if eq is not None:
        raw_items = getattr(eq, "_items", {})
        for key, value in raw_items.items():
            equipment[getattr(key, "value", str(key))] = value

    queue_items = []
    for t in getattr(player, "queue", []):
        queue_items.append(
            {
                "kind": t.__class__.__name__.replace("Task", "").lower() or "regular",
                "description": getattr(t, "description", ""),
                "duration": float(getattr(t, "duration", 0)),
                "monster": _convert_monster(getattr(t, "monster", None)),
            }
        )

    return {
        "name": getattr(player, "name", "Imported Hero"),
        "birthday": getattr(getattr(player, "birthday", None), "isoformat", lambda: None)(),
        "race": getattr(getattr(player, "race", None), "name", "Unknown"),
        "characterClass": getattr(getattr(player, "class_", None), "name", "Unknown"),
        "stats": _stat_values(getattr(player, "stats", [])),
        "elapsed": float(getattr(player, "elapsed", 0)),
        "level": int(getattr(player, "level", 1)),
        "expBar": {
            "max": float(getattr(getattr(player, "exp_bar", None), "max_", 1)),
            "position": float(getattr(getattr(player, "exp_bar", None), "position", 0)),
        },
        "questBook": {
            "act": int(getattr(quest_book, "act", 0)) if quest_book else 0,
            "quests": list(getattr(quest_book, "quests", [])) if quest_book else [],
            "plotBar": {
                "max": float(getattr(getattr(quest_book, "plot_bar", None), "max_", 1)) if quest_book else 1,
                "position": float(getattr(getattr(quest_book, "plot_bar", None), "position", 0)) if quest_book else 0,
            },
            "questBar": {
                "max": float(getattr(getattr(quest_book, "quest_bar", None), "max_", 1)) if quest_book else 1,
                "position": float(getattr(getattr(quest_book, "quest_bar", None), "position", 0)) if quest_book else 0,
            },
            "monster": _convert_monster(getattr(quest_book, "monster", None)) if quest_book else None,
        },
        "inventoryGold": int(getattr(inventory, "gold", 0)) if inventory else 0,
        "inventoryItems": inv_items,
        "inventoryCapacity": int(getattr(getattr(inventory, "encum_bar", None), "max_", 0)) if inventory else 0,
        "equipment": equipment,
        "bestEquipment": getattr(eq, "best", "") if eq else "",
        "spells": spells,
        "taskBar": {
            "max": float(getattr(getattr(player, "task_bar", None), "max_", 1)),
            "position": float(getattr(getattr(player, "task_bar", None), "position", 0)),
        },
        "task": _convert_task(task),
        "queue": queue_items,
    }


def _convert_task(task: Any) -> dict[str, Any] | None:
    if task is None:
        return None
    return {
        "kind": task.__class__.__name__.replace("Task", "").lower() or "regular",
        "description": getattr(task, "description", ""),
        "duration": float(getattr(task, "duration", 0)),
        "monster": _convert_monster(getattr(task, "monster", None)),
    }


def _convert_monster(monster: Any) -> dict[str, Any] | None:
    if monster is None:
        return None
    try:
        d = asdict(monster)
        return {"name": d.get("name"), "level": int(d.get("level", 0)), "item": d.get("item")}
    except Exception:
        return {
            "name": getattr(monster, "name", "Unknown"),
            "level": int(getattr(monster, "level", 0)),
            "item": getattr(monster, "item", None),
        }


def run_import(input_path: Path, output_path: Path) -> int:
    with input_path.open("rb") as f:
        obj = pickle.load(f)

    payload: dict[str, Any] = {"source": input_path.name}

    # pq-cli save files are usually a list of players.
    if isinstance(obj, list) and obj:
        payload["players"] = [_convert_player(p) for p in obj]
    elif isinstance(obj, dict):
        # App-exported pickle may contain canonical JSON already.
        if "activeCharacter" in obj and isinstance(obj["activeCharacter"], dict):
            payload["players"] = [obj["activeCharacter"]]
        elif "players" in obj and isinstance(obj["players"], list):
            payload["players"] = obj["players"]
        elif "characters" in obj and isinstance(obj["characters"], list):
            payload["players"] = obj["characters"]
        elif "name" in obj and "stats" in obj:
            payload["players"] = [obj]
        else:
            payload["raw"] = repr(obj)
    else:
        payload["raw"] = repr(obj)

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    return 0


def run_export(input_path: Path, output_path: Path) -> int:
    with input_path.open("r", encoding="utf-8") as f:
        obj = json.load(f)

    # Raw export for now; Swift app converts canonical save to this shape before calling export.
    with output_path.open("wb") as f:
        pickle.dump(obj, f)

    return 0


def main() -> int:
    if len(sys.argv) != 4:
        print("Usage: convert_pkl.py <import|export> <input> <output>", file=sys.stderr)
        return 2

    mode = sys.argv[1]
    input_path = Path(sys.argv[2])
    output_path = Path(sys.argv[3])

    if mode == "import":
        return run_import(input_path, output_path)
    if mode == "export":
        return run_export(input_path, output_path)

    print("Expected mode import|export", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
