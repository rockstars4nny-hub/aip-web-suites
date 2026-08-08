#!/usr/bin/env python3
"""Execute real Foundry fork tests. No mainnet broadcast."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
TEMPLATE = ROOT / "workspace-template"
FORGE = os.environ.get("FORGE_BIN") or shutil.which("forge") or str(Path.home() / ".foundry/bin/forge")
CAST = os.environ.get("CAST_BIN") or shutil.which("cast") or str(Path.home() / ".foundry/bin/cast")

BROADCAST_BAN = re.compile(
    r"\b(vm\.broadcast|vm\.startBroadcast|vm\.stopBroadcast|broadcast\s*\()\b",
    re.I,
)
ADDRESS_RE = re.compile(r"^0x[a-fA-F0-9]{40}$")

def _strip_solidity_comments(src: str) -> str:
    """Remove // and /* */ comments so policy checks ignore docs like 'no vm.broadcast'."""
    # block comments
    out = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    # line comments
    out = re.sub(r"//.*?$", "", out, flags=re.M)
    return out


def _has_broadcast_code(src: str) -> bool:
    return bool(BROADCAST_BAN.search(_strip_solidity_comments(src or "")))



FULL_SUITE_PATH = ROOT / "templates" / "AipFullForkSuite.t.sol"

DEFAULT_POC = '''// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
/// Custom PoC — runs IN ADDITION to AipFullForkSuite
contract AipCustomPoC is Test {{
    address constant TARGET = {target_addr};
    function test_Custom_TargetAlive() public view {{
        assertGt(TARGET.code.length, 0, "custom: no code");
    }}
}}
'''


def render_full_suite(target_addr: str) -> str:
    raw = FULL_SUITE_PATH.read_text(encoding="utf-8")
    if not ADDRESS_RE.match(target_addr):
        raise ValueError("full suite requires a valid 0x address")
    return raw.replace("__TARGET__", target_addr)



def default_rpc() -> str:
    return (
        os.environ.get("ETH_RPC_URL")
        or os.environ.get("MAINNET_RPC_URL")
        or "https://ethereum.publicnode.com"
    ).strip()


def redact_rpc(url: str) -> str:
    if not url:
        return ""
    # hide API keys in path/query
    return re.sub(r"(api[_-]?key=)[^&]+", r"\1***", url, flags=re.I)


def _run(cmd: list[str], cwd: Path | None = None, timeout: int = 180) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["PATH"] = str(Path.home() / ".foundry/bin") + os.pathsep + env.get("PATH", "")
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )


def health() -> dict[str, Any]:
    forge_ok = Path(FORGE).exists() or bool(shutil.which("forge"))
    cast_ok = Path(CAST).exists() or bool(shutil.which("cast"))
    rpc = default_rpc()
    block = None
    rpc_ok = False
    err = None
    if rpc:
        try:
            p = _run([CAST, "block-number", "--rpc-url", rpc], timeout=30)
            if p.returncode == 0:
                block = (p.stdout or "").strip()
                rpc_ok = True
            else:
                err = (p.stderr or p.stdout or "rpc failed").strip()[:300]
        except Exception as e:
            err = str(e)
    return {
        "ok": forge_ok and cast_ok and rpc_ok,
        "forge": forge_ok,
        "cast": cast_ok,
        "rpc_configured": bool(rpc),
        "rpc_ok": rpc_ok,
        "rpc_redacted": redact_rpc(rpc),
        "block": block,
        "error": err,
        "policy": "FORK_EXECUTED_ONLY",
    }


def inspect_address(address: str, rpc: str | None = None, block: str | None = None) -> dict[str, Any]:
    addr = (address or "").strip()
    if not ADDRESS_RE.match(addr):
        return {"ok": False, "error": "invalid address"}
    rpc_url = (rpc or default_rpc()).strip()
    cast_args_base = ["--rpc-url", rpc_url]
    if block:
        cast_args_base += ["--block", str(block)]

    def cast_out(args: list[str]) -> str:
        p = _run([CAST, *args, *cast_args_base], timeout=60)
        if p.returncode != 0:
            raise RuntimeError((p.stderr or p.stdout or "cast failed").strip()[:400])
        return (p.stdout or "").strip()

    try:
        code = cast_out(["code", addr])
        bal = cast_out(["balance", addr])
        # EIP-1967 implementation / admin slots
        impl_slot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
        admin_slot = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
        impl = cast_out(["storage", addr, impl_slot])
        admin = cast_out(["storage", addr, admin_slot])
        code_len = max(0, (len(code) - 2) // 2) if code.startswith("0x") else 0
        return {
            "ok": True,
            "address": addr,
            "rpc_redacted": redact_rpc(rpc_url),
            "block": block or "latest",
            "balance_wei": bal,
            "code_bytes": code_len,
            "is_contract": code_len > 0,
            "eip1967_implementation_slot": impl,
            "eip1967_admin_slot": admin,
            "attestation": "FORK_READ_OK" if code or bal else "FORK_READ_EMPTY",
        }
    except Exception as e:
        return {"ok": False, "error": str(e), "rpc_redacted": redact_rpc(rpc_url)}


def _prepare_workspace(*, full_suite: str, custom: str | None = None) -> Path:
    if not TEMPLATE.exists():
        raise RuntimeError(f"missing template at {TEMPLATE}")
    if not FULL_SUITE_PATH.exists():
        raise RuntimeError(f"missing full suite at {FULL_SUITE_PATH}")
    work = Path(tempfile.mkdtemp(prefix="aip-fork-"))
    for name in ("foundry.toml", "lib", "src", "test", "script"):
        src = TEMPLATE / name
        dst = work / name
        if src.is_dir():
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns("out", "cache", ".git"))
        elif src.exists():
            shutil.copy2(src, dst)
    test_dir = work / "test"
    if test_dir.exists():
        for f in test_dir.glob("*.sol"):
            f.unlink()
    else:
        test_dir.mkdir(parents=True)
    (test_dir / "AipFullForkSuite.t.sol").write_text(full_suite, encoding="utf-8")
    if custom and custom.strip():
        (test_dir / "AipCustomPoC.t.sol").write_text(custom, encoding="utf-8")
    return work


