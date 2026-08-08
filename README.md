# AIP Web Suites

Standalone browser operator consoles from **Aetherverse Intelligence Protocol (AIP)**.

| File | Modes | Role |
|------|--------|------|
| [`AIP-Web2-Suite.html`](./AIP-Web2-Suite.html) | OSINT · Pentest Matrix · **Capabilities** | Elite first-pass Web2 intel + adversarial matrix |
| [`AIP-Web3-Suite.html`](./AIP-Web3-Suite.html) | Chain Intel · Audit Matrix · **Capabilities** | Web3 hunt OS with **FORK_EXECUTED-only** PoC gate |

## Fork Lab (REAL forks — required for Audit Matrix unlock)

Audit Matrix unlocks **only** after a real `forge test --fork-url` pass — not a checklist.

```bash
cd aip-web-suites
cp .env.example .env   # set ETH_RPC_URL if you want your own provider
./fork-lab/start.sh    # listens on http://127.0.0.1:8787
```

Then open `AIP-Web3-Suite.html` → **Audit Matrix** → paste `0x…` → **Run Fork**.

## Open

Download either HTML → open in Chrome/Firefox/Edge (prefer `http://` via a local static server if your browser restricts `file://` fetches).

```bash
python3 -m http.server 8080
# then open http://127.0.0.1:8080/AIP-Web2-Suite.html
```

No install. **No backend required** for core collection / export / matrix tooling.

### Web2 standalone behavior

- Public API fallbacks: Google DNS, Shodan InternetDB, RDAP WHOIS, explorer/link modules, local export
- Optional API keys unlock deeper coverage when a proxy is present
- **Send to Pentest Matrix** hands OSINT context into TAP (target, CVEs, engagement fields)
- HTML / TXT / JSON export and printable Gov report work fully client-side

### Web3 handoff

- **Send to Audit Matrix** loads Chain Intel dossier (target, hypotheses, recommended modules, PoC scaffold)
- Live lookups (ENS / bytecode / explorer) run when public endpoints allow CORS
- Audit Matrix still enforces **FORK_EXECUTED only** before PoC unlock

## Web3 rigor

Audit Matrix enforces **FORK_EXECUTED only**:

- Persistent fork-only banner
- Attestation required before PoC scaffold / claim / export unlock
- Local Anvil/Foundry fork against a pinned block
- Simulation-only speculation and mainnet exploit broadcasts are rejected

## ROE

Authorized targets only (signed SOW, published bounty scope, or written owner consent).

## License

Proprietary — Aetherverse Intelligence. All rights reserved unless otherwise stated.
