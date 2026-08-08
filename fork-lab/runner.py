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

DEFAULT_POC = '''// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @notice AIP Fork Lab — FORK_EXECUTED evidence only. No broadcast.
contract AipForkPoC is Test {{
    // Target under test: {target_label}
    address constant TARGET = {target_addr};

    function setUp() public {{
        // Fork is provided by: forge test --fork-url --fork-block-number
    }}

    function test_Fork_TargetHasCodeOrBalance() public view {{
        uint256 bal = TARGET.balance;
        uint256 codeLen = TARGET.code.length;
        // Evidence: fork sees live state for TARGET at pinned block.
        assertTrue(codeLen > 0 || bal > 0, "target has neither code nor balance on fork");
    }}
}}
'''


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
        impl_slot = "0x360894a13ba1a3210667c828492db98dca3e2076adc198dce132a76e8c5c1"
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


def _prepare_workspace(solidity: str) -> Path:
    if not TEMPLATE.exists():
        raise RuntimeError(f"missing template at {TEMPLATE}")
    work = Path(tempfile.mkdtemp(prefix="aip-fork-"))
    # copy template minus heavy out/cache if any
    for name in ("foundry.toml", "lib", "src", "test", "script"):
        src = TEMPLATE / name
        dst = work / name
        if src.is_dir():
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns("out", "cache", ".git"))
        elif src.exists():
            shutil.copy2(src, dst)
    # wipe default tests; write ours
    test_dir = work / "test"
    if test_dir.exists():
        for f in test_dir.glob("*.sol"):
            f.unlink()
    else:
        test_dir.mkdir(parents=True)
    (test_dir / "AipForkPoC.t.sol").write_text(solidity, encoding="utf-8")
    return work


def run_fork(
    *,
    address: str | None = None,
    solidity: str | None = None,
    rpc: str | None = None,
    block: str | int | None = None,
    timeout: int = 240,
) -> dict[str, Any]:
    t0 = time.time()
    rpc_url = (rpc or default_rpc()).strip()
    if not rpc_url:
        return {"ok": False, "error": "ETH_RPC_URL not configured"}

    addr = (address or "").strip()
    if addr and not ADDRESS_RE.match(addr):
        return {"ok": False, "error": "invalid address"}

    sol = (solidity or "").strip()
    if not sol:
        target_addr = addr if addr else "address(0)"
        if addr:
            target_addr = addr  # checksum not required for const
        sol = DEFAULT_POC.format(
            target_label=addr or "unset",
            target_addr=target_addr if addr else "address(0)",
        )

    if BROADCAST_BAN.search(sol):
        return {
            "ok": False,
            "error": "REJECTED: solidity contains broadcast helpers. FORK_EXECUTED only — no mainnet send.",
            "attestation": "REJECTED_BROADCAST",
        }

    # pin block if not provided
    pinned = str(block).strip() if block not in (None, "") else ""
    if not pinned:
        p = _run([CAST, "block-number", "--rpc-url", rpc_url], timeout=30)
        if p.returncode != 0:
            return {"ok": False, "error": f"cannot read block number: {(p.stderr or p.stdout)[:300]}"}
        pinned = (p.stdout or "").strip()

    work = None
    try:
        work = _prepare_workspace(sol)
        cmd = [
            FORGE,
            "test",
            "--fork-url",
            rpc_url,
            "--fork-block-number",
            pinned,
            "-vvv",
            "--match-path",
            "test/AipForkPoC.t.sol",
        ]
        proc = _run(cmd, cwd=work, timeout=timeout)
        stdout = proc.stdout or ""
        stderr = proc.stderr or ""
        combined = (stdout + "\n" + stderr).strip()
        passed = proc.returncode == 0 and ("Suite result: ok" in combined or "PASS" in combined or "passed" in combined.lower())
        # forge returns 0 on pass
        if proc.returncode == 0:
            passed = True
        artifact = {
            "ok": passed,
            "attestation": "FORK_EXECUTED" if passed else "FORK_FAILED",
            "exit_code": proc.returncode,
            "rpc_redacted": redact_rpc(rpc_url),
            "fork_block": pinned,
            "address": addr or None,
            "duration_ms": int((time.time() - t0) * 1000),
            "stdout": stdout[-120000:],
            "stderr": stderr[-40000:],
            "solidity_sha256": hashlib.sha256(sol.encode()).hexdigest(),
            "command": "forge test --fork-url <RPC> --fork-block-number " + pinned + " -vvv",
            "policy": "no-broadcast; fork-only",
        }
        return artifact
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "forge test timed out", "attestation": "FORK_TIMEOUT"}
    except Exception as e:
        return {"ok": False, "error": str(e), "attestation": "FORK_ERROR"}
    finally:
        if work and work.exists():
            shutil.rmtree(work, ignore_errors=True)
