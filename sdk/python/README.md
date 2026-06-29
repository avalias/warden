# warden (Python)

A tiny, **dependency-free** Python client for the WARDEN custody package — the
sibling of the [TypeScript SDK](../README.md), in the same spirit as this repo's
`verify_*.py`: pure stdlib (`urllib` + `json`), nothing to install.

- **Readers** pull the live on-chain truth — vault NAV (idle + deployed), the
  ledger's keccak hash-chain head, the market feed + staleness, and the
  verifiable trade track record (accepted *and* rejected). No trust in any server.
- **Command builders** return the exact `sui client call …` argv for each entry
  point. The SDK never holds keys or signs — you run the command with your own
  CLI keypair. Custody stays where it belongs.

## Try it (read-only, no keys)

```bash
cd sdk/python
python read_state.py        # prints live vault / feed / ledger state from testnet
```

Reads object ids from `../../warden.config.json` (falls back to the example).

## Use it

```python
from warden import WardenClient, load_addresses

w = WardenClient(load_addresses())          # or WardenClient({...}, rpc="https://…")

# read
v = w.get_vault_state()                     # {'nav': ..., 'frozen': ..., ...}
head = w.get_ledger_state()["chain_head"]   # keccak hash-chain head
log = w.get_ledger_history(10)              # accepted + rejected

# build (you sign + run) — e.g. the keeper posts market data
import subprocess
subprocess.run(w.feed_update_cmd(1_000_000, 1_000))
```

### Builders

| Method | Entry point | Who calls it |
| --- | --- | --- |
| `agent_trade_cmd` | `app::agent_trade` | the agent — flows through all five gates atomically |
| `feed_update_cmd` | `app::feed_update` | the keeper / feeder |
| `owner_exit_cmd` | `app::owner_exit` | the owner (works even while frozen) |
| `owner_undeploy_cmd` | `app::owner_undeploy` | the owner (close the deployed leg) |

Each returns the `sui client call` argv; sign and run it yourself.
