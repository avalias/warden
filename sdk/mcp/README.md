# @warden/mcp

An [MCP](https://modelcontextprotocol.io) server that exposes the **WARDEN**
custody package to any MCP-speaking agent runtime (Cursor and other MCP clients)
as tools. It's a thin layer over [`@warden/sdk`](../README.md):

- **Read tools** return the live on-chain truth — vault NAV, the ledger's keccak
  hash-chain head, the unforgeable market feed, and the accepted/rejected trade
  record. So an agent reasons over what the chain *actually* enforces, not what a
  server claims.
- **Build tools** assemble **unsigned** transactions and return them serialized.
  The server never holds keys and never signs — the agent's own wallet does.

This is the "Agentic Web" surface: an agent can inspect the leash and propose a
trade, but the chain still re-derives risk, clamps, freezes, and records — the
agent stays structurally incapable of harm.

## Tools

| Tool | Kind | What |
| --- | --- | --- |
| `warden_get_vault_state` | read | owner, idle, deployed, NAV, frozen |
| `warden_get_ledger_state` | read | seq, count, keccak chain head |
| `warden_get_feed_state` | read | price, depth, staleness |
| `warden_get_ledger_history` | read | recent accepted + rejected trades |
| `warden_build_feed_update` | build | unsigned `feed_update` tx |
| `warden_build_agent_trade` | build | unsigned `agent_trade` tx (all five gates) |

## Try it (read-only, no keys)

```bash
cd sdk/mcp
npm install
npm run smoke      # spawns the server, does a real MCP round-trip against testnet
```

## Wire it into a client

Add to your MCP client's config (the `mcpServers` JSON block), using an absolute
path to `server.ts`:

```json
{
  "mcpServers": {
    "warden": {
      "command": "node",
      "args": ["--import", "tsx", "/abs/path/to/warden/sdk/mcp/server.ts"],
      "env": { "WARDEN_NETWORK": "testnet" }
    }
  }
}
```

Object ids come from `warden.config.json` at the repo root (falls back to the
example). `WARDEN_NETWORK` defaults to `testnet`. For production, `tsc`-build the
server and point `node` at the emitted JS instead of using `tsx`.
