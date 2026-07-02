# Contributing

## Ground rules

- **`main` is the frozen submission** — it moves only by fast-forward merges
  from `develop`. All work lands on `develop`.
- **The deployed package is immutable** (UpgradeCap burned). Contract-source
  changes are welcome as *proposals for the next package*; they cannot change
  what is on-chain. Test-only, SDK, docs, and site changes ship freely.
- Keep claims honest. If something is a roadmap item, label it as one — this
  repo's credibility rests on never overclaiming.

## Build & test

```bash
# Move contracts (needs the Sui CLI, >= 1.45)
cd contracts && sui move test          # full unit + property suite

# TypeScript SDK + MCP server
cd sdk && npm install && npm run typecheck && npm run read-state
cd sdk/mcp && npm install && npm run smoke

# Python SDK (stdlib only — nothing to install)
python sdk/python/read_state.py
python sdk/python/monitor.py --once

# on-chain claims (no dependencies at all)
python scripts/verify_onchain.py
python scripts/verify_ledger.py
```

CI (`verify-onchain`) runs the on-chain verification + a Python SDK smoke on
every push to `main`/`develop` and on a daily schedule.

## Style

- Move: match the existing module style — short doc comments explaining *why*,
  abort-code constants named `E...`, tests that pin behavior by name.
- TS/Python: match the file you're editing; the Python surfaces stay
  dependency-free (stdlib + urllib) by design.
- Never commit secrets, wallet output (`sui client ... --json` can contain key
  material), or `warden.config.json` (gitignored; the example ships the public
  ids).
