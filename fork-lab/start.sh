#!/usr/bin/env bash
# Start AIP Fork Lab (real Foundry forks)
set -euo pipefail
cd "$(dirname "$0")"
if [[ -f ../.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ../.env
  set +a
fi
export ETH_RPC_URL="${ETH_RPC_URL:-https://ethereum.publicnode.com}"
exec python3 server.py