def _parse_forge_counts(text: str) -> dict:
    # e.g. "1 tests passed, 0 failed, 0 skipped (1 total tests)"
    # or "Suite result: ok. 1 passed; 0 failed; 0 skipped"
    passed = failed = skipped = total = None
    m = re.search(
        r"(\d+)\s+tests?\s+passed,\s+(\d+)\s+failed,\s+(\d+)\s+skipped\s+\((\d+)\s+total",
        text,
        re.I,
    )
    if m:
        passed, failed, skipped, total = map(int, m.groups())
    else:
        m2 = re.search(r"(\d+)\s+passed;\s+(\d+)\s+failed;\s+(\d+)\s+skipped", text, re.I)
        if m2:
            passed, failed, skipped = map(int, m2.groups())
            total = passed + failed + skipped
    # individual results
    pass_names = re.findall(r"\[PASS\]\s+(\S+)", text)
    fail_names = re.findall(r"\[FAIL[^\]]*\]\s+(\S+)", text)
    return {
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "total": total,
        "pass_names": pass_names,
        "fail_names": fail_names,
    }


def run_fork(
    *,
    address: str | None = None,
    solidity: str | None = None,
    rpc: str | None = None,
    block: str | int | None = None,
    timeout: int = 600,
) -> dict[str, Any]:
    t0 = time.time()
    rpc_url = (rpc or default_rpc()).strip()
    if not rpc_url:
        return {"ok": False, "error": "ETH_RPC_URL not configured"}

    addr = (address or "").strip()
    if addr and not ADDRESS_RE.match(addr):
        return {"ok": False, "error": "invalid address"}

    if not addr:
        return {
            "ok": False,
            "error": "address required — full fork suite needs a contract 0x address",
            "attestation": "REJECTED_NO_ADDRESS",
        }

    # Address-only is enough. Full suite is always injected server-side.
    # Custom solidity is OPTIONAL and ignored when empty / is the full suite preview.
    custom = (solidity or "").strip()
    if custom:
        if "contract AipFullForkSuite" in custom:
            custom = ""
        elif _has_broadcast_code(custom):
            return {
                "ok": False,
                "error": "REJECTED: custom solidity contains live vm.broadcast / startBroadcast. Comments mentioning broadcast are OK; executable broadcast is not.",
                "attestation": "REJECTED_BROADCAST",
            }

    try:
        full_suite = render_full_suite(addr)
    except Exception as e:
        return {"ok": False, "error": str(e), "attestation": "FORK_ERROR"}

    # pin block if not provided
    pinned = str(block).strip() if block not in (None, "") else ""
    if not pinned:
        p = _run([CAST, "block-number", "--rpc-url", rpc_url], timeout=30)
        if p.returncode != 0:
            return {"ok": False, "error": f"cannot read block number: {(p.stderr or p.stdout)[:300]}"}
        pinned = (p.stdout or "").strip()

    work = None
    try:
        work = _prepare_workspace(full_suite=full_suite, custom=custom or None)
        cmd = [
            FORGE,
            "test",
            "--fork-url",
            rpc_url,
            "--fork-block-number",
            pinned,
            "-vvv",
        ]
        proc = _run(cmd, cwd=work, timeout=timeout)
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        combined = (stdout + "\n" + stderr).strip()
        passed = proc.returncode == 0 and ("Suite result: ok" in combined or "PASS" in combined or "passed" in combined.lower())
        # forge returns 0 on pass
        if proc.returncode == 0:
            passed = True
        counts = _parse_forge_counts(combined)
        artifact = {
            "ok": passed,
            "attestation": "FORK_EXECUTED" if passed else "FORK_FAILED",
            "exit_code": proc.returncode,
            "rpc_redacted": redact_rpc(rpc_url),
            "fork_block": pinned,
            "address": addr or None,
            "duration_ms": int((time.time() - t0) * 1000),
            "stdout": stdout[-200000:],
            "stderr": stderr[-60000:],
            "solidity_sha256": hashlib.sha256((full_suite + "\n" + (custom or "")).encode()).hexdigest(),
            "command": "forge test --fork-url <RPC> --fork-block-number " + pinned + " -vvv  # FULL SUITE + optional custom",
            "policy": "no-broadcast; fork-only; full-suite-always",
            "suite": "AipFullForkSuite",
            "custom_included": bool(custom),
            "counts": counts,
        }
        return artifact
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "forge test timed out", "attestation": "FORK_TIMEOUT"}
    except Exception as e:
        return {"ok": False, "error": str(e), "attestation": "FORK_ERROR"}
    finally:
        if work and work.exists():
            shutil.rmtree(work, ignore_errors=True)
