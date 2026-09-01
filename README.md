# AIP Web Suites

Standalone browser operator consoles from **Aetherverse Intelligence Protocol (AIP)**.

| File | Modes | Role |
|------|--------|------|
| [`AIP-Web2-Suite.html`](./AIP-Web2-Suite.html) | OSINT · Pentest Matrix · **Capabilities** | Elite first-pass Web2 intel + adversarial matrix |
| [`AIP-Web3-Suite.html`](./AIP-Web3-Suite.html) | Chain Intel · Audit Matrix · **Capabilities** | Web3 hunt OS with **FORK_EXECUTED-only** PoC gate |

## What you can do with AIP Web Suites

Open a single HTML file in your browser and run a **full first-pass intel or audit workflow** — no install, no backend, no account wall for the core rails.

### Web2 Suite — recon + pentest handoff

- **Seed a target** (domain, IP, org) and pull DNS, WHOIS/RDAP, Shodan InternetDB, and link/explorer modules in one pass.
- **Send findings to Pentest Matrix** — target context, CVE hints, and engagement fields carry over automatically.
- **Export a Gov-ready report** — HTML, TXT, or JSON, entirely client-side.
- **Browse the Capabilities tab** for every module reference without leaving the page.

### Web3 Suite — hunt with proof, not vibes

- **Build a chain intel dossier** — ENS, bytecode, explorer data when endpoints allow.
- **Run Audit Matrix** against a contract address — hypothesis modules, recommended tests, PoC scaffold.
- **Unlock PoC only after a real fork** — Audit Matrix refuses simulation-only claims; you need **FORK_EXECUTED** attestation from Fork Lab.

### Fork Lab (Web3 rigor)

- Spin up **real Foundry forks** @ `:8787` so your PoC actually ran against chain state — not a checklist you clicked through.

```bash
python3 -m http.server 8080
# → http://127.0.0.1:8080/AIP-Web2-Suite.html
```

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
