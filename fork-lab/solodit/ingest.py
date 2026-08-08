#!/usr/bin/env python3
"""Ingest Solodit content. Severities: Critical, High, Medium.

Promote to library.verified only after forge_verified.
Optional: CYFRIN_API_KEY + --api for live Solodit search cache.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIBRARY = ROOT / "library.json"
CACHE = ROOT / "api_cache.json"
CONTENT_DIR = Path(os.environ.get("SOLODIT_CONTENT_DIR", "/tmp/solodit_content"))
SEVS = ("Critical Risk", "High Risk", "Medium Risk")


def ensure_content_clone() -> Path:
    if (CONTENT_DIR / "reports").is_dir():
        return CONTENT_DIR
    CONTENT_DIR.parent.mkdir(parents=True, exist_ok=True)
    if CONTENT_DIR.exists():
        subprocess.check_call(["git", "-C", str(CONTENT_DIR), "pull", "--ff-only"])
    else:
        subprocess.check_call(
            ["git", "clone", "--depth", "1", "https://github.com/solodit/solodit_content.git", str(CONTENT_DIR)]
        )
    return CONTENT_DIR


def fetch_api(keywords: str, impact: list[str] | None = None, page_size: int = 20) -> dict:
    key = os.environ.get("CYFRIN_API_KEY") or os.environ.get("SOLODIT_API_KEY")
    if not key:
        raise RuntimeError("Set CYFRIN_API_KEY")
    body = {
        "page": 1,
        "pageSize": page_size,
        "filters": {
            "keywords": keywords,
            "impact": impact or ["HIGH", "MEDIUM", "CRITICAL"],
            "sortField": "Quality",
            "sortDirection": "Desc",
        },
    }
    req = urllib.request.Request(
        "https://solodit.cyfrin.io/api/v1/solodit/findings",
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Cyfrin-API-Key": key,
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", action="store_true")
    ap.add_argument("--keywords", default="reentrancy")
    args = ap.parse_args()
    ensure_content_clone()
    if LIBRARY.exists():
        lib = json.loads(LIBRARY.read_text())
        lib["severities"] = list(SEVS)
        LIBRARY.write_text(json.dumps(lib, indent=2) + "\n")
    if args.api:
        CACHE.write_text(json.dumps(fetch_api(args.keywords), indent=2)[:2_000_000])
        print(f"api cache -> {CACHE}")
    else:
        print("ok (Critical/High/Medium). use --api with CYFRIN_API_KEY for live pull")
    return 0


if __name__ == "__main__":
    sys.exit(main())
