#!/usr/bin/env bash
# Start AIP Fork Lab (real Foundry forks). Kills any stale process on the port first.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f ../.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ../.env
  set +a
fi
export ETH_RPC_URL="${ETH_RPC_URL:-https://ethereum.publicnode.com}"
HOST="${FORK_LAB_HOST:-127.0.0.1}"
PORT="${FORK_LAB_PORT:-8787}"

# Drop stale listener so Solodit routes always match this checkout
if command -v ss >/dev/null 2>&1; then
  PIDS=$(ss -ltnp "sport = :${PORT}" 2>/dev/null | awk -F'pid=' 'NR>1{split($2,a,","); print a[1]}' | sort -u || true)
  if [[ -n "${PIDS:-}" ]]; then
    echo "Stopping stale fork-lab on :${PORT} (pids: ${PIDS})"
    # shellcheck disable=SC2086
    kill ${PIDS} 2>/dev/null || true
    sleep 0.6
  fi
fi

export PATH="${HOME}/.foundry/bin:${PATH:-}"
exec python3 server.py
