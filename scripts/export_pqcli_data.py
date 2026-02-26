#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from dataclasses import asdict, is_dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PQCLI_ROOT = ROOT / "pq-cli"
if str(PQCLI_ROOT) not in sys.path:
    sys.path.insert(0, str(PQCLI_ROOT))

from pqcli import config  # type: ignore


def maybe_asdict(x):
    if is_dataclass(x):
        d = asdict(x)
        for k, v in list(d.items()):
            if isinstance(v, list):
                d[k] = [vv.value if hasattr(vv, "value") else vv for vv in v]
            elif hasattr(v, "value"):
                d[k] = v.value
        return d
    if hasattr(x, "value"):
        return x.value
    return x


def export(target: Path) -> None:
    payload = {
        "spells": config.SPELLS,
        "offenseAttrib": [maybe_asdict(x) for x in config.OFFENSE_ATTRIB],
        "defenseAttrib": [maybe_asdict(x) for x in config.DEFENSE_ATTRIB],
        "offenseBad": [maybe_asdict(x) for x in config.OFFENSE_BAD],
        "defenseBad": [maybe_asdict(x) for x in config.DEFENSE_BAD],
        "shields": [maybe_asdict(x) for x in config.SHIELDS],
        "armors": [maybe_asdict(x) for x in config.ARMORS],
        "weapons": [maybe_asdict(x) for x in config.WEAPONS],
        "specials": config.SPECIALS,
        "itemAttrib": config.ITEM_ATTRIB,
        "itemOfs": config.ITEM_OFS,
        "boringItems": config.BORING_ITEMS,
        "monsters": [maybe_asdict(x) for x in config.MONSTERS],
        "races": [maybe_asdict(x) for x in config.RACES],
        "classes": [maybe_asdict(x) for x in config.CLASSES],
        "titles": config.TITLES,
        "impressiveTitles": config.IMPRESSIVE_TITLES,
        "primeStats": [s.value for s in config.PRIME_STATS],
        "equipmentTypes": [x.value for x in config.EquipmentType],
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    out = ROOT / "Sources/PQMenuBarApp/Resources/data/default-data.json"
    if len(sys.argv) > 1:
        out = Path(sys.argv[1]).resolve()
    export(out)
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
