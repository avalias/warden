/**
 * @warden/sdk — a typed TypeScript client for the WARDEN autonomous-agent
 * custody package on Sui.
 *
 * Two halves:
 *   1. Readers — pull the live, on-chain truth (vault NAV, ledger hash-chain
 *      head, market feed + staleness, the append-only track record) straight
 *      from a fullnode. No trust in any server.
 *   2. PTB builders — assemble unsigned `Transaction`s for the package's entry
 *      points. The SDK never holds keys or signs: you sign with your own
 *      keypair / wallet and submit. That keeps custody where it belongs.
 *
 * The deployed package is immutable, so this client is a thin, stable shim over
 * a fixed ABI.
 */
import type { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';

/** The on-chain object ids of one WARDEN deployment (see `warden.config.json`). */
export interface WardenAddresses {
  package: string;
  vault: string;
  policy: string;
  gen_registry: string;
  critic_registry: string;
  critic_cap: string;
  ledger: string;
  feed: string;
}

export interface VaultState {
  owner: string;
  idle: bigint;       // capital sitting in the vault
  deployed: bigint;   // real capital the agent has steered into strategies
  nav: bigint;        // idle + deployed — all real balance inside the vault
  shares: bigint;
  frozen: boolean;
}

export interface LedgerState {
  seq: bigint;
  count: bigint;
  last_ms: bigint;
  chain_head: string; // keccak hash-chain head (hex); re-derivable off-chain
}

export interface FeedState {
  feeder: string;
  price_e6: bigint;
  depth: bigint;
  updated_ms: bigint;
  max_age_ms: bigint;
  stale: boolean;     // would the guardian reject a read right now?
}

export interface LedgerEntry {
  seq: number;
  ts_ms: number;
  risk_bps: number;
  accepted: boolean;
  fault: number;
  trade_digest: string;  // hex
  entry_digest: string;  // hex — this entry's link in the hash chain
}

// ---- parsing helpers (defensive against RPC representation differences) ----

function asU64(x: unknown): bigint {
  if (x == null) return 0n;
  if (typeof x === 'bigint') return x;
  if (typeof x === 'string' || typeof x === 'number') return BigInt(x);
  if (typeof x === 'object') {
    const o = x as Record<string, unknown>;
    if ('value' in o) return asU64(o.value);
    if ('fields' in o && o.fields && typeof o.fields === 'object' && 'value' in (o.fields as object)) {
      return asU64((o.fields as Record<string, unknown>).value);
    }
  }
  return 0n;
}

/** A Move `vector<u8>` arrives as a number[] (parsed content/events) or a
 *  base64 string. Normalise to `0x…` hex either way. */
function toHex(x: unknown): string {
  if (x == null) return '';
  if (Array.isArray(x)) return '0x' + x.map((b: number) => (b & 0xff).toString(16).padStart(2, '0')).join('');
  if (typeof x === 'string') {
    try { return '0x' + Buffer.from(x, 'base64').toString('hex'); } catch { return x; }
  }
  return '';
}

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000000000000000000000000000';

/** Little-endian u64 from the first 8 bytes (BCS return-value decoding). */
function leU64(b: ArrayLike<number>): bigint {
  let v = 0n;
  for (let i = 0; i < 8; i++) v += BigInt(b[i] ?? 0) << BigInt(8 * i);
  return v;
}

export interface GuardianVerdict {
  ok: boolean;        // would the chain approve this trade?
  derived_bps: bigint; // the risk the chain itself re-derives
  fault: number;       // 0 none · 1 diverged · 2 ceiling · 3 unsafe-direction
}

export class WardenClient {
  constructor(
    private readonly client: SuiClient,
    readonly addr: WardenAddresses,
    /** The shared Clock object id (always `0x6` on Sui). */
    private readonly clockId: string = '0x6',
  ) {}

  // ----------------------------- readers -----------------------------

  private async fields(id: string): Promise<Record<string, unknown>> {
    const o = await this.client.getObject({ id, options: { showContent: true } });
    const content = o.data?.content as { fields?: Record<string, unknown> } | undefined;
    if (!content?.fields) throw new Error(`object ${id} has no readable content (wrong id / network?)`);
    return content.fields;
  }

  /** Live custody state. `nav` is conserved by every agent op; only the owner
   *  withdraw path can shrink it. */
  async getVaultState(): Promise<VaultState> {
    const f = await this.fields(this.addr.vault);
    const idle = asU64(f.idle);
    const deployed = asU64(f.deployed);
    return {
      owner: String(f.owner ?? ''),
      idle,
      deployed,
      nav: idle + deployed,
      shares: asU64(f.shares),
      frozen: Boolean(f.frozen),
    };
  }

  /** Append-only ledger head: monotonic sequence + the keccak hash-chain head. */
  async getLedgerState(): Promise<LedgerState> {
    const f = await this.fields(this.addr.ledger);
    return {
      seq: asU64(f.seq),
      count: asU64(f.count),
      last_ms: asU64(f.last_ms),
      chain_head: toHex(f.prev_digest),
    };
  }

  /** Market feed the agent cannot forge, plus whether a read would be rejected
   *  as stale right now. */
  async getFeedState(nowMs: number = Date.now()): Promise<FeedState> {
    const f = await this.fields(this.addr.feed);
    const updated = asU64(f.updated_ms);
    const maxAge = asU64(f.max_age_ms);
    const age = BigInt(Math.max(0, Math.floor(nowMs))) - updated;
    return {
      feeder: String(f.feeder ?? ''),
      price_e6: asU64(f.price_e6),
      depth: asU64(f.depth),
      updated_ms: updated,
      max_age_ms: maxAge,
      stale: age > maxAge,
    };
  }

  /** The verifiable track record: the most recent `Recorded` events for THIS
   *  vault, newest first. Rejected trades are in here too — the chain records
   *  what the agent was NOT allowed to do. The event is per-package, so we
   *  filter on its `vault` field and paginate until `limit` entries. */
  async getLedgerHistory(limit: number = 10): Promise<LedgerEntry[]> {
    const out: LedgerEntry[] = [];
    let cursor: { txDigest: string; eventSeq: string } | null = null;
    for (let page = 0; page < 5; page++) { // safety cap: 5 pages of 50
      const res = await this.client.queryEvents({
        query: { MoveEventType: `${this.addr.package}::ledger::Recorded` },
        cursor,
        limit: 50,
        order: 'descending',
      });
      for (const e of res.data) {
        const p = e.parsedJson as Record<string, unknown>;
        if (p.vault !== this.addr.vault) continue;
        out.push({
          seq: Number(p.seq ?? 0),
          ts_ms: Number(p.ts_ms ?? 0),
          risk_bps: Number(p.risk_bps ?? 0),
          accepted: Boolean(p.accepted),
          fault: Number(p.fault ?? 0),
          trade_digest: toHex(p.trade_digest),
          entry_digest: toHex(p.entry_digest),
        });
        if (out.length >= limit) return out;
      }
      if (!res.hasNextPage || !res.nextCursor) break;
      cursor = res.nextCursor;
    }
    return out;
  }

  // ------------------------ chain simulation -------------------------
  // Ask the chain ITSELF what it would rule — no keys, no gas, no state change.
  // devInspect runs the guardian's pure re-derivation and returns its verdict,
  // so you can preview the leash before ever signing a trade.

  private async devInspectReturn(tx: Transaction): Promise<Uint8Array> {
    const res = await this.client.devInspectTransactionBlock({ sender: ZERO_ADDRESS, transactionBlock: tx });
    const rv = res.results?.[0]?.returnValues?.[0];
    if (!rv) throw new Error('devInspect returned no value' + (res.error ? `: ${res.error}` : ''));
    return Uint8Array.from(rv[0] as number[]);
  }

  /** The chain's own risk number (bps) for a hypothetical position — the exact
   *  value the guardian would re-derive on-chain. */
  async deriveRisk(p: { exposure: bigint | number; priceE6: bigint | number; depth: bigint | number }): Promise<bigint> {
    const tx = new Transaction();
    tx.moveCall({
      target: `${this.addr.package}::guardian::derive_risk_bps`,
      arguments: [tx.pure.u64(p.exposure), tx.pure.u64(p.priceE6), tx.pure.u64(p.depth)],
    });
    return leU64(await this.devInspectReturn(tx));
  }

  /** The full guardian verdict for a hypothetical trade: would it be approved,
   *  what risk does the chain derive, and which fault (if any) trips. Lets an
   *  agent preview the leash before signing anything. */
  async simulateGuardian(p: {
    claimedRiskBps: bigint | number;
    direction: 0 | 1;
    exposure: bigint | number;
    priceE6: bigint | number;
    depth: bigint | number;
  }): Promise<GuardianVerdict> {
    const tx = new Transaction();
    tx.moveCall({
      target: `${this.addr.package}::guardian::evaluate`,
      arguments: [
        tx.pure.u64(p.claimedRiskBps), tx.pure.u8(p.direction),
        tx.pure.u64(p.exposure), tx.pure.u64(p.priceE6), tx.pure.u64(p.depth),
      ],
    });
    const b = await this.devInspectReturn(tx); // BCS Assessment { ok: bool, derived_bps: u64, fault: u8 }
    return { ok: b[0] === 1, derived_bps: leU64(b.slice(1, 9)), fault: b[9] ?? 0 };
  }

  // -------------------------- PTB builders ---------------------------
  // Each returns an UNSIGNED Transaction. Sign + execute with your own keypair:
  //   const tx = warden.buildFeedUpdateTx({ priceE6: 1_000_000n, depth: 1_000n });
  //   await client.signAndExecuteTransaction({ signer, transaction: tx });

  /** The agent proposes a trade; it flows through all five gates atomically.
   *  A guardian fault freezes the vault and records the rejection. */
  buildAgentTradeTx(p: {
    amount: bigint | number;
    direction: 0 | 1;
    claimedRiskBps: bigint | number;
    walrusBlob?: number[];
    teeAttestation?: number[];
  }): Transaction {
    const tx = new Transaction();
    tx.moveCall({
      target: `${this.addr.package}::app::agent_trade`,
      arguments: [
        tx.object(this.addr.vault),
        tx.object(this.addr.policy),
        tx.object(this.addr.gen_registry),
        tx.object(this.addr.critic_registry),
        tx.object(this.addr.critic_cap),
        tx.object(this.addr.ledger),
        tx.object(this.addr.feed),
        tx.pure.u64(p.amount),
        tx.pure.u8(p.direction),
        tx.pure.u64(p.claimedRiskBps),
        tx.pure.vector('u8', p.walrusBlob ?? []),
        tx.pure.vector('u8', p.teeAttestation ?? []),
        tx.object(this.clockId),
      ],
    });
    return tx;
  }

  /** The keeper writes market data (production: pulled from Pyth + DeepBook). */
  buildFeedUpdateTx(p: { priceE6: bigint | number; depth: bigint | number }): Transaction {
    const tx = new Transaction();
    tx.moveCall({
      target: `${this.addr.package}::app::feed_update`,
      arguments: [tx.object(this.addr.feed), tx.pure.u64(p.priceE6), tx.pure.u64(p.depth), tx.object(this.clockId)],
    });
    return tx;
  }

  /** The owner withdraws — works even when the agent is frozen (non-custodial).
   *  Needs the `OwnerCap` object id held by the owner. */
  buildOwnerExitTx(p: { ownerCap: string; amount: bigint | number }): Transaction {
    const tx = new Transaction();
    tx.moveCall({
      target: `${this.addr.package}::app::owner_exit`,
      arguments: [tx.object(this.addr.vault), tx.object(p.ownerCap), tx.pure.u64(p.amount)],
    });
    return tx;
  }

  /** The owner pulls deployed capital back into idle (the close leg). */
  buildOwnerUndeployTx(p: { ownerCap: string; amount: bigint | number }): Transaction {
    const tx = new Transaction();
    tx.moveCall({
      target: `${this.addr.package}::app::owner_undeploy`,
      arguments: [tx.object(this.addr.vault), tx.object(p.ownerCap), tx.pure.u64(p.amount)],
    });
    return tx;
  }

  /** L6 fix that needs no new package: open a dead-man-switch as a SHARED
   *  object, so the named beneficiary can actually supply it to
   *  `inherit_claim` after dormancy. (The shipped `app::inherit_open` entry
   *  transfers the `Switch` to the opener — an owned object on Sui can only be
   *  used in a tx by its owner, so through that entry the beneficiary has no
   *  claim path. `inheritance::new` is public and `Switch` has `store`, so a
   *  PTB can share it at creation instead.) */
  buildInheritOpenSharedTx(p: { beneficiary: string; dormancyMs: bigint | number }): Transaction {
    const tx = new Transaction();
    const [sw] = tx.moveCall({
      target: `${this.addr.package}::inheritance::new`,
      arguments: [tx.pure.address(p.beneficiary), tx.pure.u64(p.dormancyMs), tx.object(this.clockId)],
    });
    tx.moveCall({
      target: '0x2::transfer::public_share_object',
      typeArguments: [`${this.addr.package}::inheritance::Switch`],
      arguments: [sw],
    });
    return tx;
  }
}
