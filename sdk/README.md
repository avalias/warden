# @warden/sdk

A small, typed TypeScript client for the **WARDEN** autonomous-agent custody
package on Sui. It does two things:

- **Readers** pull the live, on-chain truth from a fullnode — vault NAV (idle +
  deployed), the append-only ledger's keccak hash-chain head, the market feed and
  whether it's stale, and the verifiable trade track record (accepted *and*
  rejected). No trust in any server.
- **PTB builders** assemble **unsigned** `Transaction`s for the package's entry
  points. The SDK never holds keys and never signs — you sign with your own
  keypair / wallet and submit. Custody stays where it belongs.

The deployed package is **immutable** (`0xfd6131…7437`), so this is a thin, stable
shim over a fixed ABI.

## Install & try (read-only, no keys)

```bash
cd sdk
npm install
npm run read-state     # prints live vault / feed / ledger state from testnet
```

`read-state` reads object ids from `../warden.config.json` (falls back to
`warden.config.example.json`). Only on-chain ids are used.

## Use it

```ts
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { WardenClient } from '@warden/sdk';

const client = new SuiClient({ url: getFullnodeUrl('testnet') });
const warden = new WardenClient(client, addresses); // addresses: WardenAddresses

// read
const { nav, frozen } = await warden.getVaultState();
const head = (await warden.getLedgerState()).chain_head;   // hash-chain head
const log  = await warden.getLedgerHistory(10);            // accepted + rejected

// build (you sign) — e.g. the keeper posts market data
const tx = warden.buildFeedUpdateTx({ priceE6: 1_000_000n, depth: 1_000n });
await client.signAndExecuteTransaction({ signer, transaction: tx });
```

### Builders

| Method | Entry point | Who calls it |
| --- | --- | --- |
| `buildAgentTradeTx` | `app::agent_trade` | the agent — flows through all five gates atomically |
| `buildFeedUpdateTx` | `app::feed_update` | the keeper / feeder |
| `buildOwnerExitTx` | `app::owner_exit` | the owner (works even while frozen) |
| `buildOwnerUndeployTx` | `app::owner_undeploy` | the owner (close the deployed leg) |

Each returns an unsigned `Transaction`; sign and execute it yourself.

## Simulate the guardian (no keys, no gas)

Ask the chain *itself* what it would rule for a hypothetical trade — `devInspect`
runs the guardian's pure re-derivation and returns its verdict, changing nothing.
Preview the leash before you ever sign.

```ts
const v = await warden.simulateGuardian({
  claimedRiskBps: 100, direction: 0,        // the agent's claim
  exposure: 1_000_000, priceE6: 1_000_000, depth: 100_000, // the market it lies about
});
// { ok: false, derived_bps: 10000n, fault: 1 }  -> the chain catches the lie (diverged)

await warden.deriveRisk({ exposure: 50_000, priceE6: 1_000_000, depth: 100_000 }); // 5000n bps
```

```bash
npm run simulate     # runs examples/simulate-guardian.ts against testnet
```

## Verify the ledger off-chain

The readers expose `chain_head` and each entry's `entry_digest`. To re-derive the
whole keccak chain from on-chain events and prove nothing was dropped or forged,
see [`scripts/verify_ledger.py`](../scripts/verify_ledger.py).
