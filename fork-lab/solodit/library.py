"""Load curated Solodit PoC library (forge-verified entries only for execution)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
LIBRARY_PATH = ROOT / "library.json"


def load_library() -> dict[str, Any]:
    if not LIBRARY_PATH.exists():
        return {"verified": [], "incomplete_high_critical_fork_mentions": [], "verified_count": 0}
    return json.loads(LIBRARY_PATH.read_text(encoding="utf-8"))


def list_entries(*, verified_only: bool = True) -> list[dict[str, Any]]:
    lib = load_library()
    if verified_only:
        return [e for e in lib.get("verified", []) if e.get("status") == "forge_verified"]
    return list(lib.get("verified", []))


def get_entry(poc_id: str) -> dict[str, Any] | None:
    lib = load_library()
    for e in lib.get("verified", []):
        if e.get("id") == poc_id:
            return e
    return None


def load_poc_solidity(poc_id: str) -> str:
    entry = get_entry(poc_id)
    if not entry:
        raise FileNotFoundError(f"unknown solodit poc id: {poc_id}")
    if entry.get("status") != "forge_verified":
        raise RuntimeError(
            f"refusing to run non-verified Solodit entry {poc_id} (status={entry.get('status')})"
        )
    path = ROOT / entry["sol_file"]
    if not path.exists():
        raise FileNotFoundError(f"missing PoC file: {path}")
    return path.read_text(encoding="utf-8")
